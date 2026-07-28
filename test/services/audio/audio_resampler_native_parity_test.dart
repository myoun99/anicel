import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/native/qa_audio_native.dart';
import 'package:anicel/src/native/qa_engine_abi.dart';
import 'package:anicel/src/services/audio/audio_resampler_reference.dart';

import '../../helpers/native_engine_path.dart';

/// The C resampler must be BIT-IDENTICAL to the Dart reference.
///
/// The reference went in first and had its maths pinned by measurement —
/// 135 dB of rejection, a passband flat to 0.1 dB, and an impulse that
/// comes out where it went in. This suite makes the C inherit all of that
/// rather than re-argue it: if the two agree bit for bit, every number
/// already proven about one holds for the other.
///
/// A resampler is a multiply-accumulate loop, so it is exactly the shape
/// #614 caught Apple clang contracting into an FMA that rounds once where
/// Dart rounds twice.
void main() {
  final libraryPath = nativeEngineLibraryPathOrNull();
  final available = libraryPath != null;
  final skip = available ? false : nativeEngineMissingSkipReason;

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
          'the binary at $libraryPath loaded but the resampler entry points '
          'did not bind — an ABI mismatch, which is what this suite exists '
          'to catch',
    );
    return native!;
  }

  void expectIdentical(
    Float32List native,
    Float32List reference, {
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

  Float32List noise(int frames, int channels, int seed) {
    final random = math.Random(seed);
    final out = Float32List(frames * channels);
    for (var index = 0; index < out.length; index += 1) {
      out[index] = random.nextDouble() * 2.0 - 1.0;
    }
    return out;
  }

  group('resampler byte parity', () {
    test('the entry points bind', () {
      requireNative();
    }, skip: skip);

    test('every standard rate pair agrees bit for bit', () {
      final native = requireNative();
      const pairs = [
        (44100, 48000),
        (48000, 44100),
        (22050, 48000),
        (48000, 24000),
        (32000, 48000),
        (48000, 96000),
        (96000, 48000),
        (8000, 48000),
        (11025, 44100),
      ];
      for (final (inputRate, outputRate) in pairs) {
        final samples = noise(2000, 1, inputRate);
        final fromNative = native.resample(
          samples: samples,
          channels: 1,
          inputRate: inputRate,
          outputRate: outputRate,
        );
        final fromDart = resampleAudioReference(
          samples: samples,
          channels: 1,
          inputRate: inputRate,
          outputRate: outputRate,
        );
        expectIdentical(
          fromNative,
          fromDart.samples,
          what: '$inputRate → $outputRate',
        );
      }
    }, skip: skip);

    test('multichannel interleaving agrees', () {
      final native = requireNative();
      for (final channels in const [1, 2, 6]) {
        final samples = noise(1500, channels, 90 + channels);
        expectIdentical(
          native.resample(
            samples: samples,
            channels: channels,
            inputRate: 44100,
            outputRate: 48000,
          ),
          resampleAudioReference(
            samples: samples,
            channels: channels,
            inputRate: 44100,
            outputRate: 48000,
          ).samples,
          what: '$channels channels',
        );
      }
    }, skip: skip);

    test('an impulse — where the delay compensation shows — agrees', () {
      // The edges are where the two could most easily diverge: the
      // convolution runs off the ends and the compensation offset decides
      // exactly which taps participate.
      final native = requireNative();
      for (final at in const [0, 1, 500, 1999]) {
        final samples = Float32List(2000);
        samples[at] = 1.0;
        expectIdentical(
          native.resample(
            samples: samples,
            channels: 1,
            inputRate: 44100,
            outputRate: 48000,
          ),
          resampleAudioReference(
            samples: samples,
            channels: 1,
            inputRate: 44100,
            outputRate: 48000,
          ).samples,
          what: 'impulse at $at',
        );
      }
    }, skip: skip);

    test('the filter design parameters agree', () {
      // Different stopband or bandwidth settings must pick the SAME tap
      // count on both sides — a one-tap disagreement shifts every phase.
      final native = requireNative();
      for (final stopband in const [90.0, 120.0, 150.0]) {
        for (final bandwidth in const [0.85, 0.90, 0.95]) {
          final samples = noise(800, 1, 7);
          expectIdentical(
            native.resample(
              samples: samples,
              channels: 1,
              inputRate: 44100,
              outputRate: 48000,
              stopbandDb: stopband,
              bandwidth: bandwidth,
            ),
            resampleAudioReference(
              samples: samples,
              channels: 1,
              inputRate: 44100,
              outputRate: 48000,
              stopbandDb: stopband,
              bandwidth: bandwidth,
            ).samples,
            what: 'stopband $stopband, bandwidth $bandwidth',
          );
        }
      }
    }, skip: skip);

    test('equal rates pass through untouched on both sides', () {
      final native = requireNative();
      final samples = noise(500, 2, 11);
      final fromNative = native.resample(
        samples: samples,
        channels: 2,
        inputRate: 48000,
        outputRate: 48000,
      );
      expect(identical(fromNative, samples), isTrue);
      expect(
        resampleAudioReference(
          samples: samples,
          channels: 2,
          inputRate: 48000,
          outputRate: 48000,
        ).passthrough,
        isTrue,
      );
    }, skip: skip);

    test('degenerate geometry agrees instead of crashing', () {
      final native = requireNative();
      expect(
        native.resample(
          samples: Float32List(0),
          channels: 1,
          inputRate: 44100,
          outputRate: 48000,
        ),
        isEmpty,
      );
      expect(
        native.resample(
          samples: Float32List(8),
          channels: 0,
          inputRate: 44100,
          outputRate: 48000,
        ),
        isEmpty,
      );
      expect(
        native.resample(
          samples: Float32List(8),
          channels: 1,
          inputRate: 0,
          outputRate: 48000,
        ),
        isEmpty,
      );
    }, skip: skip);
  });
}
