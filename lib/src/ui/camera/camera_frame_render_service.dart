import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/painting.dart';

import '../../core/point_bounds.dart';
import '../../core/rgba_premultiply.dart';
import '../../models/bitmap_surface.dart';
import '../../models/camera_pose.dart';
import '../../models/canvas_size.dart';
import '../../models/composite_tree.dart';
import '../../models/pasteboard_bounds.dart';
import '../../models/project_background.dart';
import '../../services/camera_frame_corners.dart'
    show cameraFrameCornersInCanvas;
import '../../services/camera_projection_matrix.dart';
import '../../services/cut_frame_composite_plan.dart';
import '../canvas/bitmap_tile_image_cache.dart';
import '../../services/composite_effect_paint.dart';
import '../../services/layer_pose_paint.dart' show applyCameraProjection;
import '../../services/straight_rgba_image.dart';
import '../../services/viewport_transform_matrix.dart'
    show viewportOfSimilarity;
import '../canvas/display_resample.dart';
import '../canvas/layer_image_draw.dart';
import '../canvas/level_image.dart';
import '../canvas/paper_background.dart' show paintProjectPaper;
import '../canvas/subtree_image_composite.dart';
import '../canvas/tiled_surface_compose.dart';
import '../playback/camera_shot.dart' show outlineAtLevel, shotClipOnScreen;

/// Surfaces with at least this many pixels assemble their upload buffer in
/// a background isolate; smaller ones stay synchronous (the spawn/copy
/// overhead would dominate, and fake-async widget tests never pump real
/// isolates — production canvases are far above, test fixtures far below).
const int _uploadOffloadPixelThreshold = 512 * 512;

/// Test override for the isolate cutoff; null = [_uploadOffloadPixelThreshold].
@visibleForTesting
int? debugUploadOffloadPixelThreshold;

/// Test hatch: every row composed whole — what the byte-for-byte pins
/// render the ink against (`a_row_drawn_from_its_ink_is_the_same_bytes_test`).
@visibleForTesting
bool debugComposesRowsWhole = false;

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
    for (final entry in surface.tiles.entries)
      (
        originX: entry.key.x * entry.value.size,
        originY: entry.key.y * entry.value.size,
        size: entry.value.size,
        pixels: entry.value.pixels,
      ),
  ];
  final threshold =
      debugUploadOffloadPixelThreshold ?? _uploadOffloadPixelThreshold;
  final buffer = width * height >= threshold
      ? await Isolate.run(
          () => _assemblePremultipliedRgba(tiles, width, height),
        )
      : _assemblePremultipliedRgba(tiles, width, height);

  // 🚨Through [uploadRawRgba], not `ui.decodeImageFromPixels`: the SDK
  // function reports no failure to anyone, so the `Completer` that stood here
  // could only ever succeed. This is the whole-canvas upload — the exact size
  // at which an engine allocation is most likely to be refused — and its
  // callers are exports and bakes that would have waited on it forever.
  return uploadRawRgba(buffer, width: width, height: height);
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
          buffer[target] = mul255Round(pixels[source], alpha);
          buffer[target + 1] = mul255Round(pixels[source + 1], alpha);
          buffer[target + 2] = mul255Round(pixels[source + 2], alpha);
        }
        buffer[target + 3] = alpha;
        source += 4;
        target += 4;
      }
    }
  }
  return buffer;
}

/// Renders a composited cut frame as seen through the camera.
///
/// The output shows the camera view rect (the camera frame silhouette from
/// the canvas overlay): output center = pose center, one output pixel covers
/// `1 / (pose.zoom * outputSize/cameraFrameSize)` canvas pixels, and the
/// canvas appears rotated opposite to the camera's clockwise rotation.
class CameraFrameRenderService {
  const CameraFrameRenderService({this.background = const Color(0xFFFFFFFF)});

  /// Fills the whole output, including any area beyond the canvas edges.
  final Color background;

  /// [outputSize] defaults to [cameraFrameSize]; a smaller value renders a
  /// scaled-down preview of the exact same view.
  /// [layers] is the flat list; [nodes] is the composite TREE (group
  /// buffers included). Callers hand one or the other — a flat list is
  /// simply a tree of leaves.
  /// [overlayPass] draws in CANVAS space right after the picture, still
  /// inside the camera projection — the display-time annotations (the SE
  /// name tags) that never enter a composite cache. A tag lays its shot on
  /// the canvas itself (`ResolvedSeNameTag.shot`), so through this
  /// projection it stands still in the frame (I-67-Q1). A cel's render
  /// leaves it null — a cel is the artwork alone — but where the camera's
  /// work or the cut's guides are laid over it (CAM, I-89-Q18; I-105).
  ///
  /// 🚨★★★EVERY RENDER REDUCES AS THE CANVAS'S DISPLAY DOES
  /// ([displayLevelOf]): each row's image halved, a 2×2 box mean a time,
  /// until what is left of the reduction is over half ([displayResidualOf]),
  /// which the draw takes with the display's own filter
  /// ([filterQualityForDisplayScale]). A panel's picture asked for it first
  /// — the print a conte cell shows beside the canvas's live composite of
  /// the same cut (F-215, 유저 2026-09-30: 「축소시 이거 캔버스랑
  /// 같은규칙으로 안티low 필터같은거 동일적용한거맞나?」) — and the
  /// exports since (유저 2026-10-13, card video-export-speed-Q2: 「캔버스
  /// 규칙으로」): a film is what playback shows. ↩️The rest drew with one
  /// bilinear step down to a quarter and less, which samples 2×2 of each
  /// 4×4 and lets a line a pixel wide vanish between them (🔬10-13: at a
  /// camera zoom of 0.42 — the user's film runs at 0.42–0.52 — such a line
  /// went missing ten pixels and more at a stretch).
  ///
  /// [cutTo] cuts the picture at that canvas's edge where the projection
  /// lays it — the film shows no pasteboard (「페이스트보드는 포함 안
  /// 시킴」) — as playback cuts it ([shotClipOnScreen]): out to the whole
  /// pixels around where the rows end on their level's grid
  /// ([outlineAtLevel]), so the cut takes nothing of a pixel they cover in
  /// part. Only the rows and [paper]: [overlayPass] is laid over the cut.
  ///
  /// [paper] is laid under the rows on [cutTo]'s canvas as the canvas lays
  /// its paper with its rows ([paperRectAtLevel]) — a stage's, as playback
  /// lays it (`CanvasTrackStackView._unit`). ↩️A film laid it under the
  /// picture to the canvas's edge, where rows reduced to a level end in a
  /// pixel they cover in part, and the paper showed white through it — the
  /// line playback had too (playback-picture-is-not-the-canvas-picture,
  /// 유저 10-13: 「끝에 흰 선」).
  ///
  /// [rows] keeps the rows' pictures from one render to the next — a video
  /// run's (F-289-Q21). Each row's picture is asked of it, and what it
  /// hands out is its own: this render draws it and never lets it go.
  /// Without it every row is composed here and let go when the render is
  /// done.
  Future<ui.Image> renderThroughCamera({
    List<CutFrameCompositeLayer> layers = const [],
    List<CompositeNode<CutFrameCompositeLayer>>? nodes,
    required CameraPose pose,
    required CanvasSize cameraFrameSize,
    CanvasSize? outputSize,
    void Function(ui.Canvas canvas)? overlayPass,
    CanvasSize? cutTo,
    ProjectBackground? paper,
    RowPictures? rows,
  }) async {
    assert(
      paper == null || cutTo != null,
      'a paper is laid on the canvas its picture is cut to',
    );
    final tree = nodes ?? [for (final layer in layers) CompositeLeaf(layer)];
    final resolvedOutput = outputSize ?? cameraFrameSize;
    final previewScale = resolvedOutput.width / cameraFrameSize.width;
    // The scale the CTM below is at. A group that rasterises ITSELF needs it,
    // and a `Canvas` will not tell anyone. Rotation preserves scale, so the
    // projection's zoom is the whole answer.
    final cameraRasterScale = (previewScale * pose.zoom).abs();
    final level = displayLevelOf(cameraRasterScale);
    // 🚨A ROW IS COMPOSED AS ITS INK ALONE ONLY WHERE IT IS LAID DOWN TEXEL
    // FOR TEXEL — the playback cache's law (`inkCropDrawsTheSame`,
    // `LayerFrameImageCache.prepare`'s `inkSuffices`), asked of this route.
    // A projection that moves every canvas pixel onto an output pixel whole
    // draws the ink exactly as it draws the whole image; any other has a
    // crop laid back to the whole first ([drawPosedLayerImage]), which pays
    // again the raster the crop saved — and so does every render a kept row
    // is handed to, which is why [rows] has to vouch for all of them. A
    // canvas-size frame is drawn that way — the camera standing square over
    // it — and a camera-size one wherever its camera stands on whole pixels.
    // 🔬2026-10-13, the user's film (1,857 frames, card
    // export-folders-and-rows-at-their-extent): 151 → 132 s, the video's
    // bytes the same.
    final texelCopy = cameraMovesPixelsWhole(
      pose,
      cameraFrameSize,
      outputSize: resolvedOutput,
    );
    final rowsAsInk =
        texelCopy &&
        (rows?.laidTexelForTexel ?? true) &&
        !debugComposesRowsWhole;
    final layerImages = <CutFrameCompositeLayer, PositionedSurfaceImage>{};
    // What this render made, and so lets go of when it is done: every row's
    // picture that [rows] does not keep.
    final madeHere = <ui.Image>[];
    Future<void> composeImages(
      List<CompositeNode<CutFrameCompositeLayer>> list,
    ) async {
      // 🚨THE LOOP CHECKS A LOCAL OF ITS OWN FUNCTION (I-57, 2026-10-14):
      // [rows] is the method's, and a capture checked inside a loop is read
      // past its check by the AOT compiler — a null one kills the release
      // build (`a_value_checked_in_a_loop_is_read_through_a_local_test`).
      final kept = rows;
      for (final node in list) {
        switch (node) {
          case CompositeLeaf(payload: final layer):
            // Per-tile GPU compose (already-decoded tiles draw without any
            // new upload — the storyboard thumbnail after a stroke reuses
            // the editing canvas's tiles); the camera transform then
            // samples the composed full-res image exactly as before.
            //
            // 🚨POSITIONED, so the crop happens AFTER the pose. The
            // canvas-extent compose rasterised at the canvas origin, which
            // threw pasteboard tiles away BEFORE the layer's transform ran —
            // so artwork parked off-canvas and moved INTO frame by a pose
            // was on screen and missing from the file. Playback has always
            // cropped after (`composePositionedSurfaceImage`), and this is
            // what made the two disagree about the same frame.
            //
            // ⚠️This changes WHEN the crop happens, not whether. Off-canvas
            // artwork that the pose does not bring in stays out of an export
            // all the same, cut at the canvas's edge at the end ([cutTo]) —
            // 유저 확정: 「페이스트보드는 포함 안 시킴」.
            //
            // Cost is proportional to what is actually there: the positioned
            // compose only rasters a bigger rect when pasteboard tiles
            // exist, so a project that never parks artwork pays nothing.
            //
            // At [level]: the row is the picture the render draws, so a row
            // kept between renders is kept halved, and halved once.
            Future<PositionedSurfaceImage> compose() async {
              // Non-null without shouldAbort (on-demand render, never
              // abandoned).
              //
              // Somebody waits for every render made here — an export's
              // frame, a panel's picture — so a tile with no picture gets
              // one at once ([MissingTilePictures.madeAtOnce]).
              final composed = (await composePositionedSurfaceImage(
                layer.surface,
                reuse: BitmapTileImageCache.instance,
                missing: MissingTilePictures.madeAtOnce,
                over:
                    rowsAsInk &&
                        inkCropDrawsTheSame(
                          placement: layer.placement,
                          blendMode: layer.blendMode,
                          effects: layer.effects,
                        )
                    ? surfaceInkWorldRect(layer.surface)
                    : null,
              ))!;
              if (level == 0) {
                return composed;
              }
              try {
                return await _halved(composed, level);
              } finally {
                composed.image.dispose();
              }
            }

            if (kept != null) {
              layerImages[layer] = await kept.of(layer.surface, level, compose);
            } else {
              final composed = await compose();
              madeHere.add(composed.image);
              layerImages[layer] = composed;
            }
          case CompositeGroup(:final children):
            await composeImages(children);
          case CompositeAdjustment(:final children):
            await composeImages(children);
        }
      }
    }

    await composeImages(tree);

    final leafQuality = filterQualityForDisplayScale(
      displayResidualOf(cameraRasterScale),
    );

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

    // The canvas region this render can SEE, in CANVAS space — the space
    // the canvas is now in: the output rect pulled back through the camera
    // projection ([cameraFrameCornersInCanvas]), which is exactly the
    // editing stack's "visible rect" rule (R5b's lesson: ask whether it is
    // in shot). It used to be the camera frame anchored at the canvas
    // ORIGIN, which is only the right rect when the camera happens to sit
    // there: a panned or zoomed-out camera clipped group members that the
    // view plainly showed (invisible while a group only carried opacity and
    // a blend, fatal once it carries a blur).
    final visible = pointsBounds(
      cameraFrameCornersInCanvas(pose: pose, cameraFrameSize: cameraFrameSize),
    );
    // A sub-tree's buffer: what of it lies [within] what reads it — the shot
    // at the top, and under a folder that folder's buffer, which a blur on
    // it reads past the shot ([subtreeBufferBounds]). A row stands for its
    // content, never the ink alone it may be composed as ([rowsAsInk]).
    Rect bufferBoundsFor(
      CompositeNode<CutFrameCompositeLayer> node,
      Rect within,
    ) => subtreeBufferBounds(
      node,
      within: within,
      extentOf: (layer) => surfaceContentWorldRect(layer.surface),
      placementOf: (layer) => layer.placement,
    );
    void paintNodes(
      Canvas canvas,
      List<CompositeNode<CutFrameCompositeLayer>> list,
      double rasterScale,
      Rect within,
    ) {
      for (final node in list) {
        switch (node) {
          case CompositeGroup(
            :final children,
            :final opacity,
            :final blendMode,
            :final effects,
          ):
            // R27 #29: one buffer for the group, one blend on it.
            // R6: and one filter chain on it — the group's effects, in
            // CANVAS units (the camera projection is a canvas transform, so
            // Skia maps a blur's sigma through the CTM for us).
            final groupPlan = resolveCompositeEffectPlan(effects);
            final groupPaint = layerCompositePaint(
              opacity: opacity,
              blendMode: blendMode,
              effects: groupPlan.finalPaint,
            );
            // 🚨★★★A GROUP IS AN IMAGE HERE TOO. The editing stack and this
            // walk composite the same tree; if one of them kept a
            // `saveLayer` the folder would be samplable on screen and not in
            // the file, which is the asymmetry the whole round exists to
            // close.
            final bounds = effectBufferBounds(
              bufferBoundsFor(node, within),
              groupPlan.outsetPixels,
            );
            drawSubtreeAsImage(
              canvas: canvas,
              bounds: bounds,
              rasterScale: rasterScale,
              paintSubtree: (into, scale) =>
                  paintNodes(into, children, scale, bounds),
              compose: (blit) => blit(groupPaint),
              steps: groupPlan.preSteps,
            );
          case CompositeAdjustment(:final children, :final effects, :final mix):
            // R6b: the scope composes into one buffer and the row's chain
            // filters it there. Below full strength the scope is COMPOSED
            // twice — the mix is a crossfade, not a fade-out — but it is the
            // same picture both times, so it is rasterised once and blitted
            // twice. The outer `saveLayer` stays: it is an alpha group over
            // two draws of one image, not a buffer anything needs to sample.
            final pass = resolveAdjustmentScopePass(
              bounds: bufferBoundsFor(node, within),
              effects: effects,
              mix: mix,
            );
            drawSubtreeAsImage(
              canvas: canvas,
              bounds: pass.bufferBounds,
              rasterScale: rasterScale,
              paintSubtree: (into, scale) =>
                  paintNodes(into, children, scale, pass.bufferBounds),
              compose: composeAdjustmentScope(canvas, pass),
              steps: pass.preSteps,
            );
          case CompositeLeaf(payload: final layer):
            // Layer transforms apply at composite time (never baked);
            // identity layers skip the save/restore.
            final layerImage = layerImages[layer]!;
            // ★THE BYTE PIN IS KEPT WHERE IT APPLIED. `drawAtOrigin` is the
            // legacy `drawImage(Offset.zero)` path and its output is held to
            // the pixel by the composite parity suites — but it is only
            // EQUIVALENT while the composed image is the canvas rect. When
            // there are no pasteboard tiles that is still exactly what comes
            // back, so those renders take the same path they always did and
            // their bytes do not move. Only a surface with artwork outside
            // the canvas takes the general path, which is the case that was
            // broken.
            final canvasSize = layer.surface.canvasSize;
            drawPosedLayerImage(
              canvas,
              image: layerImage.image,
              // The ink alone where it was composed so ([rowsAsInk]), and
              // otherwise the whole content.
              worldRect: layerImage.worldRect,
              extent: surfaceContentWorldRect(layer.surface),
              placement: layer.placement,
              opacity: layer.opacity,
              blendMode: layer.blendMode,
              effects: layer.effects,
              // A texel copy where the projection moves pixels whole, at
              // the scale this canvas is at — a folder's buffer cut down to
              // its cap lays a crop back.
              texelScale: texelCopy ? rasterScale : null,
              filterQuality: leafQuality,
              // ⚠️And the image a texel a canvas pixel: a level
              // ([displayLevelOf]) spans the canvas at half and less, and
              // laid at the origin it would draw at that size.
              drawAtOriginWhen: (worldRect, image) =>
                  worldRect.left == 0 &&
                  worldRect.top == 0 &&
                  worldRect.width == canvasSize.width &&
                  worldRect.height == canvasSize.height &&
                  image.width == canvasSize.width &&
                  image.height == canvasSize.height,
            );
        }
      }
    }

    final projection = cameraProjectionMatrix(
      pose,
      cameraFrameSize,
      outputSize: resolvedOutput,
    );
    canvas.save();
    if (cutTo != null) {
      final cut = shotClipOnScreen(
        outlineAtLevel(cutTo.canvasRect, level: level, toScreen: projection),
        // An output pixel is the device's.
        1,
      );
      canvas.clipPath(
        Path()..addPolygon(cut.corners, true),
        doAntiAlias: cut.behavior == Clip.antiAlias,
      );
    }
    applyCameraProjection(
      canvas,
      pose,
      cameraFrameSize,
      outputSize: resolvedOutput,
    );
    if (paper != null) {
      final view = viewportOfSimilarity(projection);
      paintProjectPaper(
        canvas,
        paperRectAtLevel(cutTo!.canvasRect, level),
        paper,
        // The edge a level buffer gives its paper, seen through this
        // projection.
        antiAlias:
            view == null || displayEdgeAntiAliased(view, 1, level: level),
      );
    }
    paintNodes(canvas, tree, cameraRasterScale, visible);
    canvas.restore();
    if (overlayPass != null) {
      applyCameraProjection(
        canvas,
        pose,
        cameraFrameSize,
        outputSize: resolvedOutput,
      );
      overlayPass(canvas);
    }

    final picture = recorder.endRecording();
    try {
      return await picture.toImage(resolvedOutput.width, resolvedOutput.height);
    } finally {
      picture.dispose();
      for (final image in madeHere) {
        image.dispose();
      }
    }
  }
}

/// Where a render's row pictures come from when they are kept between
/// renders ([CameraFrameRenderService.renderThroughCamera]'s `rows`).
///
/// [of] hands back the picture [surface] composes to at [level]
/// ([displayLevelOf]) — one kept from an earlier render, or [compose]'s —
/// and it is the keeper's either way. It may be the ink alone
/// ([laidTexelForTexel]).
abstract interface class RowPictures {
  Future<PositionedSurfaceImage> of(
    BitmapSurface surface,
    int level,
    Future<PositionedSurfaceImage> Function() compose,
  );

  /// Whether every render a row kept here is handed to lays it down texel
  /// for texel — so one composed as its ink alone is never laid back whole
  /// to be drawn, which would pay that raster at every draw
  /// ([drawPosedLayerImage]).
  bool get laidTexelForTexel;
}

/// [composed] with its image halved [level] times over the same canvas
/// rect — each time the exact mean of a 2×2 block of the one above
/// ([halvingPicture]), as the display's own levels are made. The images
/// it passes through are let go of; [composed]'s own is its owner's, and
/// the one it hands back is the caller's.
Future<PositionedSurfaceImage> _halved(
  PositionedSurfaceImage composed,
  int level,
) async {
  var image = composed.image;
  for (var step = 0; step < level; step += 1) {
    final size = halvedSize(image.width, image.height);
    final picture = halvingPicture([(image: image, at: ui.Offset.zero)]);
    final ui.Image halved;
    try {
      halved = await picture.toImage(size.width, size.height);
    } finally {
      picture.dispose();
    }
    if (!identical(image, composed.image)) {
      image.dispose();
    }
    image = halved;
  }
  return PositionedSurfaceImage(image: image, worldRect: composed.worldRect);
}
