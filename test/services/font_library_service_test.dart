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

    test('only ONE NAME that ends as a font does is read from it — a word, '
        'a dash, and more', () async {
      await writeIndex({
        'version': 1,
        'fonts': [
          entry('font-100.ttf'),
          entry('../font-101.ttf'),
          entry(r'..\..\font-102.ttf'),
          entry('C:/Windows/win.ini'),
          entry('font-103.exe'),
          entry('font-104.otf'),
          entry('font-105.ttc'),
          entry('notes/font-106.ttf'),
          entry('font-107.ttf.bak'),
          entry('font-.ttf'),
          entry('-108.ttf'),
          entry('.font-109.ttf'),
          entry('font 110-a.ttf'),
          entry('1a2b3c4d-9f8e7d6c-Probe_Sans-400.ttf'),
          // What the system reads as a device, whatever follows the dot —
          // and what a name with no dash before its first dot could be.
          entry('nul.ttf'),
          entry('con.ttf'),
          entry('com1.otf'),
          entry('font.ttf'),
          entry('nul.a-b.ttf'),
          entry('${'a' * 114}-b.ttf'),
          entry('${'a' * 115}-b.ttf'),
        ],
      });

      expect(
        [for (final read in await library.loadIndex()) read.file],
        [
          'font-100.ttf',
          'font-104.otf',
          'font-105.ttc',
          '1a2b3c4d-9f8e7d6c-Probe_Sans-400.ttf',
          '${'a' * 114}-b.ttf',
        ],
      );
    });

    group('🚨a name is minted WHOLE: it means one set of bytes, on this '
        'device and on any other', () {
      const italic = FontFaceFacts(
        family: 'Probe Sans',
        weight: 700,
        italic: true,
        fsType: 0,
      );

      test('never the same name twice — for the same face, in the same '
          'folder', () {
        final minted = {
          for (var i = 0; i < 200; i += 1)
            library.mintFileName(regular, extension: 'ttf'),
        };

        expect(minted, hasLength(200));
      });

      test('a name it mints is one it reads, ends as the file does, and '
          'says the face it is — made safe', () {
        for (final extension in ['ttf', 'otf', 'ttc']) {
          final minted = library.mintFileName(regular, extension: extension);

          expect(isFontLibraryFileName(minted), isTrue, reason: minted);
          expect(
            minted,
            matches(
              RegExp(
                '^[0-9a-f]{8}-[0-9a-f]{8}-Probe_Sans-400\\.$extension\$',
              ),
            ),
          );
        }
        expect(
          library.mintFileName(italic, extension: 'otf'),
          endsWith('-Probe_Sans-700i.otf'),
        );
      });

      test('whatever a font calls its family, the name is one name — and '
          'never too long to open', () {
        for (final family in [
          '고딕체',
          r'..\..\Windows',
          '../../etc/passwd',
          'a/b',
          'C:evil',
          'x' * 128,
          '',
          '.',
          '..',
          'nul',
        ]) {
          final minted = library.mintFileName(
            FontFaceFacts(
              family: family,
              weight: 400,
              italic: false,
              fsType: 0,
            ),
            extension: 'ttf',
          );

          expect(isFontLibraryFileName(minted), isTrue, reason: minted);
          expect(minted.length, lessThanOrEqualTo(80), reason: minted);
          expect(minted, isNot(contains('/')), reason: minted);
          expect(minted, isNot(contains(r'\')), reason: minted);
        }
      });

      test('the folder it is minted for is part of it: two libraries do '
          'not start from the same names', () {
        final other = FontLibraryService(
          directoryPath: '${room.path}/another device/fonts',
        );
        String front(String name) => name.substring(0, 8);

        expect(
          front(other.mintFileName(regular, extension: 'ttf')),
          isNot(front(library.mintFileName(regular, extension: 'ttf'))),
        );
        expect(
          front(library.mintFileName(regular, extension: 'ttf')),
          front(library.mintFileName(regular, extension: 'ttf')),
        );
      });
    });

    group('where a file it holds is, for whoever knows it by name', () {
      test('the file\'s own path — once it is on the disk', () async {
        final name = library.mintFileName(regular, extension: 'ttf');
        expect(library.pathOfFontHeld(name), isNull);

        await library.writeFont(name, Uint8List.fromList([1, 2, 3]));

        final path = library.pathOfFontHeld(name);
        expect(path, isNotNull);
        expect(File(path!).readAsBytesSync(), [1, 2, 3]);

        await library.deleteFont(name);
        expect(library.pathOfFontHeld(name), isNull);
      });

      test('🚨a name that is not the library\'s is never made a path of — '
          'though a file is there to find', () {
        final outside = File('${room.path}/secret.ttf')
          ..writeAsBytesSync([9]);
        Directory(library.directoryPath).createSync(recursive: true);
        File('${library.directoryPath}/plain.ttf').writeAsBytesSync([9]);
        expect(outside.existsSync(), isTrue, reason: '⛔fixture');

        expect(library.pathOfFontHeld('../secret.ttf'), isNull);
        expect(library.pathOfFontHeld(outside.path), isNull);
        expect(library.pathOfFontHeld('plain.ttf'), isNull);
        expect(library.pathOfFontHeld('index.json'), isNull);
      });
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
