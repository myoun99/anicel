import 'dart:io';

import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/native/app_gpu_engine.dart';
import 'package:anicel/src/native/engine_tile_ledger.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/session/project_file_door.dart' show SaveAsked;
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gpu_engine/gpu_engine.dart';

import '../../helpers/opened_session.dart';
import '../../helpers/project_scratch_folder.dart';
import '../../helpers/tiles_on_the_engine.dart';

/// 🗣️gpu-canonical-store-Q11 (유저 2026-11-10): 「RAM 에 사본을 두고 앱을
/// 유지한다」, and the words the app says where its device refuses a job
/// (🗣️gpu-canonical-store-Q14): 「저장한 뒤 앱을 다시 시작해 주세요」 — a
/// save after the device is gone has every tile to read: the ones whose
/// copies had come, and for the rest the picture each was laid on.
/// ↩️Till then every tile the engine alone held was refused the save
/// (`SaveFailureCause.engineRead`), and the last save was what was left.
///
/// ⚠️ONE TEST, and the app's own engine: a device that is gone is gone for
/// its process. The cel's tiles are landed as a stroke lands them, with no
/// stroke: a first stroke compiles its kernels where it is drawn, 🔬45 s of
/// this test beside a busy line (main PC, 2026-11-11), past the time a
/// test is given.
void main() {
  test('a save after the device is gone writes the work — a tile whose '
      'copy had come as itself, and one landed since as the picture it '
      'landed on', () async {
    final folder = Directory.systemTemp.createTempSync('anicel-device-gone');
    deleteAfterSessionEnds(folder);
    final path = '${folder.path.replaceAll('\\', '/')}/project.anicel';
    final s = EditorSessionManager(initialProject: createDefaultProject());
    addTearDown(s.dispose);
    final cut = s.requireActiveCut;
    s.createDrawingAtCurrentFrame();
    final selection = s.editingCanvas.activeBrushEditorSelection!;
    final cel = s.brushFrameKeyForCut(
      cut,
      selection.layerId,
      selection.frameId,
    );
    final first = TileCoord(x: 0, y: 0);
    final second = TileCoord(x: 1, y: 0);

    // One tile of 7s, its copy come, and one of 9s landed on a tile of 3s.
    final ledger = EngineTileLedger.instance;
    final copied = landedOn(ledger, cel.cel, [null], 7).single;
    expect(ledger.copyHereABatch(), isFalse);
    expect(copied.isOnlyOnEngine, isFalse, reason: '⛔premise: its copy came');
    final under = BitmapTile(
      size: gpuTileSide,
      pixels: Uint8List(gpuTileBytes)..fillRange(0, gpuTileBytes, 3),
    );
    final landed = landedOn(ledger, cel.cel, [under], 9).single;
    expect(landed.isOnlyOnEngine, isTrue, reason: '⛔premise: no copy yet');
    s.renderCaches.brushFrameStore.storeBakedSurface(
      cel,
      BitmapSurface(
        canvasSize: cut.canvasSize,
        tileSize: gpuTileSide,
        tiles: {first: copied, second: landed},
      ),
    );

    appGpuEngine.debugLose();
    await s.projectDoor.saveProjectToFile(path, asked: SaveAsked.byAPerson);

    expect(appGpuEngineIsGone, isTrue, reason: '⛔premise: it was gone');
    expect(s.projectFile.hasUnsavedChanges, isFalse);
    final opened = await openedSession(path);
    addTearDown(opened.dispose);
    final saved = opened.renderCaches.brushFrameStore.bakedSurfaceOrNull(cel)!;
    expect(saved.tileAt(first)!.pixels, everyElement(7));
    expect(saved.tileAt(second)!.pixels, everyElement(3));
  });
}
