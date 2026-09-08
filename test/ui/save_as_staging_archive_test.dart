import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/brush_dab.dart';
import 'package:anicel/src/models/brush_history_policy.dart';
import 'package:anicel/src/models/brush_tip_shape.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/services/brush_frame_edit_session_store.dart';
import 'package:anicel/src/services/brush_frame_editing_coordinator.dart';
import 'package:anicel/src/services/persistence/anicel_incremental_writer.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/session/project_file_door.dart';

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

  void drawOnCurrentFrame(EditorSessionManager s) {
    s.createDrawingAtCurrentFrame();
    final selection = s.editingCanvas.activeBrushEditorSelection!;
    BrushFrameEditingCoordinator(
      initialFrameKey: s.brushFrameKeyForCut(
        s.requireActiveCut,
        selection.layerId,
        selection.frameId,
      ),
      frameStore: s.renderCaches.brushFrameStore,
      sessionStore: BrushFrameEditSessionStore(
        canvasSize: s.requireActiveCut.canvasSize,
        tileSize: 256,
      ),
      historyPolicy: const BrushHistoryPolicy(
        userUndoLimit: 8,
        deferredBakeRatio: 0,
      ),
    ).commitSourceStroke(
      sourceDabs: [
        BrushDab(
          center: CanvasPoint(x: 10, y: 10),
          color: 0xFF000000,
          size: 4,
          opacity: 1,
          flow: 1,
          hardness: 1,
          tipShape: BrushTipShape.round,
          pressure: 1,
          sequence: 0,
        ),
      ],
    );
  }

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

    await s.projectDoor.writeArchiveCopy(copy);

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
    await s.projectDoor.saveProjectToFile(home);

    final copy = '${folder.path.replaceAll('\\', '/')}/copy.anicel';
    await s.projectDoor.writeArchiveCopy(copy);
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
    final names = await projectDoorOf(s).writeArchiveCopy(staged);

    // What the export picker does, and all it does: MOVE.
    final placed = '${folder.path.replaceAll('\\', '/')}/placed.anicel';
    File(staged).renameSync(placed);
    final bytesAsPlaced = File(placed).readAsBytesSync();

    projectDoorOf(s).adoptPlacedArchive(placed, mediaEntryNames: names);

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
}
