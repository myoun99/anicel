import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// One stretch of the ground under a piece of writing, along the writing's
/// own x axis: it ENDS at [end] — a fraction of the writing's width, the
/// previous run's end being where it starts — and the writing takes [ink]
/// over it.
typedef GroundInkRun = ({double end, Color ink});

/// The runs over a bar with a fill: the empty track, the fill between [near]
/// and [far] (fractions of the writing's width, ordered), the track again.
List<GroundInkRun> groundInkRunsForFill({
  required double near,
  required double far,
  required Color onFill,
  required Color onTrack,
}) {
  if (far <= near) {
    return [(end: 1.0, ink: onTrack)];
  }
  return [
    if (near > 0) (end: near, ink: onTrack),
    (end: far, ink: onFill),
    if (far < 1) (end: 1.0, ink: onTrack),
  ];
}

/// Writing whose ink follows the ground under it — the text-on-ground law
/// (`textOnColor`) applied run by run, so one string changes ink PART WAY
/// THROUGH a word where the ground changes under it.
///
/// 🚨ONE WRITING FOR EVERY SURFACE THAT PAINTS BEHIND ITS TEXT (유저
/// 2026-09-11, H38 again): 「브러시 스트로크 프리뷰쪽 이름도 … 전엔 텍스트
/// 전체를 바꿨잖아. 그게아니라 슬라이더 공용 텍스트ui 그대로 재사용」. The
/// bar's fill and a brush row's stroke were two grounds that change along the
/// writing, and both answered the question the same way — here. ↩️F-82
/// (유저 2026-09-11 19:28) took the brush row off it: its name sits on a plate
/// in a fixed colour now (`BrushNameLabel`), and the column-by-column runs
/// only that row needed went with it.
///
/// ⛔NOT A `ShaderMask`, which is how the bar did this before (2026-09-08 ~
/// 09-10): that is an offscreen layer per writing on every frame the app
/// produces, and the brush list once measured that kind of layer
/// (`ColorFiltered`) at 7.4 ms a frame for four rows. The ink is the TEXT'S
/// OWN PAINT instead — a hard-stopped gradient as its foreground — which
/// costs what a solid colour costs.
///
/// ⛔Not the writing laid twice and clipped either (the first shape the bar
/// tried): that is two `Text` widgets for one string, read twice by
/// assistive tech.
class GroundInkWriting extends StatelessWidget {
  const GroundInkWriting({
    super.key,
    required this.runs,
    required this.builder,
  });

  /// The ground under the writing, left to right — see [GroundInkRun].
  final List<GroundInkRun> runs;

  /// Builds the writing with [ink] merged into its text styles: a `color`
  /// when one ink covers the whole width, a `foreground` when the ground
  /// changes under it. ⚠️`TextStyle.merge` hands the ink over whatever
  /// colour the styles carried, so they need not clear their own.
  final Widget Function(BuildContext context, TextStyle ink) builder;

  /// 🚨ONE SHAPE, WHATEVER THE GROUND (2026-09-26). The writing used to be a
  /// plain child while one ink covered it and a layout builder over a moved
  /// canvas once the ground changed under it — two element trees, so a bar
  /// whose fill crossed into or out of its words threw its writing away and
  /// built the other. The replaced child is a relayout that climbs past the
  /// bar's fixed-height box to the row's first relayout boundary: on a brush
  /// pick, three bars in the tool settings flipped and laid the whole
  /// settings column out again, each object laid out a semantics update too.
  /// Now the tree is the same every time and only the ink changes; one ink
  /// paints the ordinary way, exactly as it did.
  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final ink = _inkFor(constraints);
        return _InkAtOrigin(
          moveCanvas: ink.foreground != null,
          child: builder(context, ink),
        );
      },
    );
  }

  TextStyle _inkFor(BoxConstraints constraints) {
    if (runs.isEmpty) {
      return const TextStyle();
    }
    final first = runs.first.ink;
    // A writing with no width to measure has nowhere to put a boundary; it
    // takes the first ground's ink rather than a shader stretched to
    // infinity.
    if (runs.every((run) => run.ink == first) ||
        !constraints.hasBoundedWidth) {
      return TextStyle(color: first);
    }
    final colors = <Color>[];
    final stops = <double>[];
    var start = 0.0;
    for (final run in runs) {
      colors
        ..add(run.ink)
        ..add(run.ink);
      stops
        ..add(start)
        ..add(run.end);
      start = run.end;
    }
    final shader = LinearGradient(
      colors: colors,
      stops: stops,
    ).createShader(Offset.zero & constraints.biggest);
    return TextStyle(foreground: Paint()..shader = shader);
  }
}

/// Paints its child with the canvas moved to its own top-left, so a shader
/// laid out in the writing's box lands on the writing.
///
/// ⚠️A text's foreground shader is read in CANVAS coordinates, and a render
/// object is handed an offset into its layer rather than a moved canvas — so
/// without this the gradient would start where the LAYER starts. A child
/// that brings layers of its own cannot be moved this way; it is painted the
/// ordinary way (in the right place, its ink off true) rather than wrongly.
///
/// [moveCanvas] false paints the ordinary way: one ink needs no shader to
/// land, and the writing keeps the paint it always had.
class _InkAtOrigin extends SingleChildRenderObjectWidget {
  const _InkAtOrigin({required this.moveCanvas, required super.child});

  final bool moveCanvas;

  @override
  _RenderInkAtOrigin createRenderObject(BuildContext context) =>
      _RenderInkAtOrigin(moveCanvas: moveCanvas);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderInkAtOrigin renderObject,
  ) {
    renderObject.moveCanvas = moveCanvas;
  }
}

class _RenderInkAtOrigin extends RenderProxyBox {
  _RenderInkAtOrigin({required bool moveCanvas}) : _moveCanvas = moveCanvas;

  bool get moveCanvas => _moveCanvas;
  bool _moveCanvas;
  set moveCanvas(bool value) {
    if (_moveCanvas == value) {
      return;
    }
    _moveCanvas = value;
    markNeedsPaint();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final child = this.child;
    if (child == null) {
      return;
    }
    if (!_moveCanvas || child.needsCompositing || child.isRepaintBoundary) {
      context.paintChild(child, offset);
      return;
    }
    final canvas = context.canvas;
    canvas.save();
    canvas.translate(offset.dx, offset.dy);
    context.paintChild(child, Offset.zero);
    canvas.restore();
  }
}
