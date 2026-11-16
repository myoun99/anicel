@TestOn('vm')
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:anicel/src/core/on_a_worker.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/brush_frame_key.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/pasteboard_bounds.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/native/tile_blocks.dart';
import 'package:anicel/src/services/brush_frame_store.dart';
import 'package:anicel/src/services/persistence/open_project_file.dart';
import 'package:anicel/src/services/persistence/scratch_file.dart';
import 'package:anicel/src/services/persistence/session_scratch.dart';
import 'package:anicel/src/services/persistence/worker_file_reads.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/cels_kept_in_a_file.dart';
import '../helpers/cels_parked_cold.dart';
import '../helpers/files_written_under.dart';
import '../helpers/poll_until.dart';

/// 🚨Card a-thawed-cel-is-adopted-on-the-ui-thread, what was left of it: a
/// kept cel worked out ahead on a worker ([BrushFrameStore.thawAhead],
/// [BrushFrameStore.cutCelsAhead]) still had its bytes READ on the UI
/// thread first — 4.3 ms a cel where the user keeps a project, 112 the
/// longest, a cel a row of a frame at once. They are read on a worker now,
/// and kept only under the very ref they were read by: a save may have
/// moved what a moved ref names.
void main() {
  // The road production takes — a REAL worker. The corpus runs every
  // worker's job here (`flutter_test_config.dart`).
  setUp(() => debugWorkersRunHere = false);
  tearDown(() => debugWorkersRunHere = true);

  // The paper is 512 × 256 in tiles of 128, the engine's: at a quarter past,
  // the wall stands 128 past the sides — a tile two to the left lies past it.
  const paper = CanvasSize(width: 512, height: 256);
  final pastTheWall = TileCoord(x: -2, y: 0);

  BrushFrameKey key(String frame) => BrushFrameKey(
    projectId: const ProjectId('p'),
    trackId: const TrackId('t'),
    cutId: const CutId('c'),
    layerId: const LayerId('l'),
    frameId: FrameId(frame),
  );

  /// A tile of [side] no two pixels of which need be one colour.
  BitmapTile tile(int salt, {int side = defaultCelTileSize}) {
    final pixels = Uint8List(BitmapTile.bytesFor(side));
    for (var i = 0; i < pixels.length; i += 1) {
      pixels[i] = (i * 31 + salt) & 0xFF;
    }
    return BitmapTile(size: side, pixels: pixels);
  }

  /// Two tiles of distinct bytes, one of them past the wall a quarter
  /// leaves.
  BitmapSurface inkSurface({int salt = 3}) => BitmapSurface(
    canvasSize: paper,
    tileSize: defaultCelTileSize,
    tiles: {
      TileCoord(x: 0, y: 0): tile(salt),
      pastTheWall: tile(salt + 4),
    },
  );

  Map<TileCoord, List<int>> pixelsOf(BitmapSurface surface) => {
    for (final entry in surface.tiles.entries)
      entry.key: entry.value.pixels.toList(),
  };

  final everyWayKept =
      <
        (
          String,
          void Function(BrushFrameStore, Map<BrushFrameKey, BitmapSurface>),
        )
      >[('parked cold', parkCold), ('kept in the saved file', keepInAFile)];

  for (final (kept, keep) in everyWayKept) {
    test("🚨a cel $kept is on its way to a worker's read before the turn it "
        'was asked in ends — and thaws to the picture a read here '
        'makes', () async {
      final store = BrushFrameStore();
      final k = key('a');
      final source = inkSurface();
      keep(store, {k: source});

      final thaw = store.thawAhead(k, canvasSize: paper);
      expect(WorkerFileReads.inFlight, 1);
      await thaw;

      expect(WorkerFileReads.inFlight, 0);
      expect(pixelsOf(store.hotBakedSurfaceOrNull(k)!), pixelsOf(source));
    });
  }

  test("🚨a cel kept in the saved file is thawed without the session's "
      'handle being read through: the handle is not opened for it', () async {
    final store = BrushFrameStore();
    final k = key('f');
    keepInAFile(store, {k: inkSurface()});
    OpenProjectFile.debugResetForTests();

    await store.thawAhead(k, canvasSize: paper);

    expect(store.hotBakedSurfaceOrNull(k), isNotNull, reason: 'premise');
    expect(
      OpenProjectFile.debugOpens,
      0,
      reason: "read through the session's handle — on this thread",
    );
  });

  // The two ways a cel is hot before its thaw ahead has its bytes: drawn
  // on — the ref is let go with it — and read here by who could not wait,
  // which keeps the very ref (the file still holds those bytes).
  final everyWayHot =
      <(String, BitmapSurface Function(BrushFrameStore, BrushFrameKey))>[
        (
          'drawn on',
          (store, k) {
            final drawn = BitmapSurface(
              canvasSize: const CanvasSize(width: 48, height: 24),
              tileSize: 24,
              tiles: {TileCoord(x: 0, y: 0): tile(9, side: 24)},
            );
            store.storeBakedSurface(k, drawn);
            return drawn;
          },
        ),
        ('read here', (store, k) => store.bakedSurfaceOrNull(k)!),
      ];

  for (final (how, makeHot) in everyWayHot) {
    test('🚨a cel $how while its bytes are read is not laid again: the thaw '
        'asks for no tile block', () async {
      // A tile side no other tile in this process wears, so the list of its
      // size ([TileBlocks]) holds what this test parks there and nothing a
      // collected tile's finalizer brings.
      const side = 24;
      const small = CanvasSize(width: 2 * side, height: side);
      final length = BitmapTile.bytesFor(side);
      final store = BrushFrameStore();
      final k = key('f');
      // Read where they lie: the engine keeps no tile of this side.
      keepInAFile(
        store,
        {
          k: BitmapSurface(
            canvasSize: small,
            tileSize: side,
            tiles: {
              TileCoord(x: 0, y: 0): tile(3, side: side),
              TileCoord(x: 1, y: 0): tile(7, side: side),
            },
          ),
        },
        bytesOf: readTilesInPlace,
      );

      final thaw = store.thawAhead(k, canvasSize: small);
      expect(WorkerFileReads.inFlight, 1, reason: 'premise: being read');
      final hot = makeHot(store, k);
      // Two blocks parked on the list once the cel is hot: the next two
      // asks of that length are answered with them, the last freed first.
      final blocks = [TileBlocks.alloc(length), TileBlocks.alloc(length)];
      blocks.forEach(TileBlocks.free);
      await thaw;

      expect(store.hotBakedSurfaceOrNull(k), same(hot), reason: 'premise');
      final asked = [TileBlocks.alloc(length), TileBlocks.alloc(length)];
      addTearDown(() => asked.forEach(TileBlocks.free));
      expect(
        [for (final block in asked) block.address],
        [blocks[1].address, blocks[0].address],
        reason: 'the parked blocks lie as they lay: a thaw that laid the '
            "cel's two tiles took them",
      );
    });
  }

  test('🚨a cel drawn on while it is LAID — its bytes read already — keeps '
      'the drawing: the thaw is let go, never written over it', () async {
    final store = BrushFrameStore();
    final k = key('f');
    keepInAFile(store, {k: inkSurface()});
    final drawn = inkSurface(salt: 9);

    final thaw = store.thawAhead(k, canvasSize: paper);
    // The read has ended once it is in flight no more, and the turn that
    // ended it handed the bytes to the worker that lays them — looked at a
    // turn at a time, before the worker can have laid them.
    expect(
      await pollUntil(
        () => WorkerFileReads.inFlight == 0,
        beat: Duration.zero,
      ),
      isTrue,
    );
    expect(store.hotBakedSurfaceOrNull(k), isNull, reason: 'premise: not yet');
    store.storeBakedSurface(k, drawn);
    await thaw;

    expect(store.bakedSurfaceOrNull(k), same(drawn));
  });

  group('a ref that moved while its bytes were read', () {
    /// What the rounds worked out ahead have parked in the room, once what
    /// was let go is gone. ⚠️The room is the run's: a test before this one
    /// may have left its own there.
    Future<Set<String>> parkedAhead() async {
      await ScratchFile.lettingGo;
      return {
        for (final path in filesWrittenUnder(
          Directory(SessionScratch.stagedFolder()),
        ))
          if (path.contains('-ahead')) path,
      };
    }

    /// Every ref of [store] re-issued where it is, as a save that moved its
    /// bytes re-issues it — these bytes have not moved, and the ref says
    /// they may have.
    void moveEveryRef(
      BrushFrameStore store,
      Map<BrushFrameKey, AnicelCelFileRef> refs,
    ) => store.relocateFileRefs((_) => true, {
      for (final ref in refs.values)
        ref.dataOffset: (dataOffset: ref.dataOffset, length: ref.length),
    });

    test('premise: a kept cel the wall crosses is cut ahead, and its cut '
        'parked', () async {
      final store = BrushFrameStore();
      keepInAFile(store, {key('a'): inkSurface()});
      final before = await parkedAhead();

      await store.cutCelsAhead(PasteboardReach.quarter);

      expect((await parkedAhead()).difference(before), hasLength(1));
    });

    test("🚨its bytes are not cut ahead — they may be another's by now, and "
        'nothing of them is parked', () async {
      final store = BrushFrameStore();
      final refs = keepInAFile(store, {key('a'): inkSurface()});
      final before = await parkedAhead();

      final ahead = store.cutCelsAhead(PasteboardReach.quarter);
      expect(WorkerFileReads.inFlight, 1, reason: 'premise: being read');
      moveEveryRef(store, refs);
      await ahead;

      expect((await parkedAhead()).difference(before), isEmpty);
    });

    test('its bytes are not thawed — the cel stays kept by the ref it has '
        'now', () async {
      final store = BrushFrameStore();
      final k = key('a');
      final refs = keepInAFile(store, {k: inkSurface()});

      final thaw = store.thawAhead(k, canvasSize: paper);
      moveEveryRef(store, refs);
      await thaw;

      expect(store.hotBakedSurfaceOrNull(k), isNull);
      expect(store.isCelFileBacked(k), isTrue);
    });
  });
}
