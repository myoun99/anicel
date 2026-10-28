part of '../interactive_brush_edit_canvas_view.dart';

/// THE STROKE A TOOL LAYS — a path handed over whole and drawn as ONE
/// stroke of the brush in hand: the shape tool's rectangle, ellipse or
/// line, where its line is of the brush type (I-69).
///
/// 🚨★★★IT IS THE STROKE, NOT A STROKE LIKE IT. The path goes through
/// [_BrushEditStroke]'s own arming, its own advance and the one landing
/// ([_BrushEditPress.landActiveStroke]) — the spacing, the dynamics, the
/// ground mixing, the symmetry copies, the tip stamps, the overlay and the
/// promotion a pen stroke through the same points gets — so a shape is
/// undone, clipped by the selection and saved exactly as a stroke is.
/// 🗣️유저 2026-10-04: 「브러시 상태를 그대로 사용해서 도형그림 … 그냥 진짜
/// 브러시랑 똑같이 래스터라이즈되있는 도형」. ⛔A second generator of dabs
/// beside the stroke's would be the copy that drifts.
///
/// What differs is only what a pen brings and a tool does not: no pointer,
/// no pressure to read (the stroke is laid at the one pressure it is given
/// the whole way), no hand to steady and no ray to snap to — its points go
/// straight to the stroke's advance ([_BrushEditStroke.startToolStrokeAt]).
class _BrushEditPathStroke {
  _BrushEditPathStroke(this._state);

  final _InteractiveBrushEditCanvasViewState _state;

  /// Draws [path] — two or more points in this view's own space — as one
  /// stroke at [pressure], and answers whether it is drawn, or will be once
  /// the cel it asked for is there: laid and landed in one go, where nothing
  /// of it was laid while it was dragged ([ShapeShow.landStroke]).
  bool strokeAlong(List<CanvasPoint> path, {required double pressure}) {
    if (path.length < 2 || _state._activeDrawingPointer != null) {
      return false;
    }
    if (_state.widget.marksMakeTheirCel) {
      // Nothing to draw on, or a held cel that gives way to a new one
      // (I-113): ask for the cel, as a press that draws does (I-10,
      // [_BrushEditCelPress]). ⚠️The shape tool's own press has
      // asked already and its cel is here by now
      // (`CanvasSelectionLayer.onPressNeedsCel`); this is for a caller that
      // did not, and its block is settled as a step of its own before the
      // stroke can claim it.
      if (!(_state.widget.onPressNeedsCel?.call() ?? false)) {
        return false;
      }
      // The block is made inside that call and the rebuild that brings its
      // cel is the next frame's; the path is laid when that frame is done.
      // ⚠️After the frame, never inside it: the landing calls out to the
      // host, and a callback that reaches a `setState` during build is the
      // mid-stroke flip's red screen (R13-4).
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_state.mounted && _state.widget.editable) {
          strokeAlong(path, pressure: pressure);
        }
      });
      SchedulerBinding.instance.ensureVisualUpdate();
      return true;
    }
    // F-196: the row first — a row that takes no strokes shows no line.
    if (!_state.widget.rowAcceptsStrokes) {
      return false;
    }
    final stroke = _state._stroke..openToolStroke();
    final waypoints = _strokeWaypoints(path);
    // One path, one roll: the same shape drawn again rolls the same
    // scatter and jitter.
    stroke.startToolStrokeAt(
      waypoints.first,
      dice: Object.hashAll(path),
      pressure: pressure,
    );
    for (final point in waypoints.skip(1)) {
      stroke.advanceStrokeTo(point);
    }
    stroke.flyToolStroke();
    _state._press.landActiveStroke();
    return true;
  }
}

/// The points a stroke along [path] is taken through
/// ([_BrushEditStroke.advanceStrokeTo]): the path's own, and between two
/// more than [_waypointSpan] apart, evenly spaced ones on the line between
/// — so no one advance lays more than a share of a frame's dabs. A dragged
/// shape's stroke is laid an advance a step ([_BrushEditShapeShow]), and
/// one laid in one go goes through the very same points, so the two lay
/// the same dabs.
///
/// 🔬An advance along a 2000px edge with a 4px brush made its 2000 dabs in
/// 5–13ms on the desktop's VM (2026-10-09), a quarter frame's share three
/// times over, and the outline the hand drags waited on it.
List<CanvasPoint> _strokeWaypoints(List<CanvasPoint> path) {
  if (path.isEmpty) {
    return const [];
  }
  final points = [path.first];
  for (final (from, to) in neighbourPairs(path)) {
    final pieces = (from.distanceTo(to) / _waypointSpan).ceil();
    for (var piece = 1; piece < pieces; piece += 1) {
      points.add(CanvasPoint.lerp(from, to, piece / pieces));
    }
    points.add(to);
  }
  return points;
}

/// The longest stretch one advance takes. A stroke lays four dabs a pixel
/// at most — its spacing never falls under a quarter of one
/// (`finestDabStep`), and only a brush under ten pixels goes under one —
/// so one advance lays at four times this many places at most, at each as
/// many dabs as the brush lays at one (its symmetry copies, its scatter).
const double _waypointSpan = 128;
