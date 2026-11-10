import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/native/engine_tile_ledger.dart';

/// [tile]'s pixels as the engine alone holds them, as a landing leaves a
/// tile: what a read has to ask the GPU for.
BitmapTile tileOnEngine(BitmapTile tile) =>
    EngineTileLedger.instance.debugOnEngine(tile);

/// [surface], every tile of it the engine's alone ([tileOnEngine]).
BitmapSurface surfaceOnEngine(BitmapSurface surface) =>
    surface.withRebuiltTiles({
      for (final MapEntry(:key, :value) in surface.tiles.entries)
        key: tileOnEngine(value),
    });
