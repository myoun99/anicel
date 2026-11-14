import 'dart:async';
import 'dart:typed_data';

import 'package:anicel/src/core/on_a_worker.dart';
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
import 'package:anicel/src/native/engine_tile_ledger.dart';
import 'package:anicel/src/services/brush_frame_store.dart';
import 'package:anicel/src/services/undo_surface_snapshot.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/tiles_on_the_engine.dart';

/// Card `the-cooling-serialises-each-hot-cel-on-the-ui-isolate` (the CPU
/// census, 관제 2026-11-13): a cel that cools, and an undo snapshot that
/// parks, is serialised on a worker handed its tiles a batch at a time,
/// the screen's turns between — the save's road. ↩️Each was serialised on
/// the UI isolate, the whole cel in one stretch, and only compressed on a
/// worker.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const size = defaultCelTileSize;
  BrushFrameKey key(String frame) => BrushFrameKey(
    projectId: const ProjectId('p'),
    trackId: const TrackId('t'),
    cutId: const CutId('c'),
    layerId: const LayerId('l'),
    frameId: FrameId(frame),
  );

  BitmapTile filled(int value) {
    final bytes = BitmapTile.bytesFor(size);
    return tileOnEngine(
      BitmapTile(
        size: size,
        pixels: Uint8List(bytes)..fillRange(0, bytes, value),
      ),
    );
  }

  /// A cel of [count] tiles on the engine, nine to a row, each filled by
  /// its place.
  BitmapSurface celOf(int count) => BitmapSurface(
    canvasSize: const CanvasSize(width: 9 * size, height: 8 * size),
    tileSize: size,
    tiles: {
      for (var at = 0; at < count; at += 1)
        TileCoord(x: at % 9, y: at ~/ 9): filled(at + 1),
    },
  );

  /// Two batches of the engine's reads.
  BitmapSurface twoBatches() => celOf(72);

  // Something else that wants the UI isolate — a frame, a spinner — as a
  // zero timer that asks again each time it is answered.
  late List<String> events;
  var asking = false;
  void ask() {
    if (!asking) {
      return;
    }
    events.add('turn');
    Timer.run(ask);
  }

  void stopWatching() {
    asking = false;
    EngineTileLedger.debugBeforeRead = null;
  }

  setUp(() {
    // The road production takes: a worker of its own.
    debugWorkersRunHere = false;
    events = [];
    EngineTileLedger.debugBeforeRead = (tiles) =>
        events.add('read ${tiles.length}');
    asking = true;
    Timer.run(ask);
  });
  tearDown(() {
    stopWatching();
    debugWorkersRunHere = true;
  });

  void expectTurnsBetweenTheBatches() {
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
  }

  void expectThePicture(BitmapSurface? back, BitmapSurface cel) {
    expect(back, isNotNull, reason: 'it comes back');
    for (final MapEntry(key: at, value: tile) in cel.tiles.entries) {
      expect(back!.tiles[at]!.pixels, tile.pixels, reason: 'the tile at $at');
    }
  }

  test('🚨the screen has its turns between the batches of a cel that '
      'cools — and it comes back as it went', () async {
    final store = BrushFrameStore()..hotCelByteBudget = 0;
    final cel = twoBatches();
    store.storeBakedSurface(key('cools'), cel);
    store.storeBakedSurface(key('stays'), celOf(1));
    await store.drainCooling();
    stopWatching();

    expect(store.isCelCold(key('cools')), isTrue, reason: '⛔premise');
    expectTurnsBetweenTheBatches();
    expectThePicture(store.bakedSurfaceOrNull(key('cools')), cel);
  });

  test('🚨and between the batches of an undo snapshot that parks', () async {
    final cel = twoBatches();
    final snapshot = UndoSurfaceSnapshot(
      key: key('parks'),
      snapshot: cel,
      sharedWith: null,
    );
    addTearDown(snapshot.drop);
    expect(await snapshot.park(), isTrue, reason: '⛔premise: it parked');
    stopWatching();

    expect(snapshot.isParked, isTrue, reason: '⛔premise');
    expectTurnsBetweenTheBatches();
    expectThePicture(snapshot.surfaceOver(() => null), cel);
  });
}
