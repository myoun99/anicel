import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../theme/app_theme.dart' show AppCursors, AppShapes;
import 'icon_button_box.dart';

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

  /// The face's shape, its side the edge — none is a clear face, its hover
  /// filling the shape.
  final RoundedSuperellipseBorder edge;

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
  RoundedSuperellipseBorder edge,
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
    _layer.paint(
      context.canvas,
      _look.margin.deflateRect(offset & size),
      iconButtonLayerOf(_look.edge, _inside, ground: _look.ground),
      _look.textDirection,
    );
    super.paint(context, offset);
  }

  @override
  void dispose() {
    _layer.dispose();
    super.dispose();
  }
}
