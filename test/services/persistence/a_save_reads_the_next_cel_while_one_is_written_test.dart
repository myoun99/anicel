import 'dart:io';

import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/brush_frame_key.dart';
import 'package:anicel/src/models/canvas_point.dart';
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
/// than two under way. The save that writes the whole file and the one that
/// appends what changed take their cels the same way.
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
    final s = EditorSessionManager(initialProject: createDefaultProject());
    addTearDown(s.dispose);
    final cels = _celsOfTwoBatchesIn(s, ['a', 'b', 'c']);

    final events = await _whatTheSaveDoes(
      s,
      cels,
      '${_scratch('cels-overlap').path}/three.anicel',
    );

    _expectTwoUnderWay(events);
  });

  test('🚨and so does a save that appends what changed', () async {
    final s = EditorSessionManager(initialProject: createDefaultProject());
    addTearDown(s.dispose);
    final cels = _celsOfTwoBatchesIn(s, ['a', 'b', 'c']);
    s.cutVerbs.createCut();
    s.createDrawingAtCurrentFrame();
    final clean = _keyOfTheCurrentCel(s);
    inkCel(
      s,
      clean,
      canvasSize: s.requireActiveCut.canvasSize,
      at: CanvasPoint(x: 10, y: 10),
      size: 4,
    );
    final path = '${_scratch('cels-overlap-append').path}/four.anicel';
    await s.projectDoor.saveProjectToFile(path, asked: SaveAsked.byAPerson);
    final store = s.renderCaches.brushFrameStore;
    int cleanAt() => store.bakedSnapshotForSave().fileRefs[clean]!.dataOffset;
    final before = cleanAt();
    for (final key in cels.keys) {
      _inkTwoBatches(s, key);
    }

    final events = await _whatTheSaveDoes(s, cels, path);

    expect(
      cleanAt(),
      before,
      reason: '⛔premise: an append — the clean cel never moved',
    );
    _expectTwoUnderWay(events);
  });
}

Directory _scratch(String name) {
  final folder = Directory.systemTemp.createTempSync(name);
  deleteAfterSessionEnds(folder);
  return folder;
}

BrushFrameKey _keyOfTheCurrentCel(EditorSessionManager s) {
  final selection = s.editingCanvas.activeBrushEditorSelection!;
  return s.brushFrameKeyForCut(
    s.requireActiveCut,
    selection.layerId,
    selection.frameId,
  );
}

/// A cut for each of [names], a cel of 72 tiles in each — two batches of
/// the engine's reads — by its name.
Map<BrushFrameKey, String> _celsOfTwoBatchesIn(
  EditorSessionManager s,
  List<String> names,
) {
  final cels = <BrushFrameKey, String>{};
  for (final name in names) {
    s.cutVerbs.createCut();
    s.createDrawingAtCurrentFrame();
    final key = _keyOfTheCurrentCel(s);
    _inkTwoBatches(s, key);
    cels[key] = name;
  }
  return cels;
}

void _inkTwoBatches(EditorSessionManager s, BrushFrameKey key) => inkEachTileOf(
  s,
  key,
  canvasSize: s.requireActiveCut.canvasSize,
  columns: 9,
  rows: 8,
);

/// What a save to [path] does: each read of the engine's, by whose cel it
/// is, and `done` once it has taken a cel.
Future<List<String>> _whatTheSaveDoes(
  EditorSessionManager s,
  Map<BrushFrameKey, String> cels,
  String path,
) async {
  final whose = Map<BitmapTile, String>.identity();
  for (final MapEntry(:key, value: name) in cels.entries) {
    final surface = s.renderCaches.brushFrameStore.hotBakedSurfaceOrNull(key)!;
    expect(surface.tiles, hasLength(72), reason: '⛔premise: two batches');
    for (final tile in surface.tiles.values) {
      whose[tile] = name;
    }
  }
  final events = <String>[];
  EngineTileLedger.debugBeforeRead = (tiles) =>
      events.add('read ${whose[tiles.first]}');
  AnicelFileService.debugAfterScreenTurn = () => events.add('done');
  await s.projectDoor.saveProjectToFile(path, asked: SaveAsked.byAPerson);
  EngineTileLedger.debugBeforeRead = null;
  AnicelFileService.debugAfterScreenTurn = null;
  return events;
}

void _expectTwoUnderWay(List<String> events) {
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
}
