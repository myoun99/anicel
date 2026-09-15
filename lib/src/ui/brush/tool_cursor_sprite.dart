import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import 'tool_cursor_look.dart';

/// A tool cursor, drawn by the app and moved by the app — the same law on
/// every platform (유저, F-130, 2026-09-15: 「앱 커서만 최대한 가볍게」; the
/// OS pointer hides while a tool cursor is up).
///
/// 🚀★It is a SMALL LAYER THAT MOVES, not a panel-sized one that repaints
/// (유저, R3 #13: 브러시툴이나 지우개툴선택된상황에서 커서가 매우느림). It
/// began as a `Positioned.fill` CustomPaint whose painter took the pointer
/// position, so every hover event re-rastered a repaint boundary the size
/// of the whole canvas to move an ellipse a few pixels. The next shape made
/// the box the footprint and the POSITION its layout: a `Positioned` inside
/// a Stack of its own, re-offsetting a cached layer. That still cost a
/// widget rebuild, a Stack relayout and a re-record of everything between
/// the shell boundary and the deck, once per pointer event (F-130 measured
/// it: three widgets, two relayouts, 84 layers re-added, every move).
///
/// 🚨★★★F-130 takes the last step: the position is not even LAYOUT now.
/// This render object listens to the aim itself and moves its own inner
/// layer's offset — no build, no layout, no paint; the frame it asks for
/// is compositing only, which is as light as a drawn cursor gets. The
/// picture is recorded again only when the LOOK changes (a size, a zoom)
/// or when the cursor appears or vanishes.
///
/// ⚠️R3 #8's oracle (선택툴 누르고 다른 툴 누르면 커서가 사라짐) used to be
/// `find.byKey(...)` answering `findsNothing` before the pointer had been
/// anywhere, kept alive by returning `SizedBox.shrink()` while the aim was
/// null. The sprite is mounted whenever its tool is armed and simply shows
/// nothing until there is an aim — the oracle is [RenderToolCursorSprite.debugPosition]
/// now, null for the same reason `findsNothing` used to be.
class ToolCursorSprite extends LeafRenderObjectWidget {
  const ToolCursorSprite({
    super.key,
    required this.position,
    required this.look,
  });

  /// The aim, in the sprite's own (panel-local) coordinates; null while
  /// nothing is aimed.
  final ValueListenable<Offset?> position;

  final ToolCursorLook look;

  @override
  RenderToolCursorSprite createRenderObject(BuildContext context) =>
      RenderToolCursorSprite(position: position, look: look);

  @override
  void updateRenderObject(
    BuildContext context,
    RenderToolCursorSprite renderObject,
  ) {
    renderObject
      ..position = position
      ..look = look;
  }
}

/// The render object behind [ToolCursorSprite]: a repaint boundary whose
/// one child layer holds the look's picture and moves by offset.
class RenderToolCursorSprite extends RenderBox {
  RenderToolCursorSprite({
    required ValueListenable<Offset?> position,
    required ToolCursorLook look,
  }) : _position = position,
       _look = look;

  /// The moving layer. A handle keeps it alive across the boundary's own
  /// repaints, which drop every child layer before painting again.
  final LayerHandle<OffsetLayer> _sprite = LayerHandle<OffsetLayer>(
    OffsetLayer(),
  );

  ValueListenable<Offset?> _position;
  ValueListenable<Offset?> get position => _position;
  set position(ValueListenable<Offset?> value) {
    if (identical(value, _position)) {
      return;
    }
    if (attached) {
      _position.removeListener(_aimMoved);
      value.addListener(_aimMoved);
    }
    _position = value;
    markNeedsPaint();
  }

  ToolCursorLook _look;
  ToolCursorLook get look => _look;
  set look(ToolCursorLook value) {
    final old = _look;
    if (identical(old, value)) {
      return;
    }
    _look = value;
    if (attached) {
      old.painter.removeListener(markNeedsPaint);
      value.painter.addListener(markNeedsPaint);
    }
    // The same rule `RenderCustomPaint` applies to a swapped painter, plus
    // the box and the hot spot, which the picture and its offset depend on.
    if (old.painter.runtimeType != value.painter.runtimeType ||
        value.painter.shouldRepaint(old.painter) ||
        old.extent != value.extent ||
        old.hotspot != value.hotspot) {
      markNeedsPaint();
    }
  }

  /// Where the sprite is shown — the aim it last painted or moved to — or
  /// null while it shows nothing. The R3 #8 oracle.
  Offset? get debugPosition => _shownAt;
  Offset? _shownAt;

  /// The paint offset the boundary was last painted at, so a move between
  /// paints places the layer against the same origin.
  Offset _paintOffset = Offset.zero;

  @override
  bool get isRepaintBoundary => true;

  @override
  bool get alwaysNeedsCompositing => true;

  @override
  bool get sizedByParent => true;

  @override
  Size computeDryLayout(BoxConstraints constraints) => constraints.biggest;

  /// Never a hit: the cursor is drawn over the canvas and takes nothing
  /// from it.
  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) => false;

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _position.addListener(_aimMoved);
    _look.painter.addListener(markNeedsPaint);
  }

  @override
  void detach() {
    _position.removeListener(_aimMoved);
    _look.painter.removeListener(markNeedsPaint);
    super.detach();
  }

  @override
  void dispose() {
    _sprite.layer = null;
    super.dispose();
  }

  /// The aim moved. Appearing and vanishing change the picture, so they
  /// paint; a move between two aims is an offset on the layer and a
  /// compositing-only frame.
  void _aimMoved() {
    final at = _position.value;
    if (at == null || _shownAt == null) {
      markNeedsPaint();
      return;
    }
    _shownAt = at;
    _sprite.layer!.offset = _paintOffset + at - _look.hotspot;
    markNeedsCompositedLayerUpdate();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    _paintOffset = offset;
    final at = _position.value;
    _shownAt = at;
    if (at == null) {
      return;
    }
    final sprite = _sprite.layer!;
    sprite.offset = offset + at - _look.hotspot;
    context.pushLayer(
      sprite,
      _paintLook,
      Offset.zero,
      childPaintBounds: Offset.zero & _look.extent,
    );
  }

  void _paintLook(PaintingContext context, Offset offset) {
    _look.painter.paint(context.canvas, _look.extent);
  }
}
