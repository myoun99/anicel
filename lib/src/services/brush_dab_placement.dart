import 'dart:math' as math;

import '../models/brush_dab.dart';
import '../models/brush_dab_sequence.dart';
import '../models/brush_input_sample.dart';
import '../models/brush_settings.dart';
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
    dabs.add(
      BrushDab.fromInputSample(
        sample: sample,
        settings: settings,
        sequence: nextSequence,
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
