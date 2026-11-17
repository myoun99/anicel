import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/native/qa_audio_equalizer.dart';
import 'package:anicel/src/services/audio/audio_equalizer.dart';

import '../helpers/pinned_fingerprints.dart';

/// The app's door to the engine's equalizer (board
/// audio-fx-grows-like-the-pros ③): what it hands back for the engine's
/// own made-up sound is the bytes the engine's test pinned
/// (equalizer_tests.rs, `a_made_up_sound_is_baked_as_pinned`) — so every
/// value crosses in its place, and a span baked for playback and one baked
/// for an export are the one bake.
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

  final settings = <AudioEqualizerSetting>[
    (start: 0, equalizer: every),
    (start: 4800, equalizer: like(every, lowDb: 6, highCut: 6000)),
    (start: 9600, equalizer: none),
    (start: 14400, equalizer: like(every, lowCut: 300, highDb: -9)),
  ];

  test('the engine\'s made-up sound comes back as its test pinned it', () {
    final sound = _madeUpSound();
    for (final rate in [44100, 48000, 96000]) {
      final baked = equalizeAudio(
        samples: sound,
        channels: 2,
        rate: rate,
        settings: settings,
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
    final whole = equalizeAudio(
      samples: sound,
      channels: 2,
      rate: 48000,
      settings: settings,
    );
    // Breaks on a setting's start, beside one, and at the very first.
    final stretches = EqualizerStretches(
      channels: 2,
      rate: 48000,
      settings: settings,
    );
    final pieces = <double>[];
    for (final (from, to) in [(0, 1), (1, 4800), (4800, 9601), (9601, 20000)]) {
      pieces.addAll(
        stretches.next(Float32List.sublistView(sound, 2 * from, 2 * to)),
      );
    }
    expect(Float32List.fromList(pieces), whole);
  });

  test('an equalizer of no section hands its samples back as they were', () {
    final sound = Float32List.fromList([0.25, -0.5, 0.75, 1, -1, 0]);
    expect(
      equalizeAudio(
        samples: sound,
        channels: 2,
        rate: 48000,
        settings: const [(start: 0, equalizer: none)],
      ),
      sound,
    );
  });

  test('geometry the engine cannot read comes back empty', () {
    final sound = Float32List(6);
    for (final (channels, rate) in [(0, 48000), (2, 0), (4, 48000)]) {
      expect(
        equalizeAudio(
          samples: sound,
          channels: channels,
          rate: rate,
          settings: const [],
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
