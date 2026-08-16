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
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/services/brush_frame_store.dart';
import 'package:anicel/src/services/persistence/brush_drawing_binary_codec.dart';
import 'package:anicel/src/services/persistence/anicel_file_service.dart';

/// R20-A1 two-tier baked truth: cold cels are encoded+deflated blobs
/// (the same bytes the archive stores), materialize byte-exactly on
/// first access, and over-budget hot cels cool back down in LRU order.
/// Representation must never change existence or bytes.
void main() {
  const canvasSize = CanvasSize(width: 16, height: 16);

  BrushFrameKey key({String layer = 'l', String frame = 'f'}) => BrushFrameKey(
    projectId: const ProjectId('p'),
    trackId: const TrackId('t'),
    cutId: const CutId('c'),
    layerId: LayerId(layer),
    frameId: FrameId(frame),
  );

  BitmapSurface inkSurface({int seed = 1}) {
    final pixels = Uint8List(8 * 8 * 4);
    for (var i = 0; i < pixels.length; i += 1) {
      pixels[i] = (i * seed * 31 + seed) & 0xFF;
    }
    return BitmapSurface(
      canvasSize: canvasSize,
      tileSize: 8,
      tiles: {
        TileCoord(x: 0, y: 0): BitmapTile(
          coord: TileCoord(x: 0, y: 0),
          size: 8,
          pixels: pixels,
        ),
      },
    );
  }

  AnicelCelBlob blobOf(BrushFrameKey k, BitmapSurface surface) =>
      AnicelCelBlob.encode(AnicelCelEntry.fromSurface(k, surface));

  test('a restored (cold) cel counts as content, materializes byte-exactly '
      'on first access and promotes to hot', () {
    final store = BrushFrameStore();
    final k = key();
    final source = inkSurface();
    store.restoreBaked({k: blobOf(k, source)});

    expect(
      store.celHasRenderableContent(k),
      isTrue,
      reason: 'representation is not existence',
    );
    expect(store.isCelCold(k), isTrue);
    expect(store.hotBakedBytes, 0);

    final materialized = store.bakedSurfaceOrNull(k)!;
    expect(store.isCelCold(k), isFalse);
    expect(
      materialized.tiles[TileCoord(x: 0, y: 0)]!.pixels,
      source.tiles[TileCoord(x: 0, y: 0)]!.pixels,
      reason: 'cold → hot round trip is byte-exact',
    );
    expect(
      identical(store.bakedSurfaceOrNull(k), materialized),
      isTrue,
      reason: 'promotion is once — later reads hit the hot tier',
    );
    expect(
      identical(store.displayCacheOrNull(k)?.previewSurface, materialized),
      isTrue,
      reason: 'promotion reseeds the display cache like open used to',
    );
  });

  test('currentSurfaceWithoutReplay materializes a size-matched cold cel '
      'and rejects a mismatched one', () {
    final store = BrushFrameStore();
    final k = key();
    store.restoreBaked({k: blobOf(k, inkSurface())});

    expect(
      store.currentSurfaceWithoutReplay(
        k,
        canvasSize: const CanvasSize(width: 99, height: 99),
      ),
      isNull,
      reason: 'the cold header carries the size — no inflate to reject',
    );
    expect(store.isCelCold(k), isTrue, reason: 'rejection must not promote');

    expect(
      store.currentSurfaceWithoutReplay(k, canvasSize: canvasSize),
      isNotNull,
    );
    expect(store.isCelCold(k), isFalse);
  });

  test('over-budget hot cels COOL in LRU order; the most recent never '
      'cools; cooled bytes survive exactly', () async {
    final store = BrushFrameStore()..hotCelByteBudget = 0;
    final k1 = key(frame: 'f1');
    final k2 = key(frame: 'f2');
    final s1 = inkSurface(seed: 3);
    store.storeBakedSurface(k1, s1);
    store.storeBakedSurface(k2, inkSurface(seed: 5));
    await store.drainCooling();

    expect(store.isCelCold(k1), isTrue, reason: 'LRU victim cools first');
    expect(
      store.isCelCold(k2),
      isFalse,
      reason: 'the most recently used cel NEVER cools',
    );
    expect(
      store.displayCacheOrNull(k1),
      isNull,
      reason: 'the derived alias must drop or nothing frees',
    );
    expect(store.celHasRenderableContent(k1), isTrue);

    final back = store.bakedSurfaceOrNull(k1)!;
    expect(
      back.tiles[TileCoord(x: 0, y: 0)]!.pixels,
      s1.tiles[TileCoord(x: 0, y: 0)]!.pixels,
      reason: 'hot → cold → hot round trip is byte-exact',
    );
  });

  test(
    'a donation onto a cold key replaces it (hot wins, cold dropped)',
    () async {
      final store = BrushFrameStore();
      final k = key();
      store.restoreBaked({k: blobOf(k, inkSurface(seed: 7))});

      final donated = inkSurface(seed: 9);
      store.storeBakedSurface(k, donated);
      expect(store.isCelCold(k), isFalse);
      expect(identical(store.bakedSurfaceOrNull(k), donated), isTrue);
    },
  );

  test('bakedSnapshotForSave passes cold blobs through untouched — the '
      'save path re-encodes nothing for unedited cels', () {
    final store = BrushFrameStore();
    final k = key();
    final blob = blobOf(k, inkSurface());
    store.restoreBaked({k: blob});

    final snapshot = store.bakedSnapshotForSave();
    expect(identical(snapshot.cold[k], blob), isTrue);
    expect(snapshot.hot, isEmpty);
  });

  test('rekeyFrames moves a COLD cel with its key', () {
    final store = BrushFrameStore();
    final from = key(layer: 'a');
    final to = key(layer: 'b');
    store.restoreBaked({from: blobOf(from, inkSurface())});

    store.rekeyFrames([(from, to)]);

    expect(store.celHasRenderableContent(from), isFalse);
    expect(store.isCelCold(to), isTrue);
    expect(store.bakedSurfaceOrNull(to), isNotNull);
  });

  test('a FILE-BACKED cel counts as content, materializes byte-exactly, '
      'keeps its ref through the clean promotion, and re-cools for FREE '
      '(no encode, no cold blob) — R22-C', () async {
    final directory = await Directory.systemTemp.createTemp('qa-fileref');
    addTearDown(() => directory.delete(recursive: true));
    final store = BrushFrameStore();
    final k = key(frame: 'f1');
    final s = inkSurface(seed: 19);
    final blob = blobOf(k, s);
    final path = '${directory.path}/cel.bin';
    File(path).writeAsBytesSync(blob.bytes);
    store.restoreFromFile({
      k: AnicelCelFileRef(
        filePath: path,
        dataOffset: 0,
        length: blob.bytes.length,
        canvasSize: canvasSize,
        tileSize: blob.tileSize,
      ),
    });

    expect(store.celHasRenderableContent(k), isTrue);
    expect(store.isCelFileBacked(k), isTrue);
    expect(store.hotBakedBytes, 0);
    expect(store.dirtyCelKeysSinceSave, isEmpty);
    expect(
      store.currentSurfaceWithoutReplay(
        k,
        canvasSize: const CanvasSize(width: 99, height: 99),
      ),
      isNull,
      reason: 'the ref carries the size — no disk read to reject',
    );

    final surface = store.bakedSurfaceOrNull(k)!;
    expect(
      surface.tiles[TileCoord(x: 0, y: 0)]!.pixels,
      s.tiles[TileCoord(x: 0, y: 0)]!.pixels,
      reason: 'file → hot round trip is byte-exact',
    );
    expect(
      store.isCelFileBacked(k),
      isTrue,
      reason: 'a CLEAN promotion keeps the ref — the file bytes still match',
    );

    // Re-cooling the clean cel drops the hot bytes for free.
    store.hotCelByteBudget = 0;
    final k2 = key(frame: 'f2');
    store.storeBakedSurface(k2, inkSurface(seed: 21));
    await store.drainCooling();
    expect(store.isCelCold(k), isFalse, reason: 'free drop — no cold blob');
    expect(store.isCelFileBacked(k), isTrue);
    expect(store.celHasRenderableContent(k), isTrue);
    expect(
      store.bakedSurfaceOrNull(k)!.tiles[TileCoord(x: 0, y: 0)]!.pixels,
      s.tiles[TileCoord(x: 0, y: 0)]!.pixels,
      reason: 'the dropped cel reads back from the file byte-exactly',
    );
  });

  test('edits mark cels dirty, adoptSavedFile clears and refs them, and '
      'a re-edit kills the stale ref', () {
    final store = BrushFrameStore();
    final k = key();
    store.storeBakedSurface(k, inkSurface());
    expect(store.dirtyCelKeysSinceSave, {k});

    store.adoptSavedFile({
      k: AnicelCelFileRef(
        filePath: 'unused.anicel',
        dataOffset: 0,
        length: 1,
        canvasSize: canvasSize,
        tileSize: 8,
      ),
    });
    expect(store.dirtyCelKeysSinceSave, isEmpty);
    expect(store.isCelFileBacked(k), isTrue);
    expect(
      store.bakedSurfaceOrNull(k),
      isNotNull,
      reason: 'the hot surface stays resident through adoption',
    );

    // Session seeding re-donates the IDENTICAL surface on every cel
    // view — that must stay a clean no-op or every viewed cel would
    // re-save.
    store.storeBakedSurface(k, store.bakedSurfaceOrNull(k)!);
    expect(store.dirtyCelKeysSinceSave, isEmpty);
    expect(store.isCelFileBacked(k), isTrue);

    store.storeBakedSurface(k, inkSurface(seed: 3));
    expect(store.dirtyCelKeysSinceSave, {k});
    expect(
      store.isCelFileBacked(k),
      isFalse,
      reason: 'an edit invalidates the saved bytes',
    );
  });

  test('FULL save adopts file refs and OPEN lands every cel file-backed, '
      'byte-exact on first access', () async {
    final directory = await Directory.systemTemp.createTemp('qa-full-save');
    addTearDown(() => directory.delete(recursive: true));
    final store = BrushFrameStore();
    final k = key();
    final s = inkSurface(seed: 17);
    store.restoreBaked({k: blobOf(k, s)});

    final path = '${directory.path}/full.anicel';
    await const AnicelFileService().save(
      project: createDefaultProject(),
      brushFrameStore: store,
      filePath: path,
    );
    expect(
      store.isCelFileBacked(k),
      isTrue,
      reason: 'the saved .anicel IS the disk tier now',
    );
    expect(store.isCelCold(k), isFalse, reason: 'the RAM blob is redundant');
    expect(store.dirtyCelKeysSinceSave, isEmpty);

    final result = await const AnicelFileService().open(filePath: path);
    expect(result.cels.keys, [k]);
    final store2 = BrushFrameStore()..restoreFromFile(result.cels);
    expect(store2.isCelFileBacked(k), isTrue);
    expect(
      store2.bakedSurfaceOrNull(k)!.tiles[TileCoord(x: 0, y: 0)]!.pixels,
      s.tiles[TileCoord(x: 0, y: 0)]!.pixels,
      reason: 'save → open → materialize is byte-exact',
    );
  });

  test('INCREMENTAL save appends ONLY the dirty cel: the clean cel keeps '
      'its exact data offset and the file grows (garbage retained)', () async {
    final directory = await Directory.systemTemp.createTemp('qa-incr-save');
    addTearDown(() => directory.delete(recursive: true));
    const service = AnicelFileService();
    final store = BrushFrameStore();
    final k1 = key(frame: 'f1');
    final k2 = key(frame: 'f2');
    final s1 = inkSurface(seed: 5);
    store.storeBakedSurface(k1, s1);
    store.storeBakedSurface(k2, inkSurface(seed: 7));

    final path = '${directory.path}/incr.anicel';
    final project = createDefaultProject();
    await service.save(
      project: project,
      brushFrameStore: store,
      filePath: path,
    );
    final firstRefs = store.bakedSnapshotForSave().fileRefs;
    final firstLength = File(path).lengthSync();

    final s2Edited = inkSurface(seed: 9);
    store.storeBakedSurface(k2, s2Edited);
    expect(store.dirtyCelKeysSinceSave, {k2});
    await service.save(
      project: project,
      brushFrameStore: store,
      filePath: path,
    );

    final secondRefs = store.bakedSnapshotForSave().fileRefs;
    expect(
      secondRefs[k1]!.dataOffset,
      firstRefs[k1]!.dataOffset,
      reason: 'an append never moves existing entry data',
    );
    expect(
      secondRefs[k2]!.dataOffset,
      isNot(firstRefs[k2]!.dataOffset),
      reason: 'the dirty cel re-wrote as a NEW shadowing entry',
    );
    expect(
      File(path).lengthSync(),
      greaterThan(firstLength + 500),
      reason:
          'incremental = append (shadowed entry retained as garbage) — a '
          'silent full rewrite would land near the original size',
    );

    final result = await const AnicelFileService().open(filePath: path);
    final store2 = BrushFrameStore()..restoreFromFile(result.cels);
    expect(
      store2.bakedSurfaceOrNull(k1)!.tiles[TileCoord(x: 0, y: 0)]!.pixels,
      s1.tiles[TileCoord(x: 0, y: 0)]!.pixels,
    );
    expect(
      store2.bakedSurfaceOrNull(k2)!.tiles[TileCoord(x: 0, y: 0)]!.pixels,
      s2Edited.tiles[TileCoord(x: 0, y: 0)]!.pixels,
      reason: 'the reader sees the LATEST shadowing entry',
    );
  });

  test('a removed cel vanishes from the file on the next incremental '
      'save', () async {
    final directory = await Directory.systemTemp.createTemp('qa-remove-save');
    addTearDown(() => directory.delete(recursive: true));
    const service = AnicelFileService();
    final store = BrushFrameStore();
    final k1 = key(frame: 'f1');
    final k2 = key(frame: 'f2');
    store.storeBakedSurface(k1, inkSurface(seed: 5));
    store.storeBakedSurface(k2, inkSurface(seed: 7));
    final path = '${directory.path}/remove.anicel';
    final project = createDefaultProject();
    await service.save(
      project: project,
      brushFrameStore: store,
      filePath: path,
    );

    // An empty donation IS the removal signal (undo of a first stroke).
    store.storeBakedSurface(
      k1,
      BitmapSurface(canvasSize: canvasSize, tileSize: 8, tiles: const {}),
    );
    await service.save(
      project: project,
      brushFrameStore: store,
      filePath: path,
    );

    final result = await service.open(filePath: path);
    expect(result.cels.keys, [k2]);
  });

  test('a REKEYED cel re-labels in the file across an incremental save '
      'with its pixels intact', () async {
    final directory = await Directory.systemTemp.createTemp('qa-rekey-save');
    addTearDown(() => directory.delete(recursive: true));
    const service = AnicelFileService();
    final store = BrushFrameStore();
    final from = key(layer: 'a');
    final to = key(layer: 'b');
    final s = inkSurface(seed: 23);
    store.storeBakedSurface(from, s);
    final path = '${directory.path}/rekey.anicel';
    final project = createDefaultProject();
    await service.save(
      project: project,
      brushFrameStore: store,
      filePath: path,
    );

    store.rekeyFrames([(from, to)]);
    expect(store.dirtyCelKeysSinceSave, {from, to});
    await service.save(
      project: project,
      brushFrameStore: store,
      filePath: path,
    );

    final result = await service.open(filePath: path);
    expect(result.cels.keys, [to], reason: 'old label gone, new label in');
    final store2 = BrushFrameStore()..restoreFromFile(result.cels);
    expect(
      store2.bakedSurfaceOrNull(to)!.tiles[TileCoord(x: 0, y: 0)]!.pixels,
      s.tiles[TileCoord(x: 0, y: 0)]!.pixels,
      reason: 'rekey re-splices the header — pixels never re-encode',
    );
  });

  test('garbage past the threshold forces COMPACTION: the file shrinks '
      'and every ref stays valid', () async {
    final directory = await Directory.systemTemp.createTemp('qa-compact');
    addTearDown(() => directory.delete(recursive: true));
    const service = AnicelFileService();
    final store = BrushFrameStore();
    final k = key();

    // Incompressible-ish pixels so the cel dominates project.json and
    // the garbage ratio is deterministic.
    BitmapSurface noisySurface(int seed) {
      final pixels = Uint8List(32 * 32 * 4);
      var state = seed * 2654435761 & 0x7FFFFFFF;
      for (var i = 0; i < pixels.length; i += 1) {
        state = (state * 1103515245 + 12345) & 0x7FFFFFFF;
        pixels[i] = (state >> 16) & 0xFF;
      }
      return BitmapSurface(
        canvasSize: const CanvasSize(width: 32, height: 32),
        tileSize: 32,
        tiles: {
          TileCoord(x: 0, y: 0): BitmapTile(
            coord: TileCoord(x: 0, y: 0),
            size: 32,
            pixels: pixels,
          ),
        },
      );
    }

    final path = '${directory.path}/compact.anicel';
    final project = createDefaultProject();
    final lengths = <int>[];
    var latestSeed = 0;
    for (var i = 0; i < 4; i += 1) {
      latestSeed = 100 + i;
      store.storeBakedSurface(k, noisySurface(latestSeed));
      await service.save(
        project: project,
        brushFrameStore: store,
        filePath: path,
      );
      lengths.add(File(path).lengthSync());
    }

    var shrank = false;
    for (var i = 1; i < lengths.length; i += 1) {
      shrank = shrank || lengths[i] < lengths[i - 1];
    }
    expect(
      shrank,
      isTrue,
      reason:
          'some save must have compacted (shrunk) the file: $lengths — '
          'appends alone only ever grow it',
    );

    final result = await service.open(filePath: path);
    final store2 = BrushFrameStore()..restoreFromFile(result.cels);
    expect(
      store2.bakedSurfaceOrNull(k)!.tiles[TileCoord(x: 0, y: 0)]!.pixels,
      noisySurface(latestSeed).tiles[TileCoord(x: 0, y: 0)]!.pixels,
      reason: 'compaction preserves the latest pixels',
    );
  });

  test('R27 DATA-LOSS PIN: resize is CUT-SCOPED — another cut\'s cels '
      'are never clipped by a differently-sized active cut', () {
    final store = BrushFrameStore();
    final otherCutKey = BrushFrameKey(
      projectId: const ProjectId('p'),
      trackId: const TrackId('t'),
      cutId: const CutId('other-8k-cut'),
      layerId: const LayerId('l'),
      frameId: const FrameId('f'),
    );
    // A cel with content BEYOND a smaller canvas (tile at (1,1) of a
    // 32px canvas — outside a 16px one).
    final pixels = Uint8List(8 * 8 * 4);
    for (var i = 0; i < pixels.length; i += 1) {
      pixels[i] = (i * 31 + 7) & 0xFF;
    }
    final big = BitmapSurface(
      canvasSize: const CanvasSize(width: 32, height: 32),
      tileSize: 8,
      tiles: {
        TileCoord(x: 3, y: 3): BitmapTile(
          coord: TileCoord(x: 3, y: 3),
          size: 8,
          pixels: pixels,
        ),
      },
    );
    store.storeBakedSurface(otherCutKey, big);
    store.adoptSavedFile({
      otherCutKey: AnicelCelFileRef(
        filePath: 'unused.anicel',
        dataOffset: 0,
        length: 1,
        canvasSize: const CanvasSize(width: 32, height: 32),
        tileSize: 8,
      ),
    });

    // The OLD bug: switching to a 16px cut ran a store-GLOBAL resize
    // that clipped this 32px cel's outer tiles. Scoped resize of the
    // ACTIVE (different) cut must leave it byte-identical, clean and
    // still file-backed.
    store.resizeBakedSurfaces(
      const CanvasSize(width: 16, height: 16),
      cutId: const CutId('c'),
    );
    final after = store.bakedSurfaceOrNull(otherCutKey)!;
    expect(after.canvasSize, const CanvasSize(width: 32, height: 32));
    expect(
      after.tiles[TileCoord(x: 3, y: 3)]!.pixels,
      pixels,
      reason: 'the outer tile survives byte-exactly',
    );
    expect(store.dirtyCelKeysSinceSave, isEmpty);
    expect(store.isCelFileBacked(otherCutKey), isTrue);
  });

  test('resizeBakedSurfaces transforms cold cels WITHOUT materializing '
      'them into the hot tier', () {
    final store = BrushFrameStore();
    final k = key();
    final source = inkSurface();
    store.restoreBaked({k: blobOf(k, source)});

    const grown = CanvasSize(width: 32, height: 32);
    store.resizeBakedSurfaces(grown, cutId: const CutId('c'));

    expect(store.isCelCold(k), isTrue, reason: '1500 cels must not blow RAM');
    final resized = store.bakedSurfaceOrNull(k)!;
    expect(resized.canvasSize, grown);
    expect(
      resized.tiles[TileCoord(x: 0, y: 0)]!.pixels,
      source.tiles[TileCoord(x: 0, y: 0)]!.pixels,
      reason: 'top-left anchored resize keeps the tile bytes',
    );
  });

  test('an empty donation kills the cel in EVERY tier — a cold blob or a '
      'file ref must not resurrect the deleted picture through a save',
      () async {
    // The empty arm (an all-undone/all-erased cel) was pinned on the HOT
    // tier only; the cold and file arms carried the resurrection risk: a
    // leftover blob or ref rides the next save, and the reload's
    // first-sight trust cements the deleted picture back into the file.

    // COLD arm.
    final store = BrushFrameStore();
    final k = key(frame: 'cold-victim');
    store.restoreBaked({k: blobOf(k, inkSurface())});
    expect(store.isCelCold(k), isTrue, reason: 'fixture: really cold');
    store.storeBakedSurface(k, BitmapSurface(canvasSize: canvasSize));
    expect(store.celHasRenderableContent(k), isFalse);
    expect(store.bakedSurfaceOrNull(k), isNull);
    final coldSnap = store.bakedSnapshotForSave();
    expect(
      coldSnap.cold.containsKey(k),
      isFalse,
      reason: 'the blob must die with the cel or the save resurrects it',
    );
    expect(
      store.dirtyCelKeysSinceSave,
      contains(k),
      reason: 'the removal is a CHANGE — an incremental save that does '
          'not see it keeps the old bytes in the archive',
    );

    // FILE arm.
    final directory = await Directory.systemTemp.createTemp('qa-empty-arm');
    addTearDown(() => directory.delete(recursive: true));
    final fileStore = BrushFrameStore();
    final fk = key(frame: 'file-victim');
    final blob = blobOf(fk, inkSurface(seed: 7));
    final path = '${directory.path}/cel.bin';
    File(path).writeAsBytesSync(blob.bytes);
    fileStore.restoreFromFile({
      fk: AnicelCelFileRef(
        filePath: path,
        dataOffset: 0,
        length: blob.bytes.length,
        canvasSize: canvasSize,
        tileSize: blob.tileSize,
      ),
    });
    expect(fileStore.isCelFileBacked(fk), isTrue, reason: 'fixture');
    fileStore.storeBakedSurface(fk, BitmapSurface(canvasSize: canvasSize));
    expect(fileStore.celHasRenderableContent(fk), isFalse);
    expect(fileStore.bakedSurfaceOrNull(fk), isNull);
    final fileSnap = fileStore.bakedSnapshotForSave();
    expect(
      fileSnap.fileRefs.containsKey(fk),
      isFalse,
      reason: 'a leftover ref points the NEXT save at the deleted '
          'picture\'s bytes inside the old archive',
    );
    expect(fileStore.dirtyCelKeysSinceSave, contains(fk));
  });
}
