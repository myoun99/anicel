import 'dart:io';
import 'dart:typed_data';

import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/font_face_facts.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_font_file.dart';
import 'package:anicel/src/services/command.dart';
import 'package:anicel/src/services/font_library_service.dart';
import 'package:anicel/src/services/persistence/media_staging_store.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/session/project_file_door.dart';
import 'package:anicel/src/ui/text/canvas_letter_faces.dart';
import 'package:anicel/src/ui/text/imported_fonts.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/opened_session.dart';
import '../../helpers/placed_sound_conform.dart';
import '../../helpers/temp_dir.dart';

/// R9-rest (the text tool's faces): THE FONTS REGISTERED WITH A PROJECT, AS
/// ITS SESSION WORKS THEM — the files its letters are set with while it is
/// on screen, the registering of a font with the text set in it, and the
/// taking of one out.
///
/// 🗣️유저 2026-10-06: 「뺄때까지 두는게 맞지않나 싶은데. 글꼴을 사실상
/// 등록하는거잖아. 프리미어프로처럼」.
void main() {
  late Directory root;
  late FontLibraryService home;
  late FontLibraryService elsewhere;
  late String projectPath;
  var sessions = 0;

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
    fsType: 8,
  );
  const serif = FontFaceFacts(
    family: 'Probe Serif',
    weight: 400,
    italic: false,
    fsType: 0,
  );

  /// A face its maker did not let ride in a document that is edited.
  const kept = FontFaceFacts(
    family: 'Probe Sans',
    weight: 700,
    italic: false,
    fsType: 4,
  );

  final bytes = Uint8List.fromList(
    List<int>.generate(40 * 1024, (i) => (i ~/ 5 + 11) & 0xFF),
  );

  EditorSessionManager aSession(FontLibraryService device, [Project? project]) {
    final session = EditorSessionManager(
      initialProject: project ?? createDefaultProject(),
      mediaStagingStore: MediaStagingStore(
        directoryPath: '${root.path}/Staged${sessions += 1}',
      ),
      audioConformStore: soundConformStore(),
      fontLibrary: device,
    );
    addTearDown(session.dispose);
    return session;
  }

  /// A font file this device's library keeps, of [facts] — its name.
  Future<String> broughtHome(FontFaceFacts facts) async {
    final name = home.mintFileName(facts, extension: 'ttf');
    await home.writeFont(name, bytes);
    return name;
  }

  /// A file a family is set with, as whoever lays letters out says it.
  LetterFaceFile setWith(String name, FontFaceFacts facts) =>
      (name: name, facts: facts, read: () async => bytes);

  Future<void> save(EditorSessionManager session) =>
      session.projectDoor.saveProjectToFile(
        projectPath,
        asked: SaveAsked.byAPerson,
      );

  List<ProjectFontFile> fontsOf(EditorSessionManager session) =>
      session.repository.requireProject().fonts;

  setUp(() {
    root = Directory.systemTemp.createTempSync('anicel_project_fonts_verbs');
    home = FontLibraryService(directoryPath: '${root.path}/home/fonts');
    elsewhere = FontLibraryService(directoryPath: '${root.path}/away/fonts');
    projectPath = '${root.path}/scene.anicel';
  });

  tearDown(() => deleteTempQuietly(root));

  group('the files its families are set with while it is on screen', () {
    test('each font it carries, by the name its bytes are kept under and '
        'with what the file said of itself — read from this device\'s '
        'library while the project is not saved', () async {
      final session = aSession(home);
      final name = await broughtHome(regular);
      session.repository.updateFonts([
        ProjectFontFile(carriedAs: name, facts: regular),
      ]);

      final files = session.projectFonts.letterFaceFiles;

      expect([for (final file in files) (file.name, file.facts)], [
        (name, regular),
      ]);
      expect(await files.single.read(), bytes);
    });

    test('🚨on a device that was never brought it, out of the PROJECT '
        'FILE', () async {
      final first = aSession(home);
      final name = await broughtHome(regular);
      first.repository.updateFonts([
        ProjectFontFile(carriedAs: name, facts: regular),
      ]);
      await save(first);

      final session = await openedSession(
        projectPath,
        make: (project) => aSession(elsewhere, project),
      );

      final files = session.projectFonts.letterFaceFiles;
      expect([for (final file in files) file.name], [name]);
      expect(await files.single.read(), bytes);
    });

    test('🚨★★★opened where the font was never brought, the project\'s '
        'letters ARE SET IN IT: whoever sets letters is handed the bytes '
        'out of the project file — the journey carrying a font exists to '
        'serve', () async {
      final first = aSession(home);
      final name = await broughtHome(regular);
      first.repository.updateFonts([
        ProjectFontFile(carriedAs: name, facts: regular),
      ]);
      await save(first);
      final session = await openedSession(
        projectPath,
        make: (project) => aSession(elsewhere, project),
      );
      final handed = <List<int>>[];
      final fonts = ImportedFonts(
        service: elsewhere,
        register: (bytes, {required engineFamily}) async => handed.add(bytes),
      );
      addTearDown(() => CanvasLetterFaces.current = CanvasLetterFaces());
      addTearDown(fonts.dispose);
      await fonts.load();
      expect(fonts.faces.holds('Probe Sans'), isFalse, reason: '⛔fixture');

      // What the window says when the project comes on screen.
      final ofTheProject = session.projectFonts;
      fonts.showCarried((
        files: () => ofTheProject.letterFaceFiles,
        families: () => ofTheProject.families,
        takeOut: ofTheProject.takeOut,
      ));

      expect(fonts.faces.holds('Probe Sans'), isTrue);
      expect(fonts.carriedFamilies, ['Probe Sans']);
      expect(fonts.families, isEmpty, reason: 'this device still holds none');
      await fonts.faces.whenHere(['Probe Sans']);
      expect(handed, [bytes]);

      // And taken out through the list, it is nobody's here.
      fonts.takeOutOfProject('Probe Sans');
      fonts.showCarried((
        files: () => ofTheProject.letterFaceFiles,
        families: () => ofTheProject.families,
        takeOut: ofTheProject.takeOut,
      ));
      expect(fontsOf(session), isEmpty);
      expect(fonts.faces.holds('Probe Sans'), isFalse);
    });

    test('🚨after a save took it out and an undo brought it back, out of '
        'this run\'s ROOM', () async {
      final first = aSession(home);
      final name = await broughtHome(regular);
      final font = ProjectFontFile(carriedAs: name, facts: regular);
      first.repository.updateFonts([font]);
      await save(first);
      final session = await openedSession(
        projectPath,
        make: (project) => aSession(elsewhere, project),
      );
      session.projectFonts.takeOut('Probe Sans');
      await save(session);
      expect(session.projectFonts.letterFaceFiles, isEmpty);

      session.undo();

      final files = session.projectFonts.letterFaceFiles;
      expect([for (final file in files) file.name], [name]);
      expect(await files.single.read(), bytes);
      expect(await session.projectFile.fontBytes(font), bytes);
    });

    test('⛔a font the list names whose bytes are NOWHERE this machine can '
        'reach is not one of them — and reads as nothing', () async {
      final session = aSession(elsewhere);
      final font = ProjectFontFile(
        carriedAs: await broughtHome(regular),
        facts: regular,
      );
      session.repository.updateFonts([font]);

      expect(session.projectFonts.letterFaceFiles, isEmpty);
      expect(
        session.projectFile.fontsWithBytes(
          session.repository.requireProject(),
        ),
        isEmpty,
      );
      expect(await session.projectFile.fontBytes(font), isNull);
    });

    test('⛔nor is one the list names by anything but a name of the '
        'library\'s — though a file is there to find', () async {
      final session = aSession(home);
      File('${root.path}/home/secret.ttf')
        ..createSync(recursive: true)
        ..writeAsBytesSync(bytes);
      const crafted = ProjectFontFile(
        carriedAs: '../secret.ttf',
        facts: regular,
      );
      session.repository.updateFonts(const [crafted]);

      expect(session.projectFonts.letterFaceFiles, isEmpty);
      expect(await session.projectFile.fontBytes(crafted), isNull);
    });
  });

  // The ledger of `every_carry_stages_its_bytes_test` names this group:
  // a_registered_font_outlives_the_devices_copy.
  group('🚨★★★a registered font outlives the device\'s copy (「품은 순간 '
      '데이터를 가지고있고 불변」, kept without a copy at registration)', () {
    /// The font's bytes as [session]'s room keeps them — null when it
    /// keeps none.
    List<int>? inRoomOf(EditorSessionManager session, String name) {
      final kept = session.mediaStagingStore.findNamed(name);
      return kept == null ? null : File(kept.path).readAsBytesSync();
    }

    test('registering copies NOTHING: the bytes are the library\'s, and '
        'the room is empty', () async {
      final session = aSession(home);
      final name = await broughtHome(regular);

      session.historyManager.execute(
        session.projectFonts.landingWith(_Landing(), [setWith(name, regular)]),
      );

      expect(fontsOf(session), [
        ProjectFontFile(carriedAs: name, facts: regular),
      ]);
      expect(inRoomOf(session, name), isNull);
    });

    test('🚨before the library lets go of the file, the project takes its '
        'bytes — and with the file GONE, it still reads them, still sets '
        'letters with them, and the next save puts them in its file', () async {
      final session = aSession(home);
      final name = await broughtHome(regular);
      final font = ProjectFontFile(carriedAs: name, facts: regular);
      session.repository.updateFonts([font]);

      await session.projectFonts.holdBytesOf({name});
      await home.deleteFont(name);

      expect(home.pathOfFontHeld(name), isNull, reason: '⛔fixture: gone');
      expect(inRoomOf(session, name), bytes);
      expect(await session.projectFile.fontBytes(font), bytes);
      expect(
        [for (final file in session.projectFonts.letterFaceFiles) file.name],
        [name],
      );

      await save(session);

      final reopened = await openedSession(
        projectPath,
        make: (project) => aSession(elsewhere, project),
      );
      expect(await reopened.projectFile.fontBytes(font), bytes);
      expect(inRoomOf(session, name), isNull, reason: 'the save absorbed it');
    });

    test('⛔WITHOUT that, the file gone is the font gone — what the asking '
        'is for', () async {
      final session = aSession(home);
      final name = await broughtHome(regular);
      final font = ProjectFontFile(carriedAs: name, facts: regular);
      session.repository.updateFonts([font]);

      await home.deleteFont(name);

      expect(await session.projectFile.fontBytes(font), isNull);
    });

    test('only the files it is asked about, only the ones it carries, and '
        'only where it has them nowhere else', () async {
      final session = aSession(home);
      final sans = await broughtHome(regular);
      final other = await broughtHome(serif);
      final notCarried = await broughtHome(bold);
      session.repository.updateFonts([
        ProjectFontFile(carriedAs: sans, facts: regular),
        ProjectFontFile(carriedAs: other, facts: serif),
      ]);

      await session.projectFonts.holdBytesOf({sans, notCarried});

      expect(inRoomOf(session, sans), bytes);
      expect(inRoomOf(session, other), isNull, reason: 'not asked about');
      expect(inRoomOf(session, notCarried), isNull, reason: 'not carried');

      // Saved: the file holds both, and the room lets go of what it kept.
      await save(session);
      expect(inRoomOf(session, sans), isNull, reason: '⛔fixture: absorbed');

      await session.projectFonts.holdBytesOf({sans, other});

      expect(inRoomOf(session, sans), isNull, reason: 'the file has it');
      expect(inRoomOf(session, other), isNull, reason: 'the file has it');
    });
  });

  group('🚨a text lands WITH the faces it is set in', () {
    test('the files its letters are set with that the project does not '
        'carry are registered — as ONE step with the text', () {
      final session = aSession(home);
      final landing = _Landing();

      final step = session.projectFonts.landingWith(landing, [
        setWith('ab12-0001-Probe.ttf', regular),
        setWith('ab12-0002-Probe.ttf', bold),
      ]);
      session.historyManager.execute(step);

      expect(step.description, 'Set text');
      expect(landing.executed, 1);
      expect(fontsOf(session), const [
        ProjectFontFile(carriedAs: 'ab12-0001-Probe.ttf', facts: regular),
        ProjectFontFile(carriedAs: 'ab12-0002-Probe.ttf', facts: bold),
      ]);

      session.undo();

      expect(landing.undone, 1);
      expect(
        fontsOf(session),
        isEmpty,
        reason: 'a font tried once and undone is not carried',
      );
      expect(session.canUndo, isFalse, reason: 'it was one step');

      session.redo();

      expect(landing.executed, 2);
      expect(fontsOf(session), hasLength(2));
    });

    test('a landing with nothing to register is itself: letters in the '
        'app\'s own face, or in files the project carries already — by '
        'their NAMES', () {
      final session = aSession(home);
      session.repository.updateFonts(const [
        ProjectFontFile(carriedAs: 'ab12-0001-Probe.ttf', facts: regular),
      ]);
      final landing = _Landing();

      expect(
        session.projectFonts.landingWith(landing, const []),
        same(landing),
      );
      expect(
        session.projectFonts.landingWith(landing, [
          setWith('ab12-0001-Probe.ttf', regular),
        ]),
        same(landing),
      );
    });

    test('🚨a family rides WHOLE or not at all: one any file of which may '
        'not ride in a document that is edited registers none of its '
        'files — and the others in the text are unaffected', () {
      final session = aSession(home);

      final step = session.projectFonts.landingWith(_Landing(), [
        setWith('ab12-0001-Probe.ttf', regular),
        setWith('ab12-0002-Probe.ttf', kept),
        setWith('ab12-0003-Serif.ttf', serif),
      ]);
      session.historyManager.execute(step);

      expect(fontsOf(session), const [
        ProjectFontFile(carriedAs: 'ab12-0003-Serif.ttf', facts: serif),
      ]);
    });

    test('🚨a face has ONE file: one registered takes the place of the '
        'file the list had for the same face — and an undo puts that one '
        'back', () {
      final session = aSession(home);
      const dead = ProjectFontFile(
        carriedAs: 'ab12-0001-Probe.ttf',
        facts: regular,
      );
      const other = ProjectFontFile(
        carriedAs: 'ab12-0003-Serif.ttf',
        facts: serif,
      );
      session.repository.updateFonts(const [dead, other]);

      session.historyManager.execute(
        session.projectFonts.landingWith(_Landing(), [
          setWith('ab12-0009-Probe.ttf', regular),
        ]),
      );

      expect(fontsOf(session), const [
        other,
        ProjectFontFile(carriedAs: 'ab12-0009-Probe.ttf', facts: regular),
      ]);

      session.undo();

      expect(fontsOf(session), const [dead, other]);
    });

    test('⛔a file under a name that is not one of the library\'s is never '
        'registered: the name becomes a file\'s, wherever the project '
        'goes', () {
      final session = aSession(home);
      final landing = _Landing();

      for (final name in ['../Probe.ttf', 'Probe.ttf', 'ab12-cd34-Probe.exe']) {
        expect(
          session.projectFonts.landingWith(landing, [setWith(name, regular)]),
          same(landing),
          reason: name,
        );
      }
    });
  });

  group('taking a family out', () {
    const fonts = [
      ProjectFontFile(carriedAs: 'ab12-0001-Probe.ttf', facts: regular),
      ProjectFontFile(carriedAs: 'ab12-0003-Serif.ttf', facts: serif),
      ProjectFontFile(carriedAs: 'ab12-0002-Probe.ttf', facts: bold),
    ];

    test('🚨is one step: every file of the family leaves the list, the '
        'others stay — and an undo brings them back where they were', () {
      final session = aSession(home);
      session.repository.updateFonts(fonts);

      session.projectFonts.takeOut('Probe Sans');

      expect(fontsOf(session), [fonts[1]]);

      session.undo();

      expect(fontsOf(session), fonts);
      expect(session.canUndo, isFalse);
    });

    test('is nothing — no step of history — for a family the project '
        'carries no file of', () {
      final session = aSession(home);
      session.repository.updateFonts(fonts);

      session.projectFonts.takeOut('Probe Mono');

      expect(fontsOf(session), fonts);
      expect(session.canUndo, isFalse);
    });
  });

  test('the families it carries, as a list names them: each once, in the '
      'order a person looks for one', () {
    final session = aSession(home);
    session.repository.updateFonts(const [
      ProjectFontFile(carriedAs: 'ab12-0003-Serif.ttf', facts: serif),
      ProjectFontFile(carriedAs: 'ab12-0001-Probe.ttf', facts: regular),
      ProjectFontFile(carriedAs: 'ab12-0002-Probe.ttf', facts: bold),
      ProjectFontFile(
        carriedAs: 'ab12-0004-alpha.ttf',
        facts: FontFaceFacts(
          family: 'alpha',
          weight: 400,
          italic: false,
          fsType: 0,
        ),
      ),
    ]);

    expect(session.projectFonts.families, [
      'alpha',
      'Probe Sans',
      'Probe Serif',
    ]);
    expect(aSession(home).projectFonts.families, isEmpty);
  });
}

/// A text set on a cel, stood in for: it counts what it is asked.
class _Landing implements Command {
  int executed = 0;
  int undone = 0;

  @override
  String get description => 'Set text';

  @override
  void execute() => executed += 1;

  @override
  void undo() => undone += 1;
}
