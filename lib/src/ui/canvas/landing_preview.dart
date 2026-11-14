import 'dart:ui';

import '../../models/bitmap_tile.dart';
import '../../models/tile_coord.dart';

/// What a pending landing will put over a surface, drawn over that
/// surface's coordinates before it lands — a selection's lifted float.
///
/// A leaf of its own so the surface pass can draw one without importing the
/// selection's files, which import the surface painter (the float carries a
/// painter of its own lift).
abstract interface class LandingPreview {
  /// Everything [paintInto] draws, in CANVAS space — [Rect.zero] when it
  /// draws nothing.
  Rect get drawnWorldRect;

  /// Draws the preview in CANVAS space, one canvas pixel to one of its own:
  /// the pixels the landing will write, as they will stand. [pixelRatio] is
  /// how many device pixels a unit of [canvas]'s space lands on past its
  /// transform — the screen's ratio on screen, 1 into a raster — the grid
  /// its edges are cut on (`cutOnThePixelGrid`).
  void paintInto(Canvas canvas, {required double pixelRatio});

  /// What [paintInto] draws, as the tiles it holds, in the order it draws
  /// them: what the engine lays over the row (flip lane ⓐ-2 — 「쥔 픽셀은
  /// 타일로 쥐고 그림은 거기서 낸다」).
  List<HeldTiles> get heldTiles;
}

/// Pixels a preview holds ([LandingPreview.heldTiles]) as [tiles], by their
/// coordinates — moved by ([dx], [dy]) in the preview's space, laid as
/// [laying] says, cut at the wall of the row they lie on, as its landing is.
typedef HeldTiles = ({
  Map<TileCoord, BitmapTile> tiles,
  double dx,
  double dy,
  HeldLaying laying,
});

/// How held pixels lie over what is under them.
sealed class HeldLaying {
  const HeldLaying();
}

/// Over it, source-over: a float's own pixels.
final class LaidOver extends HeldLaying {
  const LaidOver();
}

/// Taking it away by their alpha (destination-out): what a keyed float
/// clears under itself before it is laid.
final class LaidErasing extends HeldLaying {
  const LaidErasing();
}

/// In place of it over [region], in the preview's space: a landing, which
/// IS the cel there (`BlendMode.src`) — made in its cel's own space
/// (`FloatLandsOn.landingShown`), so its region is its row's pixels.
final class LaidReplacing extends HeldLaying {
  const LaidReplacing(this.region);

  final Rect region;
}
