import '../models/bitmap_surface.dart';
import '../models/tile_coord.dart';
import 'brush_ground_color_mixing.dart';

/// How many sample points a side the ground average uses.
///
/// The average is estimated from a fixed grid rather than every covered
/// pixel, so a 1000px brush costs the same as a 10px one. Reading the real
/// area would be ~780k pixel reads per dab at pointer frequency — the exact
/// per-dab canvas read the commit pipeline was rebuilt to avoid.
const int brushGroundSampleGridSide = 8;

/// Averages the colour already on [surface] under a dab.
///
/// Only painted pixels count: transparent ones carry RGB 0, so letting them
/// into the mean would drag every mixing stroke toward black. The returned
/// coverage is how much of the sampled disc was painted, which the mixer
/// uses to scale how much colour the brush lifts.
///
/// The disc is sampled as a circle even for elliptical or rotated tips —
/// this is an average colour, not a coverage mask, and the difference is
/// far below what mixing can show.
BrushGroundSample sampleBitmapSurfaceGround(
  BitmapSurface surface, {
  required double centerX,
  required double centerY,
  required double radius,
  int gridSide = brushGroundSampleGridSide,
}) {
  if (radius <= 0.0 || !radius.isFinite) {
    return BrushGroundSample.empty;
  }
  // Bucket the sample points by tile so each tile is opened once: the tile
  // bytes are only valid inside `readPixels`.
  final pointsByTile = <TileCoord, List<int>>{};
  final tileSize = surface.tileSize;
  final step = (radius * 2) / gridSide;
  var considered = 0;

  for (var row = 0; row < gridSide; row += 1) {
    final sampleY = centerY - radius + step * (row + 0.5);
    for (var column = 0; column < gridSide; column += 1) {
      final sampleX = centerX - radius + step * (column + 0.5);
      final dx = sampleX - centerX;
      final dy = sampleY - centerY;
      if (dx * dx + dy * dy > radius * radius) {
        continue;
      }
      considered += 1;
      final pixelX = sampleX.floor();
      final pixelY = sampleY.floor();
      final coord = TileCoord(
        x: _floorDiv(pixelX, tileSize),
        y: _floorDiv(pixelY, tileSize),
      );
      if (!surface.containsTileCoord(coord)) {
        continue;
      }
      final localX = pixelX - coord.x * tileSize;
      final localY = pixelY - coord.y * tileSize;
      (pointsByTile[coord] ??= <int>[]).add((localY * tileSize + localX) * 4);
    }
  }
  if (considered == 0) {
    return BrushGroundSample.empty;
  }

  var weightedRed = 0.0;
  var weightedGreen = 0.0;
  var weightedBlue = 0.0;
  var alphaTotal = 0.0;

  for (final entry in pointsByTile.entries) {
    final tile = surface.tileAt(entry.key);
    if (tile == null) {
      // An unpainted tile is bare canvas; it contributes nothing but still
      // counts against coverage through `considered`.
      continue;
    }
    tile.readPixels((_, pixels) {
      for (final offset in entry.value) {
        if (offset + 3 >= pixels.length) {
          continue;
        }
        final alpha = pixels[offset + 3] / 255.0;
        if (alpha <= 0.0) {
          continue;
        }
        weightedRed += pixels[offset] * alpha;
        weightedGreen += pixels[offset + 1] * alpha;
        weightedBlue += pixels[offset + 2] * alpha;
        alphaTotal += alpha;
      }
    });
  }

  if (alphaTotal <= 0.0) {
    return BrushGroundSample.empty;
  }
  final red = (weightedRed / alphaTotal).round().clamp(0, 255);
  final green = (weightedGreen / alphaTotal).round().clamp(0, 255);
  final blue = (weightedBlue / alphaTotal).round().clamp(0, 255);
  return BrushGroundSample(
    rgb: (red << 16) | (green << 8) | blue,
    coverage: (alphaTotal / considered).clamp(0.0, 1.0),
  );
}

int _floorDiv(int value, int divisor) =>
    value >= 0 ? value ~/ divisor : -(((-value) + divisor - 1) ~/ divisor);

/// A sampler bound to [surface], ready for [BrushGroundColorMixer.apply].
BrushGroundColorSampler bitmapSurfaceGroundSampler(BitmapSurface surface) {
  return (x, y, radius) =>
      sampleBitmapSurfaceGround(surface, centerX: x, centerY: y, radius: radius);
}
