import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/composite_tree.dart';
import 'package:anicel/src/models/layer_blend_mode.dart';
import 'package:anicel/src/models/pasteboard_bounds.dart';
import 'package:anicel/src/models/project_background.dart';
import 'package:anicel/src/models/rgba_color.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/services/bitmap_tile_rgba.dart';
import 'package:anicel/src/ui/canvas/bitmap_surface_painter.dart';
import 'package:anicel/src/ui/canvas/canvas_layer_stack_view.dart';
import 'package:anicel/src/ui/playback/stacked_frame_picture.dart';

/// 🚨A FRAME COVERS ITS PAGE AND WHAT ITS ROWS DRAW — however far a view
/// zooms out, and never the pasteboard it could draw on: three pages a side
/// is nine times what a frame holds.
///
/// ↩️It stood as the editing canvas's buffer staying under its cap at every
/// zoom, until the engine kept a frame in tiles and no buffer had a cap.
void main() {
  const canvasSize = CanvasSize(width: 3000, height: 2000);
  const row = CompositeLeaf<CanvasStackRow>(CanvasActiveLayerRow(opacity: 1));

  BitmapSurfacePainter inkedPage() {
    final tile = writeRgbaColorToBitmapTile(
      tile: BitmapTile.blank(size: defaultCelTileSize),
      x: 4,
      y: 4,
      color: RgbaColor(r: 0, g: 0, b: 255, a: 255),
    );
    return BitmapSurfacePainter(
      surface: BitmapSurface(
        canvasSize: canvasSize,
        tiles: {TileCoord(x: 0, y: 0): tile},
      ),
      showTransparentBackground: false,
    );
  }

  Rect worldOf(List<CompositeNode<CanvasStackRow>> nodes) => stackedFrameOf(
    nodes,
    page: (
      canvasSize: canvasSize,
      pasteboardReach: PasteboardReach.whole,
      paintPaper: true,
      paperBackground: ProjectBackground.defaultBackground,
    ),
    surfaceOf: (_) => null,
    live: (
      rows: (
        activeSurfacePainter: inkedPage(),
        floatOverlay: null,
        liftedRows: const {},
      ),
      painters: LiftedRowPainters(),
    ),
  ).extent;

  test('a row inside the page covers the page', () {
    expect(worldOf(const [row]), canvasSize.canvasRect);
  });

  test('so does a folder holding it', () {
    expect(
      worldOf(const [
        CompositeGroup<CanvasStackRow>(
          children: [row],
          opacity: 0.5,
          blendMode: LayerBlendMode.normal,
        ),
      ]),
      canvasSize.canvasRect,
    );
  });
}
