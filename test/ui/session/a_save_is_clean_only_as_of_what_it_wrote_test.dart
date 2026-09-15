import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/services/persistence/anicel_file_service.dart';
import 'package:anicel/src/services/persistence/open_project_file.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/session/project_file_door.dart' show SaveAsked;

/// 🚨★★★F-128 — A SAVE IS CLEAN ONLY AS OF WHAT IT WROTE.
///
/// 유저 2026-09-14: 「그림 그렸는데 닫으려고 할때 편집한게 있으니 저장하라는
/// 메시지가 언제부턴가 안뜸. 법 통일할거 하면서 뜨도록. 최대한 규칙 단순화」.
///
/// The close asks when the session holds edits no file has. What said so
/// was a bool a save cleared at its END — so an edit that landed while the
/// autosave tick was still writing (the tick has no window, and nothing
/// stops the pen) was in no file and flagged nowhere. Unsaved is a
/// comparison now: the edits the session made against the count its file
/// holds, which a save captures before it reads the project.
///
/// The other half of F-128 — the Windows close button not reaching the app
/// at all — is `test/ui/the_close_button_asks_the_app_test.dart`.
void main() {
  late Directory folder;

  setUp(() => folder = Directory.systemTemp.createTempSync('qa_f128_'));
  tearDown(() {
    OpenProjectFile.instance.release();
    try {
      folder.deleteSync(recursive: true);
    } on Object {
      // A leaked handle on Windows must not fail the suite.
    }
  });

  String pathOf(String name) => '${folder.path.replaceAll(r'\', '/')}/$name';

  int cutsOf(EditorSessionManager s) =>
      s.repository.requireProject().tracks.first.cuts.length;

  /// The cuts the archive at [path] really holds — read from the file, not
  /// from any session.
  Future<int> cutsInFile(String path) async {
    final opened = await const AnicelFileService().open(filePath: path);
    return opened.project.tracks.first.cuts.length;
  }

  group('the record', () {
    test('an edit after the count a save captured stays unsaved', () {
      final s = EditorSessionManager(initialProject: createDefaultProject());
      addTearDown(s.dispose);
      s.cutVerbs.createCut();
      final captured = s.projectFile.editCount;
      s.cutVerbs.createCut();

      s.projectFile.bindToSavedFile(
        pathOf('law.anicel'),
        entryNames: const {},
        cleanAsOf: captured,
      );

      expect(s.projectFile.hasUnsavedChanges, isTrue);
    });

    test('with nothing after the capture, the save is clean', () {
      final s = EditorSessionManager(initialProject: createDefaultProject());
      addTearDown(s.dispose);
      s.cutVerbs.createCut();

      s.projectFile.bindToSavedFile(
        pathOf('law.anicel'),
        entryNames: const {},
        cleanAsOf: s.projectFile.editCount,
      );

      expect(s.projectFile.hasUnsavedChanges, isFalse);
    });

    test('a file opened as already differing is unsaved until a save', () {
      final s = EditorSessionManager(initialProject: createDefaultProject());
      addTearDown(s.dispose);

      s.projectFile.bindToOpenedFile(
        pathOf('opened.anicel'),
        entryNames: const {},
        unsaved: true,
      );
      expect(s.projectFile.hasUnsavedChanges, isTrue);

      s.projectFile.bindToOpenedFile(
        pathOf('opened.anicel'),
        entryNames: const {},
        unsaved: false,
      );
      expect(s.projectFile.hasUnsavedChanges, isFalse);
    });
  });

  test('🚨 an edit that lands while the clock is writing stays unsaved — '
      'and the next save carries it', () async {
    final s = EditorSessionManager(initialProject: createDefaultProject());
    addTearDown(s.dispose);
    final path = pathOf('tick.anicel');
    await s.projectDoor.saveProjectToFile(path, asked: SaveAsked.byAPerson);
    s.cutVerbs.createCut();
    final cutsAtTheTick = cutsOf(s);

    var landedInsideTheWrite = false;
    await s.projectDoor.saveProjectToFile(
      path,
      asked: SaveAsked.byTheClock,
      // A report comes back only once the project entry is in the bytes, so
      // an edit made on the first one is an edit this file cannot hold.
      onProgress: (_) {
        if (landedInsideTheWrite) {
          return;
        }
        landedInsideTheWrite = true;
        s.cutVerbs.createCut();
      },
    );

    expect(
      landedInsideTheWrite,
      isTrue,
      reason: '⛔premise: no report came back, so nothing landed inside the '
          'write',
    );
    expect(
      await cutsInFile(path),
      cutsAtTheTick,
      reason: '⛔premise: the edit really is not in the file — or this '
          'measured nothing',
    );
    expect(
      s.projectFile.hasUnsavedChanges,
      isTrue,
      reason: 'the edit is in no file, so the close must still ask',
    );

    await s.projectDoor.saveProjectToFile(path, asked: SaveAsked.byTheClock);

    expect(s.projectFile.hasUnsavedChanges, isFalse);
    expect(await cutsInFile(path), cutsAtTheTick + 1);
  });

  test('🚨 the staged copy is clean only as of what IT wrote — an edit '
      'during the staging stays unsaved after the adoption', () async {
    final s = EditorSessionManager(initialProject: createDefaultProject());
    addTearDown(s.dispose);
    s.cutVerbs.createCut();
    final cutsAtTheStaging = cutsOf(s);
    final stagedPath = pathOf('staged.anicel');

    var landedInsideTheWrite = false;
    final written = await s.projectDoor.writeArchiveCopy(
      stagedPath,
      asked: SaveAsked.byAPerson,
      onProgress: (_) {
        if (landedInsideTheWrite) {
          return;
        }
        landedInsideTheWrite = true;
        s.cutVerbs.createCut();
      },
    );

    expect(
      landedInsideTheWrite,
      isTrue,
      reason: '⛔premise: no report came back, so nothing landed inside the '
          'write',
    );
    expect(
      await cutsInFile(stagedPath),
      cutsAtTheStaging,
      reason: '⛔premise: the edit really is not in the staged file',
    );

    s.projectDoor.adoptPlacedArchive(stagedPath, staged: written);

    expect(
      s.projectFile.hasUnsavedChanges,
      isTrue,
      reason: 'the placed archive holds everything but that edit',
    );
  });
}
