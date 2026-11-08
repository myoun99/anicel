import 'dart:ffi';
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
import 'package:anicel/src/services/persistence/brush_drawing_binary_codec.dart';
import 'package:ffi/ffi.dart';
import 'package:flutter_test/flutter_test.dart';

/// A worker has no engine, so a hot cel's tiles reach it through one block
/// the main isolate reads them back into — and the block is only good for
/// as long as the worker works.
void main() {
  final bytes = BitmapTile.bytesFor(defaultCelTileSize);
  const key = BrushFrameKey(
    projectId: ProjectId('p'),
    trackId: TrackId('t'),
    cutId: CutId('c'),
    layerId: LayerId('l'),
    frameId: FrameId('f'),
  );

  BitmapTile tile(int seed) => BitmapTile(
    size: defaultCelTileSize,
    pixels: Uint8List(bytes)..fillRange(0, bytes, seed),
  );

  BitmapSurface surfaceOf(List<BitmapTile> tiles) => BitmapSurface(
    canvasSize: CanvasSize(
      width: 8 * defaultCelTileSize,
      height: 8 * defaultCelTileSize,
    ),
    tileSize: defaultCelTileSize,
    tiles: {
      for (final (at, tile) in tiles.indexed) TileCoord(x: at, y: 0): tile,
    },
  );

  List<int> addressesOf(AnicelLaidCel at) => [
    for (final record in at.tiles) record.pixels,
  ];

  test('each tile is named by where its bytes were read back to, and the '
      'one block goes when the work is done', () async {
    final (a, b) = (tile(3), tile(5));
    final counted = _Counted();

    final read = await withCelBlocks(
      key,
      surfaceOf([a, b]),
      (at) async => [
        for (final address in addressesOf(at))
          Uint8List.fromList(
            Pointer<Uint8>.fromAddress(address).asTypedList(bytes),
          ),
      ],
      blocks: counted,
    );

    expect(read, [a.pixels, b.pixels]);
    expect(counted.asked, [2 * bytes]);
    expect(counted.givenBack, 1);
  });

  test('the block is still there all the while the work waits', () async {
    final counted = _Counted();

    await withCelBlocks(key, surfaceOf([tile(3)]), (_) async {
      await Future<void>.delayed(Duration.zero);
      expect(counted.givenBack, 0);
    }, blocks: counted);

    expect(counted.givenBack, 1);
  });

  test('work that fails gives the block back, and the failure is its '
      'caller\'s', () async {
    final counted = _Counted();

    await expectLater(
      withCelBlocks<void>(
        key,
        surfaceOf([tile(3)]),
        (_) async => throw StateError('the worker died'),
        blocks: counted,
      ),
      throwsStateError,
    );

    expect(counted.givenBack, 1);
  });

  test('one tile at two places is read once, and both name it', () async {
    final same = tile(3);
    final counted = _Counted();

    final at = await withCelBlocks(
      key,
      surfaceOf([same, same]),
      (at) async => addressesOf(at),
      blocks: counted,
    );

    expect(counted.asked, [bytes]);
    expect(at, [counted.address, counted.address]);
  });

  test('two tiles of the same bytes are still two tiles', () async {
    final counted = _Counted();

    final at = await withCelBlocks(
      key,
      surfaceOf([tile(3), tile(3)]),
      (at) async => addressesOf(at),
      blocks: counted,
    );

    expect(counted.asked, [2 * bytes]);
    expect(at[0], isNot(at[1]));
  });

  test('a picture of no tiles has a block to free and no tile in it', () async {
    final counted = _Counted();

    final at = await withCelBlocks(
      key,
      surfaceOf(const []),
      (at) async => addressesOf(at),
      blocks: counted,
    );

    expect(at, isEmpty);
    expect(counted.asked, [bytes]);
    expect(counted.givenBack, 1);
  });
}

final class _Counted implements Allocator {
  final asked = <int>[];
  int givenBack = 0;
  int address = 0;

  @override
  Pointer<T> allocate<T extends NativeType>(int byteCount, {int? alignment}) {
    asked.add(byteCount);
    final block = malloc.allocate<T>(byteCount, alignment: alignment);
    address = block.address;
    return block;
  }

  @override
  void free(Pointer pointer) {
    givenBack += 1;
    malloc.free(pointer);
  }
}
