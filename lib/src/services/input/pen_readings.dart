import '../../models/canvas_point.dart';
import 'pen_lean.dart';

/// What the pen reads at a sample: how hard it presses, how it leans (null
/// where nothing measured one), how far it is turned about its barrel
/// (likewise — F-176-Q9), how fast it travelled.
typedef PenReadings = ({
  double pressure,
  PenLean? lean,
  double? twist,
  double speed,
});

/// A place on a line, and what the pen read there.
typedef PenPoint = ({CanvasPoint position, PenReadings readings});

/// [from] a [share] of the way to [to]. A lean and a twist go round the
/// shorter way; one only one side measured is [to]'s as it is.
///
/// The one blend of readings: the stabiliser's line carries them behind the
/// pen with it, and the post-correction's curve reads them off the line it
/// smooths (F-418).
PenReadings readingsBetween(PenReadings from, PenReadings to, double share) {
  double lerp(double a, double b) => a + (b - a) * share;
  final fromLean = from.lean;
  final toLean = to.lean;
  final fromTwist = from.twist;
  final toTwist = to.twist;
  return (
    pressure: lerp(from.pressure, to.pressure),
    speed: lerp(from.speed, to.speed),
    lean: fromLean == null || toLean == null
        ? toLean
        : (
            azimuthDegrees: turnedBetween(
              fromLean.azimuthDegrees,
              toLean.azimuthDegrees,
              share,
            ),
            altitude: lerp(fromLean.altitude, toLean.altitude),
          ),
    twist: fromTwist == null || toTwist == null
        ? toTwist
        : turnedBetween(fromTwist, toTwist, share),
  );
}

/// [from] turned a [share] of the shorter way round to [to], in degrees
/// 0..360 as a lean's azimuth and a twist are — 350° to 10° is twenty
/// degrees forward, not 340 back.
double turnedBetween(double from, double to, double share) {
  final apart = (to - from + 540) % 360 - 180;
  return (from + apart * share) % 360;
}
