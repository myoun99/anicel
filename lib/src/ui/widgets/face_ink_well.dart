import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../theme/app_theme.dart' show AppCursors, AppShapes, SuperellipseFace;
import 'icon_button_box.dart';
import 'superellipse_clip.dart' show SuperellipseCut;

/// AN [InkWell] WHOSE HOVER AND FOCUS ARE ITS FACE'S INSIDE — [edge] filled
/// with [fill] over the ground it stands on ([FaceGround]), the hover and
/// the focus over that, the edge drawn by fills ([iconButtonLayerOf]), as a
/// rail's plate draws itself (`RailPlateButton`). The well keeps the tap,
/// the double tap, the cursor, the focus and the semantics, and lays no
/// ink.
///
/// 🗣️a-live-dock-frame-costs-a-whole-draw-Q12 (유저 2026-11-08, 2: 「호버 ·
/// 포커스를 테두리 안쪽 채움의 색으로 그리고, 넷도 채우기 둘로」).
/// ↩️Each was a [Material] and an [InkWell] whose hover was ink on the ground
/// behind a stroked edge — and hidden where the inside was filled.
///
/// ⚠️The hover shows at once, as the icon buttons' does; the well's ink faded
/// in over 50 ms (the card's cost, answered).
class FaceInkWell extends StatefulWidget {
  const FaceInkWell({
    super.key,
    required this.edge,
    this.fill,
    this.margin = EdgeInsets.zero,
    required this.onTap,
    this.onDoubleTap,
    required this.child,
  });

  /// A well with no face of its own: its hover, its focus and its [fill]
  /// are its share of the [SharedFace] it stands in — that face's inside,
  /// cut by the well's box.
  const FaceInkWell.share({
    super.key,
    this.fill,
    required this.onTap,
    required this.child,
  }) : edge = null,
       margin = EdgeInsets.zero,
       onDoubleTap = null;

  /// The face's shape, its side the edge — none is a clear face, its hover
  /// filling the shape; null is a share ([FaceInkWell.share]).
  final RoundedSuperellipseBorder? edge;

  /// The face's own colour over its ground — a chosen cell's — or null.
  final Color? fill;

  /// How far inside the well the face stands: the well is the press's, the
  /// face the eye's.
  final EdgeInsets margin;

  /// [InkWell.onTap] — null is a dead well, which shows no hover.
  final VoidCallback? onTap;

  /// [InkWell.onDoubleTap].
  final VoidCallback? onDoubleTap;

  final Widget child;

  @override
  State<FaceInkWell> createState() => _FaceInkWellState();
}

class _FaceInkWellState extends State<FaceInkWell> {
  final _states = WidgetStatesController();

  @override
  void dispose() {
    _states.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final margin = widget.margin;
    return InkWell(
      mouseCursor: AppCursors.press,
      onTap: widget.onTap,
      onDoubleTap: widget.onDoubleTap,
      statesController: _states,
      overlayColor: const WidgetStatePropertyAll(Colors.transparent),
      child: _InkFace(
        look: (
          states: _states,
          edge: widget.edge,
          fill: widget.fill,
          ground: FaceGround.of(context),
          hoverInk: theme.hoverColor,
          focusInk: theme.focusColor,
          margin: margin,
          textDirection: Directionality.of(context),
        ),
        child: margin == EdgeInsets.zero
            ? widget.child
            : Padding(padding: margin, child: widget.child),
      ),
    );
  }
}

/// A CHOSEN CELL'S FACE — a grid's or a rail's ([FaceInkWell]): while
/// [selected], its edge the primary colour and half a pixel thicker over a
/// fill; while not, the outline's colour around nothing. Selection reads
/// from the border colour, not a glyph, which would shift the grid.
({RoundedSuperellipseBorder edge, Color? fill}) chosenCellFace(
  ColorScheme colorScheme, {
  required bool selected,
}) => (
  edge: AppShapes.container(
    AppShapes.wellRadius,
    side: BorderSide(
      color: selected ? colorScheme.primary : colorScheme.outlineVariant,
      width: selected ? 1.5 : 1,
    ),
  ),
  fill: selected ? colorScheme.surfaceContainerHigh : null,
);

/// Everything an [_InkFace] paints with.
typedef _Look = ({
  WidgetStatesController states,
  RoundedSuperellipseBorder? edge,
  Color? fill,
  Color? ground,
  Color hoverInk,
  Color focusInk,
  EdgeInsets margin,
  TextDirection textDirection,
});

class _InkFace extends SingleChildRenderObjectWidget {
  const _InkFace({required this.look, required Widget super.child});

  final _Look look;

  @override
  _RenderInkFace createRenderObject(BuildContext context) =>
      _RenderInkFace(look);

  @override
  void updateRenderObject(BuildContext context, _RenderInkFace renderObject) {
    renderObject.look = look;
  }
}

class _RenderInkFace extends RenderProxyBox {
  _RenderInkFace(this._look);

  _Look _look;
  _Look get look => _look;
  set look(_Look value) {
    if (value == _look) {
      return;
    }
    if (attached && value.states != _look.states) {
      _look.states.removeListener(markNeedsPaint);
      value.states.addListener(markNeedsPaint);
    }
    _look = value;
    markNeedsPaint();
  }

  late final IconButtonLayer _layer = IconButtonLayer(markNeedsPaint);

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _look.states.addListener(markNeedsPaint);
    FocusManager.instance.addHighlightModeListener(_highlightModeChanged);
  }

  @override
  void detach() {
    _look.states.removeListener(markNeedsPaint);
    FocusManager.instance.removeHighlightModeListener(_highlightModeChanged);
    super.detach();
  }

  void _highlightModeChanged(FocusHighlightMode mode) {
    if (_look.states.value.contains(WidgetState.focused)) {
      markNeedsPaint();
    }
  }

  /// The well's highlights where it shows them — the focus for KEYBOARD
  /// focus only, as `InkResponse.updateFocusHighlights` gates it — over the
  /// face's own fill.
  Color? get _inside {
    final states = _look.states.value;
    final live = !states.contains(WidgetState.disabled);
    final overlay = inkWellOverlay(
      focus:
          live &&
              states.contains(WidgetState.focused) &&
              FocusManager.instance.highlightMode ==
                  FocusHighlightMode.traditional
          ? _look.focusInk
          : null,
      hover: live && states.contains(WidgetState.hovered)
          ? _look.hoverInk
          : null,
    );
    return switch ((overlay, _look.fill)) {
      (final overlay?, final fill?) => Color.alphaBlend(overlay, fill),
      (final overlay, final fill) => overlay ?? fill,
    };
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final face = _look.margin.deflateRect(offset & size);
    switch (_look.edge) {
      case final edge?:
        _layer.paint(
          context.canvas,
          face,
          iconButtonLayerOf(edge, _inside, ground: _look.ground),
          _look.textDirection,
        );
      case null:
        _paintShare(context.canvas, offset, face);
    }
    super.paint(context, offset);
  }

  /// Its share of the [SharedFace] it stands in: that face's inside where
  /// [face] lies, filled with [_inside].
  void _paintShare(Canvas canvas, Offset offset, Rect face) {
    final inside = _inside;
    final shared = _sharedFace;
    assert(shared != null, 'a FaceInkWell.share stands in a SharedFace');
    if (inside == null || shared == null) {
      return;
    }
    final at = localToGlobal(Offset.zero, ancestor: shared);
    canvas.drawRSuperellipseCut(
      shared.inside.shift(offset - at),
      face,
      Paint()..color = inside,
    );
  }

  RenderSharedFace? get _sharedFace {
    for (var at = parent; at != null; at = at.parent) {
      if (at is RenderSharedFace) {
        return at;
      }
    }
    return null;
  }

  @override
  void dispose() {
    _layer.dispose();
    super.dispose();
  }
}

/// A FACE SEVERAL WELLS SHARE — a strip of pills (`PillStrip`): [edge]
/// filled with [fill] over the ground it stands on, its edge by fills, as a
/// well's own face is ([iconButtonLayerOf]). A well inside it with no face
/// of its own ([FaceInkWell.share]) shows its hover, its focus and its fill
/// as its share of the inside — the inside cut by the well's box
/// ([SuperellipseCut.drawRSuperellipseCut]).
///
/// 🗣️a-live-dock-frame-costs-a-whole-draw-Q12 (유저 2026-11-08, 2: 「호버 ·
/// 포커스를 테두리 안쪽 채움의 색으로 그리고, 넷도 채우기 둘로」).
/// ↩️A strip was clipped to its shape, its pills' hover ink on the Material
/// behind it — where an even strip's opaque frame hid it
/// (an-even-pill-strip-hides-its-hover).
class SharedFace extends SingleChildRenderObjectWidget {
  const SharedFace({
    super.key,
    required this.edge,
    this.fill,
    required Widget super.child,
  });

  /// The face's shape, its side the edge.
  final RoundedSuperellipseBorder edge;

  /// The face's own colour over its ground, or null.
  final Color? fill;

  @override
  RenderSharedFace createRenderObject(BuildContext context) =>
      RenderSharedFace(_faceIn(context));

  @override
  void updateRenderObject(
    BuildContext context,
    RenderSharedFace renderObject,
  ) {
    renderObject.face = _faceIn(context);
  }

  SharedFaceLook _faceIn(BuildContext context) => (
    edge: edge,
    fill: fill,
    ground: FaceGround.of(context),
    textDirection: Directionality.of(context),
  );
}

/// Everything a [SharedFace] paints with.
typedef SharedFaceLook = ({
  RoundedSuperellipseBorder edge,
  Color? fill,
  Color? ground,
  TextDirection textDirection,
});

/// What paints a [SharedFace] — and what its shares find above them.
class RenderSharedFace extends RenderProxyBox {
  RenderSharedFace(this._face);

  SharedFaceLook _face;
  SharedFaceLook get face => _face;
  set face(SharedFaceLook value) {
    if (value == _face) {
      return;
    }
    _face = value;
    markNeedsPaint();
  }

  late final IconButtonLayer _layer = IconButtonLayer(markNeedsPaint);

  /// Its inside where it lies — what its wells' shares are cut from: the
  /// shape its edge's width in, as its face fills it ([SuperellipseFace]).
  RSuperellipse get inside => _face.edge.borderRadius
      .resolve(_face.textDirection)
      .toRSuperellipse(Offset.zero & size)
      .deflate(_face.edge.side.width);

  @override
  void paint(PaintingContext context, Offset offset) {
    _layer.paint(
      context.canvas,
      offset & size,
      iconButtonLayerOf(_face.edge, _face.fill, ground: _face.ground),
      _face.textDirection,
    );
    super.paint(context, offset);
  }

  @override
  void dispose() {
    _layer.dispose();
    super.dispose();
  }
}
