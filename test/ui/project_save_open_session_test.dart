import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/brush_dab.dart';
import 'package:anicel/src/models/brush_history_policy.dart';
import 'package:anicel/src/models/brush_tip_shape.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/services/brush_frame_edit_session_store.dart';
import 'package:anicel/src/services/brush_frame_editing_coordinator.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';

/// P3 through the session: save/open round-trip, the load→edit→undo
/// lifecycle (both undo stacks clear on load), the dirty flag and the
/// recovery overlay.
void main() {
  late Directory directory;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('anicel-session-test');
  });

  tearDown(() => directory.delete(recursive: true));

  test('save → mutate → open restores the saved state; loading clears the '
      'undo stacks and NEW edits undo cleanly (load→edit→undo)', () async {
    final s = EditorSessionManager(initialProject: createDefaultProject());
    s.createDrawingAtCurrentFrame();
    // A real stroke in the brush store (the canvas commit path) so the
    // round-trip carries drawing content.
    final selection = s.activeBrushEditorSelection!;
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
    final path = '${directory.path}/scene.anicel';
    await s.projectDoor.saveProjectToFile(path);
    expect(s.projectFile.path, path);
    expect(s.projectFile.hasUnsavedChanges, isFalse);

    // Mutate past the save, then load the file back.
    s.cutVerbs.createCut();
    expect(s.projectFile.hasUnsavedChanges, isTrue);
    await s.projectDoor.openProjectFromFile(path);

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
    final path = '${directory.path}/scene.anicel';
    await s.projectDoor.saveProjectToFile(path);

    // A band naming a row of the project that is about to be replaced.
    s.updateFrameRangeSelectionDrag(
      layerId: s.activeLayer!.id,
      anchorIndex: 0,
      headIndex: 2,
    );
    expect(s.frameRangeSelection.value, isNotNull);

    await s.projectDoor.openProjectFromFile(path);

    expect(
      s.frameRangeSelection.value,
      isNull,
      reason:
          'the load replaces the project, so the band pointing into the '
          'old one goes with it',
    );
    expect(s.cellSelectionClaimsSubject, isFalse);
    expect(
      s.canDeleteCellAtCurrentFrame,
      isTrue,
      reason: 'and the cell verbs are live again on the loaded project',
    );
  });

  test('the atomic write leaves no temp residue and replaces an existing '
      'file in place', () async {
    final s = EditorSessionManager(initialProject: createDefaultProject());
    final path = '${directory.path}/scene.anicel';
    await s.projectDoor.saveProjectToFile(path);
    s.cutVerbs.createCut();
    await s.projectDoor.saveProjectToFile(path);

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

  test('recovery lays the snapshot OVER the real file — the saved drawing '
      'survives, and the session stays dirty until saved', () async {
    // The modern route (`overlayPath:`), not the legacy `recoverAs:` arm —
    // a snapshot is a DELTA now, and this test once fed one through the
    // whole-archive arm with a drawing-free fixture, which could not see
    // that opening a delta AS the project drops every base cel.
    final s = EditorSessionManager(initialProject: createDefaultProject());
    // A real drawn cel in the BASE — the thing recovery must not lose.
    s.createDrawingAtCurrentFrame();
    final selection = s.activeBrushEditorSelection!;
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
    final path = '${directory.path}/scene.anicel';
    await s.projectDoor.saveProjectToFile(path);

    // A newer snapshot with one extra cut.
    s.cutVerbs.createCut();
    final overlay = '${directory.path}/scene.recovery';
    await s.projectDoor.writeAutosaveSnapshot(overlay);
    final recoveredCutCount = s.repository
        .requireProject()
        .tracks
        .first
        .cuts
        .length;

    final fresh = EditorSessionManager(initialProject: createDefaultProject());
    await fresh.projectDoor.openProjectFromFile(path, overlayPath: overlay);
    expect(
      fresh.repository.requireProject().tracks.first.cuts.length,
      recoveredCutCount,
    );
    expect(fresh.projectFile.path, path, reason: 'saves go to the real file');
    expect(fresh.projectFile.hasUnsavedChanges, isTrue);
    expect(
      fresh.renderCaches.brushFrameStore.bakedSurfaceOrNull(drawnKey)?.tiles,
      isNotEmpty,
      reason:
          'the overlay holds only the delta — the base cel must come '
          'from the project file underneath it',
    );
  });
}
