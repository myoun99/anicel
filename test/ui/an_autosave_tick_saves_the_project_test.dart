import 'package:anicel/src/ui/session/project_file_door.dart' show SaveAsked;
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/services/persistence/anicel_file_service.dart';
import 'package:anicel/src/services/persistence/project_autosave_service.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/session/project_file.dart';
import '../helpers/temp_dir.dart';

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
/// The collaborator that answers whether the tick may run — named so
/// `tool/mutation_run.dart` runs this file for it: the carried-media suite
/// that also names it never asks the autosave question.
ProjectFile projectFileOf(EditorSessionManager session) => session.projectFile;

void main() {
  late Directory directory;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('anicel-tick-saves');
  });

  tearDown(() => deleteTempQuietly(directory));

  /// The service wired the way the shell wires it.
  ProjectAutosaveService autosaveFor(EditorSessionManager session) =>
      ProjectAutosaveService(
        isDirty: () =>
            session.projectFile.hasUnsavedChanges &&
            !session.projectFile.autosaveShouldStandDown,
        saveProject: (path) => session.projectDoor.saveProjectToFile(
          path,
          asked: SaveAsked.byTheClock,
        ),
        projectPath: () => session.projectFile.path!,
        needsProjectFile: () => session.projectFile.path == null,
      );

  test('🚨 a tick puts the edit in the PROJECT FILE, and the session comes '
      'out clean', () async {
    final path = '${directory.path.replaceAll(r'\', '/')}/p.anicel';
    final session = EditorSessionManager(initialProject: createDefaultProject());
    addTearDown(session.dispose);
    await session.projectDoor.saveProjectToFile(path, asked: SaveAsked.byAPerson);
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
    await session.projectDoor.saveProjectToFile(path, asked: SaveAsked.byAPerson);
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

  test('🚨 a tick stands down while a manual save runs', () async {
    // 🚨Still the law, and now for a blunter reason than the one it was
    // written for. It used to be about a tick landing after the save's
    // sidecar retirement and leaving one behind for a project that was
    // closed cleanly. The tick SAVES now, so a tick inside a save is two
    // writers on one archive — the same file, the same temp-and-rename.
    // The in-flight flag is what keeps them apart.
    final path = '${directory.path.replaceAll(r'\', '/')}/inflight.anicel';
    final session = EditorSessionManager(initialProject: createDefaultProject());
    addTearDown(session.dispose);
    await session.projectDoor.saveProjectToFile(path, asked: SaveAsked.byAPerson);
    session.cutVerbs.createCut();

    var ticked = false;
    final autosave = ProjectAutosaveService(
      isDirty: () =>
          session.projectFile.hasUnsavedChanges &&
          !session.projectFile.autosaveShouldStandDown,
      saveProject: (path) async {
        ticked = true;
        await session.projectDoor.saveProjectToFile(path, asked: SaveAsked.byAPerson);
      },
      projectPath: () => session.projectFile.path!,
    );

    final saving = session.projectDoor.saveProjectToFile(path, asked: SaveAsked.byAPerson);
    await autosave.saveNow();
    await saving;

    expect(ticked, isFalse, reason: 'the tick fired inside the save');
  });

  test('🚨 closing WITHOUT saving stands the tick down, so the way out '
      'cannot put the work back', () async {
    // 「저장 안 하고 닫기 = 버리기」 is the OFF position of the switch now,
    // but the moment the user says it, it has to hold: the tear-down that
    // follows delivers the same lifecycle callbacks any close does, and a
    // tick coming due in there would save the very work just discarded.
    final path = '${directory.path.replaceAll(r'\', '/')}/discarded.anicel';
    final session = EditorSessionManager(initialProject: createDefaultProject());
    addTearDown(session.dispose);
    await session.projectDoor.saveProjectToFile(path, asked: SaveAsked.byAPerson);
    final cutsAtSave = (await const AnicelFileService().open(
      filePath: path,
    )).project.tracks.first.cuts.length;

    session.cutVerbs.createCut();
    projectFileOf(session).discardUnsavedWork();
    expect(projectFileOf(session).autosaveShouldStandDown, isTrue);

    await autosaveFor(session).saveNow();

    expect(
      (await const AnicelFileService().open(
        filePath: path,
      )).project.tracks.first.cuts.length,
      cutsAtSave,
      reason: '⛔the discarded cut reached the file — the session is still '
          'dirty, so only the stand-down keeps the tick off it',
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
      saveProject: (path) => session.projectDoor.saveProjectToFile(
        path,
        asked: SaveAsked.byTheClock,
      ),
      projectPath: () => session.projectFile.path!,
      needsProjectFile: () => session.projectFile.path == null,
      onUnsavedProject: () => prompted += 1,
    ).saveNow();

    expect(prompted, 1);
    expect(session.projectFile.hasUnsavedChanges, isTrue);
  });
}
