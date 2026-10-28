import 'dart:math' as math;

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
    this.padding = EdgeInsets.zero,
    this.alignment,
    required this.builder,
  });

  /// The ground under the writing, left to right — see [GroundInkRun].
  final List<GroundInkRun> runs;

  /// How far the writing stands off the edges of its box — a [Padding]
  /// round it. The runs are fractions of the WHOLE box, padding and all.
  final EdgeInsets padding;

  /// Where the writing stands inside [padding] — an [Align] round it — or
  /// null for a writing that fills that room.
  final Alignment? alignment;

  /// Builds the writing with [ink] merged into its text styles: a `color`
  /// when one ink covers the whole width, a `foreground` when the ground
  /// changes under it. ⚠️`TextStyle.merge` hands the ink over whatever
  /// colour the styles carried, so they need not clear their own.
  final Widget Function(BuildContext context, TextStyle ink) builder;

  /// 🪶The box right above the writing stands it in its place — the
  /// [padding] and the [alignment] — where a [Padding] and an [Align] were
  /// two boxes more for every bar a tab reopens (card frame-panels-build-
  /// in-one-frame, 2026-10-28).
  @override
  Widget build(BuildContext context) {
    if (runs.isEmpty) {
      return _placed(builder(context, const TextStyle()));
    }
    final first = runs.first.ink;
    if (runs.every((run) => run.ink == first)) {
      return _placed(builder(context, TextStyle(color: first)));
    }
    return _WritingBox(child: _laidOver(first));
  }

  /// [writing] in its place, in a box that is also where the writing's
  /// shape changes ([_WritingBox]).
  Widget _placed(Widget writing, {bool atOrigin = false}) => _WritingBox(
    padding: padding,
    alignment: alignment,
    atOrigin: atOrigin,
    child: writing,
  );

  /// The writing over a ground that changes under it: a layout builder over
  /// a moved canvas.
  Widget _laidOver(Color first) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // A writing with no width to measure has nowhere to put a boundary;
        // it takes the first ground's ink rather than a shader stretched to
        // infinity.
        if (!constraints.hasBoundedWidth) {
          return _placed(builder(context, TextStyle(color: first)));
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
        return _placed(
          builder(context, TextStyle(foreground: Paint()..shader = shader)),
          atOrigin: true,
        );
      },
    );
  }
}

/// Where the writing changes SHAPE — one ink, or a ground that changes under
/// it — so that the change is laid out here and nowhere above.
///
/// 🚨(2026-09-26) The two shapes are two element trees, and switching them
/// replaces the child, which marks its parent for layout. The bar's own
/// fixed-height box is not a relayout boundary (its height is fixed; the row
/// above it is not), so a bar whose fill crossed into or out of its words
/// laid out everything up to the row's first boundary — on a brush pick,
/// three bars flipped and laid the whole tool settings column out again,
/// each object laid out a semantics update too. Every bar hands its writing
/// tight constraints, and a box laid out under tight constraints IS a
/// relayout boundary: the switch lays out the writing and stops.
///
/// ↩️The first answer (8f2962aa6) gave the writing one shape instead — a
/// layout builder always — and that made every rebuild of a one-ink bar a
/// forced relayout, a repaint and a semantics update where there had been
/// none: a layout builder lays itself out again whenever it is rebuilt, and
/// a repaint inside a dock throws the dock's still image away. The shapes
/// are back as they were; this box is what keeps their switch local.
///
/// It is also the box right above the writing, so it stands the writing in
/// its place ([GroundInkWriting.padding], [GroundInkWriting.alignment]) —
/// laid out as a [Padding] round an [Align] lays it out. Over a ground that
/// changes under the writing it is two: the bare box the shapes switch in,
/// and the placing one inside the layout builder, which also moves the
/// canvas to its own top-left ([atOrigin]).
class _WritingBox extends SingleChildRenderObjectWidget {
  const _WritingBox({
    this.padding = EdgeInsets.zero,
    this.alignment,
    this.atOrigin = false,
    required super.child,
  });

  final EdgeInsets padding;
  final Alignment? alignment;

  /// Paint the writing with the canvas moved to this box's top-left, so a
  /// shader laid out in the box lands on the writing.
  ///
  /// ⚠️A text's foreground shader is read in CANVAS coordinates, and a
  /// render object is handed an offset into its layer rather than a moved
  /// canvas — so without this the gradient would start where the LAYER
  /// starts. A child that brings layers of its own cannot be moved this way;
  /// it is painted the ordinary way (in the right place, its ink off true)
  /// rather than wrongly.
  final bool atOrigin;

  @override
  _RenderWritingBox createRenderObject(BuildContext context) =>
      _RenderWritingBox(
        padding: padding,
        alignment: alignment,
        atOrigin: atOrigin,
      );

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderWritingBox renderObject,
  ) {
    renderObject
      ..padding = padding
      ..alignment = alignment
      ..atOrigin = atOrigin;
  }
}

class _RenderWritingBox extends RenderShiftedBox {
  _RenderWritingBox({
    required EdgeInsets padding,
    required Alignment? alignment,
    required bool atOrigin,
  }) : _padding = padding,
       _alignment = alignment,
       _atOrigin = atOrigin,
       super(null);

  EdgeInsets get padding => _padding;
  EdgeInsets _padding;
  set padding(EdgeInsets value) {
    if (_padding == value) {
      return;
    }
    _padding = value;
    markNeedsLayout();
  }

  Alignment? get alignment => _alignment;
  Alignment? _alignment;
  set alignment(Alignment? value) {
    if (_alignment == value) {
      return;
    }
    _alignment = value;
    markNeedsLayout();
  }

  bool get atOrigin => _atOrigin;
  bool _atOrigin;
  set atOrigin(bool value) {
    if (_atOrigin == value) {
      return;
    }
    _atOrigin = value;
    markNeedsPaint();
  }

  /// The box and where the child stands in it, under [constraints], with
  /// [layChild] laying the child out — a [Padding]'s answer round an
  /// [Align]'s, each as its own render object gives it.
  ({Size size, Offset childAt}) _place(
    BoxConstraints constraints,
    Size Function(RenderBox child, BoxConstraints constraints) layChild,
  ) {
    final inner = constraints.deflate(_padding);
    final child = this.child;
    var innerSize = Size.zero;
    var at = Offset.zero;
    if (_alignment case final alignment?) {
      final laid = child == null ? null : layChild(child, inner.loosen());
      innerSize = inner.constrain(
        Size(
          inner.maxWidth == double.infinity
              ? laid?.width ?? 0
              : double.infinity,
          inner.maxHeight == double.infinity
              ? laid?.height ?? 0
              : double.infinity,
        ),
      );
      if (laid != null) {
        at = alignment.alongOffset(innerSize - laid as Offset);
      }
    } else if (child != null) {
      innerSize = layChild(child, inner);
    }
    return (
      size: constraints.constrain(
        Size(
          _padding.horizontal + innerSize.width,
          _padding.vertical + innerSize.height,
        ),
      ),
      childAt: _padding.topLeft + at,
    );
  }

  @override
  void performLayout() {
    final placed = _place(constraints, (child, constraints) {
      child.layout(constraints, parentUsesSize: true);
      return child.size;
    });
    size = placed.size;
    if (child case final child?) {
      (child.parentData! as BoxParentData).offset = placed.childAt;
    }
  }

  @override
  Size computeDryLayout(covariant BoxConstraints constraints) => _place(
    constraints,
    (child, constraints) => child.getDryLayout(constraints),
  ).size;

  @override
  double? computeDryBaseline(
    covariant BoxConstraints constraints,
    TextBaseline baseline,
  ) {
    final child = this.child;
    if (child == null) {
      return null;
    }
    BoxConstraints? childConstraints;
    final placed = _place(constraints, (child, constraints) {
      childConstraints = constraints;
      return child.getDryLayout(constraints);
    });
    final distance = child.getDryBaseline(childConstraints!, baseline);
    return distance == null ? null : distance + placed.childAt.dy;
  }

  @override
  double computeMinIntrinsicWidth(double height) =>
      _padding.horizontal +
      (child?.getMinIntrinsicWidth(_innerHeight(height)) ?? 0);

  @override
  double computeMaxIntrinsicWidth(double height) =>
      _padding.horizontal +
      (child?.getMaxIntrinsicWidth(_innerHeight(height)) ?? 0);

  @override
  double computeMinIntrinsicHeight(double width) =>
      _padding.vertical +
      (child?.getMinIntrinsicHeight(_innerWidth(width)) ?? 0);

  @override
  double computeMaxIntrinsicHeight(double width) =>
      _padding.vertical +
      (child?.getMaxIntrinsicHeight(_innerWidth(width)) ?? 0);

  double _innerHeight(double height) =>
      math.max(0.0, height - _padding.vertical);

  double _innerWidth(double width) =>
      math.max(0.0, width - _padding.horizontal);

  @override
  void paint(PaintingContext context, Offset offset) {
    final child = this.child;
    if (!_atOrigin ||
        child == null ||
        child.needsCompositing ||
        child.isRepaintBoundary) {
      super.paint(context, offset);
      return;
    }
    final canvas = context.canvas;
    canvas.save();
    canvas.translate(offset.dx, offset.dy);
    context.paintChild(child, (child.parentData! as BoxParentData).offset);
    canvas.restore();
  }
}
