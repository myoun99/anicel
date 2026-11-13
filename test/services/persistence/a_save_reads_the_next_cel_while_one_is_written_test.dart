import 'dart:io';

import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/brush_frame_key.dart';
import 'package:anicel/src/native/engine_tile_ledger.dart';
import 'package:anicel/src/services/persistence/anicel_file_service.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/session/project_file_door.dart' show SaveAsked;
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/draw_on_current_frame.dart';
import '../../helpers/project_scratch_folder.dart';

/// Card `a-save-serialises-each-hot-cel-on-the-ui-isolate` (관제 2026-11-13
/// 21:10, the cost taken down before anyone is asked to pay it): a save
/// reads the next cel in RAM while the one before it is written on its
/// worker — ↩️one at a time, each waited for the other — and never has more
/// than two under way.
///
/// On the suite's road, workers run here ([debugWorkersRunHere]): each
/// cel's job stops at its first ask, so what the save begins before it
/// awaits shows in the order of the reads, the same in every run.
void main() {
  // The session warms playback's rows in the quiet the save leaves it, and
  // a row asks the binding for the quiet it takes its turn in.
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(() {
    EngineTileLedger.debugBeforeRead = null;
    AnicelFileService.debugAfterScreenTurn = null;
  });

  test('🚨the second cel is read before the first is done — the third only '
      'once it is', () async {
    final folder = Directory.systemTemp.createTempSync('cels-overlap');
    deleteAfterSessionEnds(folder);
    final s = EditorSessionManager(initialProject: createDefaultProject());
    addTearDown(s.dispose);
    final store = s.renderCaches.brushFrameStore;
    final cels = <BrushFrameKey, String>{};
    for (final name in ['a', 'b', 'c']) {
      s.cutVerbs.createCut();
      s.createDrawingAtCurrentFrame();
      final selection = s.editingCanvas.activeBrushEditorSelection!;
      final key = s.brushFrameKeyForCut(
        s.requireActiveCut,
        selection.layerId,
        selection.frameId,
      );
      inkEachTileOf(
        s,
        key,
        canvasSize: s.requireActiveCut.canvasSize,
        columns: 9,
        rows: 8,
      );
      cels[key] = name;
    }
    final whose = Map<BitmapTile, String>.identity();
    for (final MapEntry(:key, value: name) in cels.entries) {
      final surface = store.hotBakedSurfaceOrNull(key)!;
      expect(surface.tiles, hasLength(72), reason: '⛔premise: two batches');
      for (final tile in surface.tiles.values) {
        whose[tile] = name;
      }
    }

    final events = <String>[];
    EngineTileLedger.debugBeforeRead = (tiles) =>
        events.add('read ${whose[tiles.first]}');
    AnicelFileService.debugAfterScreenTurn = () => events.add('done');
    await s.projectDoor.saveProjectToFile(
      '${folder.path}/three.anicel',
      asked: SaveAsked.byAPerson,
    );

    final reads = [for (final event in events) if (event != 'done') event];
    expect(
      reads.toSet(),
      {'read a', 'read b', 'read c'},
      reason: '⛔premise: the three cels, read for the save',
    );
    final beforeTheFirstIsDone = events
        .sublist(0, events.indexOf('done'))
        .toSet();
    expect(
      beforeTheFirstIsDone,
      hasLength(2),
      reason: 'one at a time, the second cel is read once the first is done '
          '— and two under way at most, not the third',
    );
  });
}
