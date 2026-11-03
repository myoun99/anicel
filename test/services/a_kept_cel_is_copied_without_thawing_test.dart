import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
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
import 'package:anicel/src/services/persistence/brush_drawing_binary_codec.dart';
import 'package:anicel/src/services/persistence/scratch_file.dart';

import '../helpers/cels_kept_in_a_file.dart';
import '../helpers/cels_parked_cold.dart';
import '../helpers/project_scratch_folder.dart';

/// 🗣️Card `store-copies-a-kept-cel-without-thawing` (유저 2026-11-04,
/// timeline-copy-thaws-every-cel-Q1 「저장 레인이 ①」): a timeline copy
/// thawed every cel it copied, and FU rose to 3000MB. A copy takes the
/// picture in the tier its source keeps it in.
void main() {
  const size = CanvasSize(width: 16, height: 16);

  BrushFrameKey key(String frame) => BrushFrameKey(
    projectId: const ProjectId('p'),
    trackId: const TrackId('t'),
    cutId: const CutId('c'),
    layerId: const LayerId('l'),
    frameId: FrameId(frame),
  );

  BitmapSurface inked(int seed) {
    final pixels = Uint8List(8 * 8 * 4);
    for (var i = 0; i < pixels.length; i += 1) {
      pixels[i] = (i * seed * 31 + seed) & 0xFF;
    }
    return BitmapSurface(
      canvasSize: size,
      tileSize: 8,
      tiles: {TileCoord(x: 0, y: 0): BitmapTile(size: 8, pixels: pixels)},
    );
  }

  Uint8List pixelsOf(BitmapSurface? surface) =>
      surface!.tiles[TileCoord(x: 0, y: 0)]!.pixels;

  /// What [store] shows for [cel], read as a render reads it — nothing
  /// thawed.
  Uint8List looked(BrushFrameStore store, String cel) =>
      pixelsOf(store.bakedSurfaceOrNull(key(cel), read: CelRead.look));

  test('🎯a cel kept in the saved file is copied as its stretch of the file '
      '— nothing thaws, and the copy is unsaved', () {
    final store = BrushFrameStore();
    keepInAFile(store, {key('a'): inked(1)});

    store.copyCel(key('a'), key('b'), canvasSize: size);

    expect(store.hotBakedBytes, 0, reason: 'it thawed the source');
    expect(store.isCelFileBacked(key('b')), isTrue);
    expect(store.dirtyCelKeysSinceSave, {key('b')});
    expect(store.celHasRenderableContent(key('b')), isTrue);
    expect(looked(store, 'b'), pixelsOf(inked(1)));
    expect(looked(store, 'a'), pixelsOf(inked(1)));
  });

  test('🎯a parked cel is parked again under the copy\'s name: the copy '
      'keeps its picture once the source thaws and lets its file go', () async {
    final store = BrushFrameStore();
    parkCold(store, {key('a'): inked(2)});

    store.copyCel(key('a'), key('b'), canvasSize: size);

    expect(store.hotBakedBytes, 0, reason: 'it thawed the source');
    expect(store.isCelCold(key('a')), isTrue);
    expect(store.isCelCold(key('b')), isTrue);
    expect(store.dirtyCelKeysSinceSave, contains(key('b')));

    store.bakedSurfaceOrNull(key('a'));
    await ScratchFile.lettingGo;

    expect(store.isCelCold(key('a')), isFalse, reason: 'fixture: it thawed');
    expect(
      looked(store, 'b'),
      pixelsOf(inked(2)),
      reason: 'the copy read the file the source let go',
    );
  });

  test('a hot cel is copied as its surface — the tiles are the source\'s', () {
    final store = BrushFrameStore()..storeBakedSurface(key('a'), inked(3));

    store.copyCel(key('a'), key('b'), canvasSize: size);

    expect(
      identical(
        store.hotBakedSurfaceOrNull(key('b')),
        store.hotBakedSurfaceOrNull(key('a')),
      ),
      isTrue,
    );
  });

  test('a hot cel copied onto a canvas of another size is laid to it', () {
    final store = BrushFrameStore()..storeBakedSurface(key('a'), inked(3));
    const bigger = CanvasSize(width: 32, height: 32);

    store.copyCel(key('a'), key('b'), canvasSize: bigger);

    final copy = store.hotBakedSurfaceOrNull(key('b'))!;
    expect(copy.canvasSize, bigger);
    expect(pixelsOf(copy), pixelsOf(inked(3)), reason: 'laid from the top left');
  });

  test('a copy onto an empty key is told as that key crossing to a '
      'picture', () {
    final store = BrushFrameStore();
    keepInAFile(store, {key('a'): inked(1)});
    final before = store.celContentRevision.value;

    store.copyCel(key('a'), key('b'), canvasSize: size);

    expect(store.celContentRevision.value, before + 1);
    expect(store.celsLastCrossed, {key('b')});
  });

  test('a kept cel copied onto a canvas of another size is laid to it and '
      'parked — never hot', () {
    final store = BrushFrameStore();
    keepInAFile(store, {key('a'): inked(4)});
    const bigger = CanvasSize(width: 32, height: 32);

    store.copyCel(key('a'), key('b'), canvasSize: bigger);

    expect(store.hotBakedBytes, 0);
    expect(store.isCelCold(key('b')), isTrue);
    final copy = store.bakedSurfaceOrNull(key('b'), read: CelRead.look)!;
    expect(copy.canvasSize, bigger);
    expect(pixelsOf(copy), pixelsOf(inked(4)), reason: 'laid from the top left');
  });

  group('the copy is all its key keeps afterwards', () {
    test('a picture it showed before — hot, and drawn from its preview', () {
      final store = BrushFrameStore();
      keepInAFile(store, {key('a'): inked(1)});
      store
        ..storeBakedSurface(key('b'), inked(9))
        ..storeRebuiltDisplayCache(key: key('b'), previewSurface: inked(9));

      store.copyCel(key('a'), key('b'), canvasSize: size);

      expect(store.hotBakedSurfaceOrNull(key('b')), isNull);
      expect(store.hotBakedBytes, 0);
      expect(store.validPreviewSurfaceOrNull(key('b')), isNull);
      expect(looked(store, 'b'), pixelsOf(inked(1)));
    });

    test('a picture it had parked', () async {
      final store = BrushFrameStore();
      keepInAFile(store, {key('a'): inked(1)});
      store
        ..hotCelByteBudget = 0
        ..storeBakedSurface(key('b'), inked(9))
        ..storeBakedSurface(key('c'), inked(8));
      await store.drainCooling();
      expect(store.isCelCold(key('b')), isTrue, reason: 'fixture: parked');

      store.copyCel(key('a'), key('b'), canvasSize: size);

      expect(store.isCelCold(key('b')), isFalse);
      expect(store.coldBakedBytes, 0);
      expect(looked(store, 'b'), pixelsOf(inked(1)));
    });

    test('a stretch of the saved file it was kept in', () {
      final store = BrushFrameStore();
      keepInAFile(store, {key('a'): inked(1), key('b'): inked(9)});

      store.copyCel(
        key('a'),
        key('b'),
        canvasSize: const CanvasSize(width: 32, height: 32),
      );

      expect(store.isCelFileBacked(key('b')), isFalse);
      expect(store.isCelCold(key('b')), isTrue);
    });
  });

  test('nothing kept, nothing copied', () {
    final store = BrushFrameStore();

    store.copyCel(key('a'), key('b'), canvasSize: size);

    expect(store.celHasRenderableContent(key('b')), isFalse);
    expect(store.dirtyCelKeysSinceSave, isEmpty);
  });

  group('the save writes each copy under its own name', () {
    late Directory directory;

    setUp(() {
      directory = Directory.systemTemp.createTempSync('anicel-copied-cels');
      deleteAfterSessionEnds(directory);
    });

    /// [store] saved, and each cel the file holds read back from it — by the
    /// key its entry says it is.
    Future<Map<BrushFrameKey, Uint8List>> saved(BrushFrameStore store) async {
      const service = AnicelFileService();
      final path = '${directory.path}/project.anicel';
      await service.save(
        project: createDefaultProject(),
        brushFrameStore: store,
        filePath: path,
      );
      final opened = await service.open(filePath: path);
      final file = File(path).openSync();
      try {
        return {
          for (final MapEntry(key: cel, value: ref) in opened.cels.entries)
            cel: () {
              file.setPositionSync(ref.dataOffset);
              final blob = AnicelCelBlob(file.readSync(ref.length));
              expect(blob.key, cel, reason: 'the entry wears its own key');
              return pixelsOf(blob.decode().toSurface());
            }(),
        };
      } finally {
        file.closeSync();
      }
    }

    test('a copy of a cel kept in the saved file', () async {
      final store = BrushFrameStore();
      keepInAFile(store, {key('a'): inked(5)});
      store.copyCel(key('a'), key('b'), canvasSize: size);

      expect(await saved(store), {
        key('a'): pixelsOf(inked(5)),
        key('b'): pixelsOf(inked(5)),
      });
    });

    test('a copy of a parked cel', () async {
      final store = BrushFrameStore();
      parkCold(store, {key('a'): inked(6)});
      store.copyCel(key('a'), key('b'), canvasSize: size);

      expect(await saved(store), {
        key('a'): pixelsOf(inked(6)),
        key('b'): pixelsOf(inked(6)),
      });
    });
  });
}
