import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:anicel/src/models/font_face_facts.dart';
import 'package:anicel/src/services/font_library_service.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/temp_dir.dart';

/// R9-rest (the text tool's faces): WHERE THE FONTS A PERSON BROUGHT ARE
/// KEPT — a folder of the files, and an index of what each says of itself.
void main() {
  late Directory room;
  late FontLibraryService library;

  setUp(() {
    room = Directory.systemTemp.createTempSync('anicel_font_library_');
    library = FontLibraryService(directoryPath: '${room.path}/fonts');
  });
  tearDown(() => deleteTempQuietly(room));

  const regular = FontFaceFacts(
    family: 'Probe Sans',
    weight: 400,
    italic: false,
    fsType: 8,
  );
  const bold = FontFaceFacts(
    family: 'Probe Sans',
    weight: 700,
    italic: false,
    fsType: null,
  );

  test('a library nobody has brought anything to is empty — no folder, no '
      'index, no error', () async {
    expect(await library.loadIndex(), isEmpty);
    expect(Directory(library.directoryPath).existsSync(), isFalse);
  });

  test('🚨the index comes back as it was written: each file, what it said '
      'of itself, in the order they were brought', () async {
    final entries = <FontLibraryEntry>[
      (file: 'font-2.otf', facts: bold),
      (file: 'font-1.ttf', facts: regular),
    ];

    await library.saveIndex(entries);

    expect(await library.loadIndex(), entries);
    // And by another library on the same folder — another launch.
    expect(
      await FontLibraryService(directoryPath: library.directoryPath)
          .loadIndex(),
      entries,
    );
  });

  test('a file\'s bytes are kept as they were handed over, and read back', () async {
    final bytes = Uint8List.fromList([for (var i = 0; i < 600; i += 1) i % 251]);

    await library.writeFont('font-1.ttf', bytes);

    expect(await library.readFont('font-1.ttf'), bytes);
    expect(
      File('${library.directoryPath}/font-1.ttf').readAsBytesSync(),
      bytes,
    );
  });

  test('a file that is gone reads as none, and deleting it again is no '
      'error', () async {
    await library.writeFont('font-1.ttf', Uint8List.fromList([1, 2, 3]));

    await library.deleteFont('font-1.ttf');

    expect(File('${library.directoryPath}/font-1.ttf').existsSync(), isFalse);
    expect(await library.readFont('font-1.ttf'), isNull);
    await library.deleteFont('font-1.ttf');
    await library.deleteFont('font-9.ttf');
  });

  group('🚨an index is a file on a disk, and what it says is not let name '
      'a path', () {
    Future<void> writeIndex(Object? document) async {
      final file = File(library.indexPath);
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(jsonEncode(document));
    }

    Map<String, Object?> entry(String file) => {
      'file': file,
      ...regular.toJson(),
    };

    test('only names this app mints are read from it', () async {
      await writeIndex({
        'version': 1,
        'fonts': [
          entry('font-100.ttf'),
          entry('../font-101.ttf'),
          entry(r'..\..\font-102.ttf'),
          entry('C:/Windows/win.ini'),
          entry('font-103.exe'),
          entry('font-x.ttf'),
          entry('font-104.otf'),
          entry('font-105.ttc'),
          entry('notes/font-106.ttf'),
          entry('font-107.ttf.bak'),
          entry('a-font-108.ttf'),
          entry('font-.ttf'),
        ],
      });

      expect(
        [for (final read in await library.loadIndex()) read.file],
        ['font-100.ttf', 'font-104.otf', 'font-105.ttc'],
      );
    });

    test('the names it mints are ones it reads, and say their number', () {
      for (final extension in ['ttf', 'otf', 'ttc']) {
        final minted = fontLibraryFileName(3, extension: extension);

        expect(minted, 'font-3.$extension');
        expect(isFontLibraryFileName(minted), isTrue);
        expect(fontLibraryFileNumber(minted), 3);
      }
      expect(fontLibraryFileNumber('font-x.ttf'), isNull);
      expect(fontLibraryFileNumber('font-123456789.ttf'), 123456789);
      expect(
        fontLibraryFileNumber('font-1234567890.ttf'),
        isNull,
        reason: 'more digits than the library ever counts to',
      );
    });

    test('an index that cannot be read — not json, a newer version, an '
        'entry with no facts — is an empty library', () async {
      File(library.indexPath)
        ..parent.createSync(recursive: true)
        ..writeAsStringSync('not json');
      expect(await library.loadIndex(), isEmpty);

      await writeIndex({
        'version': FontLibraryService.indexVersion + 1,
        'fonts': [entry('font-1.ttf')],
      });
      expect(await library.loadIndex(), isEmpty);

      await writeIndex({
        'version': 1,
        'fonts': [
          {'file': 'font-1.ttf'},
        ],
      });
      expect(await library.loadIndex(), isEmpty);
    });
  });

  test('the folder is the fonts\' own room among the settings', () {
    expect(
      FontLibraryService.defaultFontDirectoryPath().replaceAll(r'\', '/'),
      endsWith('/fonts'),
    );
    // ⚠️Under a test it is a sandbox, never the developer's own fonts.
    expect(
      FontLibraryService.defaultFontDirectoryPath(),
      contains('qa_test_fonts_'),
    );
  });
}
