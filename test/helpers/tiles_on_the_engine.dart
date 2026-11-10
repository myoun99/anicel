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
