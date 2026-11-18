// The engine's Rust library bakes a sound row's filters through ONE door
// that takes the filter's kind (native/audio_mix filter.rs), and its names
// are found in that code asset — no library opened, no path named. A span
// is baked once from its first sample, never on the device thread.
@DefaultAsset(gpuEngineAsset)
library;

import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import '../services/audio/sound_filters.dart';
import 'gpu_engine_asset.dart';

@Native<
  Int32 Function(
    Int32,
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
>(symbol: 'qa_audio_filter')
external int _filter(
  int kind,
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

/// The doubles one setting of the filter [kind] takes.
@Native<Int32 Function(Int32)>(symbol: 'qa_audio_filter_values')
external int _valuesOf(int kind);

/// The doubles the filter [kind] remembers over [channels].
@Native<Int32 Function(Int32, Int32)>(symbol: 'qa_audio_filter_memory')
external int _memoryOf(int kind, int channels);

/// [samples] — interleaved by [channels], at [rate] — through the filters
/// [stages] give, one after another, each by its settings in order of
/// their start and each from rest at the first sample: what the engine
/// bakes a span by. Empty where the engine refuses the geometry.
Float32List filterAudio({
  required Float32List samples,
  required int channels,
  required int rate,
  required List<List<SoundFilterSetting>> stages,
}) => FilterStretches(
  channels: channels,
  rate: rate,
  stages: stages,
).next(samples);

/// A span baked a stretch at a time — one too long to hold, read and
/// written in pieces: each stretch goes on from the filters' memory where
/// the one before left it, so the stretches together are the samples
/// [filterAudio] makes of the span at once.
///
/// A stage is the engine's door, called once a stretch with its filter's
/// kind, the next stage taking the floats it wrote: one stage a call.
final class FilterStretches {
  /// From the span's first sample at rest — or, [from] given, going on from
  /// the span's sample `first`, the filters remembering `memory`: a [kept]
  /// of a bake of the same span that got that far.
  FilterStretches({
    required this.channels,
    required this.rate,
    required this.stages,
    ({int first, Float64List memory})? from,
  }) : _ends = _memoryEnds(stages, channels),
       _first = from?.first ?? 0 {
    _memory = from == null
        ? Float64List(_ends.isEmpty ? 0 : _ends.last)
        : Float64List.fromList(from.memory);
  }

  final int channels;
  final int rate;
  final List<List<SoundFilterSetting>> stages;

  /// Where each stage's memory ends in [_memory], the first stage's first.
  final List<int> _ends;

  /// Every stage's memory, the first stage's first.
  late final Float64List _memory;

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
    final memory = Float64List.fromList(_memory);
    var baked = Float32List.fromList(samples);
    for (final (index, settings) in stages.indexed) {
      final made = _stage(
        baked,
        settings,
        Float64List.sublistView(
          memory,
          index == 0 ? 0 : _ends[index - 1],
          _ends[index],
        ),
      );
      if (made == null) {
        return Float32List(0);
      }
      baked = made;
    }
    _memory.setAll(0, memory);
    _first += samples.length ~/ channels;
    return baked;
  }

  /// [samples] through one stage's [settings], going on from [memory] and
  /// leaving it there — null where the engine refuses.
  Float32List? _stage(
    Float32List samples,
    List<SoundFilterSetting> settings,
    Float64List memory,
  ) {
    if (settings.isEmpty) {
      return samples;
    }
    final kind = settings.first.filter.door;
    final valuesEach = _valuesOf(kind);
    final frames = samples.length ~/ channels;
    final input = calloc<Float>(samples.length);
    final output = calloc<Float>(samples.length);
    final starts = calloc<Int64>(settings.length);
    final values = calloc<Double>(settings.length * valuesEach);
    final held = calloc<Double>(memory.length);
    try {
      input.asTypedList(samples.length).setAll(0, samples);
      for (final (index, setting) in settings.indexed) {
        starts[index] = setting.start;
        values
            .asTypedList(settings.length * valuesEach)
            .setAll(index * valuesEach, setting.filter.values);
      }
      held.asTypedList(memory.length).setAll(0, memory);
      final ran = _filter(
        kind,
        input,
        frames,
        channels,
        rate,
        _first,
        starts,
        values,
        settings.length,
        held,
        output,
      );
      if (ran != 1) {
        return null;
      }
      memory.setAll(0, held.asTypedList(memory.length));
      return Float32List.fromList(output.asTypedList(samples.length));
    } finally {
      calloc
        ..free(held)
        ..free(values)
        ..free(starts)
        ..free(output)
        ..free(input);
    }
  }
}

/// Where each of [stages]' memories ends, laid one after another: each as
/// many doubles as its filter remembers over [channels], none for a stage
/// of no setting.
List<int> _memoryEnds(List<List<SoundFilterSetting>> stages, int channels) {
  var end = 0;
  return [
    for (final settings in stages)
      end += settings.isEmpty || channels <= 0
          ? 0
          : _memoryOf(settings.first.filter.door, channels),
  ];
}
