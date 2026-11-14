import 'dart:ffi';

import 'package:ffi/ffi.dart';
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
      final bytes = calloc<Uint8>(gpuTileBytes);
      try {
        bytes.asTypedList(gpuTileBytes).fillRange(0, gpuTileBytes, value);
        return [
          for (final at in pool.store(cel, [for (final _ in asked) bytes]))
            (change: GpuChange.inked, tile: at),
        ];
      } finally {
        calloc.free(bytes);
      }
    },
    compared: true,
  ))
    landed.tile!,
];
