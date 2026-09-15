import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/services/persistence/anicel_incremental_writer.dart';
import 'package:anicel/src/services/persistence/open_project_file.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/session/project_file_door.dart';

import '../helpers/draw_on_current_frame.dart';

/// The Save As staging writer (실측 iPhone+Drive, 08-26): what the export
/// picker places must already BE the project. A never-saved project used
/// to stage a 22-byte placeholder on the theory that the save landing
/// after the move would fill it — and a provider that refuses in-place
/// writes turned the theory into an unopenable husk sitting exactly where
/// the user meant to put their work.
///
/// [ProjectFileDoor.writeArchiveCopy] writes the whole session as a
/// standalone archive and must change NOTHING about the session: the file
/// it produces is about to be MOVED by a document picker, so refs adopted
/// into it would be every cel dying the moment the move lands.
/// The door that writes the staged copy — named so `tool/mutation_run.dart`
/// runs this file for it: the save/open suite that also names it never takes
/// the picker road, which is where `adoptRefs: false` matters.
ProjectFileDoor projectDoorOf(EditorSessionManager session) =>
    session.projectDoor;

void main() {
  late Directory folder;

  setUp(() {
    folder = Directory.systemTemp.createTempSync('qa_stage_archive_');
  });
  tearDown(() {
    try {
      folder.deleteSync(recursive: true);
    } on Object {
      // A leaked handle on Windows must not fail the suite.
    }
  });

  test('🚨 a NEVER-saved session stages a complete archive and keeps every '
      'ref to itself — deleting the copy costs nothing', () async {
    final s = EditorSessionManager(initialProject: createDefaultProject());
    addTearDown(s.dispose);
    drawOnCurrentFrame(s);
    final selection = s.editingCanvas.activeBrushEditorSelection!;
    final drawnKey = s.brushFrameKeyForCut(
      s.requireActiveCut,
      selection.layerId,
      selection.frameId,
    );
    final copy = '${folder.path.replaceAll('\\', '/')}/staged.anicel';

    await s.projectDoor.writeArchiveCopy(copy, asked: SaveAsked.byAPerson);

    // The placed file IS the project: parseable, project.json and the
    // drawn cel inside.
    final layout = parseAnicelZipLayoutFile(copy);
    expect(layout.projectEntry(), isNotNull);
    expect(
      layout.entries.where((e) => e.name.endsWith('.celz')),
      isNotEmpty,
      reason: 'the drawing travels — an empty shell is the husk this '
          'writer exists to end',
    );

    // And the session learned NOTHING from writing it.
    expect(s.projectFile.path, isNull, reason: 'staging is not a save');
    expect(s.projectFile.hasUnsavedChanges, isTrue, reason: 'staging is not a save');
    // ⚠️ The instrument is the REF PATH, not "does the cel still read" —
    // the hot tier keeps a freshly drawn surface in RAM either way, so a
    // read survives a wrong adoption and measures nothing (a mutation
    // proved it). What adoption changes is where the refs POINT.
    expect(
      s.renderCaches.brushFrameStore
          .bakedSnapshotForSave()
          .fileRefs
          .values
          .map((ref) => ref.filePath.replaceAll('\\', '/')),
      isNot(contains(copy)),
      reason: 'refs were NOT adopted into the copy — the picker is about '
          'to move that file, and refs into it would be every cel dying',
    );
    File(copy).deleteSync();
    expect(s.renderCaches.brushFrameStore.bakedSurfaceOrNull(drawnKey)?.tiles, isNotEmpty);
  });

  test('a SAVED session can stage a copy elsewhere without its own refs '
      'moving', () async {
    final s = EditorSessionManager(initialProject: createDefaultProject());
    addTearDown(s.dispose);
    drawOnCurrentFrame(s);
    final selection = s.editingCanvas.activeBrushEditorSelection!;
    final drawnKey = s.brushFrameKeyForCut(
      s.requireActiveCut,
      selection.layerId,
      selection.frameId,
    );
    final home = '${folder.path.replaceAll('\\', '/')}/home.anicel';
    await s.projectDoor.saveProjectToFile(home, asked: SaveAsked.byAPerson);

    final copy = '${folder.path.replaceAll('\\', '/')}/copy.anicel';
    await s.projectDoor.writeArchiveCopy(copy, asked: SaveAsked.byAPerson);
    expect(parseAnicelZipLayoutFile(copy).projectEntry(),
        isNotNull);

    expect(s.projectFile.path, home);
    // Same instrument as above: the refs' PATHS are what adoption moves.
    final refPaths = s.renderCaches.brushFrameStore
        .bakedSnapshotForSave()
        .fileRefs
        .values
        .map((ref) => ref.filePath.replaceAll('\\', '/'))
        .toSet();
    expect(refPaths, contains(home), reason: 'the save adopted normally');
    expect(
      refPaths,
      isNot(contains(copy)),
      reason: 'the saved session still reads from ITS file, not the copy',
    );
    File(copy).deleteSync();
    expect(s.renderCaches.brushFrameStore.bakedSurfaceOrNull(drawnKey)?.tiles, isNotEmpty);
  });

  test('🚨 adopting what the picker PLACED costs no write — that second '
      'write is the one the provider refuses', () async {
    // 실기 08-27, iPhone: Save As placed the archive and then died with
    // 「the location refused both a direct write and a coordinated
    // replace」 — on the path it had just successfully filled. A
    // destination the picker moved a file INTO is not one the app may
    // keep writing to, and it never needed to: the picker is modal, so
    // the bytes it moved ARE the current session.
    final s = EditorSessionManager(initialProject: createDefaultProject());
    addTearDown(s.dispose);
    drawOnCurrentFrame(s);
    expect(s.projectFile.hasUnsavedChanges, isTrue);

    final staged = '${folder.path.replaceAll('\\', '/')}/staged.anicel';
    final written = await projectDoorOf(s).writeArchiveCopy(staged, asked: SaveAsked.byAPerson);

    // What the export picker does, and all it does: MOVE.
    final placed = '${folder.path.replaceAll('\\', '/')}/placed.anicel';
    File(staged).renameSync(placed);
    final bytesAsPlaced = File(placed).readAsBytesSync();

    projectDoorOf(s).adoptPlacedArchive(placed, staged: written);

    expect(s.projectFile.path, placed);
    expect(
      s.projectFile.hasUnsavedChanges,
      isFalse,
      reason: 'the placed archive IS the saved state',
    );
    expect(
      File(placed).readAsBytesSync(),
      bytesAsPlaced,
      reason: 'adoption writes nothing, so nothing can refuse it',
    );
    // And the pixels stay where a never-saved session had them: adoption
    // must not repoint refs into a file the app may not be able to read
    // back on demand.
    expect(File(placed).deleteSync, returnsNormally);
    expect(
      s.renderCaches.brushFrameStore
          .bakedSnapshotForSave()
          .fileRefs
          .values
          .map((ref) => ref.filePath.replaceAll('\\', '/')),
      isNot(contains(placed)),
    );
  });

  test('🚨a Save As copy answers for ITSELF what it could not carry — '
      'neither silent when it is one short, nor repeating what an earlier '
      'save said (F-72)', () async {
    final s = EditorSessionManager(initialProject: createDefaultProject());
    addTearDown(s.dispose);
    drawOnCurrentFrame(s);
    final selection = s.editingCanvas.activeBrushEditorSelection!;
    final drawnKey = s.brushFrameKeyForCut(
      s.requireActiveCut,
      selection.layerId,
      selection.frameId,
    );
    final base = folder.path.replaceAll('\\', '/');
    final original = '$base/original.anicel';
    await s.projectDoor.saveProjectToFile(
      original,
      asked: SaveAsked.byAPerson,
    );

    // What an earlier, lossy save would have left behind.
    s.projectDoor.celsLostToAMissingFile = {drawnKey};
    await s.projectDoor.writeArchiveCopy(
      '$base/copy.anicel',
      asked: SaveAsked.byAPerson,
    );
    expect(
      s.projectDoor.celsLostToAMissingFile,
      isEmpty,
      reason: 'the copy carried everything, and the answer is its own',
    );

    // The drawn cel cools off to the file alone: a clean file-backed cel's
    // cooling is a free drop, and the newest cel is the one the store keeps
    // hot, so a second drawing takes that place. Still hot, the copy would
    // write it from RAM and be short of nothing.
    final store = s.renderCaches.brushFrameStore;
    store.hotCelByteBudget = 0;
    s.selectFrameIndex(1);
    drawOnCurrentFrame(s);
    await store.drainCooling();

    // The file the drawn cel now lives in goes away: the next copy cannot
    // carry it.
    OpenProjectFile.instance.release();
    File(original).deleteSync();
    await s.projectDoor.writeArchiveCopy(
      '$base/copy2.anicel',
      asked: SaveAsked.byAPerson,
    );
    expect(
      s.projectDoor.celsLostToAMissingFile,
      {drawnKey},
      reason: 'a copy one cel short says so',
    );
  });
}
