import 'dart:io';
import 'dart:typed_data';

import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/font_face_facts.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_font_file.dart';
import 'package:anicel/src/services/commands/update_project_fonts_command.dart';
import 'package:anicel/src/services/font_library_service.dart';
import 'package:anicel/src/services/persistence/anicel_incremental_writer.dart'
    show parseAnicelZipLayoutFile;
import 'package:anicel/src/services/persistence/anicel_project_archive.dart'
    show anicelFontEntryName;
import 'package:anicel/src/services/persistence/media_staging_store.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/session/project_file_door.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/opened_session.dart';
import '../../helpers/placed_sound_conform.dart';
import '../../helpers/temp_dir.dart';

/// 🚨★★★A PROJECT KEEPS THE FONTS REGISTERED WITH IT THROUGH EVERY SAVE OF
/// THE REAL SESSION (R9-rest, the text tool's faces) — the door, the
/// record and the room together, on the journeys carrying a font exists
/// to serve.
///
/// 🗣️유저 2026-10-06: 「뺄때까지 두는게 맞지않나 싶은데. 글꼴을 사실상
/// 등록하는거잖아. 프리미어프로처럼」. And of what a save takes out of a
/// file, said of media and held here by the same code (유저 2026-09-25,
/// board `undo-after-save-reads-the-original`): 「이번 실행의 앱 룸으로 옮겨
/// 둔다」.
void main() {
  late Directory root;

  /// The device the font was brought to, and one that never saw it.
  late FontLibraryService home;
  late FontLibraryService elsewhere;

  late String projectPath;

  const facts = FontFaceFacts(
    family: 'Probe Sans',
    weight: 400,
    italic: false,
    fsType: 0,
  );
  final bytes = Uint8List.fromList(
    List<int>.generate(48 * 1024, (i) => (i ~/ 7 + 3) & 0xFF),
  );

  /// The font, as the project carries it: under the name this device's
  /// library keeps its file under.
  late ProjectFontFile font;

  var sessions = 0;

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

  Future<void> save(EditorSessionManager session, [String? path]) =>
      session.projectDoor.saveProjectToFile(
        path ?? projectPath,
        asked: SaveAsked.byAPerson,
      );

  /// The project's fonts become [fonts], as one step of history.
  void register(EditorSessionManager session, List<ProjectFontFile> fonts) =>
      session.historyManager.execute(
        UpdateProjectFontsCommand(
          repository: session.repository,
          fonts: fonts,
        ),
      );

  /// The font's bytes as the file at [archive] holds them — null when it
  /// holds none.
  List<int>? inFile(String archive) {
    final entry = parseAnicelZipLayoutFile(
      archive,
    ).entryNamed(anicelFontEntryName(font.carriedAs));
    if (entry == null) {
      return null;
    }
    final file = File(archive).openSync();
    try {
      file.setPositionSync(entry.dataOffset);
      return file.readSync(entry.length);
    } finally {
      file.closeSync();
    }
  }

  /// The font's bytes as [session]'s room keeps them — null when it keeps
  /// none.
  List<int>? inRoomOf(EditorSessionManager session) {
    final kept = session.mediaStagingStore.findNamed(font.carriedAs);
    return kept == null ? null : File(kept.path).readAsBytesSync();
  }

  /// The project, saved on the device that holds the font and opened on
  /// one that never saw it.
  Future<EditorSessionManager> openedElsewhere() async {
    final first = aSession(home);
    register(first, [font]);
    await save(first);
    expect(inFile(projectPath), bytes, reason: '⛔fixture: the file has it');
    return openedSession(
      projectPath,
      make: (project) => aSession(elsewhere, project),
    );
  }

  setUp(() async {
    root = Directory.systemTemp.createTempSync('anicel_project_fonts_test');
    home = FontLibraryService(directoryPath: '${root.path}/home/fonts');
    elsewhere = FontLibraryService(directoryPath: '${root.path}/away/fonts');
    projectPath = '${root.path}/scene.anicel';
    final name = home.mintFileName(facts, extension: 'ttf');
    await home.writeFont(name, bytes);
    font = ProjectFontFile(carriedAs: name, facts: facts);
  });

  tearDown(() => deleteTempQuietly(root));

  test('🚨a save puts a font registered with the project INTO its file, '
      'from the file this device\'s library keeps — and the record says '
      'so', () async {
    final session = aSession(home);
    register(session, [font]);

    await save(session);

    expect(inFile(projectPath), bytes);
    expect(
      session.projectFile.fontsInFile,
      {anicelFontEntryName(font.carriedAs)},
    );
    expect(inRoomOf(session), isNull, reason: 'nothing was taken out');
  });

  test('🚨taken out by the session that SAVED it, a font goes to the room '
      'first all the same — though this device holds it too', () async {
    final session = aSession(home);
    register(session, [font]);
    await save(session);
    expect(inFile(projectPath), bytes, reason: '⛔fixture');

    register(session, const []);
    await save(session);

    expect(inFile(projectPath), isNull);
    expect(inRoomOf(session), bytes);
  });

  test('🚨⛔taking ONE font out leaves the others in the file: what a save '
      'is handed about the fonts is the same before and after it has kept '
      'what it leaves behind', () async {
    const serifFacts = FontFaceFacts(
      family: 'Probe Serif',
      weight: 400,
      italic: false,
      fsType: 0,
    );
    final serifBytes = Uint8List.fromList(List<int>.filled(20 * 1024, 9));
    final serifName = home.mintFileName(serifFacts, extension: 'otf');
    await home.writeFont(serifName, serifBytes);
    final serif = ProjectFontFile(carriedAs: serifName, facts: serifFacts);
    final session = aSession(home);
    register(session, [font, serif]);
    await save(session);

    register(session, [serif]);
    await save(session);

    expect(inFile(projectPath), isNull, reason: 'the one taken out is gone');
    final layout = parseAnicelZipLayoutFile(projectPath);
    final kept = layout.entryNamed(anicelFontEntryName(serifName));
    expect(kept, isNotNull, reason: 'the other one stays');
    expect(kept!.length, serifBytes.length);
    expect(session.projectFile.fontsInFile, {anicelFontEntryName(serifName)});
  });

  test('a font the device was never brought is not in the file — and the '
      'save is not a failed one', () async {
    final session = aSession(elsewhere);
    register(session, [font]);

    await save(session);

    expect(inFile(projectPath), isNull);
    expect(session.projectDoor.celsLostToAMissingFile, isEmpty);
    expect(session.projectFile.hasUnsavedChanges, isFalse);
  });

  group('on a device that was never brought the font', () {
    test('🚨⛔the project opens, is saved, and STILL carries it — the '
        'journey carrying a font exists to serve', () async {
      final session = await openedElsewhere();
      expect(session.repository.requireProject().fonts, [font]);
      expect(
        session.projectFile.fontsInFile,
        {anicelFontEntryName(font.carriedAs)},
      );

      await save(session);
      await save(session);

      expect(inFile(projectPath), bytes);
    });

    test('🚨a Save As carries it into the new file, read out of the one '
        'being left', () async {
      final session = await openedElsewhere();
      final copy = '${root.path}/copy.anicel';

      await save(session, copy);

      expect(inFile(copy), bytes);
      expect(
        session.projectFile.fontsInFile,
        {anicelFontEntryName(font.carriedAs)},
      );
    });

    test('🚨a font a person takes OUT leaves the file with the next save — '
        'and its bytes are in this run\'s room first', () async {
      final session = await openedElsewhere();
      register(session, const []);

      await save(session);

      expect(inFile(projectPath), isNull, reason: 'the file lets it go');
      expect(
        inRoomOf(session),
        bytes,
        reason:
            'an undo can bring the font back, and the file was the only '
            'place this device had its bytes',
      );
      expect(session.projectFile.fontsInFile, isEmpty);
    });

    test('🚨an UNDO of that brings it back, and the next save puts it in '
        'the file again — out of the room, which then lets go of its '
        'copy', () async {
      final session = await openedElsewhere();
      register(session, const []);
      await save(session);
      expect(inFile(projectPath), isNull, reason: '⛔fixture');

      session.undo();
      expect(session.repository.requireProject().fonts, [font]);
      await save(session);

      expect(inFile(projectPath), bytes);
      expect(
        inRoomOf(session),
        isNull,
        reason: 'absorbed again — 「사본 남으면 진짜 용서안할게」',
      );
      expect(
        session.projectFile.fontsInFile,
        {anicelFontEntryName(font.carriedAs)},
      );
    });

    test('and saved twice with the font out, the room still has it for the '
        'undo: the second save has nothing more to leave behind', () async {
      final session = await openedElsewhere();
      register(session, const []);
      await save(session);
      await save(session);

      session.undo();
      await save(session);

      expect(inFile(projectPath), bytes);
    });

    test('🚨a Save As the picker places leaves behind what the file it is '
        'bound to held: the font is in the room, and comes back from '
        'there', () async {
      final session = await openedElsewhere();
      final door = session.projectDoor;
      register(session, const []);
      final placed = '${root.path}/placed.anicel';

      final staged = await door.writeArchiveCopy(
        placed,
        asked: SaveAsked.byAPerson,
      );
      door.adoptPlacedArchive(placed, staged: staged);

      expect(inFile(placed), isNull);
      expect(staged.fontsInFile, isEmpty);
      expect(session.projectFile.fontsInFile, isEmpty);
      expect(inRoomOf(session), bytes);

      session.undo();
      await save(session, placed);

      expect(inFile(placed), bytes);
      expect(inRoomOf(session), isNull);
    });

    test('🚨a placed archive that HOLDS the font is the file it is taken '
        'out of afterwards: its bytes go to the room then', () async {
      final session = await openedElsewhere();
      final door = session.projectDoor;
      final placed = '${root.path}/placed.anicel';
      final staged = await door.writeArchiveCopy(
        placed,
        asked: SaveAsked.byAPerson,
      );
      door.adoptPlacedArchive(placed, staged: staged);
      expect(inFile(placed), bytes, reason: '⛔fixture: the copy carries it');
      expect(staged.fontsInFile, {anicelFontEntryName(font.carriedAs)});

      register(session, const []);
      await save(session, placed);

      expect(inFile(placed), isNull);
      expect(inRoomOf(session), bytes);
    });

    test('⛔a font the project still holds is not copied to the room: a '
        'save that takes nothing out leaves nothing behind', () async {
      final session = await openedElsewhere();

      await save(session);

      expect(inRoomOf(session), isNull);
      expect(
        Directory(session.mediaStagingStore.directoryPath).existsSync()
            ? Directory(session.mediaStagingStore.directoryPath).listSync()
            : const <FileSystemEntity>[],
        isEmpty,
      );
    });
  });

  test('a session built with no library of its own reads the app\'s own '
      'folder — which under a test is a sandbox', () {
    final session = EditorSessionManager(
      initialProject: createDefaultProject(),
      mediaStagingStore: MediaStagingStore(
        directoryPath: '${root.path}/StagedPlain',
      ),
      audioConformStore: soundConformStore(),
    );
    addTearDown(session.dispose);

    expect(
      session.fontLibrary.directoryPath,
      FontLibraryService.defaultFontDirectoryPath(),
    );
    expect(session.fontLibrary.directoryPath, contains('qa_test_fonts_'));
  });
}
