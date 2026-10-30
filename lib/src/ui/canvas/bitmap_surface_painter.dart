import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';

import '../../models/bitmap_surface.dart';
import '../../models/tile_coord.dart';

import '../../models/canvas_viewport.dart';
import '../../models/pasteboard_bounds.dart';
import '../../models/project_background.dart';
import '../../services/cel_text_laying.dart';
import 'active_stroke_overlay.dart';
import 'bitmap_tile_image_cache.dart';
import 'blends_in_place.dart';
import 'display_resample.dart';
import 'landing_preview.dart';
import 'tile_origin.dart';
import 'tile_pages.dart';
import 'tile_picture_budget.dart';
import 'tiles_under_rect.dart';
import 'viewport_canvas_transform.dart';
import '../repaint_props.dart';
import '../timeline/memo_token.dart';

part 'surface_paint/coordinate_picture.dart';
part 'surface_paint/overlay_pass.dart';
part 'surface_paint/surface_paint_pass.dart';

/// A selection's float as a row paints it: the [preview], in CANVAS space,
/// and the matrix that carries canvas space into the row's own — null while
/// the row stands where the canvas does, the posed row's inverse otherwise.
typedef RowFloat = ({LandingPreview preview, Matrix4? canvasToRow});

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
    required BitmapSurface surface,
    this.viewport,
    this.overlayModel,
    this.landingPreview,
    this.showTransparentBackground = true,
    this.lineage,
    this.devicePixelRatio = 1.0,
    BitmapTileImageCache? tileImageCache,
    TilePictureBudget? pictureBudget,
  }) : surface = celSurfaceWithTextsLaid(surface),
       tileImageCache = tileImageCache ?? BitmapTileImageCache.instance,
       pictureBudget = pictureBudget ?? TilePictureBudget.instance,
       super(
         repaint: Listenable.merge([
           ?overlayModel,
           ?landingPreview,
         ]),
       );

  /// The tiles this painter draws — the picture AS SHOWN.
  ///
  /// 🚨★★★A PAINTER CANNOT BE HANDED A PICTURE'S DRAWING WITHOUT ITS TEXTS
  /// (R9-rest, 유저 2026-10-06: a text is 「셀의 그림이랑 정확히 동일」). A
  /// surface that still carries texts has them laid over its tiles HERE, in
  /// the constructor, so no host that mounts this painter can be the one
  /// that forgot — the same placement, for the same reason, as the colour
  /// keys in `CutFrameCompositeLayer`'s constructor. A surface that carries
  /// none (every sheet's ink, a selection's float, a cel already shown
  /// through `celSurfaceAsShown`) comes back as the object it was.
  ///
  /// ⚠️It does not replace `celSurfaceAsShown` at the routes that key: the
  /// keys filter the picture the texts are part of, so they have to be laid
  /// BEFORE the keys run, and only that seam knows the row's chain.
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
  ///
  /// ↩️F-33: the stamp's ghost had a listenable of its own beside this,
  /// drawn INSIDE the layer's paint so it took the layer's opacity, blend
  /// and group buffer (유저: 「레이어 블렌드모드나 **합성같은게 다**
  /// 반영되는」). Since brush-fidelity-Q9 (10-18) the ghost rides THIS
  /// overlay — the click's own bytes — which is drawn there too.
  final ActiveStrokeOverlayModel? overlayModel;

  /// 🚨★★★F-344 — WHAT A PENDING LANDING WILL PUT OVER [surface], in its
  /// own space: the text the text tool holds, floated over the hole its
  /// lifting left (`CelTextFloat`), the way a lifted selection floats over
  /// its own.
  ///
  /// 🗣️유저 2026-10-12: 「텍스트도구, 잡고 이동할때나 변형할때나 너무 느림.
  /// 변형로직같은거 참고/재사용하면서 라이브 빠르게 움직이도록 구조개편」. A
  /// text in hand was LAID INTO THE TILES on every move of the hand: its
  /// plate cut again, each tile under it stamped and pictured again, and
  /// the panel built again for the painter that surface then needed.
  ///
  /// A LISTENABLE: the hand moves every frame, and a new painter per position
  /// would break the memo that keeps the whole stack from recompositing.
  /// Drawn where the selection's float is ([paintContentInto]'s `float`),
  /// so it composites as this layer at every zoom (F-240).
  final ValueListenable<LandingPreview?>? landingPreview;

  /// [landingPreview] as the paint draws it — null while it draws nothing.
  RowFloat? get _ownFloat {
    final preview = landingPreview?.value;
    return preview == null || preview.drawnWorldRect.isEmpty
        ? null
        : (preview: preview, canvasToRow: null);
  }

  final bool showTransparentBackground;

  /// The lineage this painter names its cel by — what the picture budget
  /// counts a paint's shown tiles against ([TilePictureBudget.shown]).
  /// ↩️The level pyramid kept its level tiles under it too, until nothing
  /// drew a level tile (one-picture-per-frame ②-5b-2).
  ///
  /// ⚠️ A lineage, not a surface instance. Every painter in `lib/` passes
  /// one; a painter of a surface that is nobody's cel (the selection
  /// float) passes [TilePictureBudget.noLineage].
  final Object? lineage;

  final BitmapTileImageCache tileImageCache;

  /// Told which tiles each paint has under its visible rect, so the
  /// pictures it lets go are never the ones on screen
  /// ([TilePictureBudget.shown]).
  final TilePictureBudget pictureBudget;

  /// Where its surface keeps pixels, in canvas space — the clip this
  /// painter works within: the pasteboard (artwork past the canvas edge
  /// stays visible while editing), and a file's picture laid past it
  /// ([BitmapSurface.storableRect], F-374-Q8).
  Rect get storableRect => surface.storableRect;

  /// 🚨★★★EVERYTHING THIS PAINTER DRAWS, in canvas space — its surface's
  /// content and whatever it draws over that surface this frame: the
  /// overlay (a stroke in flight, or the stamp's ghost) and the text in hand.
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
      return storableRect;
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
    add(_ownFloat?.preview.drawnWorldRect);
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
    // canvas size, so output still crops to the stage. A file's picture
    // laid past the wall keeps the rest of itself (F-374-Q8). The wall cuts
    // as the display cuts the canvas's edge — ↩️at a fraction of a pixel,
    // a sheet's window's too, until the-walk-family-cuts-the-rest-on-the-grid.
    clipToTheDisplayEdge(
      canvas,
      storableRect,
      antiAlias:
          resolvedViewport != null &&
          displayEdgeAntiAliased(resolvedViewport, devicePixelRatio),
      pixelRatio: devicePixelRatio,
    );
    // The standalone route reads the display law itself: the tiles are
    // resampled by the whole device scale, so they are drawn at that
    // scale's filter — reduced, from their pictures' chains.
    paintContentInto(
      canvas,
      scale: resolvedViewport == null
          ? 1
          : displayScaleOf(resolvedViewport.zoom, devicePixelRatio),
      pixelRatio: devicePixelRatio,
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
    // ↩️A brush blend drawn on the GPU (BB-1) took this route too; since
    // brush-fidelity-Q9 nothing draws one, so only a pre-blended result
    // and an eraser's dstOut compose against the committed pixels here.
    return overlay != null &&
        !_overlayReplacesCoords &&
        overlay.hasStrokeContent &&
        (overlay.preBlended || overlay.erase);
  }

  /// 🚨★★★WHETHER EVERY DEVICE PIXEL THIS PAINTER TOUCHES, IT TOUCHES ONCE.
  ///
  /// A layer's opacity and blend have to apply to the LAYER once. Wrapping
  /// the whole painter in a `saveLayer` is one way to get that; handing the
  /// same paint to each draw is another, and the two are the same pixels
  /// exactly when no two draws land on the same pixel — and the paint's
  /// blend acts where it is drawn. 🚨F-243: on the Windows app a tile drawn
  /// in multiply blended the whole screen ([blendsInPlace]), so a row in
  /// such a blend never rides the draws, whatever this answers (the
  /// stack's `needsBuffer`).
  ///
  /// ⛔NOT A NEW LAW — it was born one level down, as the overlay's own:
  /// *"BB-1: the brush blend previews live (tiles never overlap, so per-tile
  /// draws blend each pixel exactly once)."* This is that sentence asked
  /// about the LAYER's paint instead of the stroke's. ↩️That sentence went
  /// with brush-fidelity-Q9: nothing draws a brush blend on the GPU now —
  /// strokes pre-blend on the CPU (R27 #4), and so does the stamp ghost,
  /// the last that did not.
  ///
  /// 🧪Measured on the test VM: with the tile paint this class actually uses
  /// (`isAntiAlias = false`, `FilterQuality.none`) the two routes agree to
  /// the byte at scale 1, 1.37, 0.63 and 2, at phases 0, 0.42 and 0.5 —
  /// 0 of 19200 pixels differ. Antialiased draws do NOT agree, which is why
  /// the flag belongs to the painter that knows its own paint rather than
  /// to a caller guessing.
  ///
  /// False for the ways a pixel gets touched twice: the paper rect
  /// under every tile, a float placed OVER whatever a coordinate
  /// already holds, and an overlay that cannot replace a whole coordinate
  /// (its isolation layer exists precisely because it composes against the
  /// committed pixels).
  bool get drawsDisjointCoverage {
    // ↩️F-33: a stamp ghost landed OVER whatever a coordinate held, so it
    // said false here — and false is what made it obey the layer (the
    // buffered route puts the layer's opacity and blend on the buffer).
    // Since brush-fidelity-Q9 the ghost is the overlay's whole-coordinate
    // tiles, which the overlay's own answer below covers.
    //
    // F-344: the text in hand floats OVER the hole it left — the old ghost's
    // reason, and the same answer.
    if (_ownFloat != null) {
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

  /// [scale] is how many device pixels the caller lands on each canvas
  /// pixel ([displayScaleOf]) — 1 into a buffer at the canvas's own
  /// resolution. Every coordinate is drawn as the one picture it shows, at
  /// that scale's filter ([filterQualityForDisplayScale]); reduced, from
  /// the picture's chain ([BitmapTileImageCache.chainedPictureFor]).
  /// ↩️Below 100% the committed tiles were drawn as LEVEL TILES — each the
  /// box mean of a block of tiles, drawn at `none` — until one-picture-
  /// per-frame ②-5b-2 (유저 D7-2-Q2 「배율이 어떻든 항상 원본 한장」).
  ///
  /// [pixelRatio] is how many device pixels a unit of [canvas]'s space
  /// lands on past its transform — the screen's ratio on screen, 1 into a
  /// raster — the grid each coordinate's edge is cut on where the grid of
  /// coordinates falls off it ([cutOnThePixelGrid]).
  ///
  /// [float] is a selection's lifted float, drawn over this surface's
  /// coordinates ([RowFloat]) — and with it this painter's own
  /// [landingPreview].
  void paintContentInto(
    Canvas canvas, {
    Paint? layerPaint,
    double scale = 1,
    required double pixelRatio,
    RowFloat? float,
  }) =>
      // Constructed PER PAINT: the pass keeps one paint's state in `late
      // final` fields, and a painter paints more than once.
      _SurfacePaintPass(this).paintContentInto(
        canvas,
        layerPaint: layerPaint,
        scale: scale,
        pixelRatio: pixelRatio,
        float: float,
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
  /// route including any ancestor transform. Intersecting with where the
  /// surface keeps pixels ([storableRect]) both keeps the range finite (an
  /// unclipped recorder reports a giant rect) and matches what the routes
  /// clip to anyway.
  Rect _visibleCanvasRect(Canvas canvas, Rect storableRect) {
    final clip = canvas.getLocalClipBounds();
    if (!clip.overlaps(storableRect)) {
      return Rect.zero;
    }
    return clip.intersect(storableRect);
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
