import 'dart:typed_data';

import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/brush_frame_key.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/composite_tree.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/pasteboard_bounds.dart';
import 'package:anicel/src/models/project_background.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/native/engine_frame_tools.dart';
import 'package:anicel/src/services/canvas_flood_fill.dart';
import 'package:anicel/src/services/layer_pose_matrix.dart';
import 'package:anicel/src/ui/canvas/canvas_layer_stack_view.dart';
import 'package:anicel/src/ui/playback/stacked_frame_picture.dart';

/// A cel of [canvasSize] whose pixels are [pixels]' — straight RGBA at
/// canvas (x, y), off the canvas too — on the engine's tiles, the only
/// side it reads.
BitmapSurface celOfPixels(
  CanvasSize canvasSize,
  Map<(int, int), List<int>> pixels,
) {
  const side = defaultCelTileSize;
  final buffers = <TileCoord, Uint8List>{};
  for (final MapEntry(key: (x, y), value: rgba) in pixels.entries) {
    final coord = TileCoord.fromPixel(pixelX: x, pixelY: y, tileSize: side);
    buffers
        .putIfAbsent(coord, () => Uint8List(BitmapTile.bytesFor(side)))
        .setAll(
          ((y - coord.y * side) * side + (x - coord.x * side)) * 4,
          rgba,
        );
  }
  return BitmapSurface(
    canvasSize: canvasSize,
    tileSize: side,
    tiles: {
      for (final MapEntry(key: coord, value: buffer) in buffers.entries)
        coord: BitmapTile(size: side, pixels: buffer),
    },
  );
}

/// A row of a frame a fill reads in a test: [cel] laid at [opacity] where
/// [placement] poses it.
typedef FillRow = ({
  BitmapSurface cel,
  double opacity,
  LayerPlacement? placement,
});

/// [cel] as a row a fill reads ([FillRow]).
FillRow fillRow(
  BitmapSurface cel, {
  double opacity = 1,
  LayerPlacement? placement,
}) => (cel: cel, opacity: opacity, placement: placement);

/// What a fill reads of a frame of [rows], bottom first, on a page of
/// [canvasSize] that paints no paper — the door [fillRangeAt] asks
/// ([FillPictureOver]) — in the canvas's space, or [space]'s: the engine's
/// own picture ([fillPictureOf]), of rows named here as a canvas names
/// them. A file using it opens the engine first (`opensTheEnginesScreens`).
///
/// ⚠️WHICH rows a canvas reads, and that it paints no paper, are the
/// canvas's own (`fillPictureOver`): pinned on a session, not here.
FillPictureOver fillPictureOfRows(
  List<FillRow> rows, {
  required CanvasSize canvasSize,
  LayerPlacement? space,
}) {
  BrushFrameKey keyOf(int row) => BrushFrameKey(
    projectId: const ProjectId('p'),
    trackId: const TrackId('t'),
    cutId: const CutId('c'),
    layerId: LayerId('row-$row'),
    frameId: const FrameId('f'),
  );

  final cels = {for (final (at, row) in rows.indexed) keyOf(at): row.cel};
  return (box) {
    final (:composite, :letters) = appEngineFrameToolsOpen!;
    return fillPictureOf(
      stackedFrameOf(
        [
          for (final (at, row) in rows.indexed)
            CompositeLeaf<CanvasStackRow>(
              CanvasLayerImageRequest(
                frameKey: keyOf(at),
                opacity: row.opacity,
                placement: row.placement,
              ),
            ),
        ],
        page: (
          canvasSize: canvasSize,
          pasteboardReach: PasteboardReach.whole,
          paintPaper: false,
          paperBackground: ProjectBackground.defaultBackground,
        ),
        surfaceOf: (cel) => cels[cel],
      ),
      composite,
      letters,
      box,
      space: space,
    );
  };
}
