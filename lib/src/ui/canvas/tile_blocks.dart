import 'dart:math' as math;

import '../../core/floor_math.dart';
import '../../models/bitmap_surface.dart';
import '../../models/dirty_region.dart';
import '../../models/placed_tile.dart';
import 'tile_origin.dart';

/// The edge, in pixels, of the square blocks a compose gathers a surface's
/// tiles into — so the tiles that have no picture are pictured a block at a
/// time ([tileBlocksOf]), not a tile at a time.
///
/// A picture made fresh costs the raster thread as a texture, not as
/// pixels: the first play of a cut drew some 250 of them a cel, 13–36 ms of
/// the raster thread a cel (board a-cold-cel-composes-tile-by-tile).
///
/// 🔬256, measured 2026-10-15 on the Windows app (profile build, Impeller
/// GLES; a cold cel of 199 tiles of 128 px, twelve rounds, medians) — the
/// UI thread making the pictures · the raster thread's snapshot of them:
/// a tile at a time 6.7 · 26.3 ms, blocks of 256 px 6.4 · 10.5, of 512 px
/// 10.0 · 8.8 (1024 px, five rounds: 11.7 · 11.6). The upload call costs
/// by the byte up to 256 px — 4 MB in 0.6–1.2 ms as 64 or 16 pictures —
/// and twice that as four of 512 (1.4–2.4 ms): a megabyte a picture costs
/// the engine more than its bytes. So 256: nearly all of the raster's
/// saving, the UI thread's cost a tile at a time's. The cel as ONE picture
/// snapshotted in 14–21 ms. In the first play of a cut (a user's project,
/// cuts 2→3→5, the same build either way by turns, four runs a road) the
/// raster waits of the app frames that ran past a film frame came to
/// 189–1,817 ms a tile at a time and 0–71 ms in blocks of 512 or 256.
const int tileBlockEdge = 256;

/// One picture's worth of a surface's tiles: [tiles], all inside [region].
typedef TileBlock = ({DirtyRegion region, List<PlacedTile> tiles});

/// [surface]'s tiles gathered into blocks of [tileBlockEdge] pixels a side
/// — as many whole tiles as fit, one at least — each with the region a
/// picture of it covers: the rect of the tiles it has ([tileCoordsWorldRect]),
/// so a part-filled block uploads its tiles' rect and not its square.
///
/// 🔬Regions of a power of two of tiles were tried for the halving's sake —
/// on such a texture a bilinear sample sits at an exact binary fraction —
/// and measured against these plain rects (2026-10-15): the Windows app
/// (Impeller GLES, a cel of 199 tiles of noise), the Vulkan tester and the
/// Skia tester each drew them 0 channels apart, 1:1 and halved, from the
/// cel pictured a tile at a time. The rule bought nothing measured, so the
/// plain rect stands.
List<TileBlock> tileBlocksOf(BitmapSurface surface) {
  final tileSize = surface.tileSize;
  final perSide = math.max(1, tileBlockEdge ~/ tileSize);
  final gathered = <(int, int), List<PlacedTile>>{};
  for (final entry in surface.tiles.entries) {
    final coord = entry.key;
    gathered
        .putIfAbsent(
          (floorDiv(coord.x, perSide), floorDiv(coord.y, perSide)),
          () => [],
        )
        .add((coord: coord, tile: entry.value));
  }
  return [
    for (final tiles in gathered.values)
      (region: _regionOf(tiles, tileSize), tiles: tiles),
  ];
}

DirtyRegion _regionOf(List<PlacedTile> tiles, int tileSize) {
  final rect = tileCoordsWorldRect(
    tiles.map((placed) => placed.coord),
    tileSize,
  )!;
  return DirtyRegion(
    left: rect.left.toInt(),
    top: rect.top.toInt(),
    rightExclusive: rect.right.toInt(),
    bottomExclusive: rect.bottom.toInt(),
  );
}
