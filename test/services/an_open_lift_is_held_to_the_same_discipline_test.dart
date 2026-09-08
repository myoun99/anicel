import 'dart:io';
import 'dart:typed_data';

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
import 'package:anicel/src/services/persistence/session_scratch.dart';
import 'package:anicel/src/services/undo_surface_snapshot.dart';
import 'package:flutter_test/flutter_test.dart';

/// 🚨★★★**THE SAME BYTES WERE DISCIPLINED ON ONE SIDE OF A CONFIRM AND NOT
/// THE OTHER.** A confirmed transform's pre-lift picture is budgeted and
/// parkable the moment it becomes a history entry; while the box was still
/// open the identical pixels sat in a plain Map in a widget's State, with
/// no budget, no cap and no spill. A user who had not confirmed was held
/// to LESS discipline than one who had. 유저 확정 2026-09-08
/// (`undo-41-hole-scope` = ①, Krita 식).
///
/// 🔬Krita clears the source device when the box opens exactly as we do,
/// and the lifted content is a `KisPaintDevice` — a document device — so
/// the tile swapper spills it under pressure while the transform tool
/// contains no memory-pressure code at all. This is that, in our shapes.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const size = 8;
  const canvas = CanvasSize(width: 64, height: 64);
  const key = BrushFrameKey(
    projectId: ProjectId('p'),
    trackId: TrackId('t'),
    cutId: CutId('c'),
    layerId: LayerId('l'),
    frameId: FrameId('f'),
  );

  BitmapTile tileOf(int x, int fill) {
    final coord = TileCoord(x: x, y: 0);
    return BitmapTile(
      coord: coord,
      size: size,
      pixels: Uint8List(BitmapTile.bytesFor(size))
        ..fillRange(0, BitmapTile.bytesFor(size), fill),
    );
  }

  BitmapSurface surfaceOf(Iterable<BitmapTile> tiles) => BitmapSurface(
    canvasSize: canvas,
    tileSize: size,
    tiles: {for (final tile in tiles) tile.coord: tile},
  );

  /// What a lift leaves behind: the picture as it was, measured against
  /// the surface the erase produced.
  ({UndoSurfaceSnapshot held, BitmapSurface preLift}) lift() {
    final untouched = tileOf(0, 11);
    final lifted = tileOf(1, 22);
    final preLift = surfaceOf([untouched, lifted]);
    // The erase rebuilt the lifted tile and left the other one alone.
    final afterErase = surfaceOf([untouched, tileOf(1, 0)]);
    return (
      held: UndoSurfaceSnapshot(
        key: key,
        snapshot: preLift,
        sharedWith: afterErase,
      ),
      preLift: preLift,
    );
  }

  test('an open lift reports its bytes, and a memory warning moves them '
      'out of RAM', () async {
    final store = BrushFrameStore();
    final session = lift();

    expect(
      store.liftedPixelBytes,
      0,
      reason: 'nothing lifted yet',
    );

    store.holdLiftedPixels(1, session.held);
    expect(
      store.liftedPixelBytes,
      BitmapTile.bytesFor(size),
      reason: 'only the tile the erase rebuilt — the rest is the cel\'s own',
    );

    store.respondToMemoryPressure();
    await session.held.park();

    // ⛔This is the whole round: before it, the store had no idea these
    // bytes existed and a warning left every one of them in RAM.
    expect(store.liftedPixelBytes, 0);
    expect(session.held.isParked, isTrue);
  });

  test('and the picture still comes back byte for byte afterwards', () async {
    final store = BrushFrameStore();
    final session = lift();
    store.holdLiftedPixels(1, session.held);

    store.respondToMemoryPressure();
    await session.held.park();

    final back = session.held.surface;
    expect(back, isNotNull, reason: 'a revert has to be able to read this');
    expect(back!.tiles.length, 2);
    for (final coord in session.preLift.tiles.keys) {
      expect(
        back.tileAt(coord)!.pixels,
        session.preLift.tileAt(coord)!.pixels,
        reason: 'tile $coord',
      );
    }
  });

  test('releasing takes it back from the store — a lift that ended must '
      'not go on being parked for nobody', () {
    final store = BrushFrameStore();
    store.holdLiftedPixels(1, lift().held);
    expect(store.liftedPixelBytes, greaterThan(0));

    store.releaseLiftedPixels(1);

    expect(store.liftedPixelBytes, 0);
  });

  test('🚨two warnings in a row write ONE file — a park in flight is joined, '
      'not started again', () async {
    final session = lift();
    final before = _volatilePaths();

    final both = await Future.wait([
      session.held.park(),
      session.held.park(),
    ]);

    expect(both, [true, true]);
    expect(session.held.isParked, isTrue);
    // ⛔THE FILE COUNT IS THE ASSERTION, not the parked flag. Without the
    // in-flight guard both calls encode the same tiles and each writes its
    // own file, and only the second path is remembered — the flag is true
    // and the surface reads back either way, while the first file is bytes
    // on the user's disk nothing will ever read or remove.
    expect(_volatilePaths().difference(before), hasLength(1));
  });
}

/// What is in the run's 휘발성 room right now.
Set<String> _volatilePaths() {
  final room = Directory(SessionScratch.volatileFolder());
  if (!room.existsSync()) {
    return const {};
  }
  return room.listSync().whereType<File>().map((file) => file.path).toSet();
}
