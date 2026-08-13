import 'dart:io';

import 'package:anicel/src/models/media_identity.dart';
import 'package:anicel/src/services/import/media_identity_reader.dart';
import 'package:flutter_test/flutter_test.dart';

/// Identity answers "is this the same file?" — the question relink asks
/// after a file has moved. It is deliberately NOT the mtime+size stamp
/// beside it, which answers "did the original change?" and therefore stops
/// matching in exactly the situation relink is for.
void main() {
  group('comparing', () {
    test('a different length is a decisive NO, for free', () {
      // The cheap half earning its keep: two drawings both called A1.png
      // almost always differ here, and nothing had to be read.
      expect(
        const MediaIdentity(lengthBytes: 100)
            .compare(const MediaIdentity(lengthBytes: 101)),
        MediaIdentityMatch.different,
      );
    });

    test('equal lengths alone are NOT a match — they are unknown', () {
      // The whole reason this is three-valued. Answering `true` here picks
      // a wrong drawing for someone the moment two files happen to weigh
      // the same, and the relink rule is that an unforced choice is not
      // made.
      expect(
        const MediaIdentity(lengthBytes: 100)
            .compare(const MediaIdentity(lengthBytes: 100)),
        MediaIdentityMatch.unknown,
      );
    });

    test('a CRC decides only when BOTH sides have one', () {
      const withCrc = MediaIdentity(lengthBytes: 100, crc32: 0xabcd);
      const bare = MediaIdentity(lengthBytes: 100);
      expect(withCrc.compare(bare), MediaIdentityMatch.unknown);
      expect(bare.compare(withCrc), MediaIdentityMatch.unknown);
      expect(withCrc.compare(withCrc), MediaIdentityMatch.same);
      expect(
        withCrc.compare(const MediaIdentity(lengthBytes: 100, crc32: 0x1234)),
        MediaIdentityMatch.different,
      );
    });

    test('length still wins over a matching CRC', () {
      // Length is checked first and is decisive, so a CRC collision cannot
      // talk two differently-sized files into being the same one.
      expect(
        const MediaIdentity(lengthBytes: 100, crc32: 0xabcd)
            .compare(const MediaIdentity(lengthBytes: 200, crc32: 0xabcd)),
        MediaIdentityMatch.different,
      );
    });
  });

  group('serialization', () {
    test('round-trips with and without a CRC', () {
      const bare = MediaIdentity(lengthBytes: 4096);
      const full = MediaIdentity(lengthBytes: 4096, crc32: 0xdeadbeef);
      expect(bare.toJson(), '4096');
      expect(full.toJson(), '4096:deadbeef');
      expect(MediaIdentity.fromJson(bare.toJson()), bare);
      expect(MediaIdentity.fromJson(full.toJson()), full);
    });

    test('junk reads back as null instead of throwing', () {
      // A project written by a future build must not stop an older one from
      // opening: the format is allowed to break, the reader is not.
      for (final junk in <Object?>[
        null,
        '',
        'nonsense',
        ':',
        '-1',
        <String, String>{},
        12,
      ]) {
        expect(MediaIdentity.fromJson(junk), isNull, reason: 'for $junk');
      }
    });

    test('an unreadable CRC degrades to length, not to nothing', () {
      // Half the evidence is still evidence — a length mismatch stays
      // decisive.
      final parsed = MediaIdentity.fromJson('4096:zzz');
      expect(parsed, const MediaIdentity(lengthBytes: 4096));
    });
  });

  group('reading one off disk', () {
    late Directory temp;

    setUp(() => temp = Directory.systemTemp.createTempSync('qa_identity_'));
    tearDown(() {
      try {
        temp.deleteSync(recursive: true);
      } on Object {
        // A locked file on Windows must not fail the suite.
      }
    });

    test('records the length and NOT a CRC', () {
      // Reading every referenced file end to end at import time is the cost
      // this deliberately does not pay — and after the media move the files
      // that stay references are the big ones.
      final file = File('${temp.path}/a.png')
        ..writeAsBytesSync(List<int>.filled(1234, 7));
      final identity = readMediaIdentity(file.path);
      expect(identity, isNotNull);
      expect(identity!.lengthBytes, 1234);
      expect(identity.crc32, isNull);
    });

    test('a missing path and a DIRECTORY both read as null', () {
      // `File(dir).existsSync()` answers false for a directory, so a naive
      // check would call a folder "missing" rather than "not a file".
      expect(readMediaIdentity('${temp.path}/nope.png'), isNull);
      expect(readMediaIdentity(temp.path), isNull);
    });

    test('a file that changed size stops matching what was recorded', () {
      final file = File('${temp.path}/b.png')
        ..writeAsBytesSync(List<int>.filled(10, 1));
      final before = readMediaIdentity(file.path)!;
      file.writeAsBytesSync(List<int>.filled(11, 1));
      final after = readMediaIdentity(file.path)!;
      expect(before.compare(after), MediaIdentityMatch.different);
    });

    test('a file MOVED unchanged still matches — the point of all this', () {
      // The mtime+size stamp fails this exact case on some platforms and
      // every copy, which is why identity is a separate field.
      final file = File('${temp.path}/c.png')
        ..writeAsBytesSync(List<int>.filled(2048, 3));
      final before = readMediaIdentity(file.path)!;
      final moved = '${temp.path}/moved-c.png';
      file.renameSync(moved);
      expect(before.compare(readMediaIdentity(moved)!),
          isNot(MediaIdentityMatch.different));
    });
  });
}
