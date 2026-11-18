import 'dart:typed_data';

import 'package:gpu_engine/gpu_engine.dart';

import '../services/audio/audio_peaks_extractor.dart';
import 'app_gpu_engine.dart';

/// A sound's peaks on the engine the app has, for its wave to be laid from
/// ([GpuGridBatch.wave]): handed over the first time they are asked for,
/// and the sound's as long as its peaks are ([GpuWavePeaks] — let go of
/// with them).
/// On the engine the app has ([KeptOnTheAppsEngine]): once the app lets
/// this one go, they are handed over again to the next.
abstract final class EngineWavePeaks {
  static final _kept = KeptOnTheAppsEngine<Expando<GpuWavePeaks>>();

  /// [peaks] on the app's engine.
  static GpuWavePeaks of(AudioPeaks peaks) =>
      _kept.of(Expando.new)[peaks] ??= GpuWavePeaks(appGpuEngine, [
        for (final lane in peaks.lanes) q16Of(lane),
      ]);

  /// [lane] as the pass takes a peak: round(min(|s|, 1) · 65535).
  static Uint16List q16Of(Float32List lane) => Uint16List.fromList([
    for (final peak in lane) (peak.abs().clamp(0, 1) * 65535).round(),
  ]);
}
