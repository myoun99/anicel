import 'dart:io';
import 'dart:typed_data';

import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/brush_frame_key.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/brush_frame_store.dart';
import 'package:anicel/src/services/persistence/anicel_file_service.dart';
import 'package:anicel/src/services/persistence/anicel_incremental_writer.dart';
import 'package:anicel/src/services/persistence/anicel_project_archive.dart';
import 'package:anicel/src/services/persistence/scratch_file.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/session/project_file_door.dart' show SaveAsked;
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/cels_parked_cold.dart';
import '../../helpers/project_scratch_folder.dart';

/// 🚨A cel parked in the run's room is written by a save from its park —
/// the file the save's snapshot names, read on the save's isolate after
/// the cels in RAM are made ready. A change to the cel while the save
/// runs ends its park, and the park's file went with it at once: the
/// save then found no file, left the cel out without a word, and the
/// archive it wrote held no entry for a cel the person had when they
/// saved (card cel-originals-are-held-twice-in-ram-and-on-the-gpu,
/// 저장 2026-11-21: an imported cel is parked as it lands, so every cel of
/// an import is a park a save reads).
///
/// The change itself is the next save's to write
/// (an_edit_made_while_a_save_runs_is_left_for_the_next_save_test.dart);
/// what is pinned here is that THIS save still writes what it took.
void main() {
  // The session warms playback's rows in the quiet the save leaves it, and
  // a row asks the binding for the quiet it takes its turn in.
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(() => AnicelFileService.debugAfterScreenTurn = null);

  for (final (:how, :madeHotFirst) in [
    (how: 'parked', madeHotFirst: false),
    (how: 'parked and made hot', madeHotFirst: true),
  ]) {
    test('🚨a cel $how and drawn on while the save runs is in the file the '
        'save wrote, as it was when the save began', () async {
      final s = EditorSessionManager(initialProject: createDefaultProject());
      addTearDown(s.dispose);
      final store = s.renderCaches.brushFrameStore;
      final parked = _celInANewCut(s);
      final drawn = _celInANewCut(s);
      final canvasSize = s.requireActiveCut.canvasSize;
      parkCold(store, {parked: _ink(canvasSize, 3)});
      // The cel in RAM the save makes ready first — its turn is where the
      // drawing lands.
      store.storeBakedSurface(drawn, _ink(canvasSize, 5));
      expect(
        store.isCelParked(parked),
        isTrue,
        reason: '⛔premise: parked',
      );
      expect(
        store.hotBakedSurfaceOrNull(drawn),
        isNotNull,
        reason: '⛔premise: the cel the canvas stands on stays in RAM',
      );
      if (madeHotFirst) {
        store.bakedSurfaceOrNull(parked);
        expect(store.isCelParked(parked), isTrue, reason: '⛔premise');
      }
      var drewWhileItRan = false;
      AnicelFileService.debugAfterScreenTurn = () {
        if (drewWhileItRan) {
          return;
        }
        drewWhileItRan = true;
        store.storeBakedSurface(parked, _ink(canvasSize, 9));
      };
      final park = store.bakedSnapshotForSave().cold[parked]!;
      final path = '${_scratch().path}/parked.anicel';

      await s.projectDoor.saveProjectToFile(path, asked: SaveAsked.byAPerson);

      expect(drewWhileItRan, isTrue, reason: '⛔premise: drawn mid-save');
      expect(
        readAnicelZipLayoutFile(path).entryNamed(anicelCelEntryName(parked)),
        isNotNull,
        reason: 'the save took the cel; its park is what it reads',
      );
      expect(
        store.dirtyCelKeysSinceSave,
        contains(parked),
        reason: 'what was drawn while it ran is the next save\'s',
      );
      await ScratchFile.lettingGo;
      expect(
        File(park.filePath).existsSync(),
        isFalse,
        reason: 'the save read it, and no cel keeps it: it goes',
      );
      expect(store.coldBakedBytes, 0);
    });
  }

  test('a store that lets go of every cel while a save reads a park counts '
      'nothing twice when the save lets go of it', () {
    final store = BrushFrameStore();
    const canvasSize = CanvasSize(
      width: defaultCelTileSize,
      height: defaultCelTileSize,
    );
    parkCold(store, {_key('first'): _ink(canvasSize, 3)});
    final letGo = store.holdParksForSave(
      store.bakedSnapshotForSave().cold.values,
    );
    // A whole store swapped in under the save — the next project's cels.
    parkCold(store, {_key('next'): _ink(canvasSize, 7)});
    final nextBytes = store.coldBakedBytes;

    letGo();

    expect(store.coldBakedBytes, nextBytes);
  });
}

BrushFrameKey _key(String frame) => BrushFrameKey(
  projectId: const ProjectId('p'),
  trackId: const TrackId('t'),
  cutId: const CutId('c'),
  layerId: const LayerId('l'),
  frameId: FrameId(frame),
);

Directory _scratch() {
  final folder = Directory.systemTemp.createTempSync('park-a-save-reads');
  deleteAfterSessionEnds(folder);
  return folder;
}

/// A new cut with a drawing on its current frame — the cel's key.
BrushFrameKey _celInANewCut(EditorSessionManager s) {
  s.cutVerbs.createCut();
  s.createDrawingAtCurrentFrame();
  final selection = s.editingCanvas.activeBrushEditorSelection!;
  return s.brushFrameKeyForCut(
    s.requireActiveCut,
    selection.layerId,
    selection.frameId,
  );
}

/// A cel of one tile of two colours — of one it would hold no block.
BitmapSurface _ink(CanvasSize canvasSize, int seed) {
  final pixels = Uint8List(BitmapTile.bytesFor(defaultCelTileSize))
    ..fillRange(0, BitmapTile.bytesFor(defaultCelTileSize), seed)
    ..[1] = seed + 1;
  return BitmapSurface(
    canvasSize: canvasSize,
    tileSize: defaultCelTileSize,
    tiles: {
      TileCoord(x: 0, y: 0): BitmapTile(
        size: defaultCelTileSize,
        pixels: pixels,
      ),
    },
  );
}
