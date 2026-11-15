import 'package:gpu_engine/gpu_engine.dart';

import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/native/engine_tile_ledger.dart';

/// [tile]'s pixels as the engine alone holds them, as a landing leaves a
/// tile: what a read has to ask the GPU for. Its ink is known, as the
/// engine tells a tile it lands (`EngineTileLedger.rememberInk`) — a scan
/// for it reads the pixels here, and a read then gives those and asks the
/// GPU for nothing.
BitmapTile tileOnEngine(BitmapTile tile) =>
    EngineTileLedger.instance.debugOnEngine(tile)
      ..rememberInkBounds(tile.inkBounds);

/// [surface], every tile of it the engine's alone ([tileOnEngine]).
BitmapSurface surfaceOnEngine(BitmapSurface surface) =>
    surface.withRebuiltTiles({
      for (final MapEntry(:key, :value) in surface.tiles.entries)
        key: tileOnEngine(value),
    });

/// A tile of [value] at every byte landed by [ledger] on each of [unders]
/// — a row of [cel]'s, null where there is no tile to land on — stored as
/// a kernel stores what it lands, with no kernel to compile.
List<BitmapTile> landedOn(
  EngineTileLedger ledger,
  Object cel,
  List<BitmapTile?> unders,
  int value,
) => [
  for (final landed in ledger.land(
    cel,
    [
      for (final (column, under) in unders.indexed)
        (column: column, row: 0, under: under),
    ],
    by: (pool, cel, asked) {
      // A tile, not bytes of this call's: the store's copy reads them once
      // it returns, holding what keeps them (GpuPool.store).
      final tile = BitmapTile.written(
        size: gpuTileSide,
        write: (pixels) => pixels.fillRange(0, gpuTileBytes, value),
      );
      return [
        for (final at in pool.store(cel, [
          for (final _ in asked) tile,
        ], (tile) => tile.readPixels((pointer, _) => pointer)))
          (change: GpuChange.inked, tile: at),
      ];
    },
    compared: true,
  ))
    landed.tile!,
];

/// A tile of bytes of its own — nothing but its first pixel, barely there:
/// not of one colour, every tile of which shares that colour's slot on the
/// engine and its picture (`BitmapTile.pixelsKey`). What a test that fills
/// or counts slots or pictures asks for: each of these is one. Of the
/// engine's side where no [size] is given.
BitmapTile aTileOfItsOwn({int? size}) => BitmapTile.written(
  size: size ?? gpuTileSide,
  write: (pixels) => pixels
    ..fillRange(0, pixels.length, 0)
    ..[BitmapTile.bytesPerPixel - 1] = 1,
);
