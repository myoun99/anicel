import 'dart:math' as math;

import '../models/brush_dab.dart';
import '../models/brush_dab_sequence.dart';
import '../models/brush_input_sample.dart';
import '../models/brush_settings.dart';
import 'brush_pressure_dynamics.dart';
import 'segment_spacing_walk.dart';

BrushDabSequence brushInputSamplesToBrushDabs({
  required Iterable<BrushInputSample> samples,
  required BrushSettings settings,
}) {
  final input = samples.toList(growable: false);
  if (input.isEmpty) return BrushDabSequence(const [], settings.opacity);

  final dabs = <BrushDab>[];
  var nextSequence = 0;
  void emit(BrushInputSample sample) {
    // BB-3: the base dab, then the ONE curve law. The multiplication used to
    // sit inside the factory as a fourth copy of it.
    dabs.add(
      applyBrushInputDynamics(
        BrushDab.fromInputSample(
          sample: sample,
          settings: settings,
          sequence: nextSequence,
        ),
        shape: settings.shape,
      ),
    );
    nextSequence += 1;
  }

  emit(input.first);
  if (input.length == 1) return BrushDabSequence(dabs, settings.opacity);

  final spacingDistance = settings.size * settings.spacing;
  var distanceSinceLastDab = 0.0;

  for (var i = 1; i < input.length; i += 1) {
    final previous = input[i - 1];
    final next = input[i];
    final dx = next.x - previous.x;
    final dy = next.y - previous.y;
    final segmentDistance = math.sqrt(dx * dx + dy * dy);
    if (segmentDistance == 0.0) continue;

    final placedDistance = placeAlongSegment(
      length: segmentDistance,
      spacing: spacingDistance,
      firstAt: spacingDistance - distanceSinceLastDab,
      place: (t) => emit(
        BrushInputSample(
          x: previous.x + dx * t,
          y: previous.y + dy * t,
          pressure: previous.pressure + (next.pressure - previous.pressure) * t,
          tiltAzimuthDegrees: _lerpAngleDegrees(
            previous.tiltAzimuthDegrees,
            next.tiltAzimuthDegrees,
            t,
          ),
          tiltAltitude:
              previous.tiltAltitude +
              (next.tiltAltitude - previous.tiltAltitude) * t,
        ),
      ),
    );
    distanceSinceLastDab = segmentDistance - placedDistance;
  }

  final finalSample = input.last;
  final lastDab = dabs.last;
  if (lastDab.center.x != finalSample.x || lastDab.center.y != finalSample.y) {
    emit(finalSample);
  }

  // F-12: the tool's opacity is the SEQUENCE's ceiling, not a factor on
  // each dab — the dabs carry only what varies between them.
  return BrushDabSequence(dabs, settings.opacity);
}

/// Interpolates between two ANGLES the short way round.
///
/// ⚠️Not the plain lerp the other inputs get: a pen swinging from 350° to
/// 10° travels 20°, and a linear blend would walk it 340° backwards through
/// every heading in between. Azimuth is the only wrapping value a sample
/// carries.
double _lerpAngleDegrees(double from, double to, double t) {
  final delta = ((to - from + 540.0) % 360.0) - 180.0;
  final blended = from + delta * t;
  return ((blended % 360.0) + 360.0) % 360.0;
}
