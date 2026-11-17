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

/// A sound row's equalizer at one moment, as the engine bakes a span by it
/// (native/audio_mix equalizer.rs — board audio-fx-grows-like-the-pros ③):
/// a low cut, a low shelf, a high shelf and a high cut, Hz and dB.
///
/// A cut whose corner is no frequency of the rate (at or under 0 Hz, at or
/// past half the rate) and a shelf of 0 dB are left out, so [none] hands
/// its samples back as they were.
@immutable
class AudioEqualizer {
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

  /// The [audioEqualizerValues] values in the order the engine's door
  /// reads them.
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
}

/// An equalizer from [start] — a sample of the span, 0 its first — until
/// the next one's.
typedef AudioEqualizerSetting = ({int start, AudioEqualizer equalizer});

/// Whose bake an [EqualizedSpan] is: a row's clip, the knob that moves it.
///
/// 🚨A KNOB'S BAKES ARE BOUNDED BY IT (agreed with 저장 on board
/// audio-fx-grows-like-the-pros, 11-17): each value a dragged knob passes
/// is a span of its own, so a store that kept every one kept a whole span
/// a value. A slot holds the bake last asked of it and the one last made
/// — the newest asked wins, one under way at a time. ⛔NOT «WHAT THE
/// SCHEDULE DID NOT ASK FOR»: a scrubber's and a run's schedules differ,
/// and each would let go of the other's.
typedef EqualizerSlot = ({LayerId row, FrameId clip});

/// How many values an [AudioEqualizer] hands the engine — its door's
/// `EQUALIZER_VALUES` (native/audio_mix equalizer.rs).
const audioEqualizerValues = 6;

/// An equalizer effect's sample ([EffectKind.equalizer]) as the engine
/// bakes by it: its cuts and its shelves' gains, the shelves turning where
/// the kind says ([equalizerLowShelfHz], [equalizerHighShelfHz]) and a
/// High Cut at its top no cut at any rate ([equalizerHighCutTop]).
AudioEqualizer audioEqualizerOf(ResolvedLayerEffect sample) {
  final highCut = sample.parameter('highCut');
  return AudioEqualizer(
    lowCut: sample.parameter('lowCut'),
    highCut: highCut >= equalizerHighCutTop ? 0 : highCut,
    lowShelf: equalizerLowShelfHz,
    lowDb: sample.parameter('lowGain'),
    highShelf: equalizerHighShelfHz,
    highDb: sample.parameter('highGain'),
  );
}

/// A span of a sound through its row's equalizers, in samples of the rate
/// it is baked at: [length] on from the source sample [start], each
/// setting's start counted from [start].
///
/// 🚨WHAT A BAKE IS OF (board audio-fx-grows-like-the-pros ③): the whole
/// span from its own first sample, never the part a run or an export
/// starts in — a filter remembers what it heard, so a bake begun anywhere
/// else would play other samples there. Two that are equal are one bake,
/// read by playback and an export alike.
@immutable
class EqualizedSpan {
  const EqualizedSpan({
    required this.start,
    required this.length,
    required this.stages,
    required this.slot,
  });

  final int start;
  final int length;

  /// The row's equalizers in its chain's order, each its own settings —
  /// the span through the first, what comes out through the next.
  ///
  /// 🗣️Design 1 of audio-fx-grows-like-the-pros, as approved (Q2, 유저
  /// 2026-11-17): 「효과 순서가 소리 순서다(위 → 아래)」 — two equalizers
  /// on a row are two, one after the other, as two blurs on a picture are.
  final List<List<AudioEqualizerSetting>> stages;

  /// The row's clip the span is baked for — two rows' alike spans are
  /// two bakes, each bounded by its own knob.
  final EqualizerSlot slot;

  @override
  bool operator ==(Object other) =>
      other is EqualizedSpan &&
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
      'EqualizedSpan(start: $start, length: $length, stages: $stages, '
      'slot: $slot)';
}
