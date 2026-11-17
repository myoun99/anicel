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
    Int64,
    Pointer<Int64>,
    Pointer<Double>,
    Int32,
    Pointer<Double>,
    Pointer<Float>,
  )
>(symbol: 'qa_audio_equalize')
external int _equalize(
  Pointer<Float> samples,
  int frames,
  int channels,
  int rate,
  int first,
  Pointer<Int64> starts,
  Pointer<Double> values,
  int count,
  Pointer<Double> memory,
  Pointer<Float> out,
);

/// The doubles one channel's memory takes — the door's `MEMORY_VALUES`
/// (native/audio_mix equalizer.rs).
const _memoryValues = 16;

/// [samples] — interleaved by [channels], at [rate] — through the
/// equalizer [settings] give, in order of their start, each channel from
/// rest at the first sample: what the engine bakes a span by. Empty where
/// the engine refuses the geometry.
Float32List equalizeAudio({
  required Float32List samples,
  required int channels,
  required int rate,
  required List<AudioEqualizerSetting> settings,
}) => EqualizerStretches(
  channels: channels,
  rate: rate,
  settings: settings,
).next(samples);

/// A span baked a stretch at a time — one too long to hold, read and
/// written in pieces: each stretch goes on from the filters' memory where
/// the one before left it, so the stretches together are the samples
/// [equalizeAudio] makes of the span at once.
final class EqualizerStretches {
  /// From the span's first sample at rest — or, [from] given, going on from
  /// the span's sample `first`, the filters remembering `memory`: a [kept]
  /// of a bake of the same span that got that far.
  EqualizerStretches({
    required this.channels,
    required this.rate,
    required this.settings,
    ({int first, Float64List memory})? from,
  }) : _memory = from == null
           ? Float64List(channels <= 0 ? 0 : channels * _memoryValues)
           : Float64List.fromList(from.memory),
       _first = from?.first ?? 0;

  final int channels;
  final int rate;
  final List<AudioEqualizerSetting> settings;
  final Float64List _memory;

  /// The span's sample the next stretch begins at.
  int _first;

  /// What the filters remember now, to go on from — a copy.
  Float64List get kept => Float64List.fromList(_memory);

  /// The next [samples] of the span, baked — empty where the engine
  /// refuses the geometry, and nothing then taken from the span.
  Float32List next(Float32List samples) {
    if (channels <= 0 || rate <= 0 || samples.length % channels != 0) {
      return Float32List(0);
    }
    const valuesEach = audioEqualizerValues;
    final frames = samples.length ~/ channels;
    final input = calloc<Float>(samples.length);
    final output = calloc<Float>(samples.length);
    final starts = calloc<Int64>(settings.length);
    final values = calloc<Double>(settings.length * valuesEach);
    final memory = calloc<Double>(_memory.length);
    try {
      input.asTypedList(samples.length).setAll(0, samples);
      for (final (index, setting) in settings.indexed) {
        starts[index] = setting.start;
        values
            .asTypedList(settings.length * valuesEach)
            .setAll(index * valuesEach, setting.equalizer.values);
      }
      memory.asTypedList(_memory.length).setAll(0, _memory);
      final ran = _equalize(
        input,
        frames,
        channels,
        rate,
        _first,
        starts,
        values,
        settings.length,
        memory,
        output,
      );
      if (ran != 1) {
        return Float32List(0);
      }
      _memory.setAll(0, memory.asTypedList(_memory.length));
      _first += frames;
      return Float32List.fromList(output.asTypedList(samples.length));
    } finally {
      calloc
        ..free(memory)
        ..free(values)
        ..free(starts)
        ..free(output)
        ..free(input);
    }
  }
}
