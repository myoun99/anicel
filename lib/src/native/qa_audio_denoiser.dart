// The engine's Rust library carries the denoiser (rust/src/lib.rs,
// native/audio_denoise), and its name is found in that code asset — no
// library opened, no path named.
@DefaultAsset(gpuEngineAsset)
library;

import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'gpu_engine_asset.dart';

@Native<Int32 Function(Pointer<Float>, Int64, Int32, Int32)>(
  symbol: 'qa_audio_denoise_f32',
)
external int _denoise(
  Pointer<Float> samples,
  int frames,
  int channels,
  int sampleRate,
);

/// RNNoise voice suppression over a finished take (48 kHz only — the
/// model's native rate). Returns the denoised samples, or null when the
/// engine declined (wrong rate/empty) — null always means "use the raw
/// take", never a half-processed buffer.
Float32List? denoiseVoiceTake({
  required Float32List samples,
  required int channels,
  required int sampleRate,
}) {
  if (samples.isEmpty || channels <= 0) {
    return null;
  }
  final frames = samples.length ~/ channels;
  if (frames <= 0) {
    return null;
  }
  final buffer = calloc<Float>(samples.length);
  try {
    buffer.asTypedList(samples.length).setAll(0, samples);
    final processed = _denoise(buffer, frames, channels, sampleRate);
    if (processed != 1) {
      return null;
    }
    final result = Float32List(samples.length);
    result.setAll(0, buffer.asTypedList(samples.length));
    return result;
  } finally {
    calloc.free(buffer);
  }
}
