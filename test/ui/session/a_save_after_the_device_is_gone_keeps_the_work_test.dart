import 'dart:io';

import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/native/app_gpu_engine.dart';
import 'package:anicel/src/native/engine_tile_ledger.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/session/project_file_door.dart' show SaveAsked;
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/draw_on_current_frame.dart';
import '../../helpers/opened_session.dart';
import '../../helpers/project_scratch_folder.dart';

/// 🗣️gpu-canonical-store-Q11 (유저 2026-11-10): 「RAM 에 사본을 두고 앱을
/// 유지한다」, and the words the app says where its device refuses a job
/// (🗣️gpu-canonical-store-Q14): 「저장한 뒤 앱을 다시 시작해 주세요」 — a
/// save after the device is gone has every tile to read: the strokes whose
/// copies had come, and under the last ones the picture they were laid on.
/// ↩️Till then every tile the engine alone held was refused the save
/// (`SaveFailureCause.engineRead`), and the last save was what was left.
///
/// ⚠️ONE TEST, and the app's own engine: a device that is gone is gone for
/// its process.
void main() {
  test('a save after the device is gone writes the work — a stroke whose '
      'copy had come, and not the one laid on it since', () async {
    final folder = Directory.systemTemp.createTempSync('anicel-device-gone');
    deleteAfterSessionEnds(folder);
    final path = '${folder.path.replaceAll('\\', '/')}/project.anicel';
    final s = EditorSessionManager(initialProject: createDefaultProject());
    addTearDown(s.dispose);
    final cut = s.requireActiveCut;

    // A dab at (10, 10), and its copy come.
    drawOnCurrentFrame(s);
    final selection = s.editingCanvas.activeBrushEditorSelection!;
    final cel = s.brushFrameKeyForCut(
      cut,
      selection.layerId,
      selection.frameId,
    );
    final store = s.renderCaches.brushFrameStore;
    final first = store.bakedSurfaceOrNull(cel)!.tileAt(TileCoord(x: 0, y: 0))!;
    expect(first.isOnlyOnEngine, isTrue, reason: '⛔premise: landed there');
    expect(EngineTileLedger.instance.copyHereABatch(), isFalse);
    expect(first.isOnlyOnEngine, isFalse, reason: '⛔premise: its copy came');

    // One more on the same tile, at (100, 100): the engine's alone.
    inkCel(
      s,
      cel,
      canvasSize: cut.canvasSize,
      at: CanvasPoint(x: 100, y: 100),
      size: 4,
    );
    final second = store
        .bakedSurfaceOrNull(cel)!
        .tileAt(TileCoord(x: 0, y: 0))!;
    expect(identical(second, first), isFalse, reason: '⛔premise: landed');
    expect(second.isOnlyOnEngine, isTrue, reason: '⛔premise: no copy yet');

    appGpuEngine.debugLose();
    await s.projectDoor.saveProjectToFile(path, asked: SaveAsked.byAPerson);

    expect(appGpuEngineIsGone, isTrue, reason: '⛔premise: it was gone');
    expect(s.projectFile.hasUnsavedChanges, isFalse);
    final opened = await openedSession(path);
    addTearDown(opened.dispose);
    final saved = opened.renderCaches.brushFrameStore
        .bakedSurfaceOrNull(cel)!
        .tileAt(TileCoord(x: 0, y: 0))!
        .pixels;
    int alphaAt(int x, int y) => saved[(y * second.size + x) * 4 + 3];
    expect(alphaAt(10, 10), isNonZero, reason: 'whose copy had come');
    expect(alphaAt(100, 100), 0, reason: 'the one that went with the device');
  });
}
