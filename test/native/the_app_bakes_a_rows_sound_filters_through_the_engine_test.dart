import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/native/qa_audio_filter.dart';
import 'package:anicel/src/services/audio/sound_filters.dart';

import '../helpers/pinned_fingerprints.dart';

/// The app's door to the engine's sound filters (board
/// audio-fx-grows-like-the-pros ③ · audio-fx-second-effect-and-presets):
/// what it hands back for the engine's own made-up sounds is the bytes the
/// engine's tests pinned (equalizer_tests.rs and compressor_tests.rs,
/// `a_made_up_sound_is_baked_as_pinned`) — so every value crosses in its
/// place, and a span baked for playback and one baked for an export are
/// the one bake.
void main() {
  const every = AudioEqualizer(
    lowCut: 80,
    highCut: 12000,
    lowShelf: 250,
    lowDb: -2,
    highShelf: 4000,
    highDb: 3,
  );
  const none = AudioEqualizer.none(lowShelf: 250, highShelf: 4000);

  AudioEqualizer like(
    AudioEqualizer from, {
    double? lowCut,
    double? highCut,
    double? lowDb,
    double? highDb,
  }) => AudioEqualizer(
    lowCut: lowCut ?? from.lowCut,
    highCut: highCut ?? from.highCut,
    lowShelf: from.lowShelf,
    lowDb: lowDb ?? from.lowDb,
    highShelf: from.highShelf,
    highDb: highDb ?? from.highDb,
  );

  final settings = <SoundFilterSetting>[
    (start: 0, filter: every),
    (start: 4800, filter: like(every, lowDb: 6, highCut: 6000)),
    (start: 9600, filter: none),
    (start: 14400, filter: like(every, lowCut: 300, highDb: -9)),
  ];

  test('the engine\'s made-up sound comes back as its test pinned it', () {
    final sound = _madeUpSound();
    for (final rate in [44100, 48000, 96000]) {
      final baked = filterAudio(
        samples: sound,
        channels: 2,
        rate: rate,
        stages: [settings],
      );
      expect(
        fingerprintHex(baked.buffer.asUint8List()),
        pinnedFingerprint('audio_mix/equalizer-at-$rate'),
        reason: '$rate Hz',
      );
    }
  });

  test('baked a stretch at a time, the sound comes back as baked at once',
      () {
    final sound = _madeUpSound();
    final whole = filterAudio(
      samples: sound,
      channels: 2,
      rate: 48000,
      stages: [settings],
    );
    // Breaks on a setting's start, beside one, and at the very first.
    final stretches = FilterStretches(
      channels: 2,
      rate: 48000,
      stages: [settings],
    );
    final pieces = <double>[];
    for (final (from, to) in [(0, 1), (1, 4800), (4800, 9601), (9601, 20000)]) {
      pieces.addAll(
        stretches.next(Float32List.sublistView(sound, 2 * from, 2 * to)),
      );
    }
    expect(Float32List.fromList(pieces), whole);
  });

  // 🗣️Q2 design 1 (유저 2026-11-17): 「효과 순서가 소리 순서다(위 → 아래)」
  // — a row's second filter hears what its first made.
  final darker = <SoundFilterSetting>[
    (start: 0, filter: like(every, lowDb: 9, highCut: 3000)),
    (start: 7000, filter: like(every, highDb: -12)),
  ];

  // The compressor's settings its engine test bakes its swelling sound by.
  const some = AudioCompressor(
    thresholdDb: -18,
    ratio: 4,
    attackMs: 5,
    releaseMs: 80,
    makeupDb: 3,
  );
  const level = AudioCompressor(
    thresholdDb: -20,
    ratio: 1,
    attackMs: 10,
    releaseMs: 100,
    makeupDb: 0,
  );
  final squeezing = <SoundFilterSetting>[
    (start: 0, filter: some),
    (
      start: 4800,
      filter: const AudioCompressor(
        thresholdDb: -18,
        ratio: 10,
        attackMs: 0,
        releaseMs: 80,
        makeupDb: 3,
      ),
    ),
    (start: 9600, filter: level),
    (
      start: 14400,
      filter: const AudioCompressor(
        thresholdDb: -30,
        ratio: 4,
        attackMs: 5,
        releaseMs: 400,
        makeupDb: 3,
      ),
    ),
  ];

  test('the engine\'s swelling sound comes back as its compressor test '
      'pinned it', () {
    final sound = _swellingSound();
    for (final rate in [44100, 48000, 96000]) {
      final baked = filterAudio(
        samples: sound,
        channels: 2,
        rate: rate,
        stages: [squeezing],
      );
      expect(
        fingerprintHex(baked.buffer.asUint8List()),
        pinnedFingerprint('audio_mix/compressor-at-$rate'),
        reason: '$rate Hz',
      );
    }
  });

  // Each stage's memory is as long as its kind's: a chain of kinds that
  // remember unalike goes on from where each left off.
  final chains = {
    'two equalizers': [settings, darker],
    'an equalizer, then a compressor': [settings, squeezing],
    'a compressor, then an equalizer': [squeezing, settings],
  };

  test('a chain remembers what each of its stages\' kind does: an '
      'equalizer each channel\'s sixteen, a compressor its one turning', () {
    for (final (stages, doubles) in [
      ([settings], 2 * 16),
      ([squeezing], 1),
      ([settings, squeezing], 2 * 16 + 1),
      ([squeezing, <SoundFilterSetting>[], settings], 1 + 2 * 16),
    ]) {
      expect(
        FilterStretches(channels: 2, rate: 48000, stages: stages).kept,
        hasLength(doubles),
        reason: '$stages',
      );
    }
  });

  test('🎯two stages are the first\'s sound through the second', () {
    final sound = _madeUpSound();
    for (final MapEntry(key: chain, value: stages) in chains.entries) {
      final first = filterAudio(
        samples: sound,
        channels: 2,
        rate: 48000,
        stages: [stages.first],
      );
      expect(
        filterAudio(samples: sound, channels: 2, rate: 48000, stages: stages),
        filterAudio(
          samples: first,
          channels: 2,
          rate: 48000,
          stages: [stages.last],
        ),
        reason: chain,
      );
    }
  });

  test('🎯two stages baked a stretch at a time come back as baked at once, '
      'from a stretch\'s kept memory too', () {
    final sound = _madeUpSound();
    for (final MapEntry(key: chain, value: stages) in chains.entries) {
      final whole = filterAudio(
        samples: sound,
        channels: 2,
        rate: 48000,
        stages: stages,
      );
      final stretches = FilterStretches(
        channels: 2,
        rate: 48000,
        stages: stages,
      );
      final pieces = <double>[
        ...stretches.next(Float32List.sublistView(sound, 0, 2 * 7001)),
      ];
      // A bake that goes on from what the first stretch left, as a window
      // goes on from its checkpoint.
      final goingOn = FilterStretches(
        channels: 2,
        rate: 48000,
        stages: stages,
        from: (first: 7001, memory: stretches.kept),
      );
      pieces.addAll(goingOn.next(Float32List.sublistView(sound, 2 * 7001)));
      expect(Float32List.fromList(pieces), whole, reason: chain);
    }
  });

  test('a filter that does nothing hands its samples back as they were — '
      'an equalizer of no section, a compressor at a ratio of one, a stage '
      'of no setting', () {
    final sound = Float32List.fromList([0.25, -0.5, 0.75, 1, -1, 0]);
    for (final stage in <List<SoundFilterSetting>>[
      [(start: 0, filter: none)],
      [(start: 0, filter: level)],
      [],
    ]) {
      expect(
        filterAudio(
          samples: sound,
          channels: 2,
          rate: 48000,
          stages: [stage, stage],
        ),
        sound,
        reason: '$stage',
      );
    }
  });

  test('geometry the engine cannot read comes back empty', () {
    final sound = Float32List(6);
    for (final (channels, rate) in [(0, 48000), (2, 0), (4, 48000)]) {
      expect(
        filterAudio(
          samples: sound,
          channels: channels,
          rate: rate,
          stages: const [[]],
        ),
        isEmpty,
        reason: '$channels channels at $rate',
      );
    }
  });
}

/// lowbias32 — a well-mixed u32 — as the engine's test makes its sound.
int _lowBias32(int seed) {
  var x = seed & 0xffffffff;
  x ^= x >> 16;
  x = (x * 0x7feb352d) & 0xffffffff;
  x ^= x >> 15;
  x = (x * 0x846ca68b) & 0xffffffff;
  return x ^ (x >> 16);
}

/// Two channels of 20,000 samples of a well-mixed u32 to [-1, 1), as the
/// engine's test makes its sound.
Float32List _madeUpSound() {
  final sound = Float32List(2 * 20000);
  for (var i = 0; i < sound.length; i += 1) {
    sound[i] = _lowBias32(i) / 2147483648.0 - 1.0;
  }
  return sound;
}

/// The made-up sound swelling and falling every 2,000 frames, so a
/// compressor's turning moves — as the engine's compressor test makes it.
Float32List _swellingSound() {
  final sound = Float32List(2 * 20000);
  for (var i = 0; i < sound.length; i += 1) {
    final swell = 0.1 + 0.9 * ((i ~/ 2) % 2000) / 2000.0;
    sound[i] = swell * (_lowBias32(i) / 2147483648.0 - 1.0);
  }
  return sound;
}
