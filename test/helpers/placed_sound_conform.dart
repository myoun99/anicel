import 'dart:typed_data';

import 'package:anicel/src/services/audio/audio_conform_pipeline.dart';
import 'package:anicel/src/services/audio/audio_peaks_extractor.dart';
import 'package:anicel/src/ui/audio/audio_conform_store.dart';

/// A conform store that answers every sound as [seconds] long, without the
/// isolate a widget test cannot run — a placement only asks the conform how
/// long the sound is.
AudioConformStore soundConformStore({double seconds = 1}) {
  const bucketsPerSecond = 100;
  return AudioConformStore(
    resolveConformPath: (_) => null,
    runner: (request) async => ConformResult(
      outcome: ConformOutcome.built,
      peaks: AudioPeaks(
        bucketsPerSecond: bucketsPerSecond,
        peaks: Float32List((bucketsPerSecond * seconds).round()),
      ),
      samples: Float32List(4),
      channels: 1,
      sampleRate: request.projectSampleRate,
      frames: 4,
      speedNumerator: request.speedNumerator,
      speedDenominator: request.speedDenominator,
    ),
    log: (_) {},
  );
}
