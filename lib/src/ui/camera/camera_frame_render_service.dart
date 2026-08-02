import 'dart:async';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/painting.dart';

import '../../models/bitmap_surface.dart';
import '../../models/camera_pose.dart';
import '../../models/canvas_size.dart';
import '../../services/cut_frame_composite_plan.dart';
import '../canvas/bitmap_tile_image_cache.dart';
import '../canvas/composite_effect_paint.dart';
import '../canvas/layer_image_draw.dart';
import '../canvas/tiled_surface_compose.dart';

/// File name for one exported frame: `frame_0001.png` (1-based).
String cameraSequenceFileName(int frameIndex, {int digits = 4}) {
  return 'frame_${(frameIndex + 1).toString().padLeft(digits, '0')}.png';
}

/// Surfaces with at least this many pixels assemble their upload buffer in
/// a background isolate; smaller ones stay synchronous (the spawn/copy
/// overhead would dominate, and fake-async widget tests never pump real
/// isolates — production canvases are far above, test fixtures far below).
const int _uploadOffloadPixelThreshold = 512 * 512;

/// Test override for the isolate cutoff; null = [_uploadOffloadPixelThreshold].
@visibleForTesting
int? debugUploadOffloadPixelThreshold;

/// Converts a tiled [BitmapSurface] into one [ui.Image].
///
/// Tile bytes are straight (unpremultiplied) alpha but raw rgba8888 uploads
/// are interpreted as premultiplied, so the copy premultiplies with the same
/// mul-div-255 rounding the tile image cache uses. On canvas-sized surfaces
/// that per-pixel pass is the largest post-stroke chunk left on the UI
/// thread (debug builds especially), so it runs in a background isolate.
Future<ui.Image> bitmapSurfaceToImage(BitmapSurface surface) async {
  final width = surface.canvasSize.width;
  final height = surface.canvasSize.height;
  // Sendable snapshot: tile pixel buffers are copies already (the tile
  // getter clones), so the isolate borrows plain records.
  final tiles = [
    for (final tile in surface.tiles.values)
      (
        originX: tile.coord.x * tile.size,
        originY: tile.coord.y * tile.size,
        size: tile.size,
        pixels: tile.pixels,
      ),
  ];
  final threshold =
      debugUploadOffloadPixelThreshold ?? _uploadOffloadPixelThreshold;
  final buffer = width * height >= threshold
      ? await Isolate.run(
          () => _assemblePremultipliedRgba(tiles, width, height),
        )
      : _assemblePremultipliedRgba(tiles, width, height);

  final completer = Completer<ui.Image>();
  ui.decodeImageFromPixels(
    buffer,
    width,
    height,
    ui.PixelFormat.rgba8888,
    completer.complete,
  );
  return completer.future;
}

/// The full-canvas premultiplied upload buffer, assembled from straight-
/// alpha tile snapshots. Pure bytes → bytes so it runs identically on the
/// UI thread and in the offload isolate.
Uint8List _assemblePremultipliedRgba(
  List<({int originX, int originY, int size, Uint8List pixels})> tiles,
  int width,
  int height,
) {
  final buffer = Uint8List(width * height * 4);
  for (final tile in tiles) {
    final pixels = tile.pixels;
    // Clip BOTH sides to the canvas raster: pasteboard tiles sit at
    // negative origins (and past the right/bottom edge) — the canvas
    // image simply crops them.
    final startX = math.max(0, -tile.originX);
    final startY = math.max(0, -tile.originY);
    final copyWidth = math.min(tile.size, width - tile.originX);
    final copyHeight = math.min(tile.size, height - tile.originY);
    if (copyWidth <= startX || copyHeight <= startY) {
      continue;
    }
    for (var localY = startY; localY < copyHeight; localY += 1) {
      var source = (localY * tile.size + startX) * 4;
      var target =
          ((tile.originY + localY) * width + tile.originX + startX) * 4;
      for (var localX = startX; localX < copyWidth; localX += 1) {
        final alpha = pixels[source + 3];
        if (alpha == 255) {
          buffer[target] = pixels[source];
          buffer[target + 1] = pixels[source + 1];
          buffer[target + 2] = pixels[source + 2];
        } else if (alpha != 0) {
          buffer[target] = _mul255Round(pixels[source], alpha);
          buffer[target + 1] = _mul255Round(pixels[source + 1], alpha);
          buffer[target + 2] = _mul255Round(pixels[source + 2], alpha);
        }
        buffer[target + 3] = alpha;
        source += 4;
        target += 4;
      }
    }
  }
  return buffer;
}

/// Skia's `SkMulDiv255Round`: round(value * alpha / 255) for bytes.
int _mul255Round(int value, int alpha) {
  final product = value * alpha + 128;
  return (product + (product >> 8)) >> 8;
}

/// Renders a composited cut frame as seen through the camera.
///
/// The output shows the camera view rect (the camera frame silhouette from
/// the canvas overlay): output center = pose center, one output pixel covers
/// `1 / (pose.zoom * outputSize/cameraFrameSize)` canvas pixels, and the
/// canvas appears rotated opposite to the camera's clockwise rotation.
class CameraFrameRenderService {
  const CameraFrameRenderService({
    this.background = const Color(0xFFFFFFFF),
    this.filterQuality = FilterQuality.low,
  });

  /// Fills the whole output, including any area beyond the canvas edges.
  final Color background;

  final FilterQuality filterQuality;

  /// [outputSize] defaults to [cameraFrameSize]; a smaller value renders a
  /// scaled-down preview of the exact same view.
  /// [layers] is the flat list; [nodes] is the composite TREE (group
  /// buffers included). Callers hand one or the other — a flat list is
  /// simply a tree of leaves.
  /// [overlayPass] draws in CANVAS space right after the picture, still
  /// inside the camera projection — the display-time annotations (the SE
  /// name tags) that must scale with the artwork but never enter a
  /// composite cache. Cel renders leave it null: a cel is the artwork
  /// alone.
  Future<ui.Image> renderThroughCamera({
    List<CutFrameCompositeLayer> layers = const [],
    List<CutFrameCompositeSurfaceNode>? nodes,
    required CameraPose pose,
    required CanvasSize cameraFrameSize,
    CanvasSize? outputSize,
    void Function(ui.Canvas canvas)? overlayPass,
  }) async {
    final tree =
        nodes ??
        [for (final layer in layers) CutFrameCompositeSurfaceLeaf(layer)];
    final resolvedOutput = outputSize ?? cameraFrameSize;
    final layerImages = <CutFrameCompositeLayer, ui.Image>{};
    Future<void> composeImages(List<CutFrameCompositeSurfaceNode> list) async {
      for (final node in list) {
        switch (node) {
          case CutFrameCompositeSurfaceLeaf(:final layer):
            // Per-tile GPU compose (already-decoded tiles draw without any
            // new upload — the storyboard thumbnail after a stroke reuses
            // the editing canvas's tiles); the camera transform then
            // samples the composed full-res image exactly as before.
            layerImages[layer] =
                // Non-null without shouldAbort (on-demand render, never
                // abandoned).
                (await composeTiledSurfaceImage(
                  layer.surface,
                  reuse: BitmapTileImageCache.instance,
                ))!;
          case CutFrameCompositeSurfaceGroup(:final children):
            await composeImages(children);
          case CutFrameCompositeSurfaceAdjustment(:final children):
            await composeImages(children);
        }
      }
    }

    await composeImages(tree);

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawRect(
      Rect.fromLTWH(
        0,
        0,
        resolvedOutput.width.toDouble(),
        resolvedOutput.height.toDouble(),
      ),
      Paint()..color = background,
    );

    final previewScale = resolvedOutput.width / cameraFrameSize.width;
    canvas.translate(resolvedOutput.width / 2, resolvedOutput.height / 2);
    canvas.scale(previewScale * pose.zoom);
    // The camera is rotated clockwise over the canvas, so the world appears
    // rotated the opposite way through it.
    canvas.rotate(-pose.rotationDegrees * math.pi / 180);
    canvas.translate(-pose.center.x, -pose.center.y);

    // The group buffer's size hint, in CANVAS space — the space the canvas
    // is now in. It used to be the camera frame anchored at the canvas
    // ORIGIN, which is only the right rect when the camera happens to sit
    // there: a panned or zoomed-out camera clipped group members that the
    // view plainly showed (invisible while a group only carried opacity and
    // a blend, fatal once it carries a blur). What actually matters is the
    // canvas region this render can SEE — the output rect pulled back
    // through the camera projection, which is exactly the editing stack's
    // "visible rect" rule (R5b's lesson: ask whether it is in shot).
    final visibleHalfWidth =
        resolvedOutput.width / 2 / (previewScale * pose.zoom);
    final visibleHalfHeight =
        resolvedOutput.height / 2 / (previewScale * pose.zoom);
    // Rotation turns the rect; the circumscribing half-extent (the
    // rectangle's own half-diagonal) covers every angle without a matrix.
    final visibleRadius = math.sqrt(
      visibleHalfWidth * visibleHalfWidth +
          visibleHalfHeight * visibleHalfHeight,
    );
    final groupBounds = Rect.fromCircle(
      center: Offset(pose.center.x, pose.center.y),
      radius: visibleRadius,
    );
    void paintNodes(List<CutFrameCompositeSurfaceNode> list) {
      for (final node in list) {
        switch (node) {
          case CutFrameCompositeSurfaceGroup(
            :final children,
            :final opacity,
            :final blendMode,
            :final effects,
          ):
            // R27 #29: one buffer for the group, one blend on it.
            // R6: and one filter chain on it — the group's effects, in
            // CANVAS units (the camera projection is a canvas transform, so
            // Skia maps a blur's sigma through the CTM for us).
            final groupEffects = resolveCompositeEffectPaint(effects);
            final groupPaint = Paint()
              ..color = Color.fromRGBO(0, 0, 0, opacity)
              ..blendMode = blendMode.paintBlendMode;
            groupEffects.applyTo(groupPaint);
            canvas.saveLayer(
              effectBufferBounds(groupBounds, groupEffects),
              groupPaint,
            );
            paintNodes(children);
            canvas.restore();
          case CutFrameCompositeSurfaceAdjustment(
            :final children,
            :final effects,
            :final mix,
          ):
            // R6b: the scope composes into one buffer and the row's chain
            // filters it there. Below full strength the scope is drawn
            // twice — the mix is a crossfade, not a fade-out.
            final pass = resolveAdjustmentScopePass(
              bounds: groupBounds,
              effects: effects,
              mix: mix,
            );
            if (pass.crossfades) {
              canvas.saveLayer(pass.bufferBounds, pass.crossfadeLayerPaint!);
              canvas.saveLayer(pass.bufferBounds, pass.unfilteredPaint!);
              paintNodes(children);
              canvas.restore();
            }
            canvas.saveLayer(pass.bufferBounds, pass.filteredPaint);
            paintNodes(children);
            canvas.restore();
            if (pass.crossfades) {
              canvas.restore();
            }
          case CutFrameCompositeSurfaceLeaf(:final layer):
            // Layer transforms apply at composite time (never baked);
            // identity layers skip the save/restore.
            final layerImage = layerImages[layer]!;
            drawPosedLayerImage(
              canvas,
              image: layerImage,
              worldRect: Rect.fromLTWH(
                0,
                0,
                layerImage.width.toDouble(),
                layerImage.height.toDouble(),
              ),
              canvasSize: layer.surface.canvasSize,
              pose: layer.pose,
              anchorPoint: layer.anchorPoint,
              opacity: layer.opacity,
              blendMode: layer.blendMode,
              effects: layer.effects,
              filterQuality: filterQuality,
              // This route has always drawn its canvas-extent image whole,
              // and a camera test pins its pixels exactly.
              drawAtOrigin: true,
            );
        }
      }
    }

    paintNodes(tree);
    overlayPass?.call(canvas);

    final picture = recorder.endRecording();
    try {
      return await picture.toImage(resolvedOutput.width, resolvedOutput.height);
    } finally {
      picture.dispose();
      for (final image in layerImages.values) {
        image.dispose();
      }
    }
  }
}
