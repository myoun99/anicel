import 'package:flutter/foundation.dart' show immutable, listEquals;

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

/// How many values an [AudioEqualizer] hands the engine — its door's
/// `EQUALIZER_VALUES` (native/audio_mix equalizer.rs).
const audioEqualizerValues = 6;

/// A span of a sound through its row's equalizer, in samples of the rate
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
    required this.settings,
  });

  final int start;
  final int length;
  final List<AudioEqualizerSetting> settings;

  @override
  bool operator ==(Object other) =>
      other is EqualizedSpan &&
      other.start == start &&
      other.length == length &&
      listEquals(other.settings, settings);

  @override
  int get hashCode => Object.hash(start, length, Object.hashAll(settings));

  @override
  String toString() =>
      'EqualizedSpan(start: $start, length: $length, settings: $settings)';
}
