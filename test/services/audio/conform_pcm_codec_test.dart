import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/project_frame_rate.dart';
import 'package:anicel/src/services/audio/conform_pcm_codec.dart';
import 'package:anicel/src/services/audio/wav16_header.dart';

void main() {
  const fingerprint = ConformSourceFingerprint(
    sourceLength: 123456,
    sourceCrc32: 0x9AE0DAAF,
  );

  Float32List ramp(int count) {
    final data = Float32List(count);
    for (var index = 0; index < count; index += 1) {
      data[index] = (index / count) * 2.0 - 1.0;
    }
    return data;
  }

  group('round trip', () {
    test('samples survive a write/read cycle within one LSB', () {
      final samples = ramp(512);
      final decoded = decodeConform(
        encodeConform(samples: samples, channels: 2, sampleRate: 48000),
      );
      expect(decoded.channels, 2);
      expect(decoded.sampleRate, 48000);
      expect(decoded.samples.length, samples.length);
      for (var index = 0; index < samples.length; index += 1) {
        expect(
          decoded.samples[index],
          closeTo(samples[index], 1 / 32767.0),
          reason: 'sample $index',
        );
      }
    });

    test('raw int16 values round trip bit-exactly', () {
      // The 32768 convention (dr_wav's, and the industry's) means every
      // stored sample comes back as itself. -1.0 maps to -32768 exactly;
      // +1.0 is the one value that clamps, since 32768 does not fit an
      // int16 — so it returns 32767/32768, an LSB short of full scale.
      final raw = <int>[-32768, -32767, -1, 0, 1, 16384, 32767];
      final samples = Float32List.fromList([
        for (final value in raw) value / 32768.0,
      ]);
      final decoded = decodeConform(
        encodeConform(samples: samples, channels: 1, sampleRate: 48000),
      );
      expect(decoded.samples.toList(), samples.toList());

      final edges = decodeConform(
        encodeConform(
          samples: Float32List.fromList([1.0, -1.0, 0.0]),
          channels: 1,
          sampleRate: 48000,
        ),
      );
      expect(edges.samples.toList(), [32767 / 32768.0, -1.0, 0.0]);
    });

    test('values past full scale clip — a container has no headroom', () {
      final decoded = decodeConform(
        encodeConform(
          samples: Float32List.fromList([2.5, -2.5]),
          channels: 1,
          sampleRate: 48000,
        ),
      );
      // The positive rail is 32767/32768 — an LSB short of 1.0, because
      // 32768 does not fit an int16. The negative rail reaches -1.0 exactly.
      expect(decoded.samples.toList(), [32767 / 32768.0, -1.0]);
    });

    test('an odd sample count stays word-aligned and readable', () {
      // 3 samples = 6 bytes of data: even. 1 sample = 2 bytes. The pad
      // path needs an odd BYTE count, which 16-bit PCM never produces —
      // this pins that the writer still emits a valid file either way.
      for (final count in const [1, 3, 7, 33]) {
        final decoded = decodeConform(
          encodeConform(samples: ramp(count), channels: 1, sampleRate: 48000),
        );
        expect(decoded.samples.length, count, reason: 'count $count');
      }
    });
  });

  group('provenance', () {
    test('the fingerprint survives the round trip', () {
      final decoded = decodeConform(
        encodeConform(
          samples: ramp(64),
          channels: 1,
          sampleRate: 48000,
          fingerprint: fingerprint,
        ),
      );
      expect(decoded.fingerprint, fingerprint);
      expect(conformMatchesSource(decoded, fingerprint), isTrue);
    });

    test('a replaced source is detected', () {
      final decoded = decodeConform(
        encodeConform(
          samples: ramp(64),
          channels: 1,
          sampleRate: 48000,
          fingerprint: fingerprint,
        ),
      );
      const edited = ConformSourceFingerprint(
        sourceLength: 123456,
        sourceCrc32: 0x9AE0DAB0, // same size, different bytes
      );
      expect(conformMatchesSource(decoded, edited), isFalse);

      const regrown = ConformSourceFingerprint(
        sourceLength: 999999, // different length
        sourceCrc32: 0x9AE0DAAF,
      );
      expect(conformMatchesSource(decoded, regrown), isFalse);
    });

    test('a conform with no fingerprint counts as stale', () {
      // Written by another tool: nothing is known about where it came
      // from, and guessing wrong plays the wrong sound against someone's
      // drawing.
      final decoded = decodeConform(
        encodeConform(samples: ramp(16), channels: 1, sampleRate: 48000),
      );
      expect(decoded.fingerprint, isNull);
      expect(conformMatchesSource(decoded, fingerprint), isFalse);
    });

    test('🪦a corrupt provenance chunk is not a state any more', () {
      // The provenance used to be JSON inside a `qacf` RIFF chunk, so it
      // could be well-framed and unreadable at once — and the rule was
      // 「unreadable = unknown, the audio is still fine」. A fixed header has
      // no such middle: the fields are either there or the magic is wrong.
      //
      // ⛔What survived is the CONSEQUENCE, and it is what this now pins:
      // a conform whose fingerprint is absent counts as STALE, so it is
      // rebuilt rather than played against the wrong source.
      final noFingerprint = decodeConform(
        encodeConform(samples: ramp(16), channels: 1, sampleRate: 48000),
      );
      expect(noFingerprint.fingerprint, isNull);
      expect(noFingerprint.samples.length, 16, reason: 'the audio is fine');
      expect(
        conformMatchesSource(noFingerprint, fingerprint),
        isFalse,
        reason: 'unknown provenance means rebuild, never「probably fine」',
      );
    });
  });

  group('reading files we did not write', () {
    test('🪦a WAV is one of them now', () {
      // Conforms were WAVs until 2026-08-30, so this group used to be about
      // TOLERANCE: unknown chunks stepped over, a truncated tail keeping
      // whatever was whole. None of that is a property any more — a conform
      // is a fixed header this app writes, and everything else is refused.
      //
      // 유저 asked the question that removed it: 「애초에 다른프로그램에서 열
      // 이유가 없다면 wav로 디코드? 할 이유가있나?」
      final wav = Uint8List.fromList([
        ...wav16HeaderBytes(dataBytes: 4, sampleRate: 48000, channels: 1),
        0,
        0,
        0,
        0,
      ]);
      expect(
        () => decodeConform(wav),
        throwsA(isA<ConformFormatException>()),
        reason: 'a real WAV is a foreign file to this codec',
      );
    });

    test('🚨a conform SHORT of the PCM it claims is refused', () {
      // ⛔The one tolerance that would be dangerous. A restore killed
      // mid-write leaves exactly this, and reading it would serve silence
      // from past the end rather than saying「rebuild me」 — which is what
      // lets the restore write straight to its final name with no `.part`
      // neighbour to leak.
      final base = encodeConform(
        samples: ramp(64),
        channels: 1,
        sampleRate: 48000,
        fingerprint: fingerprint,
      );
      expect(
        () => decodeConform(base.sublist(0, base.length - 40)),
        throwsA(isA<ConformFormatException>()),
      );
      expect(
        () => decodeConform(base.sublist(0, ConformHeader.length)),
        throwsA(isA<ConformFormatException>()),
        reason: 'a header with no PCM behind it is not an empty conform',
      );
    });
  });

  group('rejects what it cannot honestly read', () {
    test('bytes without our magic', () {
      expect(
        () => decodeConform(Uint8List.fromList(utf8.encode('not a wav!!!'))),
        throwsA(isA<ConformFormatException>()),
      );
      expect(
        () => decodeConform(Uint8List(4)),
        throwsA(isA<ConformFormatException>()),
      );
    });

    test('a bit depth we do not write', () {
      final base = encodeConform(
        samples: ramp(8),
        channels: 1,
        sampleRate: 48000,
      );
      final fmtAt = _findChunk(base, 'fmt ');
      ByteData.view(base.buffer).setUint16(fmtAt + 8 + 14, 24, Endian.little);
      expect(() => decodeConform(base), throwsA(isA<ConformFormatException>()));
    });

    test('nonsense geometry is refused at write time', () {
      expect(
        () => encodeConform(
          samples: Float32List(4),
          channels: 0,
          sampleRate: 48000,
        ),
        throwsA(isA<ConformFormatException>()),
      );
      expect(
        () =>
            encodeConform(samples: Float32List(4), channels: 1, sampleRate: 0),
        throwsA(isA<ConformFormatException>()),
      );
    });
  });

  group('the timing bridge', () {
    test('duration is an exact ratio, never a double', () {
      // A double here is how "2 seconds" became 49 frames before RT.
      final decoded = decodeConform(
        encodeConform(
          samples: Float32List(48000 * 2),
          channels: 1,
          sampleRate: 48000,
        ),
      );
      final duration = decoded.durationSeconds;
      expect(duration.numerator, 96000);
      expect(duration.denominator, 48000);

      const rate = ProjectFrameRate.fps24;
      expect(
        rate.framesCoveringExactSeconds(
          duration.numerator,
          duration.denominator,
        ),
        48,
        reason: 'exactly 2 seconds is exactly 48 frames, not 49',
      );
    });

    test('stereo length counts sample frames, not raw samples', () {
      final decoded = decodeConform(
        encodeConform(
          samples: Float32List(48000 * 2 * 2),
          channels: 2,
          sampleRate: 48000,
        ),
      );
      expect(decoded.length, 96000, reason: '2 seconds of stereo');
      const rate = ProjectFrameRate.fps24;
      final duration = decoded.durationSeconds;
      expect(
        rate.framesCoveringExactSeconds(
          duration.numerator,
          duration.denominator,
        ),
        48,
      );
    });
  });
}

/// Byte offset of the named chunk header, or -1.
int _findChunk(Uint8List bytes, String id) {
  final marker = utf8.encode(id);
  for (var index = 12; index + 8 <= bytes.length; index += 1) {
    var hit = true;
    for (var offset = 0; offset < 4; offset += 1) {
      if (bytes[index + offset] != marker[offset]) {
        hit = false;
        break;
      }
    }
    if (hit) {
      return index;
    }
  }
  return -1;
}
