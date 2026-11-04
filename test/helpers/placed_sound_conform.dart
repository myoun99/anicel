import 'dart:typed_data';

import 'package:anicel/src/models/media_asset.dart' show MediaCarry;
import 'package:anicel/src/services/audio/audio_conform_pipeline.dart';
import 'package:anicel/src/services/audio/audio_conform_runner.dart'
    show ConformRequest;
import 'package:anicel/src/services/audio/audio_peaks_extractor.dart';
import 'package:anicel/src/services/media/media_byte_source.dart'
    show MediaByteSource;
import 'package:anicel/src/ui/audio/audio_conform_store.dart';

/// A conform store that answers every sound as [seconds] long, without the
/// isolate a widget test cannot run — a placement only asks the conform how
/// long the sound is.
///
/// [secondsOf] answers instead, from the request — which says whose bytes
/// it is of ([ConformRequest.effectiveSource]) — and [resolveByteSource]
/// and [resolveCarry] are the session's, for a test that asks which bytes
/// a sound is read from.
AudioConformStore soundConformStore({
  double seconds = 1,
  double Function(ConformRequest request)? secondsOf,
  MediaByteSource Function(String path)? resolveByteSource,
  MediaCarry? Function(String path)? resolveCarry,
}) {
  const bucketsPerSecond = 100;
  return AudioConformStore(
    resolveConformPath: (_) => null,
    resolveByteSource: resolveByteSource,
    resolveCarry: resolveCarry,
    runner: (request) async => ConformResult(
      outcome: ConformOutcome.built,
      peaks: AudioPeaks(
        bucketsPerSecond: bucketsPerSecond,
        peaks: Float32List(
          (bucketsPerSecond * (secondsOf?.call(request) ?? seconds)).round(),
        ),
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
