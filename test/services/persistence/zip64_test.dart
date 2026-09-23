import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/services/persistence/anicel_incremental_writer.dart';
import '../../helpers/temp_dir.dart';

/// ZIP64 — what happens past the limits a 1989 format was given.
///
/// The plain end-of-central-directory record holds the entry count in
/// SIXTEEN bits and the central directory's offset in thirty-two. Dart's
/// `ByteData.setUint16` truncates rather than throwing, so entry 65,536
/// used to write a count of zero and the reader believed it: the project
/// opened with nothing in it, silently, with every byte still on disk.
///
/// 🚨 That ceiling is not far away. One entry per cel is what makes a cel
/// addressable by `{offset, length}` without inflating the archive — the
/// thing that lets a 1500-cut project open at all — and 1500 cuts at a
/// few dozen cels each clears 65,535 comfortably.
void main() {
  late Directory temp;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('qa_zip64_');
  });

  tearDown(() => deleteTempQuietly(temp));

  /// Entries small enough that sixty-six thousand of them is a few
  /// megabytes — the COUNT is what is being tested, never the bytes.
  Iterable<({String name, Uint8List bytes})> manyEntries(int count) sync* {
    for (var i = 0; i < count; i += 1) {
      yield (
        name: 'cels/$i.celz',
        bytes: Uint8List.fromList([i & 0xFF, (i >> 8) & 0xFF]),
      );
    }
  }

  group('the shipping shape — ZIP64 always, at any size', () {
    // `anicelAlwaysZip64` is true in production, so this is the ordinary
    // archive. Set explicitly anyway: a test that depends on a global
    // should say which value it is depending on.
    setUp(() => anicelAlwaysZip64 = true);

    test('the SHIPPED default is always-ZIP64', () {
      // The mutable switch is reset by the test config, so only the const
      // mirror can pin what production actually starts with — without
      // this, flipping the shipped default keeps every suite green.
      expect(anicelAlwaysZip64Shipped, isTrue);
    });

    test('a three-entry archive round-trips through the ZIP64 records', () {
      final path = '${temp.path}/tiny64.anicel';
      writeAnicelArchiveFile(path: path, entries: manyEntries(3));

      final bytes = File(path).readAsBytesSync();
      expect(_containsSignature(bytes, 0x06064b50), isTrue, reason: 'end');
      expect(_containsSignature(bytes, 0x07064b50), isTrue, reason: 'locator');

      // Both readers: the in-memory one and the tail-reading one, which
      // compute the central directory's end differently and so can drift
      // apart exactly here.
      expect(parseAnicelZipLayout(bytes).entries, hasLength(3));
      final fromFile = parseAnicelZipLayoutFile(path);
      expect(fromFile.entries.map((e) => e.name), [
        'cels/0.celz',
        'cels/1.celz',
        'cels/2.celz',
      ]);
      expect(
        ZipDecoder().decodeBytes(bytes).files.map((f) => f.name),
        ['cels/0.celz', 'cels/1.celz', 'cels/2.celz'],
      );
    });

    test('🚨 the plain EOCD still tells the truth where the truth fits',
        () {
      // The rule that decides how expensive flipping the switch is. A
      // sentinel belongs in a field only when the value does not fit —
      // NOT merely because ZIP64 records are present. Written that way, a
      // reader which has never heard of ZIP64 reads the real count at the
      // real offset and never looks at the extra records behind it, so an
      // always-ZIP64 archive that happens to fit stays openable by an
      // older build.
      //
      // ⚠️ This test failed when it was first written, and the CODE was
      // wrong, not the expectation: the count was being stamped 0xFFFF
      // whenever ZIP64 was on. That would have thrown away backward
      // compatibility for every small file, for nothing.
      final path = '${temp.path}/truthful.anicel';
      writeAnicelArchiveFile(path: path, entries: manyEntries(3));
      final bytes = File(path).readAsBytesSync();
      final data = ByteData.sublistView(bytes);
      final eocd = bytes.length - 22;
      expect(data.getUint32(eocd, Endian.little), 0x06054b50);
      expect(data.getUint16(eocd + 10, Endian.little), 3);
      expect(
        data.getUint32(eocd + 16, Endian.little),
        lessThan(0xFFFFFFFF),
        reason: 'the real central-directory offset, not a sentinel',
      );
    });

    test('an append onto a ZIP64 file stays ZIP64 and keeps everything', () {
      final path = '${temp.path}/grow64.anicel';
      writeAnicelArchiveFile(path: path, entries: manyEntries(4));
      appendAnicelEntries(
        path: path,
        newEntries: {'cels/99.celz': Uint8List.fromList([9])},
      );

      final layout = parseAnicelZipLayoutFile(path);
      expect(layout.entries, hasLength(5));
      expect(layout.entryNamed('cels/0.celz'), isNotNull);
      expect(layout.entryNamed('cels/99.celz'), isNotNull);
      expect(
        ZipDecoder().decodeBytes(File(path).readAsBytesSync()).files,
        hasLength(5),
      );
    });
  });

  group('switched off — the shape builds before this wrote', () {
    // The one-line revert, kept under test rather than kept as a comment.
    // If some reader in the wild turns out to disagree with ZIP64, this
    // is what the app goes back to, and a revert path nobody exercises is
    // a revert path that does not work.
    setUp(() => anicelAlwaysZip64 = false);

    test('a small archive gets no ZIP64 records at all', () {
      final path = '${temp.path}/small.anicel';
      writeAnicelArchiveFile(path: path, entries: manyEntries(8));

      final bytes = File(path).readAsBytesSync();
      expect(
        _containsSignature(bytes, 0x06064b50),
        isFalse,
        reason: 'no ZIP64 end record',
      );
      expect(
        _containsSignature(bytes, 0x07064b50),
        isFalse,
        reason: 'no ZIP64 locator',
      );
      expect(parseAnicelZipLayout(bytes).entries, hasLength(8));
    });

    test('but past the ceiling it still writes them — the limit is not a '
        'preference', () {
      final path = '${temp.path}/forced.anicel';
      writeAnicelArchiveFile(path: path, entries: manyEntries(65600));
      expect(
        _containsSignature(File(path).readAsBytesSync(), 0x06064b50),
        isTrue,
      );
      expect(parseAnicelZipLayoutFile(path).entries, hasLength(65600));
    });
  });

  test('🚨 past 65,535 entries every one of them comes back', () {
    // The case that used to open an empty project.
    const count = 65600;
    final path = '${temp.path}/many.anicel';
    writeAnicelArchiveFile(path: path, entries: manyEntries(count));

    final layout = parseAnicelZipLayoutFile(path);
    expect(layout.entries, hasLength(count));
    expect(layout.entries.first.name, 'cels/0.celz');
    expect(layout.entries.last.name, 'cels/${count - 1}.celz');

    // And the bytes are addressable, which is the point of the layout.
    final raf = File(path).openSync();
    try {
      final last = layout.entries.last;
      raf.setPositionSync(last.dataOffset);
      final data = raf.readSync(last.length);
      expect(data, [(count - 1) & 0xFF, ((count - 1) >> 8) & 0xFF]);
    } finally {
      raf.closeSync();
    }
  });

  test('🚨 and a STANDARD decoder reads it too', () {
    // ⚠️ Our reader agreeing with our writer proves nothing about the
    // format — this repo has already shipped a patch offset that our own
    // parser accepted and every other tool rejected. A project people
    // hand to each other has to open in something that is not us.
    const count = 65600;
    final path = '${temp.path}/many.anicel';
    writeAnicelArchiveFile(path: path, entries: manyEntries(count));

    final decoded = ZipDecoder().decodeBytes(File(path).readAsBytesSync());
    expect(decoded.files, hasLength(count));
    expect(decoded.files.last.name, 'cels/${count - 1}.celz');
    expect(decoded.files.last.readBytes(), [
      (count - 1) & 0xFF,
      ((count - 1) >> 8) & 0xFF,
    ]);
  });

  test('🚨 an append that CROSSES the ceiling keeps what was already there',
      () {
    // The realistic way a project arrives here: it grows into it, one
    // save at a time. The append rewrites the central directory, so this
    // is the moment the record shape has to change under an existing file.
    final path = '${temp.path}/growing.anicel';
    writeAnicelArchiveFile(path: path, entries: manyEntries(65000));

    final grown = appendAnicelEntries(
      path: path,
      newEntries: {
        for (var i = 65000; i < 65800; i += 1)
          'cels/$i.celz': Uint8List.fromList([i & 0xFF, (i >> 8) & 0xFF]),
      },
    );
    expect(grown.entries, hasLength(65800));

    final reread = parseAnicelZipLayoutFile(path);
    expect(reread.entries, hasLength(65800));
    expect(
      reread.entryNamed('cels/7.celz'),
      isNotNull,
      reason: 'an entry from before the crossing',
    );
    expect(reread.entryNamed('cels/65799.celz'), isNotNull);
    expect(
      ZipDecoder().decodeBytes(File(path).readAsBytesSync()).files,
      hasLength(65800),
    );
  });

  test('🚨 a reader opens both shapes, whichever wrote the file', () {
    // The property the whole migration rests on. Files already on disk
    // were written without ZIP64, files written from now on carry it, and
    // the same build has to read both without being told which is which.
    final plain = '${temp.path}/plain.anicel';
    anicelAlwaysZip64 = false;
    writeAnicelArchiveFile(path: plain, entries: manyEntries(6));

    final zip64 = '${temp.path}/zip64.anicel';
    anicelAlwaysZip64 = true;
    writeAnicelArchiveFile(path: zip64, entries: manyEntries(6));

    expect(
      File(plain).lengthSync(),
      lessThan(File(zip64).lengthSync()),
      reason: 'the fixture has to actually differ or this proves nothing',
    );
    for (final path in [plain, zip64]) {
      expect(parseAnicelZipLayoutFile(path).entries, hasLength(6));
      expect(
        parseAnicelZipLayout(File(path).readAsBytesSync()).entries,
        hasLength(6),
      );
    }
  });

  group('ZIP64 sizes — an entry past the field limit (유저 08-26: '
      '「zip64로 통일화」, the format stretches instead of refusing)', () {
    // 4GB fixtures are not a thing a suite can write, so the limit is
    // lowered until ordinary entries cross it — the sentinel shape is the
    // thing under test, not the gigabytes. Offsets cross the same limit,
    // so the combined extra (sizes + offset, spec order) runs here too.
    setUp(() => anicelZip64FieldLimit = 64);
    tearDown(() => anicelZip64FieldLimit = anicelZip64FieldLimitShipped);

    // Three entries, three extra-field shapes — the combined one is the
    // one a wrong FIELD ORDER corrupts, so a fixture without it proved
    // nothing about the order (a mutation showed exactly that):
    //  - `first` at offset 0, 80 bytes  → sizes flagged, offset not;
    //  - `both` past offset 64, 200 B   → sizes AND offset flagged;
    //  - `tiny` past offset 64, 3 bytes → offset flagged, sizes not.
    ({String path, Uint8List first, Uint8List both, Uint8List tiny}) oversized(
        String name) {
      final first = Uint8List.fromList(
        List<int>.generate(80, (i) => (i * 13 + 1) & 0xFF),
      );
      final both = Uint8List.fromList(
        List<int>.generate(200, (i) => (i * 7 + 3) & 0xFF),
      );
      final tiny = Uint8List.fromList(const [1, 2, 3]);
      final path = '${temp.path}/$name';
      writeAnicelArchiveFile(
        path: path,
        entries: [
          (name: 'cels/first.celz', bytes: first),
          (name: 'cels/both.celz', bytes: both),
          (name: 'cels/tiny.celz', bytes: tiny),
        ],
      );
      return (path: path, first: first, both: both, tiny: tiny);
    }

    void expectWholeTruth(
      AnicelZipLayout layout,
      Uint8List file, {
      required Uint8List first,
      required Uint8List both,
      required Uint8List tiny,
    }) {
      for (final (name, bytes) in [
        ('cels/first.celz', first),
        ('cels/both.celz', both),
        ('cels/tiny.celz', tiny),
      ]) {
        final entry = layout.entryNamed(name)!;
        expect(entry.length, bytes.length, reason: name);
        expect(
          file.sublist(entry.dataOffset, entry.dataOffset + entry.length),
          bytes,
          reason: '$name — the offset and length both have to be the truth: '
              'a wrong size is a file that opens and reads the wrong bytes',
        );
      }
    }

    test('both parsers read every sentinel shape back whole', () {
      final f = oversized('sizes.anicel');
      final bytes = File(f.path).readAsBytesSync();
      expectWholeTruth(
        parseAnicelZipLayout(bytes),
        bytes,
        first: f.first,
        both: f.both,
        tiny: f.tiny,
      );
      expectWholeTruth(
        parseAnicelZipLayoutFile(f.path),
        bytes,
        first: f.first,
        both: f.both,
        tiny: f.tiny,
      );
    });

    test('🚨 and a STANDARD decoder reads it too', () {
      // Same law as the count test above: our reader agreeing with our
      // writer proves nothing about the format.
      final f = oversized('foreign.anicel');
      final decoded = ZipDecoder().decodeBytes(File(f.path).readAsBytesSync());
      expect(
        decoded.files
            .singleWhere((e) => e.name == 'cels/both.celz')
            .readBytes(),
        f.both,
      );
      expect(
        decoded.files
            .singleWhere((e) => e.name == 'cels/first.celz')
            .readBytes(),
        f.first,
      );
    });

    test('an append over it keeps the oversized survivors intact', () {
      final f = oversized('append.anicel');
      appendAnicelEntries(
        path: f.path,
        newEntries: {
          'cels/new.celz': Uint8List.fromList(const [9, 9, 9]),
        },
      );
      final bytes = File(f.path).readAsBytesSync();
      final layout = parseAnicelZipLayout(bytes);
      expectWholeTruth(
        layout,
        bytes,
        first: f.first,
        both: f.both,
        tiny: f.tiny,
      );
      expect(layout.entryNamed('cels/new.celz'), isNotNull);
    });

    test('🚨 torn-tail recovery reads the sizes out of the LOCAL headers',
        () {
      // The walker has no central directory to lean on — the local ZIP64
      // extra is the only place the truth survives a torn append.
      final f = oversized('torn.anicel');
      final healthy = parseAnicelZipLayoutFile(f.path);
      File(f.path).openSync(mode: FileMode.append)
        ..truncateSync(healthy.centralDirectoryOffset + 7)
        ..closeSync();

      final recovered = recoverAnicelZipLayoutFile(f.path);
      expect(recovered.entries.length, healthy.entries.length);
      final bytes = File(f.path).readAsBytesSync();
      expectWholeTruth(
        recovered,
        bytes,
        first: f.first,
        both: f.both,
        tiny: f.tiny,
      );
    });

    test('a streamed full save patches the CRC through the longer header',
        () {
      // The STREAMED path writes a placeholder header first and seeks
      // back to headerOffset+14 for the CRC once the bytes have gone by —
      // a header that grew a ZIP64 extra must not have moved the CRC out
      // from under that patch.
      final big = Uint8List.fromList(
        List<int>.generate(200, (i) => (i * 11 + 5) & 0xFF),
      );
      final path = '${temp.path}/streamed.anicel';
      writeAnicelArchiveFile(
        path: path,
        entries: const [],
        streamedEntries: [
          AnicelStreamedEntry(
            name: 'media/voice.wav',
            length: big.length,
            readInto: (buffer, position, size) {
              buffer.setRange(0, size, big, position);
              return size;
            },
          ),
        ],
      );
      final entry = parseAnicelZipLayoutFile(path)
          .entryNamed('media/voice.wav')!;
      expect(entry.length, big.length);
      expect(entry.crc32, anicelCrc32(big));
      final bytes = File(path).readAsBytesSync();
      expect(
        bytes.sublist(entry.dataOffset, entry.dataOffset + entry.length),
        big,
      );
    });

    test('the SHIPPED limit is the 32-bit ceiling', () {
      expect(anicelZip64FieldLimitShipped, 0xFFFFFFFF);
    });
  });
}

/// Whether a four-byte little-endian signature appears anywhere.
///
/// Crude on purpose: the question is "did the writer emit this record at
/// all", and a false positive from entry DATA is impossible here because
/// the fixtures' payloads are two bytes each.
bool _containsSignature(Uint8List bytes, int signature) {
  final data = ByteData.sublistView(bytes);
  for (var i = 0; i + 4 <= bytes.length; i += 1) {
    if (data.getUint32(i, Endian.little) == signature) {
      return true;
    }
  }
  return false;
}
