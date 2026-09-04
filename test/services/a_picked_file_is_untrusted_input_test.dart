import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/services/abr/abr_decoder.dart';
import 'package:anicel/src/services/abr/photoshop_pattern.dart';
import 'package:anicel/src/models/import/tvpp_parse.dart';
import 'package:anicel/src/services/photoshop/psd_reader.dart';

/// 🚨A FILE THE USER PICKED IS UNTRUSTED INPUT.
///
/// Every one of these readers walks a length-prefixed binary format, and
/// the lengths come from the file. A truncated download, a half-written
/// export or somebody's unrelated .abr must end as "nothing usable", never
/// as a crash out of the import and never as a walk that does not finish.
///
/// This drives each reader with bytes shaped to break it — the header it
/// looks for followed by garbage, so it gets PAST the sniff and into the
/// walk, which is where the length arithmetic lives. A sniff-only test
/// would prove nothing about the part that reads.
void main() {
  Uint8List bytesOf(List<int> values) => Uint8List.fromList(values);

  /// Deterministic garbage — a seed, not a clock, so a failure is a
  /// failure anyone can reproduce.
  Uint8List noiseAfter(List<int> header, int length, int seed) {
    final random = math.Random(seed);
    return bytesOf([
      ...header,
      for (var i = 0; i < length; i += 1) random.nextInt(256),
    ]);
  }

  group('the PSD reader', () {
    // '8BPS', version 1 — what looksLikePsdBytes asks for.
    const header = [0x38, 0x42, 0x50, 0x53, 0x00, 0x01];

    test('empty bytes are not a PSD', () {
      expect(looksLikePsdBytes(Uint8List(0)), isFalse);
    });

    test('the sniff wants the signature, not the extension', () {
      expect(looksLikePsdBytes(bytesOf([...header, 0, 0])), isTrue);
      expect(
        looksLikePsdBytes(bytesOf([0x89, 0x50, 0x4e, 0x47, 0, 0])),
        isFalse,
      );
    });

    test('a header followed by GARBAGE is refused, not crashed through', () {
      for (var seed = 0; seed < 40; seed += 1) {
        expect(
          () => readPsdDocument(noiseAfter(header, 200, seed)),
          throwsA(isA<FormatException>()),
          reason: 'seed $seed',
        );
      }
    });

    test('a NON-PSD says so — the sniff answers before the walk, so the '
        'message names the real problem instead of whatever byte ran out '
        'first', () {
      expect(
        () => readPsdDocument(bytesOf([0x89, 0x50, 0x4e, 0x47, 0, 0, 0, 0])),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            'Not a Photoshop document.',
          ),
        ),
      );
    });

    test('a TRUNCATED header is refused', () {
      for (var length = 0; length < header.length; length += 1) {
        expect(
          () => readPsdDocument(bytesOf(header.sublist(0, length))),
          throwsA(isA<FormatException>()),
          reason: 'length $length',
        );
      }
    });
  });

  group('the ABR reader', () {
    // The version words the section walk reads before it seeks 8BIM.
    const header = [0x00, 0x06, 0x00, 0x02];

    test('garbage fails as an AbrDecodeException — the ONE failure the '
        'import catches, never a RangeError out of the byte walk', () {
      for (var seed = 0; seed < 40; seed += 1) {
        expect(
          () => decodeAbrBrushFile(
            noiseAfter(header, 400, seed),
            sourceName: 'somebody-elses.abr',
          ),
          throwsA(isA<AbrDecodeException>()),
          reason: 'seed $seed',
        );
      }
    });

    test('an EMPTY file fails the same way', () {
      expect(
        () => decodeAbrBrushFile(Uint8List(0), sourceName: 'empty.abr'),
        throwsA(isA<AbrDecodeException>()),
      );
    });
  });

  group('the ABR pattern section', () {
    test('garbage yields no patterns and terminates', () {
      for (var seed = 0; seed < 40; seed += 1) {
        expect(
          readPatternSection(noiseAfter(const [], 300, seed)),
          isEmpty,
          reason: 'seed $seed',
        );
      }
    });

    test('a record claiming MORE than the payload holds stops the walk '
        'rather than reading past it', () {
      // A four-byte length of 0x7FFFFFFF followed by almost nothing.
      final payload = bytesOf([0x7f, 0xff, 0xff, 0xff, ...List.filled(20, 0)]);

      expect(readPatternSection(payload), isEmpty);
    });

    test('a NEGATIVE record length stops the walk', () {
      final payload = bytesOf([0xff, 0xff, 0xff, 0xff, ...List.filled(20, 0)]);

      expect(readPatternSection(payload), isEmpty);
    });
  });

  group('the .tvpp structure reader', () {
    test('bytes with no clip header are refused', () {
      for (var seed = 0; seed < 20; seed += 1) {
        expect(
          () => parseTvppStructure(noiseAfter(const [], 300, seed)),
          throwsA(isA<TvppParseException>()),
          reason: 'seed $seed',
        );
      }
    });
  });
}
