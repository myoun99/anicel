import 'dart:ffi';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';

/// A tile the engine holds and its cel's kept bytes hold besides — a shell
/// of a cel a look let go of (card `let-go-cels-keep-their-gpu-tiles`) — is
/// never the engine's alone ([BitmapTile.isOnlyOnEngine]): a full pool lets
/// its slot go as freely as one whose bytes are here, where a tile the
/// engine alone holds is read back first.
void main() {
  test('a tile kept besides the engine is not the engine\'s alone; one the '
      'engine alone holds is', () {
    final besides = BitmapTile.onEngine(
      size: defaultCelTileSize,
      on: _KeptBesides(),
    );
    final alone = BitmapTile.onEngine(
      size: defaultCelTileSize,
      on: _OnEngine(),
    );

    expect(besides.isOnEngine, isTrue);
    expect(besides.isOnlyOnEngine, isFalse);
    expect(alone.isOnlyOnEngine, isTrue);
  });
}

final class _OnEngine implements TilePixelsOnEngine {
  @override
  void readInto(BitmapTile tile, Pointer<Uint8> into) {}
}

final class _KeptBesides implements TilePixelsKeptBesides {
  @override
  void readInto(BitmapTile tile, Pointer<Uint8> into) {}
}
