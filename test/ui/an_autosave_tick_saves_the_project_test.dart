import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/services/persistence/anicel_file_service.dart';
import 'package:anicel/src/services/persistence/project_autosave_service.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';

/// 🚨★★★**THE TICK SAVES THE PROJECT FILE.**
///
/// 유저 2026-09-07, asked what happens to 「저장 안 하고 닫기 = 버리기」 if
/// autosave touches the file: 「기존 결정대로 자동저장이 파일갱신. **그게
/// 싫으면 자동저장 off하면된다**고 말했는데 안바꿧나보네」. So the discard
/// rule is the OFF position of a switch, not a property of the app, and
/// this is the ON position doing what it says.
///
/// ⛔The old tick wrote a recovery SIDECAR and left the project file
/// alone. Both shapes leave the session clean and the work safe, so a
/// test that only checked「the work survived」would pass either way — what
/// separates them is WHICH FILE CHANGED, and that is what is asserted.
void main() {
  late Directory directory;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('anicel-tick-saves');
  });

  tearDown(() {
    try {
      directory.deleteSync(recursive: true);
    } on Object {
      // A locked file on Windows must not fail the suite.
    }
  });

  /// The service wired the way the shell wires it.
  ProjectAutosaveService autosaveFor(EditorSessionManager session) =>
      ProjectAutosaveService(
        isDirty: () =>
            session.projectFile.hasUnsavedChanges &&
            !session.projectFile.autosaveShouldStandDown,
        saveProject: session.projectDoor.saveProjectToFile,
        projectPath: () => session.projectFile.path!,
        needsProjectFile: () => session.projectFile.path == null,
      );

  test('🚨 a tick puts the edit in the PROJECT FILE, and the session comes '
      'out clean', () async {
    final path = '${directory.path.replaceAll(r'\', '/')}/p.anicel';
    final session = EditorSessionManager(initialProject: createDefaultProject());
    addTearDown(session.dispose);
    await session.projectDoor.saveProjectToFile(path);
    final cutsAtSave = (await const AnicelFileService().open(
      filePath: path,
    )).project.tracks.first.cuts.length;

    session.cutVerbs.createCut();
    expect(session.projectFile.hasUnsavedChanges, isTrue);

    await autosaveFor(session).saveNow();

    expect(
      (await const AnicelFileService().open(filePath: path))
          .project
          .tracks
          .first
          .cuts
          .length,
      cutsAtSave + 1,
      reason: '⛔the FILE, not a sidecar. A tick that wrote somewhere else '
          'would leave the session just as safe and this project just as '
          'stale, which is the difference nothing else can see.',
    );
    expect(
      session.projectFile.hasUnsavedChanges,
      isFalse,
      reason: 'and it was a real save, so there is nothing left to save',
    );
  });

  test('⛔ a clean session ticks and writes nothing', () async {
    final path = '${directory.path.replaceAll(r'\', '/')}/clean.anicel';
    final session = EditorSessionManager(initialProject: createDefaultProject());
    addTearDown(session.dispose);
    await session.projectDoor.saveProjectToFile(path);
    final wroteAt = File(path).lastModifiedSync();

    await autosaveFor(session).saveNow();

    expect(
      File(path).lastModifiedSync(),
      wroteAt,
      reason: 'the clock fires on a schedule, not on work — a tick that '
          'rewrote an untouched project would churn the file (and, in a '
          'synced folder, the upload) every n minutes for nothing',
    );
  });

  test('⛔ a NEVER-SAVED project still writes nowhere', () async {
    // PEN-12 #8 unchanged: there is no file to save INTO, and piling one
    // into a hidden app-data folder for a document with no identity yet is
    // exactly what that decision refused.
    final session = EditorSessionManager(initialProject: createDefaultProject());
    addTearDown(session.dispose);
    session.cutVerbs.createCut();

    var prompted = 0;
    await ProjectAutosaveService(
      isDirty: () => session.projectFile.hasUnsavedChanges,
      saveProject: session.projectDoor.saveProjectToFile,
      projectPath: () => session.projectFile.path!,
      needsProjectFile: () => session.projectFile.path == null,
      onUnsavedProject: () => prompted += 1,
    ).saveNow();

    expect(prompted, 1);
    expect(session.projectFile.hasUnsavedChanges, isTrue);
  });
}
