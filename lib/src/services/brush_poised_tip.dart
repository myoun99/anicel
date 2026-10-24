import '../models/brush_dab.dart';
import '../models/brush_input_source.dart';
import '../models/brush_shape.dart';
import '../models/canvas_point.dart';
import 'brush_pressure_dynamics.dart';
import 'brush_stroke_dynamics.dart';
import 'input/pen_pose.dart';

/// A tip's footprint: its size in canvas pixels, its roundness and its angle
/// in dab degrees.
typedef PoisedTip = ({double size, double roundness, double angleDegrees});

/// The tip a pen held at [pose] lays down where it lands — its size,
/// roundness and angle as the stroke's own dynamics read that pose, and
/// nothing the stroke has not measured yet.
///
/// 유저 2026-10-21 (F-176-Q7, 「펜을 따라 바뀐다」): the brush cursor of a
/// tilted pencil stayed round while the pencil laid a wedge. The cursor asks
/// this, so the outline IS the tip — through the same curves
/// ([applyBrushInputDynamics]) and the same turn ([tipTurnDegrees]) as a
/// stroke's dab.
///
/// ⛔NOT pressure, speed, the stroke's direction or its dice. Before the pen
/// touches there is no pressure and no travel, and a throw is the stroke's
/// to make — so each is left out by the door a device that cannot say goes
/// through: its source is skipped, its turn is none. The size stays the
/// BASE that pressure would scale (`brushCursorShape`).
///
/// A mouse, or a pen that reports no pose, gets the brush's own size,
/// roundness and angle back.
PoisedTip poisedTip(BrushShape shape, PenPose pose) {
  final lean = pose.lean;
  final reading = BrushDab(
    center: CanvasPoint(x: 0, y: 0),
    color: shape.color,
    size: shape.size,
    opacity: 1,
    flow: 1,
    hardness: 1,
    pressure: 1,
    sequence: 0,
    tiltAzimuthDegrees: lean?.azimuthDegrees ?? 0.0,
    tiltAltitude: lean?.altitude,
    twistDegrees: pose.twist,
    roundness: shape.roundness,
    angleDegrees: shape.angleDegrees,
  );
  final read = applyBrushInputDynamics(
    reading,
    shape: shape,
    sources: const [BrushInputSource.tilt],
  );
  final turn = tipTurnDegrees(
    shape.rotationMode,
    reading,
    directionDegrees: null,
  );
  return (
    size: read.size,
    roundness: read.roundness,
    angleDegrees: shape.angleDegrees + (turn ?? 0.0),
  );
}
