import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/native/qa_audio_native.dart';
import 'package:anicel/src/native/qa_engine_abi.dart';
import 'package:anicel/src/services/audio/audio_mixer_reference.dart';

import '../../helpers/native_engine_path.dart';

/// 2B: the native mixer must be BIT-IDENTICAL to the Dart reference.
///
/// This is the same discipline the raster core runs under, and it earns its
/// keep for the same reason: #614 found Apple clang fusing `a*b + c` into an
/// FMA that rounds once where Dart rounds twice, and the mixer is a
/// multiply-accumulate loop end to end — nothing in this project is denser
/// in the expression that contracts.
///
/// `expect(a, b)` on doubles here is exact equality, deliberately. A mixer
/// that is merely CLOSE is a mixer that will drift.
void main() {
  final libraryPath = nativeEngineLibraryPathOrNull();
  final available = libraryPath != null;

  setUp(() {
    QaAudioNative.debugResetForTests();
    debugQaEngineLibraryPathOverride = libraryPath;
    QaAudioNative.debugForceDartFallback = false;
  });

  tearDown(() {
    QaAudioNative.debugResetForTests();
    debugQaEngineLibraryPathOverride = null;
    QaAudioNative.debugForceDartFallback = false;
  });

  QaAudioNative requireNative() {
    final native = QaAudioNative.instance;
    expect(
      native,
      isNotNull,
      reason:
          'the binary at $libraryPath loaded but the audio entry points did '
          'not bind — an ABI or struct-layout mismatch, which is exactly '
          'what this suite exists to catch',
    );
    return native!;
  }

  void expectIdentical(
    Float64List native,
    Float64List reference, {
    required String what,
  }) {
    expect(native.length, reference.length, reason: '$what: length');
    for (var index = 0; index < reference.length; index += 1) {
      expect(
        native[index],
        reference[index],
        reason:
            '$what: sample $index — native ${native[index]} vs reference '
            '${reference[index]}',
      );
    }
  }

  group('native mixer byte parity', () {
    test('the struct layouts agree on both sides', () {
      // The loader returns null on any sizeof disagreement, so simply
      // binding is the assertion — a silent layout drift would make every
      // field read garbage, and garbage in an audio buffer is a loud noise
      // in someone's headphones.
      requireNative();
    }, skip: available ? false : nativeEngineMissingSkipReason);

    test('randomized clip layouts stay bit-identical', () {
      final native = requireNative();
      final random = Random(20260720);

      for (var round = 0; round < 200; round += 1) {
        final sourceCount = 1 + random.nextInt(3);
        final sources = <AudioMixSource>[];
        for (var index = 0; index < sourceCount; index += 1) {
          final channels = 1 + random.nextInt(2);
          final samples = 1 + random.nextInt(64);
          final data = Float32List(samples * channels);
          for (var i = 0; i < data.length; i += 1) {
            data[i] = random.nextDouble() * 2.0 - 1.0;
          }
          sources.add(
            AudioMixSource(
              samples: data,
              channels: channels,
              // A non-zero window start exercises the streaming shape.
              sourceStart: random.nextBool() ? random.nextInt(8) : 0,
            ),
          );
        }

        final clipCount = random.nextInt(5);
        final clips = <AudioMixClip>[];
        for (var index = 0; index < clipCount; index += 1) {
          final start = random.nextInt(48) - 8;
          final length = 1 + random.nextInt(32);
          // AUDIO-PRO R1 surfaces, randomized alongside the originals:
          // precomputed pan factors, the sqrt fade curve, and a small
          // sorted envelope (keys allowed BEFORE the clip too — the
          // trimmed-lead shape).
          final pan = equalPowerPanGains(random.nextDouble() * 2.0 - 1.0);
          final envelopeCount = random.nextBool() ? random.nextInt(4) : 0;
          var envelopeSample = -4 + random.nextInt(8);
          final envelope = <AudioEnvelopePoint>[
            for (var key = 0; key < envelopeCount; key += 1)
              AudioEnvelopePoint(
                sample: envelopeSample += random.nextInt(16),
                gain: random.nextDouble() * 2.0,
              ),
          ];
          clips.add(
            AudioMixClip(
              sourceIndex: random.nextInt(sourceCount + 1) - 1,
              startSample: start,
              endSample: start + length,
              sourceOffset: random.nextInt(8),
              // Past unity on purpose: the bus has headroom and both
              // sides must agree about what that sounds like.
              gain: random.nextDouble() * 2.0,
              fadeInSamples: random.nextBool() ? random.nextInt(12) : 0,
              fadeOutSamples: random.nextBool() ? random.nextInt(12) : 0,
              panLeft: random.nextBool() ? pan.left : 1.0,
              panRight: random.nextBool() ? pan.right : 1.0,
              fadeCurve: random.nextInt(2),
              envelope: envelope,
            ),
          );
        }

        final startSample = random.nextInt(40) - 8;
        final sampleCount = 1 + random.nextInt(24);
        final outChannels = 1 + random.nextInt(2);

        final fromNative = native.mix(
          clips: clips,
          sources: sources,
          startSample: startSample,
          sampleCount: sampleCount,
          outChannels: outChannels,
        );
        final fromDart = mixAudioReference(
          clips: clips,
          sources: sources,
          startSample: startSample,
          sampleCount: sampleCount,
          outChannels: outChannels,
        );
        expectIdentical(fromNative, fromDart, what: 'round $round');
      }
    }, skip: available ? false : nativeEngineMissingSkipReason);

    test('a long timeline position does not drift', () {
      // Sample-exact at any distance from zero is the mixer's whole
      // promise. A float position would have lost bits long before here.
      final native = requireNative();
      final data = Float32List(64);
      for (var index = 0; index < data.length; index += 1) {
        data[index] = index / 64.0;
      }
      final sources = [AudioMixSource(samples: data, channels: 1)];

      for (final start in const [
        0,
        48000,
        48000 * 60 * 60, // an hour
        48000 * 60 * 60 * 3, // three hours
      ]) {
        final clips = [
          AudioMixClip(
            sourceIndex: 0,
            startSample: start,
            endSample: start + 32,
            gain: 0.75,
            fadeInSamples: 8,
            fadeOutSamples: 8,
          ),
        ];
        final fromNative = native.mix(
          clips: clips,
          sources: sources,
          startSample: start - 4,
          sampleCount: 40,
          outChannels: 2,
        );
        final fromDart = mixAudioReference(
          clips: clips,
          sources: sources,
          startSample: start - 4,
          sampleCount: 40,
          outChannels: 2,
        );
        expectIdentical(fromNative, fromDart, what: 'start $start');
      }
    }, skip: available ? false : nativeEngineMissingSkipReason);

    test('dense overlap sums identically', () {
      // The case where a float bus would diverge from Dart: 40 clips
      // stacked on the same samples. Narrowing after each add would round
      // 40 times in C and once in Dart.
      final native = requireNative();
      final random = Random(4242);
      final data = Float32List(32);
      for (var index = 0; index < data.length; index += 1) {
        data[index] = random.nextDouble() * 2.0 - 1.0;
      }
      final sources = [AudioMixSource(samples: data, channels: 1)];
      final clips = [
        for (var index = 0; index < 40; index += 1)
          AudioMixClip(
            sourceIndex: 0,
            startSample: 0,
            endSample: 16,
            sourceOffset: index % 8,
            gain: 0.05 + random.nextDouble() * 0.3,
          ),
      ];

      final fromNative = native.mix(
        clips: clips,
        sources: sources,
        startSample: 0,
        sampleCount: 16,
        outChannels: 2,
      );
      final fromDart = mixAudioReference(
        clips: clips,
        sources: sources,
        startSample: 0,
        sampleCount: 16,
        outChannels: 2,
      );
      expectIdentical(fromNative, fromDart, what: 'dense overlap');
    }, skip: available ? false : nativeEngineMissingSkipReason);

    test('the output stage converts identically', () {
      final native = requireNative();
      final random = Random(99);
      final bus = Float64List(256);
      for (var index = 0; index < bus.length; index += 1) {
        // Spans past +/-1 so the clipping branch is exercised on both
        // sides, and includes exact half-LSB values so the rounding
        // contract (half away from zero) is pinned.
        bus[index] = random.nextDouble() * 5.0 - 2.5;
      }
      bus[0] = 0.5 / 32767.0;
      bus[1] = -0.5 / 32767.0;
      bus[2] = 1.0;
      bus[3] = -1.0;
      bus[4] = 0.0;

      expect(native.busToFloat(bus).toList(), audioBusToFloat(bus).toList());
      expect(native.busToInt16(bus).toList(), audioBusToInt16(bus).toList());
    }, skip: available ? false : nativeEngineMissingSkipReason);

    test('degenerate input agrees instead of crashing', () {
      final native = requireNative();
      final sources = [
        AudioMixSource(samples: Float32List.fromList([0.5]), channels: 1),
      ];

      final cases = <(List<AudioMixClip>, List<AudioMixSource>, int, int, int)>[
        (const [], const [], 0, 4, 1),
        (const [], sources, 0, 4, 2),
        (
          const [AudioMixClip(sourceIndex: 9, startSample: 0, endSample: 4)],
          sources,
          0,
          4,
          1,
        ),
        (
          const [AudioMixClip(sourceIndex: 0, startSample: 4, endSample: 2)],
          sources,
          0,
          4,
          1,
        ),
      ];
      for (var index = 0; index < cases.length; index += 1) {
        final (clips, caseSources, start, count, channels) = cases[index];
        expectIdentical(
          native.mix(
            clips: clips,
            sources: caseSources,
            startSample: start,
            sampleCount: count,
            outChannels: channels,
          ),
          mixAudioReference(
            clips: clips,
            sources: caseSources,
            startSample: start,
            sampleCount: count,
            outChannels: channels,
          ),
          what: 'degenerate case $index',
        );
      }
    }, skip: available ? false : nativeEngineMissingSkipReason);
  });
}
