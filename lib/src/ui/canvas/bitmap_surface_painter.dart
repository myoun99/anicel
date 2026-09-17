import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';

import '../../models/bitmap_surface.dart';
import '../../models/brush_blend_mode.dart';
import '../../models/tile_coord.dart';

import '../../models/canvas_viewport.dart';
import '../../models/pasteboard_bounds.dart';
import '../../models/project_background.dart';
import '../brush/cut_piece_preview.dart' show CutStampPreview, paintCutPiece;
import 'active_stroke_overlay.dart';
import 'bitmap_tile_image_cache.dart';
import 'display_resample.dart';
import 'tile_origin.dart';
import 'tile_picture_budget.dart';
import 'tile_pyramid.dart';
import 'tiles_under_rect.dart';
import 'viewport_canvas_transform.dart';
import '../repaint_props.dart';
import '../timeline/memo_token.dart';

part 'surface_paint/coordinate_picture.dart';
part 'surface_paint/level_blocks.dart';
part 'surface_paint/overlay_pass.dart';
part 'surface_paint/surface_paint_pass.dart';

/// Paints the brush canvas — committed artwork plus the in-progress stroke —
/// with the viewport transform applied INSIDE the picture.
///
/// The zoom/pan used to live in a Transform widget above the paint layers.
/// Under a fractional zoom the compositor then resampled each rasterized
/// layer texture through the transform, and starting/stopping the overlay's
/// per-move repaints changed how that resampling landed — boundary pixels of
/// every line on the canvas visibly jittered while drawing (stable at 100% /
/// 200% where texel edges align with device pixels). Applying
/// `canvas.translate/scale` here means every frame rasterizes the canvas
/// content directly at final resolution through one code path, so idle and
/// drawing frames are pixel-identical at any zoom by construction.
class BitmapSurfacePainter extends CustomPainter with RepaintOnProps {
  BitmapSurfacePainter({
    required this.surface,
    this.viewport,
    this.overlayModel,
    this.stampPreview,
    this.showTransparentBackground = true,
    this.lineage,
    this.devicePixelRatio = 1.0,
    BitmapTileImageCache? tileImageCache,
    TilePictureBudget? pictureBudget,
  }) : tileImageCache = tileImageCache ?? BitmapTileImageCache.instance,
       pictureBudget = pictureBudget ?? TilePictureBudget.instance,
       super(repaint: Listenable.merge([?overlayModel, ?stampPreview]));

  final BitmapSurface surface;

  /// Zoom/pan applied inside the picture; `null` paints at identity.
  final CanvasViewport? viewport;

  /// The view's DPR, for [applyViewportTransform]'s pan-phase snap. Only
  /// the standalone route reads it ([viewport] non-null); the merged stack
  /// draws this painter through [paintContentInto] under its own snapped
  /// transform, so the null-viewport painters never need it.
  final double devicePixelRatio;

  /// Live in-progress stroke; drawn above the committed tiles with plain
  /// source-over. Its notifications repaint this painter directly.
  final ActiveStrokeOverlayModel? overlayModel;

  /// 🚨★★★F-33 — the STAMP's ghost, drawn INSIDE the layer's own paint so
  /// it inherits the layer's opacity, blend and group buffer.
  ///
  /// 유저: 「레이어 블렌드모드나 **합성같은게 다** 반영되는」 프리뷰. The
  /// cursor overlay it replaces was a `Positioned` widget ON TOP of the
  /// canvas, so the only thing it could honour was the stamp's own opacity.
  /// Here [paintContentInto] hands it `layerPaint` like every other draw.
  ///
  /// A LISTENABLE, not a value: the pointer moves on every frame of a
  /// hover, and a new painter per position would break the memo that keeps
  /// the whole stack from recompositing (`_activeSurfacePainterToken`).
  /// Subscribed through [repaint], so a move repaints and nothing rebuilds.
  ///
  /// ⛔The image inside is BORROWED from the held piece — see
  /// [CutStampPreview]. Nothing here disposes it.
  final ValueListenable<CutStampPreview?>? stampPreview;

  final bool showTransparentBackground;

  /// The lineage this painter names its cel by — what the level pyramid
  /// keeps its level tiles under ([TilePyramid]) and the picture budget
  /// counts a paint's shown tiles against ([TilePictureBudget.shown]).
  ///
  /// ⚠️ A lineage, not a surface instance. Every painter in `lib/` passes
  /// one; a painter of a surface that is nobody's cel (the selection
  /// float) passes [TilePyramid.noLineage].
  final Object? lineage;

  final BitmapTileImageCache tileImageCache;

  /// Told which tiles each paint has under its visible rect, so the
  /// pictures it lets go are never the ones on screen
  /// ([TilePictureBudget.shown]).
  final TilePictureBudget pictureBudget;

  /// The pasteboard rect in canvas space — the clip this painter works
  /// within (artwork past the canvas edge stays visible while editing).
  Rect get pasteboardRect => surface.canvasSize.pasteboardRect;

  /// 🚨★★★EVERYTHING THIS PAINTER DRAWS, in canvas space — its surface's
  /// content and whatever it draws over that surface this frame: the stroke
  /// in flight, the stamp ghost.
  ///
  /// F-85 (유저 2026-09-11): 「펜 그리는 도중, 페이스트보드의 일부?까지
  /// 그려지는데 정확히 페이스트보드 끝까지 그림 그려지지않음. 그 상태에서 손
  /// 떼면 정상적으로 페이스트보드에 그림 남아있음」. The merged stack sizes its
  /// one display buffer by what each row covers, and it asked this painter's
  /// SURFACE (`surfaceContentWorldRect`) — so every draw past the ink that had
  /// already landed was cut at that ink's edge until a commit put tiles
  /// there.
  ///
  /// ⛔Whoever sizes a buffer around this painter reads THIS, never the
  /// surface alone — and a draw added to [paintContentInto] without its rect
  /// here is the same defect again.
  ///
  /// 🚨WHAT IT DRAWS, NOT THE CANVAS IT BELONGS TO (review 2026-09-15). This
  /// used to start from `surfaceContentWorldRect`, which seeds the whole
  /// canvas rect — and the selection's float is a painter too, built on a
  /// canvas-sized surface: a move drag claimed page ∪ the page shifted by the
  /// drag on every frame, even for a ten-pixel selection, and a page past
  /// 4096 could push the buffer over its cap mid-drag. The canvas rect is
  /// this painter's only when it paints its own paper there
  /// ([showTransparentBackground]); the merged stack seeds the page itself.
  /// Empty ([Rect.zero]) when it draws nothing.
  ///
  /// ⛔And its CLIP when it draws from state it does not publish
  /// ([drawsOnlyFromPublishedState] is exactly the question 「can what this
  /// draws be located from what it publishes」). Measured by its published
  /// state alone, a test double drawing a mutable colour claimed nothing, a
  /// folder around it sized its buffer without it, and the stroke vanished
  /// from the canvas (`static_bake_render_parity_test`, 2026-09-15).
  Rect get drawnWorldRect {
    if (!drawsOnlyFromPublishedState) {
      return pasteboardRect;
    }
    Rect? drawn;
    void add(Rect? rect) {
      if (rect != null) {
        drawn = drawn?.expandToInclude(rect) ?? rect;
      }
    }

    if (showTransparentBackground) {
      add(surface.canvasSize.canvasRect);
    }
    add(tileCoordsWorldRect(surface.tiles.keys, surface.tileSize));
    final overlay = overlayModel;
    if (overlay != null) {
      add(tileCoordsWorldRect(overlay.tileImages.keys, overlay.tileSize));
    }
    final ghost = stampPreview?.value;
    if (ghost != null && ghost.image != null) {
      add(ghost.canvasRect);
    }
    return drawn ?? Rect.zero;
  }

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    final resolvedViewport = viewport;
    if (resolvedViewport != null) {
      applyViewportTransform(
        canvas,
        resolvedViewport,
        devicePixelRatio: devicePixelRatio,
      );
    }
    // The clip is the PASTEBOARD: artwork past the canvas edge stays
    // visible while editing (dimmed below); composite/export raster at
    // canvas size, so output still crops to the stage.
    canvas.clipRect(pasteboardRect);
    // The standalone route reads the display law itself: below 100% the
    // committed tiles are drawn as LEVEL TILES ([TilePyramid]) whose
    // residual under the transform lies in (0.5, 1] — the pictures a level
    // buffer draws 1:1 ([_LevelBlocks]).
    paintContentInto(
      canvas,
      level: resolvedViewport == null
          ? 0
          : displayLevelOf(
              displayScaleOf(resolvedViewport.zoom, devicePixelRatio),
            ),
    );
    canvas.restore();
  }

  /// Whether everything this painter draws can be LOCATED from the state it
  /// publishes — [surface]'s tiles, their pictures, and the overlay's.
  ///
  /// 🚨★★★This exists so a cache can ask before trusting itself. (v)'s
  /// composite buffer holds the live surface inside it, which is only sound
  /// while it can tell WHEN the live surface changed. It works that out
  /// from published state — and a subclass drawing from anything else (a
  /// test double with a mutable colour, most obviously) would be kept and
  /// would then freeze mid-stroke.
  ///
  /// ⛔The honest default is not "true", it is "true for what THIS class
  /// draws". An override of [paintContentInto] that reads state this class
  /// does not publish MUST override this to false, and false is never a
  /// bug: it costs a re-raster and keeps the picture right.
  bool get drawsOnlyFromPublishedState => true;

  /// A PRE-BLENDED overlay on the SAME grid: the base pass skips the
  /// committed tile where an overlay image exists and the overlay pass lays
  /// the result tile with plain srcOver.
  bool get _overlayReplacesCoords {
    final overlay = overlayModel;
    return overlay != null &&
        overlay.preBlended &&
        overlay.hasStrokeContent &&
        overlay.tileSize == surface.tileSize;
  }

  /// The isolation-layer route, for overlays that cannot replace a whole
  /// coordinate.
  bool get _overlayBlendsInLayer {
    final overlay = overlayModel;
    return overlay != null &&
        !_overlayReplacesCoords &&
        overlay.hasStrokeContent &&
        (overlay.preBlended ||
            overlay.erase ||
            overlay.blendMode.previewBlendMode != BlendMode.srcOver);
  }

  /// 🚨★★★WHETHER EVERY DEVICE PIXEL THIS PAINTER TOUCHES, IT TOUCHES ONCE.
  ///
  /// A layer's opacity and blend have to apply to the LAYER once. Wrapping
  /// the whole painter in a `saveLayer` is one way to get that; handing the
  /// same paint to each draw is another, and the two are the same pixels
  /// exactly when no two draws land on the same pixel.
  ///
  /// ⛔NOT A NEW LAW — the overlay's own blend already rides it one level
  /// down: *"BB-1: the brush blend previews live (tiles never overlap, so
  /// per-tile draws blend each pixel exactly once)."* This is that sentence
  /// asked about the LAYER's paint instead of the stroke's.
  ///
  /// 🧪Measured: with the tile paint this class actually uses
  /// (`isAntiAlias = false`, `FilterQuality.none`) the two routes agree to
  /// the byte at scale 1, 1.37, 0.63 and 2, at phases 0, 0.42 and 0.5 —
  /// 0 of 19200 pixels differ. Antialiased draws do NOT agree, which is why
  /// the flag belongs to the painter that knows its own paint rather than
  /// to a caller guessing.
  ///
  /// False for the three ways a pixel gets touched twice: the paper rect
  /// under every tile, a stamp ghost placed OVER whatever a coordinate
  /// already holds, and an overlay that cannot replace a whole coordinate
  /// (its isolation layer exists precisely because it composes against the
  /// committed pixels).
  bool get drawsDisjointCoverage {
    // 🚨★★★F-33: a stamp ghost lands OVER whatever the coordinate already
    // holds — so this must say false.
    //
    // ⚠️And saying false is what MAKES the ghost obey the layer, which is
    // the whole point of moving it here. False means the stack takes the
    // buffered route, and the buffered route puts the layer's opacity and
    // blend on the BUFFER — so everything drawn into it, ghost included,
    // composites as that layer. A ghost that reported disjoint coverage
    // would ride the per-draw path with no layer paint of its own and be
    // exactly as wrong as the widget it replaced.
    if (stampPreview?.value?.image != null) {
      return false;
    }
    if (showTransparentBackground) {
      return false;
    }
    final overlay = overlayModel;
    if (overlay == null || !overlay.hasStrokeContent) {
      return true;
    }
    return _overlayReplacesCoords;
  }

  // The content paint (Round 6): one paint of the surface, as its own object.

  /// [level] is the level of the display's pyramid the caller composes
  /// at ([displayLevelOf]): 0 draws the tiles themselves; above it the
  /// committed tiles are drawn as LEVEL TILES ([TilePyramid]), 1:1 in
  /// level pixels, and only a block no level tile can be made for yet
  /// falls back to its tiles under the caller's scale ([_LevelBlocks]).
  void paintContentInto(Canvas canvas, {Paint? layerPaint, int level = 0}) =>
      // Constructed PER PAINT: the pass keeps one paint's state in `late
      // final` fields, and a painter paints more than once.
      _SurfacePaintPass(this).paintContentInto(
        canvas,
        layerPaint: layerPaint,
        level: level,
      );

  /// The part of CANVAS space this paint can actually reach, read off the
  /// canvas's own clip.
  ///
  /// NOT re-derived from [viewport] and the widget size. That worked only
  /// for the standalone [paint] route: the merged stack painter applies
  /// the viewport ITSELF and hands [paintContentInto] an already
  /// transformed canvas with `viewport` left null (see
  /// BrushCanvasPanel._activeSurfacePainterFor), and the selection float
  /// stacks a drag/warp Transform on top of the viewport. In those routes
  /// a viewport-derived rect is a SCREEN rect read as canvas space — it
  /// culled tiles that were on screen, which blanked the active layer
  /// wherever pan/zoom moved the view off the origin.
  ///
  /// The clip is in local space by definition, so it is correct for every
  /// route including any ancestor transform. Intersecting with the
  /// pasteboard both keeps the range finite (an unclipped recorder
  /// reports a giant rect) and matches what the routes clip to anyway.
  Rect _visibleCanvasRect(Canvas canvas, Rect pasteboardRect) {
    final clip = canvas.getLocalClipBounds();
    if (!clip.overlaps(pasteboardRect)) {
      return Rect.zero;
    }
    return clip.intersect(pasteboardRect);
  }

  @override
  Object get props => (
    // Identity comparison: BitmapSurface is immutable with structural tile
    // sharing, so a changed surface is always a new instance. The previous
    // deep `!=` compared every tile's pixel bytes on each rebuild (megabytes
    // per pointer move while drawing).
    ByIdentity(surface),
    showTransparentBackground,
    viewport,
    // The pan-phase snap reads it — a monitor move must repaint, not
    // keep the old phase.
    devicePixelRatio,
    ByIdentity(overlayModel),
  );
}
