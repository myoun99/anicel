import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:anicel/src/services/font_file_reader.dart';
import 'package:anicel/src/services/font_library_service.dart';
import 'package:anicel/src/services/persistence/versioned_settings_file.dart';
import 'package:anicel/src/ui/brush/picked_file.dart';
import 'package:anicel/src/ui/text/app_strings.dart';
import 'package:anicel/src/ui/text/canvas_letter_faces.dart';
import 'package:anicel/src/ui/text/imported_fonts.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/font_file_fixture.dart';
import '../../helpers/font_library_in_memory.dart';
import '../../helpers/temp_dir.dart';

/// R9-rest (the text tool's faces): THE FONTS A PERSON BROUGHT TO THIS
/// DEVICE — 유저 2026-10-06: 「유저가 알아서 자기가 가지고있는 글꼴 넣는게
/// 아니야?」. Bringing one from a file, the families a list shows, taking
/// one away, and what the engine's side is told of each.
void main() {
  late Directory room;
  late FontLibraryService library;
  late List<({String engineFamily, Uint8List bytes})> handed;

  Future<void> register(Uint8List bytes, {required String engineFamily}) async {
    handed.add((engineFamily: engineFamily, bytes: bytes));
  }

  setUp(() {
    room = Directory.systemTemp.createTempSync('anicel_imported_fonts_');
    library = FontLibraryService(directoryPath: '${room.path}/fonts');
    handed = [];
  });
  tearDown(() {
    CanvasLetterFaces.current = CanvasLetterFaces();
    deleteTempQuietly(room);
  });

  ImportedFonts fontsOf({FilePicker? picker}) {
    final fonts = ImportedFonts(
      service: library,
      picker: picker,
      register: register,
    );
    addTearDown(fonts.dispose);
    return fonts;
  }

  /// Has [family] handed to the engine, and waits until it is.
  Future<void> setIn(ImportedFonts fonts, String family) async {
    await fonts.faces.whenHere([family]);
  }

  List<String> filesKept() => [
    if (Directory(library.directoryPath).existsSync())
      for (final entity in Directory(library.directoryPath).listSync())
        if (!entity.path.endsWith('index.json'))
          entity.path.replaceAll(r'\', '/').split('/').last,
  ]..sort();

  group('bringing a file', () {
    test('🚨a font is kept on this device, listed by its family\'s name, '
        'and letters can be set in it from that moment', () async {
      final fonts = fontsOf();
      await fonts.load();
      var told = 0;
      fonts.addListener(() => told += 1);
      final bytes = fontFileSaying(family: 'Probe Sans');

      final outcome = await fonts.importBytes(bytes);

      expect(outcome, (family: 'Probe Sans', refusal: null));
      expect(fonts.families, [
        (name: 'Probe Sans', ridesInEditedDocuments: true),
      ]);
      expect(told, 1);
      expect(fonts.faces.holds('Probe Sans'), isTrue);
      expect(CanvasLetterFaces.current, same(fonts.faces));
      // Its file is the library's own copy, under a name the app minted.
      final kept = filesKept();
      expect(kept, hasLength(1));
      expect(isFontLibraryFileName(kept.single), isTrue);
      expect(kept.single, endsWith('-Probe_Sans-400.ttf'));
      expect(await library.readFont(kept.single), bytes);

      // And the engine is handed it when letters are asked for in it.
      expect(handed, isEmpty);
      await setIn(fonts, 'Probe Sans');
      expect([for (final face in handed) face.bytes], [bytes]);
    });

    test('🚨it is there at the next launch: another library on the same '
        'folder lists it, and reads it when asked', () async {
      final bytes = fontFileSaying(family: 'Probe Sans', fsType: 2);
      await fontsOf().importBytes(bytes);

      final next = fontsOf();
      expect(next.families, isEmpty, reason: 'the index is not read yet');
      await next.load();

      expect(next.families, [
        (name: 'Probe Sans', ridesInEditedDocuments: false),
      ]);
      expect(handed, isEmpty, reason: 'listing a family opens none of its files');
      await setIn(next, 'Probe Sans');
      expect([for (final face in handed) face.bytes], [bytes]);
    });

    test('a file that is not a font is refused, with the sentence that says '
        'so — and nothing is kept', () async {
      final fonts = fontsOf();

      final outcome = await fonts.importBytes(
        Uint8List.fromList(List.filled(64, 7)),
      );

      expect(outcome, (
        family: null,
        refusal: AppText.strings.textToolFontUnreadable,
      ));
      expect(fonts.families, isEmpty);
      expect(filesKept(), isEmpty);
    });

    test('🚨a file that names one of the APP\'S OWN families is refused: '
        'the engine would hear it as more faces of the interface\'s own', () async {
      final fonts = fontsOf();

      for (final own in [
        File('assets/fonts/BIZUDPGothic-Regular.ttf').readAsBytesSync(),
        fontFileSaying(family: 'Nanum Gothic'),
      ]) {
        expect(await fonts.importBytes(own), (
          family: null,
          refusal: AppText.strings.textToolFontIsTheApps,
        ));
      }
      expect(fonts.families, isEmpty);
      expect(filesKept(), isEmpty);
    });

    test('a font that could not be written is refused, and is not listed', () async {
      // The folder's place is taken by a file: nothing can be written in it.
      File(library.directoryPath).writeAsStringSync('in the way');
      final fonts = fontsOf();

      final outcome = await fonts.importBytes(fontFileSaying());

      expect(outcome, (
        family: null,
        refusal: AppText.strings.textToolFontNotKept,
      ));
      expect(fonts.families, isEmpty);
    });

    test('picked from a dialog, it is what the dialog handed over', () async {
      final bytes = fontFileSaying(family: 'Picked Sans');
      final fonts = fontsOf(
        picker: () async => (name: 'whatever.bin', bytes: bytes),
      );

      expect(await fonts.importFromFile(), (
        family: 'Picked Sans',
        refusal: null,
      ));
      expect(fonts.families.single.name, 'Picked Sans');
    });

    test('a dialog closed without a file brings nothing and says nothing', () async {
      final fonts = fontsOf(picker: () async => null);

      expect(await fonts.importFromFile(), (family: null, refusal: null));
      expect(fonts.families, isEmpty);
    });

    test('a dialog that would not open says so', () async {
      final fonts = fontsOf(picker: () async => throw StateError('no dialog'));

      final outcome = await fonts.importFromFile();

      expect(outcome.family, isNull);
      expect(outcome.refusal, contains('no dialog'));
    });
  });

  group('a family\'s faces', () {
    test('🚨another weight of a family JOINS it: one family in the list, '
        'and both files are what the engine is handed for it', () async {
      final fonts = fontsOf();
      final regular = fontFileSaying(family: 'Probe Sans');
      final bold = fontFileSaying(family: 'Probe Sans', weight: 700);

      await fonts.importBytes(regular);
      await fonts.importBytes(bold);

      expect([for (final family in fonts.families) family.name], ['Probe Sans']);
      expect(filesKept(), hasLength(2));
      await setIn(fonts, 'Probe Sans');
      expect(
        [for (final face in handed) face.bytes],
        unorderedEquals([regular, bold]),
      );
      expect({for (final face in handed) face.engineFamily}, hasLength(1));
    });

    test('🚨the SAME face brought again takes the place of the one that '
        'was there — its file too — and the engine is handed the new one '
        'under another name', () async {
      final fonts = fontsOf();
      final older = fontFileSaying(family: 'Probe Sans', fsType: 0);
      final newer = fontFileSaying(family: 'Probe Sans', fsType: 8);
      await fonts.importBytes(older);
      await setIn(fonts, 'Probe Sans');
      final first = fonts.faces.engineFamilyOf('Probe Sans');

      await fonts.importBytes(newer);
      expect(
        fonts.faces.engineFamilyOf('Probe Sans'),
        isNull,
        reason: 'what the engine was handed before is not the family now',
      );

      expect(fonts.families, hasLength(1));
      final kept = filesKept();
      expect(kept, hasLength(1), reason: 'the older file is gone');
      expect(await library.readFont(kept.single), newer);
      await setIn(fonts, 'Probe Sans');
      final second = fonts.faces.engineFamilyOf('Probe Sans');
      expect(second, isNotNull);
      expect(second, isNot(first));
      expect(
        [
          for (final face in handed)
            if (face.engineFamily == second) face.bytes,
        ],
        [newer],
      );
    });

    test('🚨a family rides in a project only if EVERY file of it may', () async {
      final fonts = fontsOf();
      await fonts.importBytes(fontFileSaying(family: 'Probe Sans', fsType: 8));
      expect(fonts.familyNamed('Probe Sans')!.ridesInEditedDocuments, isTrue);

      await fonts.importBytes(
        fontFileSaying(family: 'Probe Sans', weight: 700, fsType: 2),
      );

      expect(fonts.familyNamed('Probe Sans')!.ridesInEditedDocuments, isFalse);
      expect(fonts.familyNamed('Nobody\'s'), isNull);

      // In whichever order they came: the one that may not, first.
      await fonts.importBytes(
        fontFileSaying(family: 'Probe Serif', fsType: 2),
      );
      await fonts.importBytes(
        fontFileSaying(family: 'Probe Serif', weight: 700, fsType: 8),
      );
      expect(fonts.familyNamed('Probe Serif')!.ridesInEditedDocuments, isFalse);
    });

    test('the families are listed by name, as a person looks for one — '
        'whatever case they are written in, in whatever order they came', () async {
      final fonts = fontsOf();
      for (final family in ['zeta', 'alpha', 'beta', 'Beta', '고딕']) {
        await fonts.importBytes(fontFileSaying(family: family));
      }

      // 「alpha」 before 「Beta」, which a sort by the letters' numbers would
      // put first; the two spellings of beta side by side, capital first.
      expect(
        [for (final family in fonts.families) family.name],
        ['alpha', 'Beta', 'beta', 'zeta', '고딕'],
      );
    });
  });

  group('taking a family away', () {
    test('🚨its files go, it is listed no more — at the next launch too — '
        'and letters in it are set in the app\'s own face from that moment', () async {
      final fonts = fontsOf();
      await fonts.importBytes(fontFileSaying(family: 'Probe Sans'));
      await fonts.importBytes(fontFileSaying(family: 'Probe Sans', weight: 700));
      await fonts.importBytes(fontFileSaying(family: 'Probe Serif'));
      await setIn(fonts, 'Probe Sans');
      expect(fonts.faces.engineFamilyOf('Probe Sans'), isNotNull);
      expect(handed, hasLength(2), reason: 'its own two files, and no other');
      var told = 0;
      fonts.addListener(() => told += 1);

      await fonts.delete('Probe Sans');

      expect([for (final family in fonts.families) family.name], ['Probe Serif']);
      expect(told, 1);
      expect(fonts.faces.holds('Probe Sans'), isFalse);
      expect(fonts.faces.engineFamilyOf('Probe Sans'), isNull);
      expect(filesKept(), hasLength(1));
      final next = fontsOf();
      await next.load();
      expect([for (final family in next.families) family.name], ['Probe Serif']);
    });

    test('a family that is not here is nothing to take away', () async {
      final fonts = fontsOf();
      await fonts.importBytes(fontFileSaying(family: 'Probe Sans'));
      var told = 0;
      fonts.addListener(() => told += 1);

      await fonts.delete('Probe Serif');

      expect(told, 0);
      expect(fonts.families, hasLength(1));
      expect(filesKept(), hasLength(1));
    });
  });

  group('the index, read', () {
    test('🚨a font brought BEFORE the index was read waits for it — and so '
        'does not take the name of a file that is there', () async {
      final serif = fontFileSaying(family: 'Probe Serif');
      final sans = fontFileSaying(family: 'Probe Sans');
      final memory = FontLibraryInMemory()
        ..files['font-1.ttf'] = serif
        ..index = [(file: 'font-1.ttf', facts: readFontFaceFacts(serif)!)]
        ..indexGate = Completer<void>();
      final fonts = ImportedFonts(service: memory, register: register);
      addTearDown(fonts.dispose);

      var brought = false;
      final bringing = fonts.importBytes(sans).whenComplete(() => brought = true);
      await Future<void>.delayed(Duration.zero);

      expect(brought, isFalse);
      expect(memory.files.keys, ['font-1.ttf']);
      expect(memory.files['font-1.ttf'], serif);

      memory.indexGate!.complete();
      await bringing;

      expect(memory.files.keys, ['font-1.ttf', 'font-2.ttf']);
      expect(memory.files['font-1.ttf'], serif, reason: 'not written over');
      expect(
        [for (final family in fonts.families) family.name],
        ['Probe Sans', 'Probe Serif'],
      );
      expect(
        [for (final entry in memory.index) entry.file],
        ['font-1.ttf', 'font-2.ttf'],
      );
    });

    test('the index is read ONCE, whoever asks and however often', () async {
      final memory = FontLibraryInMemory();
      final fonts = ImportedFonts(service: memory, register: register);
      addTearDown(fonts.dispose);

      await fonts.load();
      await fonts.load();
      await fonts.importBytes(fontFileSaying(family: 'Probe Sans'));
      await fonts.importBytes(fontFileSaying(family: 'Probe Serif'));

      expect(memory.indexReads, 1);
    });

    test('🚨a font brought at the next launch JOINS what is there, though '
        'nobody asked for the index first: the file that was there and '
        'its line of the index both stay', () async {
      final sans = fontFileSaying(family: 'Probe Sans');
      await fontsOf().importBytes(sans);
      final first = filesKept().single;

      final next = fontsOf();
      await next.importBytes(fontFileSaying(family: 'Probe Serif'));

      expect(filesKept(), hasLength(2));
      expect(await library.readFont(first), sans);
      expect(
        [for (final family in next.families) family.name],
        ['Probe Sans', 'Probe Serif'],
      );
      expect(
        [for (final entry in await library.loadIndex()) entry.facts.family],
        ['Probe Sans', 'Probe Serif'],
        reason: 'an index written from a library nobody had read',
      );
    });

    test('reading it writes nothing', () async {
      await fontsOf().importBytes(fontFileSaying(family: 'Probe Sans'));
      final writes = <String>[];
      debugSettingsFileWrite = (path, text) async => writes.add(path);
      addTearDown(() => debugSettingsFileWrite = null);

      final fonts = fontsOf();
      await fonts.load();
      // Long enough for a write that was asked for to have been begun.
      await Future<void>.delayed(Duration.zero);

      expect(fonts.families, hasLength(1), reason: '⛔fixture: it was read');
      expect(writes, isEmpty);
    });
  });

  group('the run\'s faces', () {
    test('🚨are these fonts\' own while they live, and nobody\'s after: '
        'letters go back to the app\'s face', () async {
      final fonts = ImportedFonts(service: library, register: register);
      await fonts.importBytes(fontFileSaying(family: 'Probe Sans'));
      final faces = fonts.faces;
      expect(CanvasLetterFaces.current, same(faces));

      fonts.dispose();

      expect(CanvasLetterFaces.current, isNot(same(faces)));
      expect(CanvasLetterFaces.current.holds('Probe Sans'), isFalse);
    });

    test('fonts that are gone do not take the faces of the ones that came '
        'after them', () {
      final first = ImportedFonts(service: library, register: register);
      final second = ImportedFonts(service: library, register: register);
      addTearDown(second.dispose);

      first.dispose();

      expect(CanvasLetterFaces.current, same(second.faces));
    });
  });
}
