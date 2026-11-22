import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
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
import 'package:anicel/src/services/import/raster_cel_import.dart';

import '../helpers/a_room_that_refuses.dart';
import '../helpers/cels_kept_in_a_file.dart';
import '../helpers/shells_with_no_bytes.dart';

/// 🚨Card `cel-originals-are-held-twice-in-ram-and-on-the-gpu`, Q6 (유저
/// 2026-11-21 04:28, 「disk 임시 방에 미리 내려 둔다 — 형식 불문」:
/// 「아무튼 들여올때 바로가 낫지않나싶은데. 들여오기 길어지는건 거기서
/// 개선해서 줄인다던가. 디스크없으면 vram, 없으면 ram인건 이해했어. …
/// 아무튼 사본이나 ram에있는걸 최대한 없애고싶어서」): a cel an import
/// lands (`landImportedCel`) is parked in the run's room behind, several
/// at once, and holds no bytes here from then — where it was the RAM's
/// alone till a save. ↩️Parked only past the hot budget, and one after
/// another: 🔬a line-art .tvpp of 220 cels held 1,543 MiB here once opened.
///
/// What a parked cel is from there — made hot, it is parked still — is
/// a_cel_made_hot_keeps_its_park_test.dart's.
void main() {
  const canvasSize = CanvasSize(
    width: defaultCelTileSize,
    height: defaultCelTileSize,
  );
  final origin = TileCoord(x: 0, y: 0);

  BrushFrameKey key(String frame) => BrushFrameKey(
    projectId: const ProjectId('p'),
    trackId: const TrackId('t'),
    cutId: const CutId('c'),
    layerId: const LayerId('l'),
    frameId: FrameId(frame),
  );

  /// A cel of one tile, drawn on: not of one colour, so its bytes weigh.
  BitmapSurface ink(int seed) {
    final pixels = Uint8List(defaultCelTileSize * defaultCelTileSize * 4);
    for (var i = 0; i < pixels.length; i += 4) {
      pixels[i] = (seed * 20 + i ~/ 4) % 251;
      pixels[i + 3] = 255;
    }
    return BitmapSurface(
      canvasSize: canvasSize,
      tileSize: defaultCelTileSize,
      tiles: {origin: BitmapTile(size: defaultCelTileSize, pixels: pixels)},
    );
  }

  Uint8List pixelsOf(int seed) => ink(seed).tiles[origin]!.pixels;

  late ShellsWithNoBytes engine;
  late BrushFrameStore store;
  late int atOnce;

  setUp(() {
    // An engine that holds no tile of a cel no screen has shown.
    engine = ShellsWithNoBytes()..holds = false;
    store = BrushFrameStore(shells: engine);
    atOnce = BrushFrameStore.parksAtOnce;
    addTearDown(() => BrushFrameStore.parksAtOnce = atOnce);
  });

  void land(String frame, int seed) =>
      landImportedCel(store, key(frame), ink(seed));

  test('🚨a cel an import lands is parked behind and holds no bytes here: '
      'cold, its picture read back as it came', () async {
    land('f', 4);
    land('g', 5);
    expect(store.hotBakedBytes, greaterThan(0), reason: '⛔premise: hot');

    await store.drainTiering();

    for (final frame in ['f', 'g']) {
      expect(store.isCelCold(key(frame)), isTrue, reason: frame);
      expect(store.hotBakedSurfaceOrNull(key(frame)), isNull, reason: frame);
    }
    expect(store.hotBakedBytes, 0);
    expect(store.coldBakedBytes, greaterThan(0));
    expect(
      engine.laid,
      isEmpty,
      reason: 'to the room, and nothing laid on the engine for it',
    );
    expect(
      store
          .bakedSurfaceOrNull(key('f'), read: CelRead.look)!
          .tiles[origin]!
          .pixels,
      pixelsOf(4),
    );
    expect(
      store
          .bakedSurfaceOrNull(key('g'), read: CelRead.look)!
          .tiles[origin]!
          .pixels,
      pixelsOf(5),
    );
  });

  test('🚨under no budget\'s asking: the budget is not reached', () async {
    store.hotCelByteBudget = 1 << 40;

    land('f', 4);
    land('g', 5);
    await store.drainTiering();

    expect(store.hotBakedBytes, 0);
  });

  test('the cel is unsaved still: the save has it to write, from its park',
      () async {
    land('f', 4);
    await store.drainTiering();

    final snapshot = store.bakedSnapshotForSave();

    expect(store.dirtyCelKeysSinceSave, contains(key('f')));
    expect(snapshot.cold.containsKey(key('f')), isTrue);
    expect(snapshot.hot.containsKey(key('f')), isFalse);
  });

  test('🚨what it is shown from goes with its bytes: nothing here holds '
      'them', () async {
    land('f', 4);
    expect(
      store.validPreviewSurfaceOrNull(key('f')),
      isNotNull,
      reason: '⛔premise: a landing seeds what the cel is shown from',
    );

    await store.drainTiering();

    expect(store.validPreviewSurfaceOrNull(key('f')), isNull);
  });

  test('🚨a cel a canvas stands on is parked as any other, and hot '
      'still: its bytes here till the rest lays its tiles on the engine',
      () async {
    store.setCelsStoodOn(() => [key('f')]);
    land('f', 4);
    final landed = store.hotBakedSurfaceOrNull(key('f'));
    land('g', 5);

    await store.drainTiering();

    expect(store.hotBakedSurfaceOrNull(key('f')), same(landed));
    expect(store.isCelParked(key('f')), isTrue);
    expect(store.isCelCold(key('g')), isTrue);
    expect(store.hotBakedSurfaceOrNull(key('g')), isNull);
    expect(engine.laid, isEmpty, reason: 'the rest\'s to lay');

    store.letGoOfBytesTheEngineHolds();

    expect(engine.laid.single.surface, same(landed));
    expect(store.hotBakedBytes, 0);
    expect(
      store.hotBakedSurfaceOrNull(key('f'))!.tiles[origin]!.pixels,
      pixelsOf(4),
    );
  });

  test('one a canvas came to stand on while it was parked keeps its bytes '
      '— and its park — till the rest its park asks for', () async {
    var stands = <BrushFrameKey>[];
    store.setCelsStoodOn(() => stands);
    land('f', 4);
    final landed = store.hotBakedSurfaceOrNull(key('f'));
    expect(store.isBeingParked(key('f')), isTrue, reason: '⛔premise');
    expect(engine.restsAsked, 0, reason: '⛔premise: kept by nothing yet');
    stands = [key('f')];

    await store.drainTiering();

    expect(store.hotBakedSurfaceOrNull(key('f')), same(landed));
    expect(store.isCelParked(key('f')), isTrue);
    expect(engine.restsAsked, 1);

    store.letGoOfBytesTheEngineHolds();

    expect(engine.laid.single.surface, same(landed));
    expect(store.hotBakedBytes, 0);
    expect(store.isCelParked(key('f')), isTrue);
  });

  test('🚨one the engine holds every tile of is left the looks\' shell: '
      'no bytes here, and nothing to put on the engine again', () async {
    engine.holds = true;
    land('f', 4);

    await store.drainTiering();

    expect(store.hotBakedSurfaceOrNull(key('f')), isNull);
    expect(store.isCelCold(key('f')), isTrue);
    expect(store.shells, [same(engine.made.single)]);
    expect(store.hotBakedBytes, 0);
    // And a use takes it, thawing nothing.
    expect(store.bakedSurfaceOrNull(key('f')), same(engine.made.single));
  });

  test('🚨several at once, and no more than may be', () async {
    BrushFrameStore.parksAtOnce = 2;
    for (final (seed, frame) in ['f', 'g', 'h', 'i'].indexed) {
      land(frame, seed + 1);
    }

    final underWay = [
      for (final frame in ['f', 'g', 'h', 'i'])
        if (store.isBeingParked(key(frame))) frame,
    ];

    expect(underWay, ['f', 'g']);
    await store.drainTiering();
    for (final frame in ['f', 'g', 'h', 'i']) {
      expect(store.isCelCold(key(frame)), isTrue, reason: frame);
    }
  });

  test('a picture stored over a cel while it was parked wins: what is '
      'parked is the picture it holds', () async {
    land('f', 4);
    expect(store.isBeingParked(key('f')), isTrue, reason: '⛔premise');
    store.storeBakedSurface(key('f'), ink(9));

    store.parkBehind();
    await store.drainTiering();

    expect(
      store
          .bakedSurfaceOrNull(key('f'), read: CelRead.look)!
          .tiles[origin]!
          .pixels,
      pixelsOf(9),
    );
  });

  test('🚨a cel a save took while it was parked is the file\'s, and gets '
      'no park beside', () async {
    land('f', 4);
    expect(store.isBeingParked(key('f')), isTrue, reason: '⛔premise');
    final snapshot = store.bakedSnapshotForSave();
    // As a save wrote it: a stretch of a file, named as an open names one.
    final saved = keepInAFile(BrushFrameStore(shells: engine), {
      key('f'): ink(4),
    })[key('f')]!;
    store.adoptSavedFile({
      key('f'): saved,
    }, dirtyTicksAtSnapshot: snapshot.dirtyTicks);

    await store.drainTiering();

    expect(store.isCelFileBacked(key('f')), isTrue);
    expect(store.isCelParked(key('f')), isFalse);
    expect(store.coldBakedBytes, 0);
  });

  test('🚨a room that refuses leaves every cel hot, its bytes here, and '
      'asks no more', () async {
    refuseTheRoom();
    BrushFrameStore.parksAtOnce = 1;
    land('f', 4);
    land('g', 5);
    final f = store.hotBakedSurfaceOrNull(key('f'));
    final g = store.hotBakedSurfaceOrNull(key('g'));

    await store.drainTiering();

    expect(store.hotBakedSurfaceOrNull(key('f')), same(f));
    expect(store.hotBakedSurfaceOrNull(key('g')), same(g));
    expect(store.isCelParked(key('f')), isFalse);
    expect(store.isCelParked(key('g')), isFalse);
    expect(store.isBeingParked(key('g')), isFalse);

    store.parkBehind();

    expect(store.isBeingParked(key('f')), isFalse, reason: 'a later ask');
  });

  test('🧱every import lands its cels by the one door: none bakes a cel '
      'past it', () {
    final doors = [
      'lib/src/ui/session/tvpp_import_door.dart',
      'lib/src/ui/session/clip_import_door.dart',
      'lib/src/ui/session/cut_folder_import_door.dart',
      'lib/src/ui/session/project_import_doors.dart',
    ];

    for (final door in doors) {
      final source = File(door).readAsStringSync();
      expect(source, contains('landImportedCel('), reason: '⛔premise: $door');
      expect(
        RegExp(r'\bbakeCelSurface\(').hasMatch(source),
        isFalse,
        reason: '$door bakes a cel the store is not asked to park',
      );
    }
  });
}
