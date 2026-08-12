import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/brush_dab.dart';
import 'package:anicel/src/models/brush_history_policy.dart';
import 'package:anicel/src/models/brush_tip_shape.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/services/brush_frame_edit_session_store.dart';
import 'package:anicel/src/services/brush_frame_editing_coordinator.dart';
import 'package:anicel/src/services/persistence/project_autosave_service.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';

/// P3 through the session: save/open round-trip, the load→edit→undo
/// lifecycle (both undo stacks clear on load), the dirty flag and the
/// autosave sidecar.
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
      frameStore: s.brushFrameStore,
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
    s.createCut();
    final savedCutCount = s.repository
        .requireProject()
        .tracks
        .first
        .cuts
        .length;
    final path = '${directory.path}/scene.anicel';
    await s.saveProjectToFile(path);
    expect(s.projectFilePath, path);
    expect(s.hasUnsavedChanges, isFalse);

    // Mutate past the save, then load the file back.
    s.createCut();
    expect(s.hasUnsavedChanges, isTrue);
    await s.openProjectFromFile(path);

    expect(
      s.repository.requireProject().tracks.first.cuts.length,
      savedCutCount,
    );
    expect(s.hasUnsavedChanges, isFalse);
    // Loaded state has NO history.
    expect(s.canUndo, isFalse);
    expect(s.canRedo, isFalse);

    // The saved drawing survived the round-trip as BAKED raster truth
    // (R19 bake-only: opens carry no commands — the picture is the file).
    expect(s.brushFrameStore.bakedSurfaceOrNull(drawnKey)?.tiles, isNotEmpty);

    // New edits after the load are undoable and undo cleanly.
    s.selectCut(s.repository.requireProject().tracks.first.cuts.first.id);
    s.createCut();
    expect(s.canUndo, isTrue);
    s.undo();
    expect(
      s.repository.requireProject().tracks.first.cuts.length,
      savedCutCount,
    );
    expect(s.canUndo, isFalse);
  });

  test('the atomic write leaves no temp residue and replaces an existing '
      'file in place', () async {
    final s = EditorSessionManager(initialProject: createDefaultProject());
    final path = '${directory.path}/scene.anicel';
    await s.saveProjectToFile(path);
    s.createCut();
    await s.saveProjectToFile(path);

    final entries = directory.listSync().map((e) => e.uri.pathSegments.last);
    expect(entries, ['scene.anicel']);
  });

  test('the autosave service snapshots only DIRTY sessions into the '
      'sidecar; a manual save retires it', () async {
    final s = EditorSessionManager(initialProject: createDefaultProject());
    final path = '${directory.path}/scene.anicel';
    await s.saveProjectToFile(path);

    final autosave = ProjectAutosaveService(
      isDirty: () => s.hasUnsavedChanges,
      writeSnapshot: s.writeAutosaveSnapshot,
      autosavePath: () => s.autosaveSidecarPath!,
    );
    // Clean session: nothing written. The snapshot lives in app support
    // now, so its path comes from the session rather than from the
    // project's own name.
    await autosave.tick();
    final sidecar = File(s.autosaveSidecarPath!);
    addTearDown(() {
      if (sidecar.parent.existsSync()) {
        sidecar.parent.deleteSync(recursive: true);
      }
    });
    expect(sidecar.existsSync(), isFalse);

    // Dirty session: the sidecar lands; the dirty flag stays (autosave is
    // not a manual save).
    s.createCut();
    await autosave.tick();
    expect(sidecar.existsSync(), isTrue);
    expect(s.hasUnsavedChanges, isTrue);
    expect(
      ProjectAutosaveService.sidecarIsNewer(
        filePath: path,
        sidecarPath: sidecar.path,
      ),
      isTrue,
    );

    // Manual save deletes the sidecar (awaited inside the save).
    await s.saveProjectToFile(path);
    expect(sidecar.existsSync(), isFalse);
  });

  test('recovery opens the SIDECAR bytes under the real file path and '
      'stays dirty until saved', () async {
    final s = EditorSessionManager(initialProject: createDefaultProject());
    final path = '${directory.path}/scene.anicel';
    await s.saveProjectToFile(path);

    // A newer autosave with one extra cut.
    s.createCut();
    await s.writeAutosaveSnapshot('$path.autosave');
    final recoveredCutCount = s.repository
        .requireProject()
        .tracks
        .first
        .cuts
        .length;

    final fresh = EditorSessionManager(initialProject: createDefaultProject());
    await fresh.openProjectFromFile('$path.autosave', recoverAs: path);
    expect(
      fresh.repository.requireProject().tracks.first.cuts.length,
      recoveredCutCount,
    );
    expect(fresh.projectFilePath, path, reason: 'saves go to the real file');
    expect(fresh.hasUnsavedChanges, isTrue);
  });
}
