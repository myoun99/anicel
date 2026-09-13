import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/brush_dab.dart';
import 'package:anicel/src/models/brush_history_policy.dart';
import 'package:anicel/src/models/brush_tip_shape.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/services/brush_frame_edit_session_store.dart';
import 'package:anicel/src/services/brush_frame_editing_coordinator.dart';
import 'package:anicel/src/services/persistence/folder_grant.dart'
    show MaterializeCancelled;
import 'package:anicel/src/ui/session/project_file_door.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';

/// P3 through the session: save/open round-trip, the load→edit→undo
/// lifecycle (both undo stacks clear on load), the dirty flag and the
/// staged-copy binding.
/// The save/open door itself — named so `tool/mutation_run.dart` has a
/// suite to run for it.
ProjectFileDoor projectDoorOf(EditorSessionManager session) =>
    session.projectDoor;

void main() {
  late Directory directory;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('anicel-session-test');
  });

  tearDown(() => directory.delete(recursive: true));

  test('a Cancel pressed during the read is honoured before anything lands '
      '— the session keeps what it had', () async {
    // The open stands behind the wait window from its first frame
    // (2026-09-13), and that window has a Cancel: during the read it must
    // mean what it says. The read runs to its end — nothing can interrupt
    // a parse — and the press is honoured at the last moment it still
    // means「nothing changed」.
    final s = EditorSessionManager(initialProject: createDefaultProject());
    final door = s.projectDoor;
    final path = '${directory.path}/cancel.anicel';
    await door.saveProjectToFile(path, asked: SaveAsked.byAPerson);
    final before = s.requireActiveCut;

    await expectLater(
      door.openProjectFromFile(path, isCancelled: () => true),
      throwsA(isA<MaterializeCancelled>()),
    );
    expect(
      identical(s.requireActiveCut, before),
      isTrue,
      reason: 'the read happened, the press was honoured, nothing landed',
    );
  });

  test('save → mutate → open restores the saved state; loading clears the '
      'undo stacks and NEW edits undo cleanly (load→edit→undo)', () async {
    final s = EditorSessionManager(initialProject: createDefaultProject());
    s.createDrawingAtCurrentFrame();
    // A real stroke in the brush store (the canvas commit path) so the
    // round-trip carries drawing content.
    final selection = s.editingCanvas.activeBrushEditorSelection!;
    final drawnKey = s.brushFrameKeyForCut(
      s.requireActiveCut,
      selection.layerId,
      selection.frameId,
    );
    BrushFrameEditingCoordinator(
      initialFrameKey: drawnKey,
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
    s.cutVerbs.createCut();
    final savedCutCount = s.repository
        .requireProject()
        .tracks
        .first
        .cuts
        .length;
    final door = projectDoorOf(s);
    final path = '${directory.path}/scene.anicel';
    await door.saveProjectToFile(path, asked: SaveAsked.byAPerson);
    expect(s.projectFile.path, path);
    expect(s.projectFile.hasUnsavedChanges, isFalse);

    // Mutate past the save, then load the file back.
    s.cutVerbs.createCut();
    expect(s.projectFile.hasUnsavedChanges, isTrue);
    await door.openProjectFromFile(path);

    expect(
      s.repository.requireProject().tracks.first.cuts.length,
      savedCutCount,
    );
    expect(s.projectFile.hasUnsavedChanges, isFalse);
    // Loaded state has NO history.
    expect(s.canUndo, isFalse);
    expect(s.canRedo, isFalse);

    // The saved drawing survived the round-trip as BAKED raster truth
    // (R19 bake-only: opens carry no commands — the picture is the file).
    expect(
      s.renderCaches.brushFrameStore.bakedSurfaceOrNull(drawnKey)?.tiles,
      isNotEmpty,
    );

    // New edits after the load are undoable and undo cleanly.
    s.selectCut(s.repository.requireProject().tracks.first.cuts.first.id);
    s.cutVerbs.createCut();
    expect(s.canUndo, isTrue);
    s.undo();
    expect(
      s.repository.requireProject().tracks.first.cuts.length,
      savedCutCount,
    );
    expect(s.canUndo, isFalse);
  });

  test('an OPEN clears the selections: a band naming the discarded '
      'project\'s rows is drawn nowhere, so leaving it live darkens every '
      'cell verb with nothing on screen to explain it', () async {
    final s = EditorSessionManager(initialProject: createDefaultProject());
    addTearDown(s.dispose);
    s.createDrawingAtCurrentFrame();
    final door = projectDoorOf(s);
    final path = '${directory.path}/scene.anicel';
    await door.saveProjectToFile(path, asked: SaveAsked.byAPerson);

    // A band naming a row of the project that is about to be replaced.
    s.updateFrameRangeSelectionDrag(
      layerId: s.activeLayer!.id,
      anchorIndex: 0,
      headIndex: 2,
    );
    expect(s.frameRangeSelection.value, isNotNull);

    await door.openProjectFromFile(path);

    expect(
      s.frameRangeSelection.value,
      isNull,
      reason:
          'the load replaces the project, so the band pointing into the '
          'old one goes with it',
    );
    expect(s.cells.cellSelectionClaimsSubject, isFalse);
    expect(
      s.cells.canDeleteCellAtCurrentFrame,
      isTrue,
      reason: 'and the cell verbs are live again on the loaded project',
    );
  });

  test('the atomic write leaves no temp residue and replaces an existing '
      'file in place', () async {
    final s = EditorSessionManager(initialProject: createDefaultProject());
    final door = projectDoorOf(s);
    final path = '${directory.path}/scene.anicel';
    await door.saveProjectToFile(path, asked: SaveAsked.byAPerson);
    s.cutVerbs.createCut();
    await door.saveProjectToFile(path, asked: SaveAsked.byAPerson);

    final entries = directory.listSync().map((e) => e.uri.pathSegments.last);
    expect(entries, ['scene.anicel']);
  });

  // 🪦**「the autosave service snapshots only DIRTY sessions into the
  // sidecar; a manual save retires it」 LIVED HERE.** The tick saves the
  // PROJECT FILE now (유저 2026-09-07: 「기존 결정대로 자동저장이 파일갱신
  // … 그게 싫으면 자동저장 off하면된다」), so「only dirty sessions」and「a
  // clean tick writes nothing」moved to
  // `an_autosave_tick_saves_the_project_test`, where they are asserted
  // against the file that now changes. ⛔The claims are not gone; only
  // the file they were about is.
  //
  // 🪦And so did 「recovery lays the snapshot OVER the real file」, which
  // stood right here — an overlay opened onto its base, the base cel
  // surviving, the session dirty until saved. That is not a claim that
  // moved: there is no overlay, and nothing writes one.

  test('🚨 reading a STAGED COPY still binds the session to the real file, '
      'and leaves it dirty', () async {
    // The scoped-platform road: a File Provider pick can be a placeholder
    // that refuses a random-access read, so the open reads a local copy the
    // app made — and every save after that has to land at the address the
    // user knows, not in the app's own scratch.
    //
    // 🚨It has to stay DIRTY too, because the cels are being read out of
    // that copy: a save is what moves those pixels back to the real file.
    //
    // ⚠️The parameter is `bindTo` now. It was `recoverAs`, shared with the
    // autosave recovery flow, and when that flow was deleted this road was
    // left as the only caller — with no test of its own, because its
    // coverage had come from the recovery tests. This is that test.
    final s = EditorSessionManager(initialProject: createDefaultProject());
    s.createDrawingAtCurrentFrame();
    final real = '${directory.path.replaceAll(r'\', '/')}/scene.anicel';
    await s.projectDoor.saveProjectToFile(real, asked: SaveAsked.byAPerson);
    final cuts = s.repository.requireProject().tracks.first.cuts.length;
    s.dispose();

    // What `materializeOpenedFile` hands back: the same bytes, elsewhere.
    final copy = '${directory.path.replaceAll(r'\', '/')}/staged.anicel';
    File(copy).writeAsBytesSync(File(real).readAsBytesSync());

    final opened = EditorSessionManager(initialProject: createDefaultProject());
    addTearDown(opened.dispose);
    await opened.projectDoor.openProjectFromFile(copy, bindTo: real);

    expect(
      opened.repository.requireProject().tracks.first.cuts.length,
      cuts,
      reason: 'the copy is what was read',
    );
    expect(
      opened.projectFile.path,
      real,
      reason: '⛔saves go to the file the user picked, never to the copy',
    );
    expect(
      opened.projectFile.hasUnsavedChanges,
      isTrue,
      reason: 'the cels live in a temp copy until a save moves them back',
    );
  });
}
