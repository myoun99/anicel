import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/brush_frame_key.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/ui/canvas/selection_float_overlay.dart';

/// A float is nobody's cel, and every float is counted under the ONE name
/// for that ([BrushFrameKey.noCel]), not a name of its own: the picture
/// budget and the engine ledger keep a count for every name they are
/// given, so a name made a float would grow them with every paint.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  BitmapSurface surfaceOf(int seed) => BitmapSurface(
    canvasSize: const CanvasSize(width: 16, height: 16),
    tileSize: 16,
    tiles: {
      TileCoord(x: 0, y: 0): BitmapTile(
        size: 16,
        pixels: Uint8List(16 * 16 * 4)..fillRange(0, 4, seed),
      ),
    },
  );

  test("every float's painter names nobody's cel by its one name", () {
    for (final seed in [1, 2]) {
      expect(
        floatPainter(surfaceOf(seed), const []).lineage,
        same(BrushFrameKey.noCel),
      );
    }
  });
}
