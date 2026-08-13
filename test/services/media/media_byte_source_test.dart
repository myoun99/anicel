import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:anicel/src/services/media/media_byte_source.dart';
import 'package:flutter_test/flutter_test.dart';

/// The one named answer to "where are this asset's bytes", introduced while
/// every answer is still a file, so that the archive variant lands later as
/// a second case rather than as a change to four call sites.
void main() {
  late Directory temp;

  setUp(() => temp = Directory.systemTemp.createTempSync('qa_bytes_'));
  tearDown(() {
    try {
      temp.deleteSync(recursive: true);
    } on Object {
      // A locked file on Windows must not fail the suite.
    }
  });

  test('a file source hands back exactly what is on disk', () {
    final file = File('${temp.path}/a.bin')
      ..writeAsBytesSync(Uint8List.fromList([1, 2, 3, 4]));
    expect(MediaFileBytes(file.path).readSync(), [1, 2, 3, 4]);
  });

  test('stat answers the cheap facts without opening anything', () {
    final file = File('${temp.path}/b.bin')
      ..writeAsBytesSync(Uint8List(64));
    final stamp = MediaFileBytes(file.path).statSync();
    expect(stamp, isNotNull);
    expect(stamp!.lengthBytes, 64);
    expect(stamp.modifiedMicros, greaterThan(0));
  });

  test('null means NOTHING IS THERE — not "not a file"', () {
    // The distinction the conform pipeline reads: null sends it down the
    // "the source is gone" path, and anything else means something exists
    // that may or may not be readable right now — a transient failure that
    // must not spend the retry budget. A directory is therefore NOT null:
    // it is something, and reporting it missing would let a real problem
    // be recorded as a permanent absence.
    expect(MediaFileBytes('${temp.path}/nope.bin').statSync(), isNull);
    expect(MediaFileBytes(temp.path).statSync(), isNotNull);
  });

  test('asks the path, not a File — the trap that reads as "missing"', () {
    // `File(dir).existsSync()` answers false for a directory, so the
    // obvious spelling would report a path that plainly has something at
    // it as nothing at all.
    expect(File(temp.path).existsSync(), isFalse, reason: 'the trap itself');
    expect(MediaFileBytes(temp.path).statSync(), isNotNull);
  });

  test('serves a WINDOW without reading the whole thing', () {
    // The reason "give me the bytes" was not a sufficient contract: a PDF
    // opened by path is read page by page, and handing PDFium a whole
    // Uint8List instead would pull a hundred-page conte into memory. The
    // archive variant answers this out of the entry's byte range.
    final file = File('${temp.path}/e.bin')
      ..writeAsBytesSync(Uint8List.fromList(List<int>.generate(256, (i) => i)));
    final bytes = MediaFileBytes(file.path);
    expect(bytes.lengthSync(), 256);

    final buffer = Uint8List(4);
    expect(bytes.readIntoSync(buffer, 10, 4), 4);
    expect(buffer, [10, 11, 12, 13]);

    // A window that runs off the end returns what there was, not a throw.
    final tail = Uint8List(8);
    expect(bytes.readIntoSync(tail, 252, 8), 4);
    expect(tail.sublist(0, 4), [252, 253, 254, 255]);
  });

  test('a file never claims to know its own checksum', () {
    // Nothing on a filesystem does. The archive variant will, because ZIP
    // writes a CRC-32 per entry anyway — which is the whole reason this
    // getter exists before there is anything to return from it.
    final file = File('${temp.path}/c.bin')..writeAsBytesSync(Uint8List(8));
    expect(MediaFileBytes(file.path).knownCrc32, isNull);
  });

  test('sources compare by value, so one can be a map key', () {
    expect(const MediaFileBytes('/x/a.wav'), const MediaFileBytes('/x/a.wav'));
    expect(
      const MediaFileBytes('/x/a.wav'),
      isNot(const MediaFileBytes('/x/b.wav')),
    );
    expect(
      {const MediaFileBytes('/x/a.wav'): 1}[const MediaFileBytes('/x/a.wav')],
      1,
    );
  });

  test('a source survives being sent through an isolate', () async {
    // The constraint that made this plain data rather than a callback:
    // conforming runs inside Isolate.run, which carries values but cannot
    // carry a closure over the session.
    final file = File('${temp.path}/d.bin')
      ..writeAsBytesSync(Uint8List.fromList([9, 8, 7]));
    // The SOURCE crosses, not a path the closure rebuilds one from — that
    // is what a caller in the conform runner actually does.
    final source = MediaFileBytes(file.path);
    final read = await Isolate.run(source.readSync);
    expect(read, [9, 8, 7]);
  });
}
