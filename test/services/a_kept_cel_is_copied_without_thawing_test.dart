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
import 'package:anicel/src/services/bitmap_surface_geometry.dart'
    show resizeBitmapSurfaceCanvas;
import 'package:anicel/src/services/brush_frame_store.dart';
import 'package:anicel/src/services/persistence/anicel_file_service.dart';
import 'package:anicel/src/services/persistence/brush_drawing_binary_codec.dart';
import 'package:anicel/src/services/persistence/scratch_file.dart';
import 'package:anicel/src/services/persistence/session_scratch.dart';

import '../helpers/cels_kept_in_a_file.dart';
import '../helpers/cels_parked_cold.dart';
import '../helpers/files_written_under.dart';
import '../helpers/project_scratch_folder.dart';

/// 🗣️Card `store-copies-a-kept-cel-without-thawing` (유저 2026-11-04,
/// timeline-copy-thaws-every-cel-Q1 「저장 레인이 ①」): a timeline copy
/// thawed every cel it copied, and FU rose to 3000MB. A copy takes the
/// picture in the tier its source keeps it in.
void main() {
  // Two tiles across and down, on the engine's side.
  const size = CanvasSize(
    width: 2 * defaultCelTileSize,
    height: 2 * defaultCelTileSize,
  );

  BrushFrameKey key(String frame) => BrushFrameKey(
    projectId: const ProjectId('p'),
    trackId: const TrackId('t'),
    cutId: const CutId('c'),
    layerId: const LayerId('l'),
    frameId: FrameId(frame),
  );

  BitmapSurface inked(int seed) {
    final pixels = Uint8List(defaultCelTileSize * defaultCelTileSize * 4);
    for (var i = 0; i < pixels.length; i += 1) {
      pixels[i] = (i * seed * 31 + seed) & 0xFF;
    }
    return BitmapSurface(
      canvasSize: size,
      tileSize: defaultCelTileSize,
      tiles: {
        TileCoord(x: 0, y: 0): BitmapTile(
          size: defaultCelTileSize,
          pixels: pixels,
        ),
      },
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

  test('🎯a parked cel\'s copy keeps its picture once the source thaws and '
      'lets go of what it kept', () async {
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
    const bigger = CanvasSize(
      width: 4 * defaultCelTileSize,
      height: 4 * defaultCelTileSize,
    );

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
    const bigger = CanvasSize(
      width: 4 * defaultCelTileSize,
      height: 4 * defaultCelTileSize,
    );

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
        canvasSize: const CanvasSize(
          width: 4 * defaultCelTileSize,
          height: 4 * defaultCelTileSize,
        ),
      );

      expect(store.isCelFileBacked(key('b')), isFalse);
      expect(store.isCelCold(key('b')), isTrue);
    });
  });

  group('an undo that stores the copy a blank lets the copy go, and the '
      'source keeps its own', () {
    // `UnlinkLayerCommand` · `LeaveSyncCommand` undo a copy so: the key and
    // its size, a surface that holds nothing.
    void blank(BrushFrameStore store) =>
        store.storeBakedSurface(key('b'), BitmapSurface(canvasSize: size));

    test('a stretch of the saved file', () {
      final store = BrushFrameStore();
      keepInAFile(store, {key('a'): inked(1)});
      store.copyCel(key('a'), key('b'), canvasSize: size);

      blank(store);

      expect(store.isCelFileBacked(key('b')), isFalse);
      expect(store.celHasRenderableContent(key('b')), isFalse);
      expect(store.celsLastCrossed, {key('b')});
      expect(looked(store, 'a'), pixelsOf(inked(1)));
    });

    test('a parked file', () async {
      final store = BrushFrameStore();
      parkCold(store, {key('a'): inked(2)});
      store.copyCel(key('a'), key('b'), canvasSize: size);

      blank(store);
      await ScratchFile.lettingGo;

      expect(store.isCelCold(key('b')), isFalse);
      expect(store.celHasRenderableContent(key('b')), isFalse);
      expect(looked(store, 'a'), pixelsOf(inked(2)));
    });
  });

  test('nothing kept, nothing copied — and it answers so', () {
    final store = BrushFrameStore();

    expect(store.copyCel(key('a'), key('b'), canvasSize: size), isNull);
    expect(store.celHasRenderableContent(key('b')), isFalse);
    expect(store.dirtyCelKeysSinceSave, isEmpty);
  });

  test('a copy answers the size it is kept at — what an undo empties', () {
    final store = BrushFrameStore();
    keepInAFile(store, {key('a'): inked(1)});
    const bigger = CanvasSize(
      width: 4 * defaultCelTileSize,
      height: 4 * defaultCelTileSize,
    );

    expect(store.copyCel(key('a'), key('b'), canvasSize: size), size);
    expect(store.copyCel(key('a'), key('c'), canvasSize: bigger), bigger);
  });

  // 🗣️Card store-copies-a-kept-cel-without-thawing (저장 → 타임라인/콘티,
  // 2026-11-04): the sheets' handwriting copies the same way, at the size
  // its surface is — the sheet's, whatever the cut's canvas.
  group('left without a size, a copy keeps the size its source is kept '
      'at', () {
    const sheet = CanvasSize(
      width: 3 * defaultCelTileSize,
      height: 5 * defaultCelTileSize,
    );

    BitmapSurface onTheSheet(int seed) =>
        resizeBitmapSurfaceCanvas(inked(seed), sheet);

    test('hot: the very surface — the tiles shared, nothing laid', () {
      final store = BrushFrameStore()
        ..storeBakedSurface(key('a'), onTheSheet(3));

      expect(store.copyCel(key('a'), key('b')), sheet);
      expect(
        identical(
          store.hotBakedSurfaceOrNull(key('b')),
          store.hotBakedSurfaceOrNull(key('a')),
        ),
        isTrue,
      );
    });

    test('kept in the saved file: the same stretch, nothing thawed', () {
      final store = BrushFrameStore();
      keepInAFile(store, {key('a'): onTheSheet(1)});

      expect(store.copyCel(key('a'), key('b')), sheet);
      expect(store.hotBakedBytes, 0);
      expect(store.isCelFileBacked(key('b')), isTrue);
      expect(looked(store, 'b'), pixelsOf(inked(1)));
    });

    test('parked: parked again, never hot', () {
      final store = BrushFrameStore();
      parkCold(store, {key('a'): onTheSheet(2)});

      expect(store.copyCel(key('a'), key('b')), sheet);
      expect(store.hotBakedBytes, 0);
      expect(store.isCelCold(key('b')), isTrue);
      expect(looked(store, 'b'), pixelsOf(inked(2)));
    });
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
              return pixelsOf(blob.toSurface());
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

  // 🗣️Card a-kept-cel-copied-to-another-canvas-size-is-rewritten-on-the-ui-
  // thread (저장 11-14): a copy at its source's size keeps the very ref, a
  // parked file as a stretch of the saved file — the file read and written
  // again on the UI thread was 3 ms a cel of small ones.
  group('a parked copy at its source\'s size keeps the very file', () {
    /// Every file in the run's room — once what was let go is gone.
    Future<Set<String>> roomFiles() async {
      await ScratchFile.lettingGo;
      return filesWrittenUnder(
        Directory(SessionScratch.stagedFolder()),
      ).toSet();
    }

    test('🎯nothing is written, and its bytes are counted once', () async {
      final store = BrushFrameStore();
      parkCold(store, {key('a'): inked(2)});
      final before = await roomFiles();
      final bytes = store.coldBakedBytes;

      store.copyCel(key('a'), key('b'), canvasSize: size);

      expect(await roomFiles(), before);
      expect(store.coldBakedBytes, bytes);
      expect(store.isCelCold(key('b')), isTrue);
    });

    test('🎯the file goes with the last cel that keeps it', () async {
      final store = BrushFrameStore();
      parkCold(store, {key('a'): inked(2)});
      store.copyCel(key('a'), key('b'), canvasSize: size);
      final before = await roomFiles();
      final bytes = store.coldBakedBytes;

      store.bakedSurfaceOrNull(key('a'));

      expect(await roomFiles(), before, reason: 'the copy keeps it');
      expect(store.coldBakedBytes, bytes);

      store.bakedSurfaceOrNull(key('b'));

      expect(before.difference(await roomFiles()), hasLength(1));
      expect(store.coldBakedBytes, 0);
    });

    test('a pass that rewrites the source leaves the copy the file it '
        'keeps', () async {
      final store = BrushFrameStore();
      const elsewhere = BrushFrameKey(
        projectId: ProjectId('p'),
        trackId: TrackId('t'),
        cutId: CutId('d'),
        layerId: LayerId('l'),
        frameId: FrameId('b'),
      );
      parkCold(store, {key('a'): inked(2)});
      store.copyCel(key('a'), elsewhere, canvasSize: size);
      const bigger = CanvasSize(
        width: 4 * defaultCelTileSize,
        height: 4 * defaultCelTileSize,
      );

      store.resizeBakedSurfaces(bigger, cutId: const CutId('c'));
      await ScratchFile.lettingGo;

      expect(
        pixelsOf(store.bakedSurfaceOrNull(elsewhere, read: CelRead.look)),
        pixelsOf(inked(2)),
      );
      expect(
        store.bakedSurfaceOrNull(key('a'), read: CelRead.look)!.canvasSize,
        bigger,
        reason: 'fixture: the source was rewritten',
      );
    });

    test('a copy onto the key it is copied from keeps its picture', () async {
      final store = BrushFrameStore();
      parkCold(store, {key('a'): inked(2)});

      store.copyCel(key('a'), key('a'), canvasSize: size);
      await ScratchFile.lettingGo;

      expect(store.isCelCold(key('a')), isTrue);
      expect(looked(store, 'a'), pixelsOf(inked(2)));
    });
  });

  test('a room that will not take a copy laid to another size leaves the '
      'copy hot', () {
    final store = BrushFrameStore();
    keepInAFile(store, {key('a'): inked(4)});
    const bigger = CanvasSize(
      width: 4 * defaultCelTileSize,
      height: 4 * defaultCelTileSize,
    );
    // A FILE where the room's folder has to go (`a_cooled_cel_parks_on_disk_
    // test`).
    final room = Directory(SessionScratch.stagedFolder());
    if (room.existsSync()) {
      room.deleteSync(recursive: true);
    }
    final blocker = File(SessionScratch.stagedFolder())
      ..createSync(recursive: true)
      ..writeAsBytesSync(const [0]);
    addTearDown(() {
      if (blocker.existsSync()) {
        blocker.deleteSync();
      }
    });

    expect(store.copyCel(key('a'), key('b'), canvasSize: bigger), bigger);

    final copy = store.hotBakedSurfaceOrNull(key('b'))!;
    expect(copy.canvasSize, bigger);
    expect(pixelsOf(copy), pixelsOf(inked(4)));
  });
}
