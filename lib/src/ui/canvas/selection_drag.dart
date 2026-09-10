import 'dart:ui' show Offset;

import '../../models/canvas_point.dart';
import '../../models/canvas_shape_kind.dart';
import '../../services/canvas_selection.dart';
import '../../services/canvas_selection_region.dart';

/// ONE in-flight selection drag, as its own object — begun by CONSTRUCTING
/// it, closed by exactly one of a commit or a cancel, then discarded.
///
/// The lifecycle is [EditorDragSession]'s, stated there for the timeline
/// families (`lib/src/ui/session/drags/editor_drag_session.dart`) and
/// signed up to here without implementing that interface: its update
/// surface is one scalar and a canvas drag's is a point, so pretending
/// otherwise would lie about the family — the same reason `RowOrderDrag`
/// gives.
///
/// ⛔ONE FIELD ANSWERS "IS A DRAG LIVE", and this type is it. The layer used
/// to hold three spellings of that one question — a `_DragMode` enum, an
/// `_activePointer`, and the mode's own mid-gesture fields, all cleared in
/// one place and settable from six. A sealed hierarchy makes the disagreement
/// unrepresentable: the mode IS the runtime type, the pointer rides on the
/// object, and dropping the object is the only way to end a drag
/// ([[make-the-invariant-unrepresentable]]).
///
/// ⚠️Mid-gesture state that outlives the gesture is the defect this shape
/// removes, so a subtype holds ONLY what dies with the drag. What survives a
/// release — the committed region, the lift session, the open transform box
/// — stays on the layer.
sealed class SelectionDrag {
  SelectionDrag({required this.pointer});

  /// The pointer this drag belongs to. A move or an up carrying any other
  /// pointer is not this drag's, and a second TOUCH is the navigate signal.
  final int pointer;
}

/// The marquee/lasso drag: the tools that TRACE a new outline.
///
/// Rect, ellipse and lasso are one drag with one geometry rule — the shape
/// kind picks which corner-or-path reading of the same two-point/one-path
/// state it is. The polygon is NOT here: it has no drag verb at all
/// ([VertexTapDrag]).
final class MarqueeDrag extends SelectionDrag {
  MarqueeDrag({
    required super.pointer,
    required this.shapeKind,
    required this.before,
    required CanvasPoint at,
  }) : start = at,
       _current = at,
       _traced = tracesPointerPath(shapeKind) ? [at] : const [];

  /// Which outline this drag traces — fixed at the press, because the tool
  /// setting must not change what a gesture already started drawing.
  final CanvasShapeKind shapeKind;

  /// The committed region as it stood when this drag started — the undo
  /// record's BEFORE, and what a CANCELLED drag puts back.
  ///
  /// Null for the verbs that never touch the region (cut, shape fill): the
  /// drag leaves it alone, so a cancel has nothing to put back.
  final CanvasSelectionRegion? before;

  /// Where the drag went down, in canvas space.
  final CanvasPoint start;

  CanvasPoint _current;
  List<CanvasPoint> _traced;

  /// Whether the active shape IS the pointer's path (points accumulate as
  /// the drag runs) rather than being derived from its two corners.
  ///
  /// Exhaustive on purpose: a new [CanvasShapeKind] fails to compile here
  /// until it has said which kind of drag it is.
  static bool tracesPointerPath(CanvasShapeKind kind) => switch (kind) {
    CanvasShapeKind.rect => false,
    CanvasShapeKind.ellipse => false,
    CanvasShapeKind.lasso => true,
    CanvasShapeKind.polygon => false,
  };

  void update(CanvasPoint at) {
    _current = at;
    if (tracesPointerPath(shapeKind)) {
      _traced = [..._traced, at];
    }
  }

  /// The path traced so far, for the ants to draw while the drag runs.
  /// Empty for the shapes that are read from their corners instead.
  List<CanvasPoint> get openTrail => _traced;

  /// The in-progress or final marquee polygon; null while degenerate.
  ///
  /// This is the one place a shape kind turns into geometry — every other
  /// site asks a predicate rather than branching on the kind itself.
  CanvasSelectionShape? shape() {
    switch (shapeKind) {
      case CanvasShapeKind.lasso:
        if (_traced.length < 3) {
          return null;
        }
        return CanvasSelectionShape(_traced);
      case CanvasShapeKind.polygon:
        // Tapped out, not dragged: its outline is the channel's open trace
        // and it is built when the trace CLOSES, not while a drag runs.
        return null;
      case CanvasShapeKind.rect:
      case CanvasShapeKind.ellipse:
        // A click (or a drag too small to have meant one) is degenerate for
        // both box shapes — an ellipse in a 1px box is not a thinner
        // ellipse, it is nothing.
        if ((_current.x - start.x).abs() < 2 &&
            (_current.y - start.y).abs() < 2) {
          return null;
        }
        return shapeKind == CanvasShapeKind.ellipse
            ? CanvasSelectionShape.ellipse(
                left: start.x,
                top: start.y,
                right: _current.x,
                bottom: _current.y,
              )
            : CanvasSelectionShape.rect(
                left: start.x,
                top: start.y,
                right: _current.x,
                bottom: _current.y,
              );
    }
  }
}

/// The MOVE tool's drag: the selected pixels follow the hand.
///
/// Its whole mid-gesture state is the screen-space delta. What is being
/// carried — the lift token, the floating stamp — belongs to the move
/// SESSION, which outlives every drag in it until the confirm (R16-①), and
/// so stays on the layer.
final class MoveDrag extends SelectionDrag {
  MoveDrag({required super.pointer});

  /// The drag so far, in screen pixels. The layer rounds it into whole
  /// canvas pixels before anything is shown or landed (TP5).
  Offset screenDelta = Offset.zero;
}

/// Which part of the Ctrl+T box a drag grabbed.
enum TransformHandle {
  topLeft,
  topRight,
  bottomRight,
  bottomLeft,
  topEdge,
  rightEdge,
  bottomEdge,
  leftEdge,
  rotate,
  inside,
}

/// The grabbed handle's BASE-LOCAL coordinates (relative to the base box
/// center = the affine pivot); null for rotate/inside.
CanvasPoint? handleLocal(TransformHandle handle, double w, double h) {
  switch (handle) {
    case TransformHandle.topLeft:
      return CanvasPoint(x: -w / 2, y: -h / 2);
    case TransformHandle.topRight:
      return CanvasPoint(x: w / 2, y: -h / 2);
    case TransformHandle.bottomRight:
      return CanvasPoint(x: w / 2, y: h / 2);
    case TransformHandle.bottomLeft:
      return CanvasPoint(x: -w / 2, y: h / 2);
    case TransformHandle.topEdge:
      return CanvasPoint(x: 0, y: -h / 2);
    case TransformHandle.rightEdge:
      return CanvasPoint(x: w / 2, y: 0);
    case TransformHandle.bottomEdge:
      return CanvasPoint(x: 0, y: h / 2);
    case TransformHandle.leftEdge:
      return CanvasPoint(x: -w / 2, y: 0);
    case TransformHandle.rotate:
    case TransformHandle.inside:
      return null;
  }
}

/// A drag on the Ctrl+T box — a scale/rotate handle, a 퍼스 corner, a 메쉬
/// control point, or the inside.
///
/// The box itself is NOT here: it survives the release (Enter/Escape close
/// it), so the affine, the base box and the warp offsets stay on the layer.
///
/// ⛔WHAT THE PRESS GRABBED IS ONE OF EXACTLY TWO THINGS, so it is two
/// subtypes and not five nullable fields the press had to set in an
/// agreeing pattern. Every begin site set the pointer plus EITHER the warp
/// points and their start offsets OR the handle and its start affine, and
/// nothing but the shape of that code said the two never mix.
sealed class TransformDrag extends SelectionDrag {
  TransformDrag({required super.pointer, required this.startPointer});

  /// Where the drag went down, in canvas space — every branch measures its
  /// displacement from here.
  final CanvasPoint startPointer;
}

/// A control-point drag — one corner in 퍼스, one grid point in 메쉬, or the
/// two corners 퍼스's edge handle carries together (F-42, 유저 2026-08-29).
final class WarpPointDrag extends TransformDrag {
  WarpPointDrag({
    required super.pointer,
    required super.startPointer,
    required this.points,
    required this.startOffsets,
  });

  /// WHICH control points this drag carries — one index for a corner or a
  /// mesh point, TWO for 퍼스's edge handle, which moves the edge's pair
  /// together (F-42, 유저 2026-08-29).
  ///
  /// ⛔A LIST RATHER THAN A SECOND FIELD. An `int? warpDragCorner` beside
  /// a `warpDragEdge` would be two fields answering one question — "what
  /// moves?" — and the day they disagreed the drag would move a corner AND
  /// an edge ([[make-the-invariant-unrepresentable]]).
  ///
  /// ⚠️NULL IS REACHABLE and means something: the press landed INSIDE the
  /// mesh boundary but not on a point. It carried no point before this
  /// field became a list, and it still carries none — `[null]` would make
  /// the update move offset 0.
  final List<int>? points;

  /// The offsets as the press found them — the drag adds ONE displacement
  /// to these rather than accumulating frame by frame.
  final List<CanvasPoint> startOffsets;
}

/// A scale, rotate or inside drag on the affine box.
final class BoxHandleDrag extends TransformDrag {
  BoxHandleDrag({
    required super.pointer,
    required super.startPointer,
    required this.handle,
    required this.start,
    required this.lastAngle,
  });

  final TransformHandle handle;

  /// The affine as the press found it. The scale solver works from this,
  /// so a drag is one solve from the start rather than a chain of deltas.
  final SelectionAffine start;

  /// The rotate knob's wrapped-delta accumulator (the camera lever rule):
  /// continuous across the ±180° seam. Meaningless for the other handles,
  /// which never read it.
  double lastAngle;
}

/// The polygon's press: it has no drag verb at all — the aim is taken where
/// the stylus landed and nothing is placed until the hand comes off (유저
/// 법: 선택은 탭 = 손 떼야). Taking the release position instead would slide
/// the vertex out from under a finger that rolled.
final class VertexTapDrag extends SelectionDrag {
  VertexTapDrag({required super.pointer, required this.tapStart});

  /// Where the tap went DOWN, in this layer's own coordinates — the point
  /// it will place.
  final Offset tapStart;
}
