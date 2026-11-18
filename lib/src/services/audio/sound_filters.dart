import 'package:flutter/foundation.dart' show immutable;

import '../../core/collection_equality.dart';
import '../../models/frame_id.dart';
import '../../models/layer_effect.dart'
    show
        EffectKind,
        ResolvedLayerEffect,
        equalizerHighCutTop,
        equalizerHighShelfHz,
        equalizerLowShelfHz;
import '../../models/layer_id.dart';

/// A sound row's filter at one moment, as the engine bakes a span by it:
/// one of the kinds its ONE door takes (native/audio_mix filter.rs —
/// board audio-fx-second-effect-and-presets), told by [door].
@immutable
sealed class SoundFilter {
  const SoundFilter();

  /// The engine's number for this filter, the `kind` its door reads
  /// (filter.rs `Filter::of`).
  int get door;

  /// Its values in the order the engine's door reads them — as many as
  /// the door's `qa_audio_filter_values` says.
  List<double> get values;
}

/// A sound row's equalizer at one moment (native/audio_mix equalizer.rs —
/// board audio-fx-grows-like-the-pros ③): a low cut, a low shelf, a high
/// shelf and a high cut, Hz and dB.
///
/// A cut whose corner is no frequency of the rate (at or under 0 Hz, at or
/// past half the rate) and a shelf of 0 dB are left out, so [none] hands
/// its samples back as they were.
final class AudioEqualizer extends SoundFilter {
  const AudioEqualizer({
    required this.lowCut,
    required this.highCut,
    required this.lowShelf,
    required this.lowDb,
    required this.highShelf,
    required this.highDb,
  });

  /// Every section left out, the shelves' corners where [lowDb] and
  /// [highDb] would turn them.
  const AudioEqualizer.none({
    required this.lowShelf,
    required this.highShelf,
  }) : lowCut = 0,
       highCut = 0,
       lowDb = 0,
       highDb = 0;

  /// Hz: the lows under it fall away.
  final double lowCut;

  /// Hz: the highs over it fall away.
  final double highCut;

  /// The low shelf's corner, Hz, and its gain, dB.
  final double lowShelf;
  final double lowDb;

  /// The high shelf's corner, Hz, and its gain, dB.
  final double highShelf;
  final double highDb;

  @override
  int get door => 0;

  @override
  List<double> get values => [
    lowCut,
    highCut,
    lowShelf,
    lowDb,
    highShelf,
    highDb,
  ];

  @override
  bool operator ==(Object other) =>
      other is AudioEqualizer &&
      other.lowCut == lowCut &&
      other.highCut == highCut &&
      other.lowShelf == lowShelf &&
      other.lowDb == lowDb &&
      other.highShelf == highShelf &&
      other.highDb == highDb;

  @override
  int get hashCode =>
      Object.hash(lowCut, highCut, lowShelf, lowDb, highShelf, highDb);

  @override
  String toString() =>
      'AudioEqualizer(lowCut: $lowCut, highCut: $highCut, '
      'lowShelf: $lowShelf, lowDb: $lowDb, highShelf: $highShelf, '
      'highDb: $highDb)';
}

/// A sound row's compressor at one moment (native/audio_mix
/// compressor.rs): what rises over [thresholdDb] is turned down by
/// [ratio], the turning following the level in [attackMs] and letting go
/// in [releaseMs], and the whole raised by [makeupDb]. A [ratio] of 1 and
/// no makeup hand the samples back as they were.
final class AudioCompressor extends SoundFilter {
  const AudioCompressor({
    required this.thresholdDb,
    required this.ratio,
    required this.attackMs,
    required this.releaseMs,
    required this.makeupDb,
  });

  final double thresholdDb;
  final double ratio;
  final double attackMs;
  final double releaseMs;
  final double makeupDb;

  @override
  int get door => 1;

  @override
  List<double> get values => [
    thresholdDb,
    ratio,
    attackMs,
    releaseMs,
    makeupDb,
  ];

  @override
  bool operator ==(Object other) =>
      other is AudioCompressor &&
      other.thresholdDb == thresholdDb &&
      other.ratio == ratio &&
      other.attackMs == attackMs &&
      other.releaseMs == releaseMs &&
      other.makeupDb == makeupDb;

  @override
  int get hashCode =>
      Object.hash(thresholdDb, ratio, attackMs, releaseMs, makeupDb);

  @override
  String toString() =>
      'AudioCompressor(thresholdDb: $thresholdDb, ratio: $ratio, '
      'attackMs: $attackMs, releaseMs: $releaseMs, makeupDb: $makeupDb)';
}

/// A sound row's noise removal at one moment (native/audio_mix
/// denoiser.rs): [amount], 0 to 1, of the take's RNNoise heard over the
/// sound as it was. An [amount] of 0 hands the samples back as they were.
final class AudioDenoiser extends SoundFilter {
  const AudioDenoiser({required this.amount});

  final double amount;

  @override
  int get door => 2;

  @override
  List<double> get values => [amount];

  @override
  bool operator ==(Object other) =>
      other is AudioDenoiser && other.amount == amount;

  @override
  int get hashCode => amount.hashCode;

  @override
  String toString() => 'AudioDenoiser(amount: $amount)';
}

/// A filter from [start] — a sample of the span, 0 its first — until the
/// next one's.
typedef SoundFilterSetting = ({int start, SoundFilter filter});

/// A sound's filter sample ([EffectKind.filtersSound]) as the engine bakes
/// by it. An equalizer's shelves turn where the kind says
/// ([equalizerLowShelfHz], [equalizerHighShelfHz]) and a High Cut at its
/// top is no cut at any rate ([equalizerHighCutTop]).
///
/// ⛔A picture's kind is no sound filter — asked of one, it throws: the
/// rows that ask take only a sound's ([EffectKind.isTakenByARow]).
SoundFilter soundFilterOf(ResolvedLayerEffect sample) => switch (sample.kind) {
  EffectKind.equalizer => AudioEqualizer(
    lowCut: sample.parameter('lowCut'),
    highCut: switch (sample.parameter('highCut')) {
      final top when top >= equalizerHighCutTop => 0,
      final cut => cut,
    },
    lowShelf: equalizerLowShelfHz,
    lowDb: sample.parameter('lowGain'),
    highShelf: equalizerHighShelfHz,
    highDb: sample.parameter('highGain'),
  ),
  EffectKind.compressor => AudioCompressor(
    thresholdDb: sample.parameter('threshold'),
    ratio: sample.parameter('ratio'),
    attackMs: sample.parameter('attack'),
    releaseMs: sample.parameter('release'),
    makeupDb: sample.parameter('makeup'),
  ),
  EffectKind.noiseRemoval => AudioDenoiser(
    amount: sample.parameter('amount') / 100,
  ),
  EffectKind.brightnessContrast ||
  EffectKind.hueSaturation ||
  EffectKind.blur ||
  EffectKind.directionalBlur ||
  EffectKind.radialBlur ||
  EffectKind.cameraLensBlur ||
  EffectKind.colorKey ||
  EffectKind.celNumber ||
  EffectKind.plugin => throw ArgumentError.value(
    sample.kind,
    'sample',
    'filters no sound',
  ),
};

/// Whose bake an [FilteredSpan] is: a row's clip, the knob that moves it.
///
/// 🚨A KNOB'S BAKES ARE BOUNDED BY IT (agreed with 저장 on board
/// audio-fx-grows-like-the-pros, 11-17): each value a dragged knob passes
/// is a span of its own, so a store that kept every one kept a whole span
/// a value. A slot holds the bake last asked of it and the one last made
/// — the newest asked wins, one under way at a time. ⛔NOT «WHAT THE
/// SCHEDULE DID NOT ASK FOR»: a scrubber's and a run's schedules differ,
/// and each would let go of the other's.
typedef FilterSlot = ({LayerId row, FrameId clip});

/// A span of a sound through its row's filters, in samples of the rate
/// it is baked at: [length] on from the source sample [start], each
/// setting's start counted from [start].
///
/// 🚨WHAT A BAKE IS OF (board audio-fx-grows-like-the-pros ③): the whole
/// span from its own first sample, never the part a run or an export
/// starts in — a filter remembers what it heard, so a bake begun anywhere
/// else would play other samples there. Two that are equal are one bake,
/// read by playback and an export alike.
@immutable
class FilteredSpan {
  const FilteredSpan({
    required this.start,
    required this.length,
    required this.stages,
    required this.slot,
  });

  final int start;
  final int length;

  /// The row's filters in its chain's order, each one effect's settings —
  /// so one kind's — the span through the first, what comes out through
  /// the next.
  ///
  /// 🗣️Design 1 of audio-fx-grows-like-the-pros, as approved (Q2, 유저
  /// 2026-11-17): 「효과 순서가 소리 순서다(위 → 아래)」 — two equalizers
  /// on a row are two, one after the other, as two blurs on a picture are.
  final List<List<SoundFilterSetting>> stages;

  /// The row's clip the span is baked for — two rows' alike spans are
  /// two bakes, each bounded by its own knob.
  final FilterSlot slot;

  @override
  bool operator ==(Object other) =>
      other is FilteredSpan &&
      other.start == start &&
      other.length == length &&
      other.slot == slot &&
      listsMatch(other.stages, stages, listEquals);

  @override
  int get hashCode => Object.hash(
    start,
    length,
    slot,
    Object.hashAll([for (final stage in stages) Object.hashAll(stage)]),
  );

  @override
  String toString() =>
      'FilteredSpan(start: $start, length: $length, stages: $stages, '
      'slot: $slot)';
}
