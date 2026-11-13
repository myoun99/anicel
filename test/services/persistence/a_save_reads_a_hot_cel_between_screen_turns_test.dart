import 'dart:async';
import 'dart:io';

import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/core/on_a_worker.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart' show readTilesInPlace;
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/native/engine_tile_ledger.dart';
import 'package:anicel/src/services/persistence/anicel_incremental_writer.dart'
    show parseAnicelZipLayoutFile;
import 'package:anicel/src/services/persistence/anicel_project_archive.dart'
    show anicelCelEntryName;
import 'package:anicel/src/services/persistence/brush_drawing_binary_codec.dart'
    show AnicelCelBlob, encodeCelEntryFromSurface;
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/session/project_file_door.dart' show SaveAsked;
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/draw_on_current_frame.dart';
import '../../helpers/project_scratch_folder.dart';

/// Card `a-save-serialises-each-hot-cel-on-the-ui-isolate` (the CPU census,
/// 관제 2026-11-13): a cel in RAM is serialised for the save on a worker,
/// handed its tiles a batch at a time — ↩️it was serialised on the UI
/// isolate, the whole cel in one stretch (30–43 ms a whole-canvas cel).
void main() {
  // The session warms playback's rows in the quiet the save leaves it, and
  // a row asks the binding for the quiet it takes its turn in.
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(() {
    debugWorkersRunHere = true;
    EngineTileLedger.debugBeforeRead = null;
  });

  test('🚨the screen has its turns between the batches of one cel a save '
      'reads — and what lands is the cel\'s stream as it is serialised '
      'here', () async {
    // The road production takes: a worker of its own.
    debugWorkersRunHere = false;
    final folder = Directory.systemTemp.createTempSync('cel-off-the-ui');
    deleteAfterSessionEnds(folder);
    final path = '${folder.path}/one.anicel';
    final s = EditorSessionManager(initialProject: createDefaultProject());
    addTearDown(s.dispose);
    s.cutVerbs.createCut();
    s.createDrawingAtCurrentFrame();
    final selection = s.editingCanvas.activeBrushEditorSelection!;
    final key = s.brushFrameKeyForCut(
      s.requireActiveCut,
      selection.layerId,
      selection.frameId,
    );
    final canvas = s.requireActiveCut.canvasSize;
    expect(
      (canvas.width >= 9 * defaultCelTileSize,
          canvas.height >= 8 * defaultCelTileSize),
      (true, true),
      reason: '⛔premise: room for 9 × 8 tiles',
    );
    // A dab at the middle of each of 9 × 8 tiles: 72, past a batch of 64.
    for (var y = 0; y < 8; y += 1) {
      for (var x = 0; x < 9; x += 1) {
        inkCel(
          s,
          key,
          canvasSize: canvas,
          at: CanvasPoint(
            x: x * defaultCelTileSize + defaultCelTileSize / 2,
            y: y * defaultCelTileSize + defaultCelTileSize / 2,
          ),
          size: 4,
        );
      }
    }
    final here = s.renderCaches.brushFrameStore.hotBakedSurfaceOrNull(key)!;
    expect(here.tiles, hasLength(72), reason: '⛔premise: one tile a dab');
    final expected = encodeCelEntryFromSurface(key, here);

    final events = <String>[];
    EngineTileLedger.debugBeforeRead = (tiles) =>
        events.add('read ${tiles.length}');
    // Something else that wants the UI isolate — a frame, a spinner — as a
    // zero timer that asks again each time it is answered.
    var asking = true;
    void ask() {
      if (!asking) {
        return;
      }
      events.add('turn');
      Timer.run(ask);
    }

    Timer.run(ask);
    await s.projectDoor.saveProjectToFile(path, asked: SaveAsked.byAPerson);
    asking = false;

    final reads = [
      for (final (index, event) in events.indexed)
        if (event.startsWith('read')) index,
    ];
    expect(
      [for (final at in reads) events[at]],
      ['read 64', 'read 8'],
      reason: '⛔premise: the one cel, read a batch at a time',
    );
    expect(
      events.sublist(reads.first, reads.last),
      contains('turn'),
      reason: 'serialised here, the cel holds the screen till it is all '
          'read and written',
    );

    final entry = parseAnicelZipLayoutFile(path).entryNamed(
      anicelCelEntryName(key),
    )!;
    final file = File(path).openSync();
    addTearDown(file.closeSync);
    file.setPositionSync(entry.dataOffset);
    final landed = AnicelCelBlob(file.readSync(entry.length)).decoded(
      (written) => encodeCelEntryFromSurface(
        key,
        written.toSurface(),
        bytesOf: readTilesInPlace,
      ),
    );
    expect(landed, expected);
  });
}
