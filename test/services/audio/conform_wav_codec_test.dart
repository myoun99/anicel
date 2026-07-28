import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/project_frame_rate.dart';
import 'package:anicel/src/services/audio/conform_wav_codec.dart';

void main() {
  const fingerprint = ConformSourceFingerprint(
    sourceLength: 123456,
    sourceModifiedMicros: 1784000000000000,
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
      final decoded = decodeConformWav(
        encodeConformWav(samples: samples, channels: 2, sampleRate: 48000),
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
      final decoded = decodeConformWav(
        encodeConformWav(samples: samples, channels: 1, sampleRate: 48000),
      );
      expect(decoded.samples.toList(), samples.toList());

      final edges = decodeConformWav(
        encodeConformWav(
          samples: Float32List.fromList([1.0, -1.0, 0.0]),
          channels: 1,
          sampleRate: 48000,
        ),
      );
      expect(edges.samples.toList(), [32767 / 32768.0, -1.0, 0.0]);
    });

    test('values past full scale clip — a container has no headroom', () {
      final decoded = decodeConformWav(
        encodeConformWav(
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
        final decoded = decodeConformWav(
          encodeConformWav(
            samples: ramp(count),
            channels: 1,
            sampleRate: 48000,
          ),
        );
        expect(decoded.samples.length, count, reason: 'count $count');
      }
    });
  });

  group('provenance', () {
    test('the fingerprint survives the round trip', () {
      final decoded = decodeConformWav(
        encodeConformWav(
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
      final decoded = decodeConformWav(
        encodeConformWav(
          samples: ramp(64),
          channels: 1,
          sampleRate: 48000,
          fingerprint: fingerprint,
        ),
      );
      const edited = ConformSourceFingerprint(
        sourceLength: 123456,
        sourceModifiedMicros: 1784000000000001, // touched
      );
      expect(conformMatchesSource(decoded, edited), isFalse);

      const regrown = ConformSourceFingerprint(
        sourceLength: 999999, // different bytes
        sourceModifiedMicros: 1784000000000000,
      );
      expect(conformMatchesSource(decoded, regrown), isFalse);
    });

    test('a conform with no fingerprint counts as stale', () {
      // Written by another tool: nothing is known about where it came
      // from, and guessing wrong plays the wrong sound against someone's
      // drawing.
      final decoded = decodeConformWav(
        encodeConformWav(samples: ramp(16), channels: 1, sampleRate: 48000),
      );
      expect(decoded.fingerprint, isNull);
      expect(conformMatchesSource(decoded, fingerprint), isFalse);
    });

    test('a corrupt provenance chunk does not fail the open', () {
      final good = encodeConformWav(
        samples: ramp(16),
        channels: 1,
        sampleRate: 48000,
        fingerprint: fingerprint,
      );
      // Scribble over the JSON payload but keep the chunk framing.
      final marker = utf8.encode('sourceLength');
      var at = -1;
      for (var index = 0; index + marker.length <= good.length; index += 1) {
        var hit = true;
        for (var offset = 0; offset < marker.length; offset += 1) {
          if (good[index + offset] != marker[offset]) {
            hit = false;
            break;
          }
        }
        if (hit) {
          at = index;
          break;
        }
      }
      expect(at, greaterThan(0), reason: 'the provenance chunk should be there');
      good[at] = 0x00;

      final decoded = decodeConformWav(good);
      expect(decoded.fingerprint, isNull, reason: 'unreadable = unknown');
      expect(decoded.samples.length, 16, reason: 'the audio is still fine');
    });
  });

  group('reading files we did not write', () {
    test('unknown chunks before data are skipped, not tripped over', () {
      // Real WAVs carry LIST/fact/bext in arbitrary order. Splice a fake
      // 'LIST' chunk in between fmt and data.
      final base = encodeConformWav(
        samples: Float32List.fromList([0.5, -0.5]),
        channels: 1,
        sampleRate: 48000,
      );
      final dataAt = _findChunk(base, 'data');
      expect(dataAt, greaterThan(0));

      const payload = 6;
      final spliced = Uint8List(base.length + 8 + payload);
      spliced.setRange(0, dataAt, base);
      final view = ByteData.view(spliced.buffer);
      spliced.setRange(dataAt, dataAt + 4, utf8.encode('LIST'));
      view.setUint32(dataAt + 4, payload, Endian.little);
      spliced.setRange(
        dataAt + 8 + payload,
        spliced.length,
        base.sublist(dataAt),
      );
      view.setUint32(4, spliced.length - 8, Endian.little);

      final decoded = decodeConformWav(spliced);
      // The point here is that the LIST chunk was stepped over and the
      // data chunk still found — the samples carry the usual 16-bit
      // quantization, nothing more.
      expect(decoded.samples.length, 2);
      expect(decoded.samples[0], closeTo(0.5, 1 / 32767.0));
      expect(decoded.samples[1], closeTo(-0.5, 1 / 32767.0));
    });

    test('a truncated tail keeps the chunks that are whole', () {
      final base = encodeConformWav(
        samples: ramp(64),
        channels: 1,
        sampleRate: 48000,
        fingerprint: fingerprint,
      );
      // Lop off the data chunk entirely; fmt and qacf remain.
      final dataAt = _findChunk(base, 'data');
      expect(
        () => decodeConformWav(base.sublist(0, dataAt)),
        throwsA(isA<ConformFormatException>()),
        reason: 'no data chunk means no audio, which must be explicit',
      );
    });
  });

  group('rejects what it cannot honestly read', () {
    test('non-RIFF bytes', () {
      expect(
        () => decodeConformWav(Uint8List.fromList(utf8.encode('not a wav!!!'))),
        throwsA(isA<ConformFormatException>()),
      );
      expect(
        () => decodeConformWav(Uint8List(4)),
        throwsA(isA<ConformFormatException>()),
      );
    });

    test('a bit depth we do not write', () {
      final base = encodeConformWav(
        samples: ramp(8),
        channels: 1,
        sampleRate: 48000,
      );
      final fmtAt = _findChunk(base, 'fmt ');
      ByteData.view(base.buffer).setUint16(fmtAt + 8 + 14, 24, Endian.little);
      expect(
        () => decodeConformWav(base),
        throwsA(isA<ConformFormatException>()),
      );
    });

    test('nonsense geometry is refused at write time', () {
      expect(
        () => encodeConformWav(
          samples: Float32List(4),
          channels: 0,
          sampleRate: 48000,
        ),
        throwsA(isA<ConformFormatException>()),
      );
      expect(
        () => encodeConformWav(
          samples: Float32List(4),
          channels: 1,
          sampleRate: 0,
        ),
        throwsA(isA<ConformFormatException>()),
      );
    });
  });

  group('the timing bridge', () {
    test('duration is an exact ratio, never a double', () {
      // A double here is how "2 seconds" became 49 frames before RT.
      final decoded = decodeConformWav(
        encodeConformWav(
          samples: Float32List(48000 * 2),
          channels: 1,
          sampleRate: 48000,
        ),
      );
      final duration = decoded.durationSeconds;
      expect(duration.numerator, 96000);
      expect(duration.denominator, 48000);

      const rate = ProjectFrameRate.integer(24);
      expect(
        rate.framesCoveringExactSeconds(duration.numerator, duration.denominator),
        48,
        reason: 'exactly 2 seconds is exactly 48 frames, not 49',
      );
    });

    test('stereo length counts sample frames, not raw samples', () {
      final decoded = decodeConformWav(
        encodeConformWav(
          samples: Float32List(48000 * 2 * 2),
          channels: 2,
          sampleRate: 48000,
        ),
      );
      expect(decoded.length, 96000, reason: '2 seconds of stereo');
      const rate = ProjectFrameRate.integer(24);
      final duration = decoded.durationSeconds;
      expect(
        rate.framesCoveringExactSeconds(duration.numerator, duration.denominator),
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
