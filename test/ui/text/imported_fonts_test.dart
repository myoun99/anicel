import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:anicel/src/models/font_face_facts.dart';
import 'package:anicel/src/services/font_file_reader.dart';
import 'package:anicel/src/services/font_library_service.dart';
import 'package:anicel/src/services/persistence/versioned_settings_file.dart';
import 'package:anicel/src/ui/brush/picked_file.dart';
import 'package:anicel/src/ui/text/app_strings.dart';
import 'package:anicel/src/ui/text/canvas_letter_faces.dart';
import 'package:anicel/src/ui/text/imported_fonts.dart';
import 'package:anicel/src/ui/theme/app_theme.dart';
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

  group('🚨the project on screen: its fonts are laid over this device\'s', () {
    const regular = FontFaceFacts(
      family: 'Probe Sans',
      weight: 400,
      italic: false,
      fsType: 0,
    );
    const bold = FontFaceFacts(
      family: 'Probe Sans',
      weight: 700,
      italic: false,
      fsType: 0,
    );

    /// A font file a project carries under [name], whose bytes are [seed]
    /// thrice — and a note of every time it is read.
    final read = <String>[];
    LetterFaceFile carried(String name, FontFaceFacts facts, int seed) => (
      name: name,
      facts: facts,
      read: () async {
        read.add(name);
        return Uint8List.fromList([seed, seed, seed]);
      },
    );

    setUp(read.clear);

    /// Stands a project on screen that carries [files], and nothing a list
    /// would ask of it.
    void show(ImportedFonts fonts, List<LetterFaceFile> Function() files) =>
        fonts.showCarried((
          files: files,
          families: () => const [],
          takeOut: (family) {},
        ));

    List<String> namesSetWith(ImportedFonts fonts, String family) => [
      for (final file in fonts.filesSetWith(family)) file.name,
    ];

    test('a family the project carries and this device was never brought '
        'is one letters can be set in — read from the project when they '
        'are asked for, and not before', () async {
      final fonts = fontsOf();
      await fonts.load();
      var told = 0;
      fonts.addListener(() => told += 1);

      show(fonts, () => [carried('ab12-cd34-Probe.ttf', regular, 5)]);

      expect(told, 1);
      expect(fonts.faces.holds('Probe Sans'), isTrue);
      expect(fonts.families, isEmpty, reason: 'this device holds none');
      expect(namesSetWith(fonts, 'Probe Sans'), ['ab12-cd34-Probe.ttf']);
      expect(read, isEmpty);

      await setIn(fonts, 'Probe Sans');

      expect(read, ['ab12-cd34-Probe.ttf']);
      expect([for (final face in handed) face.bytes], [
        [5, 5, 5],
      ]);
    });

    test('🚨the project\'s file of a face is what that face is set with, '
        'though this device holds one of its own — and a face only the '
        'device holds joins the family', () async {
      final fonts = fontsOf();
      final devicesRegular = fontFileSaying(family: 'Probe Sans');
      final devicesBold = fontFileSaying(family: 'Probe Sans', weight: 700);
      await fonts.importBytes(devicesRegular);
      await fonts.importBytes(devicesBold);
      final ofTheDevice = namesSetWith(fonts, 'Probe Sans');
      expect(ofTheDevice, hasLength(2), reason: '⛔fixture');

      show(fonts, () => [carried('ab12-cd34-Probe.ttf', regular, 5)]);

      expect(namesSetWith(fonts, 'Probe Sans'), [
        'ab12-cd34-Probe.ttf',
        ofTheDevice.last,
      ]);
      await setIn(fonts, 'Probe Sans');
      expect(
        [for (final face in handed) face.bytes],
        unorderedEquals([
          [5, 5, 5],
          devicesBold,
        ]),
        reason: 'the device\'s own regular is not what this project is set in',
      );
    });

    test('🚨⛔THE SAME FILE, held by the device and carried by the project '
        'under the one name it has, is one set of files: registering a '
        'font with a project reads nothing, hands the engine nothing, and '
        'sets no letter again', () async {
      final fonts = fontsOf();
      await fonts.importBytes(fontFileSaying(family: 'Probe Sans'));
      await setIn(fonts, 'Probe Sans');
      final name = namesSetWith(fonts, 'Probe Sans').single;
      final engine = fonts.faces.engineFamilyOf('Probe Sans');
      final generation = fonts.faces.generation;
      final handedBefore = handed.length;

      show(fonts, () => [carried(name, regular, 5)]);

      expect(fonts.faces.engineFamilyOf('Probe Sans'), engine);
      expect(fonts.faces.generation, generation);
      expect(fonts.faces.isOnItsWay('Probe Sans'), isFalse);
      expect(handed, hasLength(handedBefore));
      expect(read, isEmpty);
    });

    test('🚨the ORDER its files are said in does not make a family another '
        'set: a project that carries one face of two — the device\'s own '
        'file, by its name — reads nothing', () async {
      final fonts = fontsOf();
      await fonts.importBytes(fontFileSaying(family: 'Probe Sans'));
      await fonts.importBytes(
        fontFileSaying(family: 'Probe Sans', weight: 700),
      );
      await setIn(fonts, 'Probe Sans');
      final ofTheDevice = namesSetWith(fonts, 'Probe Sans');
      final engine = fonts.faces.engineFamilyOf('Probe Sans');
      final generation = fonts.faces.generation;
      final handedBefore = handed.length;

      // The bold, carried: it is said FIRST now, where it was second.
      show(fonts, () => [carried(ofTheDevice.last, bold, 5)]);

      expect(namesSetWith(fonts, 'Probe Sans'), ofTheDevice.reversed);
      expect(fonts.faces.engineFamilyOf('Probe Sans'), engine);
      expect(fonts.faces.generation, generation);
      expect(handed, hasLength(handedBefore));
      expect(read, isEmpty);
    });

    test('🚨another project on screen, and back: a family is set with '
        'each one\'s files in turn, and the files it had before are not '
        'read again', () async {
      final fonts = fontsOf();
      await fonts.load();
      List<LetterFaceFile> one() => [carried('ab12-0001-P.ttf', regular, 1)];
      List<LetterFaceFile> two() => [carried('ab12-0002-P.ttf', regular, 2)];

      show(fonts, one);
      await setIn(fonts, 'Probe Sans');
      final inOne = fonts.faces.engineFamilyOf('Probe Sans');
      show(fonts, two);
      await setIn(fonts, 'Probe Sans');
      final inTwo = fonts.faces.engineFamilyOf('Probe Sans');
      expect(inTwo, isNot(inOne));
      read.clear();

      show(fonts, one);

      expect(fonts.faces.engineFamilyOf('Probe Sans'), inOne);
      show(fonts, two);
      expect(fonts.faces.engineFamilyOf('Probe Sans'), inTwo);
      expect(read, isEmpty);
      expect(handed, hasLength(2));
    });

    test('with no project on screen any more, the families are this '
        'device\'s alone', () async {
      final fonts = fontsOf();
      await fonts.load();
      show(fonts, () => [carried('ab12-cd34-Probe.ttf', regular, 5)]);
      expect(fonts.faces.holds('Probe Sans'), isTrue, reason: '⛔fixture');

      fonts.showCarried(null);

      expect(fonts.faces.holds('Probe Sans'), isFalse);
      expect(fonts.filesSetWith('Probe Sans'), isEmpty);
    });

    test('🚨which of a project\'s fonts can be read is asked AGAIN whenever '
        'this device\'s library changes: a font registered from here lives '
        'in this library until the project is saved', () async {
      final fonts = fontsOf();
      await fonts.load();
      var readable = <LetterFaceFile>[];
      var asked = 0;
      show(fonts, () {
        asked += 1;
        return readable;
      });
      expect(fonts.faces.holds('Probe Sans'), isFalse);
      final askedBefore = asked;

      readable = [carried('ab12-cd34-Probe.ttf', bold, 5)];
      await fonts.importBytes(fontFileSaying(family: 'Probe Serif'));

      expect(asked, greaterThan(askedBefore));
      expect(namesSetWith(fonts, 'Probe Sans'), ['ab12-cd34-Probe.ttf']);
    });

    test('⛔a file a project names for one of the APP\'S OWN families is '
        'nobody\'s face: the interface is written in those', () async {
      final fonts = fontsOf();
      await fonts.load();
      const apps = FontFaceFacts(
        family: AppTypography.bundledFamily,
        weight: 400,
        italic: false,
        fsType: 0,
      );

      show(fonts, () => [carried('ab12-cd34-Apps.ttf', apps, 5)]);

      expect(fonts.filesSetWith(AppTypography.bundledFamily), isEmpty);
      expect(
        fonts.faces.engineFamilyOf(AppTypography.bundledFamily),
        AppTypography.bundledFamily,
      );
      await Future<void>.delayed(Duration.zero);
      expect(read, isEmpty);
    });

  });

  group('🚨before a file is taken off this device, whoever still needs its '
      'bytes is asked — and has them', () {
    /// Every asking: the files named, and whether each was on the disk
    /// when it was asked about — and still there once the one asked had
    /// taken its time.
    late List<({Set<String> files, bool there, bool stillThere})> asked;

    bool onDisk(Set<String> files) =>
        files.every((file) => library.pathOfFontHeld(file) != null);

    ImportedFonts askingFonts() {
      asked = [];
      final fonts = ImportedFonts(
        service: library,
        register: register,
        beforeLettingGo: (files) async {
          final there = onDisk(files);
          // Whoever takes the bytes takes a while over tens of megabytes.
          await Future<void>.delayed(const Duration(milliseconds: 5));
          asked.add((files: files, there: there, stillThere: onDisk(files)));
        },
      );
      addTearDown(fonts.dispose);
      return fonts;
    }

    test('a family deleted: asked once, for every file of it, each on the '
        'disk until the one asked is done — and gone after', () async {
      final fonts = askingFonts();
      for (final file in [
        fontFileSaying(family: 'Probe Sans'),
        fontFileSaying(family: 'Probe Sans', weight: 700),
        fontFileSaying(family: 'Probe Serif'),
      ]) {
        await fonts.importBytes(file);
      }
      final ofSans = filesKept().where((file) => file.contains('Probe_Sans'));
      expect(ofSans, hasLength(2), reason: '⛔fixture');
      expect(asked, isEmpty, reason: 'nothing has left yet');

      await fonts.delete('Probe Sans');

      expect(asked, hasLength(1));
      expect(asked.single.files, ofSans.toSet());
      expect(asked.single.there, isTrue);
      expect(asked.single.stillThere, isTrue, reason: 'it did not wait');
      expect(filesKept(), hasLength(1));
      expect(onDisk(ofSans.toSet()), isFalse);
    });

    test('a face brought again: asked for the file it takes the place '
        'of', () async {
      final fonts = askingFonts();
      await fonts.importBytes(fontFileSaying(family: 'Probe Sans', fsType: 0));
      final older = filesKept().single;

      await fonts.importBytes(fontFileSaying(family: 'Probe Sans', fsType: 8));

      expect(asked, hasLength(1));
      expect(asked.single.files, {older});
      expect(asked.single.there, isTrue);
      expect(asked.single.stillThere, isTrue, reason: 'it did not wait');
      expect(filesKept(), isNot(contains(older)));
    });

    test('nobody is asked when nothing leaves — and deleting a family this '
        'device does not hold asks nobody', () async {
      final fonts = askingFonts();

      await fonts.importBytes(fontFileSaying(family: 'Probe Sans'));
      await fonts.delete('Probe Mono');

      expect(asked, isEmpty);
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
