import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/services/audio/conform_pcm_codec.dart';
import 'package:anicel/src/services/audio/conform_pcm_stream.dart';
import 'package:anicel/src/services/audio/wav16_header.dart';
import 'package:anicel/src/services/media/media_byte_source.dart';

/// 🚨★★★**THE CONFORM STOPPED WEARING A WAV, AND NOTHING ELSE MOVED.**
///
/// 유저 2026-08-30: 「애초에 다른프로그램에서 열 이유가 없다면 wav로 디코드?
/// 할 이유가있나?」 — the answer was no. The WAV envelope was buying one
/// thing (an ownership tag for the cache collector) and costing two chunk
/// walks that had to agree.
///
/// ⛔So the assertions here are not「it round-trips」. They are the three
/// properties the change is allowed to keep or lose:
///
/// 1. **The PCM is identical**, sample for sample, at the same 32768 scale.
/// 2. **The whole-file read and the WINDOW read parse the same header** —
///    the two used to walk separately, and a walk that agrees with itself
///    is what a round-trip test proves.
/// 3. **A file that is not ours, or is short of what it claims, is
///    REFUSED** — that refusal is what makes「rebuild it」a safe automatic
///    answer, and what lets a restore write straight to its final name.
void main() {
  late Directory dir;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('qa-conform-header');
  });

  tearDown(() {
    try {
      dir.deleteSync(recursive: true);
    } on Object {
      // A locked file on Windows must not fail the suite.
    }
  });

  var next = 0;

  /// The bytes as a source, through the entrance production uses.
  MediaByteSource sourceOf(Uint8List bytes) {
    next += 1;
    final path = '${dir.path}/take$next.aaaabbbb.wav';
    File(path).writeAsBytesSync(bytes);
    return mediaAppFileSource(path);
  }

  Float32List ramp(int n) {
    final out = Float32List(n);
    for (var i = 0; i < n; i += 1) {
      out[i] = ((i % 4096) / 4096.0) - 0.5;
    }
    return out;
  }

  Uint8List conform({
    int frames = 5000,
    int channels = 2,
    int sampleRate = 48000,
    ConformSourceFingerprint? fingerprint,
    ConformSourceStat? sourceStat,
    int speedNumerator = 1,
    int speedDenominator = 1,
  }) => encodeConform(
    samples: ramp(frames * channels),
    channels: channels,
    sampleRate: sampleRate,
    fingerprint: fingerprint,
    sourceStat: sourceStat,
    speedNumerator: speedNumerator,
    speedDenominator: speedDenominator,
  );

  group('the header', () {
    test('is a fixed 64 bytes and the PCM starts on that boundary', () {
      final bytes = conform(frames: 100);
      expect(ConformHeader.length, 64);
      expect(bytes.length, 64 + 100 * 2 * 2);
      // 🔑Not decoration: an EVEN start is what lets the converter take an
      // Int16List.view instead of pulling every sample through ByteData.
      expect(ConformHeader.length.isEven, isTrue);
    });

    test('carries everything the old qacf JSON carried', () {
      final bytes = conform(
        sampleRate: 44100,
        channels: 1,
        frames: 321,
        fingerprint: const ConformSourceFingerprint(
          sourceLength: 987654321,
          sourceCrc32: 0xDEADBEEF,
        ),
        sourceStat: const ConformSourceStat(
          sourceLength: 987654321,
          sourceModifiedMicros: 1735689600000000,
        ),
        speedNumerator: 1001,
        speedDenominator: 1000,
      );
      final head = ConformHeader.parse(bytes);
      expect(head.sampleRate, 44100);
      expect(head.channels, 1);
      expect(head.frames, 321);
      expect(head.speedNumerator, 1001);
      expect(head.speedDenominator, 1000);
      expect(head.fingerprint?.sourceLength, 987654321);
      expect(head.fingerprint?.sourceCrc32, 0xDEADBEEF);
      expect(head.sourceStat?.sourceModifiedMicros, 1735689600000000);
    });

    test('a missing fingerprint is absent, not zero', () {
      // ⛔The difference decides a reuse. A conform with NO fingerprint is
      // STALE — nothing is known about where it came from — and a zeroed
      // one would compare equal to a zero-length, zero-CRC source.
      final head = ConformHeader.parse(conform(frames: 8));
      expect(head.fingerprint, isNull);
      expect(head.sourceStat, isNull);
    });

    test('⛔a stat never rides without a fingerprint', () {
      // The stat is the cheap half of one question and cannot answer it
      // alone: conforms that carried a timestamp and no hash are exactly
      // the ones that had to be treated as unknown.
      final head = ConformHeader.parse(
        conform(
          frames: 8,
          sourceStat: const ConformSourceStat(
            sourceLength: 5,
            sourceModifiedMicros: 7,
          ),
        ),
      );
      expect(head.sourceStat, isNull);
    });

    test('⛔bytes that are not ours are refused — by the MAGIC', () {
      // 🚨★★★THE FIXTURE IS THE TEST HERE, and it took three tries.
      //
      // v1 was `RIFF`, `WAVE`, then zeroes — which put a 0 where this
      // header reads `channels`, so it threw「no channels」and passed
      // whether or not the magic was ever compared. v2 was a real WAV but
      // only 52 bytes, so it threw「too short」 — before the magic, again.
      // A mutation that deletes the magic check survived both.
      //
      // ⇒ It has to be a real WAV LONGER than the header: 'fm' at offset 12
      // makes `channels` plausible, and the length gets past the size guard,
      // so the magic is the only thing left that can refuse it.
      final wav = Uint8List.fromList([
        ...wav16HeaderBytes(dataBytes: 128, sampleRate: 48000, channels: 2),
        ...List<int>.filled(128, 0),
      ]);
      expect(
        wav.length,
        greaterThan(ConformHeader.length),
        reason: 'fixture: the LENGTH must not be the thing refusing',
      );
      expect(
        ByteData.sublistView(wav).getUint16(12, Endian.little),
        greaterThan(0),
        reason: 'fixture: the channels field must NOT be the thing refusing',
      );
      expect(
        () => ConformHeader.parse(wav),
        throwsA(isA<ConformFormatException>()),
        reason:
            'a WAV is what conforms USED to be — accepting one would read '
            'its chunk table as a fixed header',
      );
      expect(() => decodeConform(wav), throwsA(isA<ConformFormatException>()));
      expect(ConformPcmStreamReader.over(sourceOf(wav)), isNull);
      expect(
        () => ConformHeader.parse(Uint8List(10)),
        throwsA(isA<ConformFormatException>()),
      );
    });

    test('looksLikeConform is the collector\'s cheap proof', () {
      expect(looksLikeConform(conform(frames: 4)), isTrue);
      expect(looksLikeConform(Uint8List.fromList([0x52, 0x49, 0x46])), isFalse);
      expect(looksLikeConform(const <int>[]), isFalse);
    });
  });

  group('the PCM', () {
    test('round-trips at the 32768 scale, exactly', () {
      // Every int16 lands on itself through float32, so a conform written
      // from decoded samples reads back bit-identical.
      final samples = Float32List.fromList([
        0.0, 0.5, -0.5, 1.0, -1.0, 1.0 / 32768.0, -1.0 / 32768.0, 0.25,
      ]);
      final back = decodeConform(
        encodeConform(samples: samples, channels: 2, sampleRate: 48000),
      );
      expect(back.samples.length, samples.length);
      for (var i = 0; i < samples.length; i += 1) {
        // 1.0 is the one that clips: 32768 rounds to 32767 on the way in.
        final want = samples[i] == 1.0 ? 32767 / 32768.0 : samples[i];
        expect(back.samples[i], closeTo(want, 1e-7), reason: 'sample $i');
      }
    });

    test('🚨the WINDOW read and the WHOLE read agree, sample for sample', () {
      // ⛔This is the property the two chunk walks used to have to keep by
      // hand — and a walk that agrees with ITSELF is all a round-trip test
      // can see. One header parse is what makes it structural.
      final bytes = conform(frames: 9000);
      final whole = decodeConform(bytes);
      final reader = ConformPcmStreamReader.over(sourceOf(bytes))!;
      expect(reader.channels, 2);
      expect(reader.sampleRate, 48000);
      expect(reader.length, whole.length);

      for (final at in <int>[0, 1, 1234, 8000, 8999]) {
        final window = reader.readWindow(at, 250);
        expect(window.startSample, at);
        for (var i = 0; i < window.samples.length; i += 1) {
          expect(
            window.samples[i],
            whole.samples[at * 2 + i],
            reason: 'sample $i of the window at $at',
          );
        }
      }
    });

    test('a window clamps into the file rather than inventing samples', () {
      final reader = ConformPcmStreamReader.over(sourceOf(conform(frames: 1000)))!;
      expect(reader.readWindow(-50, 100).startSample, 0);
      expect(reader.readWindow(950, 100).samples, hasLength(50 * 2));
      expect(reader.readWindow(5000, 100).samples, isEmpty);
    });
  });

  group('a broken conform is refused, not half-read', () {
    test('short of the PCM it claims — decode throws', () {
      final bytes = conform(frames: 500);
      final cut = Uint8List.sublistView(bytes, 0, bytes.length - 200);
      expect(
        () => decodeConform(cut),
        throwsA(isA<ConformFormatException>()),
        reason:
            '⛔this refusal is what makes a restore safe to write straight '
            'to its final name: a kill mid-write is rebuilt, never played',
      );
    });

    test('short of the PCM it claims — the stream reader will not open', () {
      final bytes = conform(frames: 500);
      final cut = Uint8List.sublistView(bytes, 0, bytes.length - 200);
      expect(
        ConformPcmStreamReader.over(sourceOf(cut)),
        isNull,
        reason:
            'opening it would serve silence from past the end instead of '
            'saying the conform is unusable',
      );
    });

    test('not a conform at all — the stream reader will not open', () {
      expect(
        ConformPcmStreamReader.over(sourceOf(Uint8List.fromList([1, 2, 3, 4]))),
        isNull,
      );
    });
  });
}

