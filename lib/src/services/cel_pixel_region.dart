import 'dart:math' as math;
import 'dart:typed_data';

import '../models/bitmap_surface.dart';
import '../models/canvas_point.dart';
import '../models/canvas_size.dart';
import '../models/pasteboard_bounds.dart';
import '../models/transform_track.dart' show TransformPose;
import 'layer_pose_matrix.dart' show canvasToArtwork;
import 'canvas_selection.dart' show SelectionMaskOptions, buildSelectionMask;
import 'canvas_selection_region.dart';
import 'cel_pixel_overwrite.dart';

/// WHICH PIXELS a pixel verb acts on — 선택 있으면 그 영역, 없으면 전체.
///
/// The user stated that law three separate times, for three separate verbs
/// (픽셀 비우기, 픽셀 복사, and 색 변환), so it is a law rather than a
/// preference and lives in exactly one place. "전체" means the whole
/// drawing including the pasteboard, not the canvas rectangle: artwork
/// parked off-stage is still the drawing.
///
/// Returns a walk in the shape [overwriteCelPixels] consumes. Build it
/// fresh at each execution rather than storing it in a command: a walk
/// closes over its mask, and an undo entry that held one would keep
/// megabytes alive for the rest of the session — the very thing the recipe
/// design exists to avoid.
CelPixelWalk celPixelWalkFor({
  required BitmapSurface surface,
  CanvasSelectionRegion? region,
  SelectionMaskOptions options = SelectionMaskOptions.none,
}) {
  // Tile order is a CONTRACT, not an incidental: a recipe stores its values
  // positionally, so undo must revisit the tiles in the same sequence. The
  // surface's tile map preserves insertion order, which a commit elsewhere
  // could perfectly well change between the forward pass and the undo, so
  // the order is imposed here instead of borrowed.
  final coords = surface.tiles.keys.toList()
    ..sort((a, b) => a.y != b.y ? a.y - b.y : a.x - b.x);

  if (region == null || region.steps.isEmpty) {
    return (visit) {
      for (final coord in coords) {
        visit(coord, null);
      }
    };
  }

  final tileSize = surface.tileSize;
  final canvasSize = surface.canvasSize;
  // Coverage, not the tight fold: the mask must be allocated over every
  // pixel a step could have added, and the fold zeroes what a 삭제 took
  // back. Padded for the post-passes, then clipped to the pasteboard wall.
  final bounds = region.coverageBounds;
  final pad = options.bboxPad;
  final left = math.max(canvasSize.pasteboardLeft, bounds.left.floor() - pad);
  final top = math.max(canvasSize.pasteboardTop, bounds.top.floor() - pad);
  final right = math.min(
    canvasSize.pasteboardRightExclusive,
    bounds.right.ceil() + 1 + pad,
  );
  final bottom = math.min(
    canvasSize.pasteboardBottomExclusive,
    bounds.bottom.ceil() + 1 + pad,
  );
  if (right <= left || bottom <= top) {
    return (visit) {};
  }
  final width = right - left;
  final height = bottom - top;

  // ONE mask over the whole region, sliced per tile — not one mask per
  // tile. The post-passes (grow/feather/AA) read neighbouring pixels, so a
  // tile rasterized on its own would soften against its own edge and leave
  // a seam at every tile boundary.
  final mask = buildSelectionMask(
    region: region,
    options: options,
    left: left,
    top: top,
    width: width,
    height: height,
  );

  return (visit) {
    // One reusable tile buffer: the kernel reads the mask inside the visit
    // and never keeps it.
    final tileMask = Uint8List(tileSize * tileSize);
    for (final coord in coords) {
      final tileLeft = coord.x * tileSize;
      final tileTop = coord.y * tileSize;
      final startX = math.max(tileLeft, left);
      final endX = math.min(tileLeft + tileSize, right);
      final startY = math.max(tileTop, top);
      final endY = math.min(tileTop + tileSize, bottom);
      if (endX <= startX || endY <= startY) {
        continue;
      }
      tileMask.fillRange(0, tileMask.length, 0);
      final runLength = endX - startX;
      for (var y = startY; y < endY; y += 1) {
        final tileRow = (y - tileTop) * tileSize + (startX - tileLeft);
        final maskRow = (y - top) * width + (startX - left);
        tileMask.setRange(tileRow, tileRow + runLength, mask, maskRow);
      }
      visit(coord, tileMask);
    }
  };
}

/// [region], stated in the pixels of a layer POSED by [pose].
///
/// A selection is drawn on the canvas, but a cel's pixels are the layer's
/// own artwork: rotate or scale a layer and the two stop agreeing. This
/// verb runs across SEVERAL layers at once, each free to carry its own
/// pose, so the region has to be restated per layer or the pass would
/// recolour a different part of every posed row than the one the user
/// drew over.
///
/// The inverse is [canvasToArtwork] — the one the eyedropper's pick (R28 #7)
/// and the fill's raster ask — applied to the region's points instead of
/// to one pick. An unposed layer — the overwhelming majority — gets the
/// region back unchanged, so the pass stays byte-identical to what a lift
/// on the same selection would take.
///
/// Null when the pose is singular. ⚠️That is a BACKSTOP rather than a path:
/// [CameraPose] refuses a zero zoom outright, so no pose the model can hold
/// collapses a layer. `cel_pixel_region_test` pins that refusal, which is
/// what would tell a later round the guard had become reachable.
CanvasSelectionRegion? regionInArtworkSpace({
  required CanvasSelectionRegion region,
  required TransformPose? pose,
  required CanvasSize canvasSize,
  CanvasPoint? anchorPoint,
}) {
  if (pose == null) {
    return region;
  }
  final toArtwork = canvasToArtwork(
    (pose: pose, anchorPoint: anchorPoint),
    canvasSize,
  );
  return toArtwork == null ? null : region.mapped(toArtwork.apply);
}
