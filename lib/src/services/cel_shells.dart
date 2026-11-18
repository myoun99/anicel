import '../models/bitmap_surface.dart';

/// What keeps a cel's tiles on the engine once a look lets go of its
/// pixels here — the engine's tile ledger (card
/// `let-go-cels-keep-their-gpu-tiles`): the next look at the same kept
/// bytes is handed the tiles the engine still holds, where it thawed them
/// from the file again and put every one back on the engine.
abstract interface class CelShells {
  /// A shell of [surface] — its tiles, each holding the slot on the engine
  /// its own held and no bytes here (`TilePixelsKeptBesides`) — or null
  /// where the engine holds none of them. A tile of it whose slot the
  /// engine lets go reads its pixels from [readAgain]: the cel's kept bytes,
  /// as the look read them.
  BitmapSurface? shellOf(
    BitmapSurface surface, {
    required BitmapSurface Function() readAgain,
  });

  /// Whether every tile of [shell] still has its slot on the engine: a full
  /// pool lets a shell's slots go as freely as any whose bytes are here.
  bool isWhole(BitmapSurface shell);
}
