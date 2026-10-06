import 'dart:math' as math;
import 'dart:ui' show Offset, Rect;

import 'package:flutter/gestures.dart' show PointerDownEvent, computeHitSlop;
import 'package:flutter/services.dart' show TextSelection;

import '../../../models/bitmap_surface.dart';
import '../../../models/canvas_point.dart';
import '../../../models/cel_text.dart';
import '../../../services/cel_text_box_edits.dart';
import '../../../services/transform_box_law.dart';
import '../../text/cel_text_layout.dart';
import '../box_press.dart';
import 'cel_text_session.dart';
import 'cel_text_stage.dart';
import 'cel_text_tool.dart';

/// What a press on the text tool's layer works on: the hand, the stage it
/// is on, the cel under it — and what a press on nothing hands back, the
/// box it traces and the text it begins.
class CelTextScene {
  const CelTextScene({
    required this.tool,
    required this.stage,
    required this.cel,
    required this.onTraced,
    required this.onBegin,
  });

  final CelTextTool tool;
  final CelTextStage stage;

  /// The cel under the press — null for the press that ASKED for one: the
  /// cel it made is a frame away, and nothing of it is needed until the
  /// press comes up ([onBegin]).
  final CelTextCel? cel;

  /// The box an empty drag is tracing on the artwork — null once it has
  /// none.
  final void Function(Rect? box) onTraced;

  /// A press on nothing came up: a text begins at [anchor], as wide as
  /// [wrapWidth] or growing with what is typed — on the cel under the tool
  /// THEN, which for the press that made its cel is not [cel].
  final void Function(CanvasPoint anchor, {double? wrapWidth}) onBegin;
}

/// [cel]'s picture as it stands.
BitmapSurface _pictureOf(CelTextCel cel) =>
    cel.coordinator.currentSurfaceOf(cel.key);

/// THE PRESS TABLE (R9-rest, taken by 유저 on 2026-10-06): what a press at
/// [artwork] takes hold of, by what the tool has in hand. Null when the
/// press has done all it does by going down.
///
/// · NOTHING in hand: on a text → take it (a drag then moves it) · on
///   nothing → a text begins there when the press comes up, growing for a
///   click and as wide as the drag for a drag. ⚠️A frame with NO CEL is
///   that last case and no other law: the press asked for the cel, and is
///   the press on nothing it would have been with one (유저 2026-09-20:
///   the same code answers whatever is there — as a stroke's press on an
///   empty frame is still that stroke, `_BrushEditCelPress`).
/// · A text by its LETTERS: inside it → the caret, and dragged a selection
///   · on another text → confirm, take that one · on nothing → confirm and
///   let go.
/// · A text by its BOX — the one order every box on the canvas keeps
///   ([boxPressAt], F-222): a corner → scale · a side edge (a box only) →
///   its width · inside → move, or let go where it went down, its letters
///   · outside → another text if one is there, else the turn, or let go
///   where it went down.
CelTextPress? celTextPressAt(
  CelTextScene scene,
  PointerDownEvent event,
  Offset artwork,
) {
  final cel = scene.cel;
  if (cel == null) {
    return _EmptyPress(event, artwork);
  }
  final pressed = (scene: scene, cel: cel, event: event, artwork: artwork);
  final session = scene.tool.session;
  if (session == null) {
    return _takeOr(pressed, () => _EmptyPress(event, artwork));
  }
  return scene.tool.hold == CelTextHold.letters
      ? _pressWhileTyping(pressed, session)
      : _pressOnBox(pressed, session);
}

/// A press that went down on a cel: where, and on what.
typedef _Pressed = ({
  CelTextScene scene,
  CelTextCel cel,
  PointerDownEvent event,
  Offset artwork,
});

/// A press on another text takes it — a drag then moves it; with none
/// there, [otherwise].
CelTextPress? _takeOr(_Pressed pressed, CelTextPress? Function() otherwise) {
  final (:scene, :cel, :event, :artwork) = pressed;
  final other = _textAt(scene.tool, cel, artwork);
  if (other == null) {
    return otherwise();
  }
  scene.tool.takeText(cel, other);
  return _InsidePress(event, artwork, cel: cel, held: false);
}

CelTextPress? _pressWhileTyping(_Pressed pressed, CelTextSession session) {
  final scene = pressed.scene;
  final artwork = pressed.artwork;
  final layout = session.shown.layout;
  if (layout.boxContains(artwork)) {
    final at = layout.positionAt(artwork).offset;
    scene.tool.typeAt(TextSelection.collapsed(offset: at));
    return _LetterPress(pressed.event, base: at);
  }
  return _takeOr(pressed, () {
    scene.tool.confirm();
    return null;
  });
}

CelTextPress? _pressOnBox(_Pressed pressed, CelTextSession session) {
  final (:scene, :cel, :event, :artwork) = pressed;
  final layout = session.shown.layout;
  final hit = boxPressAt(
    event.localPosition,
    anchor: null,
    handles: [
      for (final handle in celTextHandlesOf(layout))
        scene.stage.onPanel(handle),
    ],
    inside: (at) {
      final point = scene.stage.artworkAt(at);
      return point != null && layout.boxContains(point);
    },
    onStage: scene.stage.onStage,
  );
  final centre = layout.toCanvas(layout.box.center);
  return switch (hit?.press) {
    BoxPress.handle when hit!.handle < _leftEdgeHandle => _ScalePress(
      event,
      start: session.content,
      centre: centre,
      reach: _reachOf(scene, event.localPosition, centre),
    ),
    BoxPress.handle => _WidthPress(
      event,
      artwork,
      start: session.content,
      byLeftEdge: hit!.handle == _leftEdgeHandle,
    ),
    BoxPress.inside => _InsidePress(event, artwork, cel: cel, held: true),
    // Outside the box: another text if one is there. Else on stage it is
    // the turn — and off it nothing to turn about, so the press lets go.
    BoxPress.anchor || BoxPress.turn || null => _takeOr(pressed, () {
      if (hit == null) {
        scene.tool.confirm();
        return null;
      }
      return _TurnPress(
        event,
        artwork,
        start: session.content,
        centre: centre,
      );
    }),
  };
}

/// How far [local] is from [centre] on the panel — never zero: a press on
/// the centre itself would make every ratio endless.
double _reachOf(CelTextScene scene, Offset local, Offset centre) =>
    math.max((local - scene.stage.onPanel(centre)).distance, 0.001);

/// The topmost text of [cel] whose box [artwork] is in — the newest is on
/// top (유저 2026-10-02) — leaving out the one in [tool]'s hand.
CelText? _textAt(CelTextTool tool, CelTextCel cel, Offset artwork) {
  final inHand = tool.session?.textId;
  for (final text in _pictureOf(cel).texts.reversed) {
    if (text.id == inHand) {
      continue;
    }
    final layout = layoutCelText(text.content);
    final inside = layout.boxContains(artwork);
    layout.dispose();
    if (inside) {
      return text;
    }
  }
  return null;
}

/// The side edges' handles follow the four corners in [celTextHandlesOf].
const int _leftEdgeHandle = 4;

/// Where a text held by its box can be taken, on the artwork: its four
/// corners — the scale — and, for a box, the middle of its two side edges:
/// its width. The chrome draws these and a press is asked of them, so what
/// is seen is what is grabbed.
List<Offset> celTextHandlesOf(CelTextLayout layout) {
  final corners = layout.boxCorners;
  return [
    ...corners,
    if (layout.content.wrapWidth != null) ...[
      (corners[0] + corners[3]) / 2,
      (corners[1] + corners[2]) / 2,
    ],
  ];
}

/// A press the layer is following: which pointer, where it went down on
/// the panel, whether it has travelled far enough to be a drag — and what
/// it does as the hand moves, comes up, or goes away.
sealed class CelTextPress {
  CelTextPress(PointerDownEvent event)
    : pointer = event.pointer,
      down = event.localPosition,
      _slop = computeHitSlop(event.kind, null);

  final int pointer;
  final Offset down;

  /// How far a press may wander and still be a click — the device's own
  /// (`computeHitSlop`): a pen never comes up exactly where it went down.
  final double _slop;

  /// Whether the press has left where it went down. It does not go back: a
  /// drag that returns is still a drag.
  bool dragged = false;

  /// The hand is at [local] on the panel — [artwork] on the cel.
  void moveTo(CelTextScene scene, Offset local, Offset artwork) {
    if ((local - down).distance > _slop) {
      dragged = true;
    }
    _move(scene, local, artwork);
  }

  void _move(CelTextScene scene, Offset local, Offset artwork);

  /// The hand came up at [local].
  void up(CelTextScene scene, Offset local);

  /// The press went away with nothing to keep: what it was showing goes
  /// back to where it began.
  void cancel(CelTextScene scene) {}
}

/// On the letters of the text in hand: the caret, and dragged, a selection
/// from [base].
final class _LetterPress extends CelTextPress {
  _LetterPress(super.event, {required this.base});

  final int base;

  @override
  void _move(CelTextScene scene, Offset local, Offset artwork) {
    final session = scene.tool.session;
    if (session == null || !dragged) {
      return;
    }
    scene.tool.typeAt(
      TextSelection(
        baseOffset: base,
        extentOffset: session.shown.layout.positionAt(artwork).offset,
      ),
    );
  }

  @override
  void up(CelTextScene scene, Offset local) {}
}

/// Inside a text's box: dragged, it moves — in whole pixels, as a hand on
/// the canvas does (09-22); let go where it went down on a text that was
/// [held] before the press, it opens the letters there.
final class _InsidePress extends CelTextPress {
  _InsidePress(
    super.event,
    this.artwork, {
    required this.cel,
    required this.held,
  });

  final Offset artwork;

  /// The cel the text is on: its picture is the grid a moved plate is cut
  /// on.
  final CelTextCel cel;
  final bool held;

  /// The text as it stood when the drag began — null until it is one.
  CelTextMoveOrigin? _origin;

  @override
  void _move(CelTextScene scene, Offset local, Offset artwork) {
    final session = scene.tool.session;
    if (session == null || !dragged) {
      return;
    }
    final travel = TransformBoxLaw.wholePixels(
      CanvasPoint(
        x: artwork.dx - this.artwork.dx,
        y: artwork.dy - this.artwork.dy,
      ),
    );
    session.showMoved(
      _origin ??= session.moveOrigin,
      _pictureOf(cel),
      dx: travel.x.toInt(),
      dy: travel.y.toInt(),
    );
  }

  @override
  void up(CelTextScene scene, Offset local) {
    final session = scene.tool.session;
    if (_origin != null) {
      scene.tool.landEdit();
    } else if (held && session != null) {
      scene.tool.typeAt(
        TextSelection.collapsed(
          offset: session.shown.layout.positionAt(artwork).offset,
        ),
      );
    }
  }

  @override
  void cancel(CelTextScene scene) {
    final origin = _origin;
    if (origin != null) {
      scene.tool.session?.showMoved(origin, _pictureOf(cel), dx: 0, dy: 0);
      scene.tool.landEdit();
    }
  }
}

/// A press that shows the text set differently as the hand moves and lands
/// it when the hand comes up — the scale, the width and the turn.
sealed class _BoxEditPress extends CelTextPress {
  _BoxEditPress(super.event, {required this.start});

  /// The text as it stood when the press went down.
  final CelTextContent start;

  @override
  void up(CelTextScene scene, Offset local) => scene.tool.landEdit();

  @override
  void cancel(CelTextScene scene) => scene.tool
    ..showEdit(start)
    ..landEdit();
}

/// On a corner: the text scales about [centre], by how far the hand is
/// from it against how far it was ([reach]) — distance from the centre
/// scales with the box, so the ratio IS the scale, as a row's box reads its
/// corner.
final class _ScalePress extends _BoxEditPress {
  _ScalePress(
    super.event, {
    required super.start,
    required this.centre,
    required this.reach,
  });

  final Offset centre;
  final double reach;

  @override
  void _move(CelTextScene scene, Offset local, Offset artwork) =>
      scene.tool.showEdit(
        celTextScaledAbout(
          start,
          _reachOf(scene, local, centre) / reach,
          CanvasPoint(x: centre.dx, y: centre.dy),
        ),
      );
}

/// On a side edge of a box: its width, in whole pixels, by how far the hand
/// has gone along the text's own line.
final class _WidthPress extends _BoxEditPress {
  _WidthPress(
    super.event,
    this.artwork, {
    required super.start,
    required this.byLeftEdge,
  });

  final Offset artwork;
  final bool byLeftEdge;

  @override
  void _move(CelTextScene scene, Offset local, Offset artwork) {
    final radians = start.rotationDegrees * math.pi / 180;
    final along =
        (artwork.dx - this.artwork.dx) * math.cos(radians) +
        (artwork.dy - this.artwork.dy) * math.sin(radians);
    final width = start.wrapWidth!;
    scene.tool.showEdit(
      celTextBoxWidened(
        start,
        (byLeftEdge ? width - along : width + along).roundToDouble(),
        byLeftEdge: byLeftEdge,
      ),
    );
  }
}

/// Outside the box, on stage: dragged, the text turns about [centre]; let
/// go where it went down, the tool lets go of the text.
final class _TurnPress extends _BoxEditPress {
  _TurnPress(
    super.event,
    Offset artwork, {
    required super.start,
    required Offset centre,
  }) : _centre = CanvasPoint(x: centre.dx, y: centre.dy) {
    _angle = TransformBoxLaw.angleAbout(
      _centre,
      CanvasPoint(x: artwork.dx, y: artwork.dy),
    );
  }

  final CanvasPoint _centre;

  /// The hand's angle about the centre at the last move, and the turn so
  /// far ([TransformBoxLaw.turn] — canvas angles, folded at the seam).
  late double _angle;
  double _turned = 0;

  @override
  void _move(CelTextScene scene, Offset local, Offset artwork) {
    if (!dragged) {
      return;
    }
    final step = TransformBoxLaw.turn(
      centre: _centre,
      pointer: CanvasPoint(x: artwork.dx, y: artwork.dy),
      lastAngle: _angle,
    );
    _angle = step.angle;
    _turned += step.turned;
    scene.tool.showEdit(celTextTurnedAbout(start, _turned, _centre));
  }

  @override
  void up(CelTextScene scene, Offset local) {
    if (dragged) {
      scene.tool.landEdit();
    } else {
      scene.tool.confirm();
    }
  }
}

/// On nothing: let go where it went down, a text that grows; dragged, a
/// box as wide as the drag.
final class _EmptyPress extends CelTextPress {
  _EmptyPress(super.event, this.artwork);

  final Offset artwork;

  @override
  void _move(CelTextScene scene, Offset local, Offset artwork) {
    if (dragged) {
      scene.onTraced(Rect.fromPoints(this.artwork, artwork));
    }
  }

  @override
  void up(CelTextScene scene, Offset local) {
    final traced = _tracedTo(scene.stage.artworkAt(local));
    if (traced == null) {
      scene.onBegin(celTextWholePixel(artwork));
      return;
    }
    scene.onBegin(
      celTextWholePixel(traced.topLeft),
      wrapWidth: math.max(traced.width.roundToDouble(), celTextMinWrapWidth),
    );
  }

  /// The box traced by the time the press came up at [artwork] — null for a
  /// click, or a drag too small to have meant a box (both sides under two
  /// pixels: the marquee's own rule, `MarqueeDrag.shape`).
  Rect? _tracedTo(Offset? artwork) {
    if (!dragged || artwork == null) {
      return null;
    }
    final traced = Rect.fromPoints(this.artwork, artwork);
    return traced.width < 2 && traced.height < 2 ? null : traced;
  }
}

/// A text is set on whole pixels, as a hand on the canvas moves in them.
CanvasPoint celTextWholePixel(Offset artwork) => CanvasPoint(
  x: artwork.dx.roundToDouble(),
  y: artwork.dy.roundToDouble(),
);
