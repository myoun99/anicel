import 'dart:ffi';
import 'dart:math' as math;
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
import 'package:anicel/src/native/engine_tile_ledger.dart';
import 'package:anicel/src/services/persistence/brush_drawing_binary_codec.dart';
import 'package:anicel/src/services/persistence/thaw_in_worker.dart';
import 'package:ffi/ffi.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gpu_engine/gpu_engine.dart' show GpuReadFailed;

import '../../helpers/tiles_on_the_engine.dart';

/// A worker has no engine, so it asks the main isolate for a hot cel's
/// tiles, a batch at a time, a block a batch — never the cel whole (저장's
/// review of the flip lane, 11-09: 132 MiB for a cel of 5800² inked whole).
/// The block is the worker's once it has its address: the batch is copied
/// there, not here (card `a-save-serialises-each-hot-cel-on-the-ui-isolate`
/// ⓑ, 2026-11-14).
void main() {
  final bytes = BitmapTile.bytesFor(defaultCelTileSize);
  const key = BrushFrameKey(
    projectId: ProjectId('p'),
    trackId: TrackId('t'),
    cutId: CutId('c'),
    layerId: LayerId('l'),
    frameId: FrameId('f'),
  );

  BitmapTile tile(int seed) => tileOnEngine(
    BitmapTile(
      size: defaultCelTileSize,
      pixels: Uint8List(bytes)..fillRange(0, bytes, seed),
    ),
  );

  BitmapSurface surfaceOf(
    List<BitmapTile> tiles, {
    PasteboardReach reach = PasteboardReach.whole,
  }) => BitmapSurface(
    canvasSize: const CanvasSize(
      width: 200 * defaultCelTileSize,
      height: 8 * defaultCelTileSize,
    ),
    pasteboardReach: reach,
    tileSize: defaultCelTileSize,
    tiles: {
      for (final (at, tile) in tiles.indexed) TileCoord(x: at, y: 0): tile,
    },
  );

  List<BitmapTile> seeded(int count) => [
    for (var at = 0; at < count; at++) tile(at % 250 + 1),
  ];

  late List<int> reads;
  setUp(() {
    reads = [];
    EngineTileLedger.debugBeforeRead = (tiles) => reads.add(tiles.length);
  });
  tearDown(() {
    EngineTileLedger.debugBeforeRead = null;
    debugWorkersRunHere = true;
  });

  test('the copy holds each tile\'s bytes at its place, and its block goes '
      'back', () async {
    final (a, b) = (tile(3), tile(5));
    final counted = _Counted();

    final read = await onAWorkerWithCelCopy(
      key.cel,
      surfaceOf([a, b]),
      _pixelsAcross,
      blocks: counted,
    );

    expect(read, [a.pixels, b.pixels]);
    expect(counted.asked, [2 * bytes]);
    expect(counted.givenBack, 1);
  });

  test('🚨 a cel past a batch is read a batch at a time, a block a batch, '
      'each given back before the next is asked for', () async {
    final counted = _Counted();
    final tiles = seeded(130);

    final read = await onAWorkerWithCelCopy(
      key.cel,
      surfaceOf(tiles),
      _pixelsAcross,
      blocks: counted,
    );

    expect(reads, [64, 64, 2]);
    expect(counted.asked, [64 * bytes, 64 * bytes, 2 * bytes]);
    expect(counted.mostHeld, 1);
    expect(counted.givenBack, 3);
    expect(read.map((pixels) => pixels.first), tiles.map((t) => t.pixels[0]));
  });

  test('a cel of exactly a batch is one read', () async {
    await onAWorkerWithCelCopy(key.cel, surfaceOf(seeded(64)), _pixelsAcross);

    expect(reads, [64]);
  });

  test('one tile at two places is read once, and is one tile there too',
      () async {
    final same = tile(3);
    final counted = _Counted();

    final twoPlaces = await onAWorkerWithCelCopy(
      key.cel,
      surfaceOf([same, same]),
      _firstTwoAreOne,
      blocks: counted,
    );

    expect(twoPlaces, isTrue);
    expect(reads, [1]);
    expect(counted.asked, [bytes]);
  });

  test('two tiles of the same bytes are still two tiles', () async {
    final twoPlaces = await onAWorkerWithCelCopy(
      key.cel,
      surfaceOf([tile(3), tile(3)]),
      _firstTwoAreOne,
    );

    expect(twoPlaces, isFalse);
    expect(reads, [2]);
  });

  test('a picture of no tiles asks for none, and takes no block', () async {
    final counted = _Counted();

    final read = await onAWorkerWithCelCopy(
      key.cel,
      surfaceOf(const []),
      _pixelsAcross,
      blocks: counted,
    );

    expect(read, isEmpty);
    expect(reads, isEmpty);
    expect(counted.asked, isEmpty);
    expect(counted.givenBack, 0);
  });

  test('the copy stands behind the wall the picture stands behind', () async {
    final reach = await onAWorkerWithCelCopy(
      key.cel,
      surfaceOf([tile(3)], reach: PasteboardReach.quarter),
      (copy) => copy.pasteboardReach,
    );

    expect(reach, PasteboardReach.quarter);
  });

  test('work that fails gives the block back, and the failure is its '
      'caller\'s', () async {
    final counted = _Counted();

    await expectLater(
      onAWorkerWithCelCopy<void>(
        key.cel,
        surfaceOf([tile(3)]),
        (_) => throw StateError('the worker died'),
        blocks: counted,
      ),
      throwsStateError,
    );

    expect(counted.givenBack, 1);
  });

  test('🚨 a read the engine refuses stops the work, by its own name, and '
      'gives the block back', () async {
    final counted = _Counted();
    EngineTileLedger.debugBeforeRead = (_) => throw GpuReadFailed('lost');
    var worked = false;

    await expectLater(
      onAWorkerWithCelCopy<void>(
        key.cel,
        surfaceOf([tile(3)]),
        (_) => worked = true,
        blocks: counted,
      ),
      throwsA(isA<GpuReadFailed>()),
    );

    expect(worked, isFalse);
    expect(counted.givenBack, 1);
  });

  group('on a real worker', () {
    setUp(() => debugWorkersRunHere = false);

    test('🚨 the closures cross, and the batches come back in order', () async {
      final tiles = seeded(130);

      final read = await onAWorkerWithCelCopy(
        key.cel,
        surfaceOf(tiles),
        _pixelsAcross,
      );

      expect(reads, [64, 64, 2]);
      expect(read.map((pixels) => pixels.first), tiles.map((t) => t.pixels[0]));
    });

    test('🚨 each block this isolate read a batch into, the worker gives '
        'back', () async {
      final across = _HeldAcross();
      addTearDown(across.dispose);

      await onAWorkerWithCelCopy(
        key.cel,
        surfaceOf(seeded(130)),
        _pixelsAcross,
        blocks: across,
      );

      expect(reads, [64, 64, 2]);
      expect(across.held, 0);
    });

    test('🚨 a move and a cut do their work without asking for the ledger — '
        'a tile fresh from bytes knows no ink box, and a scan of one there '
        'would be refused by name', () async {
      final surface = surfaceOf([tile(200)]);

      final moved = await moveHotCelInWorker(
        key,
        surface,
        move: (
          canvasSize: surface.canvasSize,
          dx: defaultCelTileSize,
          dy: 0,
        ),
      );

      expect(moved.tiles.keys, [TileCoord(x: 1, y: 0)]);
      expect(
        moved.tiles[TileCoord(x: 1, y: 0)]!.pixels,
        surface.tiles[TileCoord(x: 0, y: 0)]!.pixels,
      );

      final cut = await cutHotCelInWorker(
        key,
        BitmapSurface(
          canvasSize: surface.canvasSize,
          pasteboardReach: PasteboardReach.whole,
          tileSize: defaultCelTileSize,
          tiles: {
            TileCoord(x: 0, y: 0): tile(200),
            TileCoord(x: 0, y: 10): tile(90),
          },
        ),
        PasteboardReach.none,
      );

      expect(cut!.tiles.keys, [TileCoord(x: 0, y: 0)]);
    });

    test('a move keeps the wall its picture stands behind', () async {
      final surface = surfaceOf([tile(200)], reach: PasteboardReach.quarter);

      final moved = await moveHotCelInWorker(
        key,
        surface,
        move: (
          canvasSize: surface.canvasSize,
          dx: defaultCelTileSize,
          dy: 0,
        ),
      );

      expect(moved.pasteboardReach, PasteboardReach.quarter);
    });

    test('🚨 a read refused here is thrown by its own name, not as a '
        'worker\'s error', () async {
      final counted = _Counted();
      var left = 2;
      EngineTileLedger.debugBeforeRead = (_) {
        left -= 1;
        if (left == 0) {
          throw GpuReadFailed('lost');
        }
      };

      await expectLater(
        onAWorkerWithCelCopy(
          key.cel,
          surfaceOf(seeded(130)),
          _pixelsAcross,
          blocks: counted,
        ),
        throwsA(isA<GpuReadFailed>()),
      );

      expect(counted.givenBack, 1);
    });
  });
}

/// The bytes of each of [copy]'s tiles, from the left — a job that carries
/// nothing across.
List<Uint8List> _pixelsAcross(BitmapSurface copy) => [
  for (var x = 0; x < copy.tiles.length; x++)
    copy.tiles[TileCoord(x: x, y: 0)]!.pixels,
];

bool _firstTwoAreOne(BitmapSurface copy) => identical(
  copy.tiles[TileCoord(x: 0, y: 0)],
  copy.tiles[TileCoord(x: 1, y: 0)],
);

final class _Counted implements Allocator {
  final asked = <int>[];
  int givenBack = 0;

  /// The most blocks held at once.
  int mostHeld = 0;

  @override
  Pointer<T> allocate<T extends NativeType>(int byteCount, {int? alignment}) {
    asked.add(byteCount);
    mostHeld = math.max(mostHeld, asked.length - givenBack);
    return malloc.allocate<T>(byteCount, alignment: alignment);
  }

  @override
  void free(Pointer pointer) {
    givenBack += 1;
    malloc.free(pointer);
  }
}

/// [malloc]'s blocks held, counted where every isolate of the process
/// reads the same count: a worker frees what this isolate took, with its
/// own copy of this allocator.
final class _HeldAcross implements Allocator {
  _HeldAcross() : _cell = malloc<Int64>().address {
    _count.value = 0;
  }

  final int _cell;

  Pointer<Int64> get _count => Pointer<Int64>.fromAddress(_cell);

  int get held => _count.value;

  void dispose() => malloc.free(_count);

  @override
  Pointer<T> allocate<T extends NativeType>(int byteCount, {int? alignment}) {
    _count.value += 1;
    return malloc.allocate<T>(byteCount, alignment: alignment);
  }

  @override
  void free(Pointer pointer) {
    _count.value -= 1;
    malloc.free(pointer);
  }
}
