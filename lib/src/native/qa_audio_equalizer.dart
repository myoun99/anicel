// The engine's Rust library bakes a sound row's equalizer
// (native/audio_mix equalizer.rs), and its name is found in that code
// asset — no library opened, no path named. A span is baked once from its
// first sample, never on the device thread.
@DefaultAsset(gpuEngineAsset)
library;

import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import '../services/audio/audio_equalizer.dart';
import 'gpu_engine_asset.dart';

@Native<
  Int32 Function(
    Pointer<Float>,
    Int64,
    Int32,
    Int32,
    Pointer<Int64>,
    Pointer<Double>,
    Int32,
    Pointer<Float>,
  )
>(symbol: 'qa_audio_equalize')
external int _equalize(
  Pointer<Float> samples,
  int frames,
  int channels,
  int rate,
  Pointer<Int64> starts,
  Pointer<Double> values,
  int count,
  Pointer<Float> out,
);

/// [samples] — interleaved by [channels], at [rate] — through the
/// equalizer [settings] give, in order of their start, each channel from
/// rest at the first sample: what the engine bakes a span by. Empty where
/// the engine refuses the geometry.
Float32List equalizeAudio({
  required Float32List samples,
  required int channels,
  required int rate,
  required List<AudioEqualizerSetting> settings,
}) {
  if (channels <= 0 || rate <= 0 || samples.length % channels != 0) {
    return Float32List(0);
  }
  const valuesEach = audioEqualizerValues;
  final input = calloc<Float>(samples.length);
  final output = calloc<Float>(samples.length);
  final starts = calloc<Int64>(settings.length);
  final values = calloc<Double>(settings.length * valuesEach);
  try {
    input.asTypedList(samples.length).setAll(0, samples);
    for (final (index, setting) in settings.indexed) {
      starts[index] = setting.start;
      values
          .asTypedList(settings.length * valuesEach)
          .setAll(index * valuesEach, setting.equalizer.values);
    }
    final ran = _equalize(
      input,
      samples.length ~/ channels,
      channels,
      rate,
      starts,
      values,
      settings.length,
      output,
    );
    if (ran != 1) {
      return Float32List(0);
    }
    return Float32List.fromList(output.asTypedList(samples.length));
  } finally {
    calloc
      ..free(values)
      ..free(starts)
      ..free(output)
      ..free(input);
  }
}
