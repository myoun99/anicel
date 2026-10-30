import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/painting.dart';

import '../../core/point_bounds.dart';
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
import '../canvas/composite_tree_paint.dart';
import '../../services/layer_pose_matrix.dart' show LayerPlacement;
import '../../services/layer_pose_paint.dart' show applyCameraProjection;
import '../../services/viewport_transform_matrix.dart'
    show viewportOfSimilarity;
import '../canvas/display_resample.dart';
import '../canvas/fx_plugin_stages.dart';
import '../canvas/image_pieces.dart';
import '../canvas/layer_image_draw.dart';
import '../canvas/paper_background.dart' show paintProjectPaper;
import '../canvas/subtree_image_composite.dart' show RowPainter;
import '../canvas/tiled_surface_compose.dart';
import '../playback/camera_shot.dart' show outlineThrough, shotClipOnScreen;

/// Test hatch: every row composed whole — what the byte-for-byte pins
/// render the ink against (`a_row_drawn_from_its_ink_is_the_same_bytes_test`).
@visibleForTesting
bool debugComposesRowsWhole = false;

/// What a render lays over its picture, in CANVAS space under the camera's
/// projection — handed the scale that projection rasters a canvas pixel at,
/// which a `Canvas` will not tell anyone: a pass that rasters a picture of
/// its own (an SE tag with its row's effects) asks it as a folder does.
typedef CameraOverlayPass = void Function(ui.Canvas canvas, double rasterScale);

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
  /// ([filterQualityForDisplayScale]): each row's picture at canvas
  /// resolution, reduced by the GPU from its own mip chain at the display's
  /// filter — as a frame's one picture is (one-picture-per-frame, 유저
  /// D7-2-Q2 「배율이 어떻든 항상 원본 한장」). A panel's picture asked for it
  /// first — the print a conte cell shows beside the canvas's live composite
  /// of the same cut (F-215, 유저 2026-09-30: 「축소시 이거 캔버스랑
  /// 같은규칙으로 안티low 필터같은거 동일적용한거맞나?」) — and the
  /// exports since (유저 2026-10-13, card video-export-speed-Q2: 「캔버스
  /// 규칙으로」): a film is what playback shows. ↩️Each row's image was
  /// halved, a 2×2 box mean a time, until what was left of the reduction was
  /// over half, while the canvas's display did so — until ②-5b-3. ↩️Before
  /// that the rest drew with one bilinear step down to a quarter and less,
  /// which samples 2×2 of each 4×4 and lets a line a pixel wide vanish
  /// between them (🔬10-13: at a camera zoom of 0.42 — the user's film runs
  /// at 0.42–0.52 — such a line went missing ten pixels and more at a
  /// stretch); a chain is that 2×2 mean, level by level.
  ///
  /// [canvasSize] is the canvas the rows are laid on — a cut's — and where
  /// a folder's blur that repeats the paper's edge finds it (I-132-Q14 a).
  ///
  /// [cutsToTheCanvas] cuts the picture at the canvas's edge where the
  /// projection lays it — the film shows no pasteboard (「페이스트보드는 포함
  /// 안 시킴」) — as playback cuts it ([shotClipOnScreen]): out to the whole
  /// pixels around where the rows end, the canvas's own edge
  /// ([outlineThrough]), so the cut takes nothing of a pixel they cover in
  /// part. ↩️On their level's grid while the rows were halved (until
  /// one-picture-per-frame ②-5b-3). Only the rows and [paper]:
  /// [overlayPass] is laid over the cut.
  ///
  /// [paper] is laid under the rows on the canvas they are cut to, as the
  /// canvas lays its paper with its rows — a stage's, as playback lays it
  /// (`CanvasTrackStackView._unit`) — yielding the pixel the canvas's edge
  /// falls inside to the rows ([_paperYieldingToTheRows]). ↩️A film laid
  /// it under the picture to the canvas's edge, where rows reduced to a
  /// level end in a pixel they cover in part, and the paper showed white
  /// through it — the line playback had too
  /// (playback-picture-is-not-the-canvas-picture, 유저 10-13: 「끝에 흰
  /// 선」).
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
    CameraOverlayPass? overlayPass,
    required CanvasSize canvasSize,
    bool cutsToTheCanvas = false,
    ProjectBackground? paper,
    RowPictures? rows,
  }) async {
    assert(
      paper == null || cutsToTheCanvas,
      'a paper is laid on the canvas its picture is cut to',
    );
    // A row in an advanced blend is composed over what lies below it
    // (brush-fidelity-Q4) — the plan's tree is already; a flat list is here.
    final rowNodes =
        nodes ??
        composeOverTheirBackdrops(
          [for (final layer in layers) CompositeLeaf(layer)],
          blendOf: (layer) => layer.blendMode,
          paintedNormal: (layer) => layer.paintedNormal(),
        );
    // ⚠️The ground is laid under the rows as well as around the shot, so it
    // has to be one a second coat leaves as it was: opaque, or nothing —
    // the export's grounds are white, black or none.
    assert(
      background.a == 0 || background.a == 1,
      'a ground of $background would lie twice where the rows are laid',
    );
    final tree = onUnderlay(
      mapCompositeLeaves<CutFrameCompositeLayer, _CameraRow>(
        rowNodes,
        _CameraLayer.new,
      ),
      const _CameraGround(),
    );
    final resolvedOutput = outputSize ?? cameraFrameSize;
    final previewScale = resolvedOutput.width / cameraFrameSize.width;
    // The scale the CTM below is at. A group that rasterises ITSELF needs it,
    // and a `Canvas` will not tell anyone. Rotation preserves scale, so the
    // projection's zoom is the whole answer.
    final cameraRasterScale = (previewScale * pose.zoom).abs();
    // 🚨A ROW IS COMPOSED AS ITS INK ALONE ONLY WHERE IT IS LAID DOWN TEXEL
    // FOR TEXEL — `inkCropDrawsTheSame`, asked of this route. ↩️The playback
    // cache asked it of its rows too, until it kept no row image
    // (one-picture-per-frame ②-5b-1).
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
    final madeHere = <ImagePiece>[];
    Future<void> composeImages(
      List<CompositeNode<_CameraRow>> list,
    ) async {
      // 🚨THE LOOP CHECKS A LOCAL OF ITS OWN FUNCTION (I-57, 2026-10-14):
      // [rows] is the method's, and a capture checked inside a loop is read
      // past its check by the AOT compiler — a null one kills the release
      // build (`a_value_checked_in_a_loop_is_read_through_a_local_test`).
      final kept = rows;
      for (final node in list) {
        switch (node) {
          case CompositeLeaf(payload: _CameraLayer(:final layer)):
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
            // all the same, cut at the canvas's edge at the end
            // ([cutsToTheCanvas]) — 유저 확정: 「페이스트보드는 포함 안 시킴」.
            //
            // Cost is proportional to what is actually there: the positioned
            // compose only rasters a bigger rect when pasteboard tiles
            // exist, so a project that never parks artwork pays nothing.
            //
            // At canvas resolution, whatever the camera's zoom: the row is
            // the picture the render draws, reduced from its own chain.
            // ↩️It was halved to the display's level, and kept so between
            // renders, until one-picture-per-frame ②-5b-3.
            //
            // Non-null without shouldAbort (on-demand render, never
            // abandoned). Somebody waits for every render made here — an
            // export's frame, a panel's picture — so a tile with no picture
            // gets one at once ([MissingTilePictures.madeAtOnce]).
            Future<PositionedSurfaceImage> compose() async =>
                (await composePositionedSurfaceImage(
                  layer.surface,
                  reuse: BitmapTileImageCache.instance,
                  missing: MissingTilePictures.madeAtOnce,
                  over:
                      rowsAsInk &&
                          inkCropDrawsTheSame(
                            placement: layer.placement,
                            effects: layer.effects,
                            paper: canvasSize.canvasRect,
                          )
                      ? surfaceInkWorldRect(layer.surface)
                      : null,
                ))!;

            if (kept != null) {
              layerImages[layer] = await kept.of(layer.surface, compose);
            } else {
              final composed = await compose();
              madeHere.addAll(composed.pieces);
              layerImages[layer] = composed;
            }
          case CompositeLeaf(payload: _CameraGround()):
            break;
          case CompositeGroup(:final children):
          case CompositeAdjustment(:final children):
          case CompositeBackdropBlend(:final children):
          case CompositeClip(:final children):
          // And the rows it reads, each a picture of its own.
          case CompositeReadsRows(:final children):
            await composeImages(children);
          // The base it paints again is composed with its clip.
          case CompositeOpaque():
          // Letters, not a picture: the row they are written on is composed
          // as its own leaf.
          case CompositeCelNumber():
            break;
        }
      }
    }

    await composeImages(tree);

    final leafQuality = filterQualityForDisplayScale(cameraRasterScale);

    final frame = Rect.fromLTWH(
      0,
      0,
      resolvedOutput.width.toDouble(),
      resolvedOutput.height.toDouble(),
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
    // The rect a row stands for — its content, never the ink alone it may be
    // composed as ([rowsAsInk]) — and where it lies: what a sub-tree's buffer
    // covers ([subtreeBufferBounds]).
    Rect extentOf(_CameraRow row) => switch (row) {
      _CameraLayer(:final layer) => surfaceContentWorldRect(layer.surface),
      // The ground has no edge: it is wherever a buffer reaches.
      _CameraGround() => Rect.largest,
    };
    LayerPlacement? placementOf(_CameraRow row) => switch (row) {
      _CameraLayer(:final layer) => layer.placement,
      _CameraGround() => null,
    };
    final projection = cameraProjectionMatrix(
      pose,
      cameraFrameSize,
      outputSize: resolvedOutput,
    );
    // What the rows are laid on: the ground the output is filled with, and
    // [paper] where a stage carries its own. The bottom row of the tree
    // ([onUnderlay]) — what a blend at the root reads below the rows.
    void layGround(Canvas canvas) {
      canvas.drawPaint(Paint()..color = background);
      final stage = paper;
      if (stage == null) {
        return;
      }
      final view = viewportOfSimilarity(projection);
      // The edge the display gives its paper, seen through this
      // projection — on the output's own pixels.
      final antiAlias = view == null || displayEdgeAntiAliased(view, 1);
      paintProjectPaper(
        canvas,
        antiAlias
            ? _paperYieldingToTheRows(canvasSize.canvasRect, cameraRasterScale)
            : canvasSize.canvasRect,
        stage,
        antiAlias: antiAlias,
        pixelRatio: 1,
      );
    }

    // A row of this render: the ground, or a layer's image posed, faded,
    // blended and filtered where it lies — whole, whatever of it the
    // buffer holding it reads ([within]).
    void paintRow(
      Canvas canvas,
      _CameraRow row,
      double rasterScale,
      RowPainter? rows,
      Rect within,
    ) {
      switch (row) {
        case _CameraGround():
          layGround(canvas);
        case _CameraLayer(:final layer):
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
          final ownCanvas = layer.surface.canvasSize;
          drawPosedLayerImage(
            canvas,
            // The ink alone where it was composed so ([rowsAsInk]), and
            // otherwise the whole content.
            pieces: layerImage.pieces,
            extent: surfaceContentWorldRect(layer.surface),
            placement: layer.placement,
            opacity: layer.opacity,
            blendMode: layer.blendMode,
            effects: layer.effects,
            // Its own canvas, as the rows' are laid on.
            paper: ownCanvas.canvasRect,
            // A texel copy where the projection moves pixels whole, at
            // the scale this canvas is at — a folder's buffer cut down to
            // its cap lays a crop back.
            texelScale: texelCopy ? rasterScale : null,
            filterQuality: leafQuality,
            // ↩️It asked the image to be a texel a canvas pixel as well,
            // while a level spanned the canvas at half and less — until
            // one-picture-per-frame ②-5b-3: every row is at canvas
            // resolution now.
            drawAtOriginWhen: (worldRect, _) =>
                worldRect.left == 0 &&
                worldRect.top == 0 &&
                worldRect.width == ownCanvas.width &&
                worldRect.height == ownCanvas.height,
            rows: rows,
          );
      }
    }

    ui.Picture recorded() {
      final recorder = ui.PictureRecorder();
      // Bounded by the frame's pixels, so a draw into it can ask what it can
      // land on (`drawPosedLayerImage`, a picture in pieces).
      final canvas = Canvas(recorder, frame);
      canvas.drawRect(frame, Paint()..color = background);
      canvas.save();
      if (cutsToTheCanvas) {
        final cut = shotClipOnScreen(
          outlineThrough(canvasSize, projection),
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
      // What of the tree lies within what reads it: the shot at the top,
      // and under a folder that folder's buffer, which a blur on it reads
      // past the shot ([subtreeBufferBounds]).
      paintCompositeTree(
        canvas,
        tree,
        rasterScale: cameraRasterScale,
        within: visible,
        route: (
          paintRow: paintRow,
          extentOf: extentOf,
          placementOf: placementOf,
          shownWithin: null,
          held: null,
          paper: canvasSize.canvasRect,
        ),
      );
      canvas.restore();
      if (overlayPass != null) {
        applyCameraProjection(
          canvas,
          pose,
          cameraFrameSize,
          outputSize: resolvedOutput,
        );
        overlayPass(canvas, cameraRasterScale);
      }
      return recorder.endRecording();
    }

    // 🗣️I-132-Q34 a (유저 2026-10-30): a plugin's step in the tree runs over
    // what its chain made before it, and every render made here WAITS for
    // it — a film's frame, a panel's picture ([FxPluginStages]).
    final picture = await FxPluginStages.recordedThrough(
      recorded,
      discard: (made) => made.dispose(),
    );
    try {
      return await picture.toImage(resolvedOutput.width, resolvedOutput.height);
    } finally {
      picture.dispose();
      madeHere.disposeAll();
    }
  }
}

/// The paper under rows drawn through a camera whose edge is anti-aliased,
/// on the canvas [canvasRect]: one output pixel in from the canvas's edge
/// — [scale] output pixels a canvas pixel — or the whole canvas where that
/// leaves nothing, so a small one does not vanish.
///
/// #15 — the paper yields the pixel the canvas's edge falls inside to the
/// rows: the two drawn there each anti-aliased on its own, a paper that
/// ended on that pixel's far side showed past ink covering it in part —
/// the 1px bright ring the device saw below ~30%, and the film's white
/// line (playback-picture-is-not-the-canvas-picture, 유저 10-13 「끝에 흰
/// 선」). The canvas lays its paper INTO the frame's one picture under its
/// rows, so its own yields nothing. ↩️It yielded a level pixel, under rows
/// halved to the level (`paperRectAtLevel`), and nothing at canvas
/// resolution — until every row was drawn at canvas resolution and reduced
/// on the output's pixels (one-picture-per-frame ②-5b-3).
Rect _paperYieldingToTheRows(Rect canvasRect, double scale) {
  final yielded = canvasRect.deflate(1 / scale);
  return yielded.isEmpty ? canvasRect : yielded;
}

/// What a camera render's tree paints: one of its rows, or the ground they
/// are laid on ([onUnderlay]).
sealed class _CameraRow {
  const _CameraRow();
}

final class _CameraLayer extends _CameraRow {
  const _CameraLayer(this.layer);

  final CutFrameCompositeLayer layer;
}

final class _CameraGround extends _CameraRow {
  const _CameraGround();
}

/// Where a render's row pictures come from when they are kept between
/// renders ([CameraFrameRenderService.renderThroughCamera]'s `rows`).
///
/// [of] hands back the picture [surface] composes to — one kept from an
/// earlier render, or [compose]'s — and it is the keeper's either way. It
/// may be the ink alone ([laidTexelForTexel]). ↩️It was asked at a level,
/// a picture a halving, until one-picture-per-frame ②-5b-3.
abstract interface class RowPictures {
  Future<PositionedSurfaceImage> of(
    BitmapSurface surface,
    Future<PositionedSurfaceImage> Function() compose,
  );

  /// Whether every render a row kept here is handed to lays it down texel
  /// for texel — so one composed as its ink alone is never laid back whole
  /// to be drawn, which would pay that raster at every draw
  /// ([drawPosedLayerImage]).
  bool get laidTexelForTexel;
}
