import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';


import '../../models/bitmap_surface.dart';
import '../../models/bitmap_tile.dart';
import '../../models/tile_coord.dart';

import '../../models/canvas_viewport.dart';
import '../../models/pasteboard_bounds.dart';
import '../../models/project_background.dart';
import '../brush/cut_piece_preview.dart' show CutStampPreview, paintCutPiece;
import '../debug/measurement_mode.dart';
import 'active_stroke_overlay.dart';
import 'bitmap_tile_image_cache.dart';
import 'tile_origin.dart';
import 'tiles_under_rect.dart';
import 'viewport_canvas_transform.dart';

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
class BitmapSurfacePainter extends CustomPainter {
  BitmapSurfacePainter({
    required this.surface,
    this.viewport,
    this.overlayModel,
    this.stampPreview,
    this.showTransparentBackground = true,
    this.staleScope,
    this.devicePixelRatio = 1.0,
    BitmapTileImageCache? tileImageCache,
  }) : tileImageCache = tileImageCache ?? BitmapTileImageCache.instance,
       super(
         repaint: Listenable.merge([
           tileImageCache ?? BitmapTileImageCache.instance,
           ?overlayModel,
           ?stampPreview,
           // So toggling Settings ▸ Show Unpainted Tiles repaints instead of
           // waiting for the next edit — a diagnosis switch that needs a
           // gesture before it takes effect is one nobody trusts.
           MeasurementMode.showUnpaintedTiles,
         ]),
       );

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

  /// Identifies this surface's lineage so the stale tile fallback never
  /// shows another lineage's artwork; see
  /// [BitmapTileImageCache.latestImageForCoord].
  ///
  /// ⚠️ A lineage, not a surface instance. Every painter in `lib/` must
  /// pass one: the transform float went without, which put it in a bucket
  /// shared by every float ever lifted, so opening a second transform drew
  /// the FIRST one's artwork at the first one's place and size. Where a
  /// lineage's CONTENT is replaced rather than edited, the owner empties
  /// its scope at that moment — [BitmapTileImageCache.resetScope] — rather
  /// than going without one.
  final Object? staleScope;

  final BitmapTileImageCache tileImageCache;

  /// The pasteboard rect in canvas space — the clip this painter works
  /// within (artwork past the canvas edge stays visible while editing).
  Rect get pasteboardRect => Rect.fromLTRB(
    surface.canvasSize.pasteboardLeft.toDouble(),
    surface.canvasSize.pasteboardTop.toDouble(),
    surface.canvasSize.pasteboardRightExclusive.toDouble(),
    surface.canvasSize.pasteboardBottomExclusive.toDouble(),
  );

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
    paintContentInto(canvas);
    canvas.restore();
  }

  /// Whether everything this painter draws can be LOCATED from the state it
  /// publishes — [surface]'s tiles, their decoded images, and the overlay's.
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
  /// under every tile, a fill stamp placed OVER whatever a coordinate
  /// already holds, and an overlay that cannot replace a whole coordinate
  /// (its isolation layer exists precisely because it composes against the
  /// committed pixels).
  bool get drawsDisjointCoverage {
    // 🚨★★★F-33: a stamp ghost lands OVER whatever the coordinate already
    // holds, exactly like the fill stamp below — so this must say false.
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
    if (overlay == null) {
      return true;
    }
    if (overlay.stampImage != null) {
      return false;
    }
    if (!overlay.hasStrokeContent) {
      return true;
    }
    return _overlayReplacesCoords;
  }

  // The content paint (Round 6): one paint of the surface, as its own object.

  void paintContentInto(Canvas canvas, {Paint? layerPaint}) =>
      // Constructed PER PAINT: the pass keeps one paint's state in `late
      // final` fields, and a painter paints more than once.
      _SurfacePaintPass(this).paintContentInto(canvas, layerPaint: layerPaint);

  /// Maximum decode STARTS per paint. Completions notify → repaint → the
  /// next chunk starts, so pending tiles always drain; the value trades
  /// per-frame UI-thread cost (copy + premultiply per start) against how
  /// many frames a full-canvas convergence takes.
  static const int decodeStartBudget = BitmapTileImageCache.decodeStartBudget;

  /// Starts the decode work [paintContentInto]'s collect pass would have
  /// started — budgeted and visible-first exactly the same way — WITHOUT
  /// drawing anything.
  ///
  /// For the frame(s) the merged stack covers this surface with the
  /// first-activation stand-in: the walk is skipped there, and the
  /// stand-in can only ever hand off if the decodes it is waiting on
  /// actually begin. [canvas] provides the visibility priority (the same
  /// clip read the paint itself uses).
  void startPendingDecodes(Canvas canvas) {
    List<BitmapTile>? pending;
    for (final tile in surface.tiles.values) {
      if (tileImageCache.needsDecodeStart(tile)) {
        (pending ??= <BitmapTile>[]).add(tile);
      }
    }
    if (pending == null) {
      return;
    }
    _startPrioritizedDecodes(
      pending,
      _visibleCanvasRect(canvas, pasteboardRect),
    );
  }

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

  /// Starts up to [decodeStartBudget] of [pending]'s decodes — when over
  /// budget, tiles overlapping [visibleRect] go first (nearest the view
  /// center), off-screen tiles strictly after.
  void _startPrioritizedDecodes(List<BitmapTile> pending, Rect visibleRect) {
    var ordered = pending;
    if (pending.length > decodeStartBudget) {
      final center = visibleRect.center;
      // Dominates any real distance² (canvas diagonals stay far below),
      // so off-screen tiles sort after every visible one.
      const offscreenBias = 1e18;
      double score(BitmapTile tile) {
        final tileSize = tile.size.toDouble();
        final rect = Rect.fromLTWH(
          tile.coord.x * tileSize,
          tile.coord.y * tileSize,
          tileSize,
          tileSize,
        );
        final distance = (rect.center - center).distanceSquared;
        return rect.overlaps(visibleRect) ? distance : distance + offscreenBias;
      }

      final scored = [
        for (final tile in pending) (score: score(tile), tile: tile),
      ];
      scored.sort((a, b) => a.score.compareTo(b.score));
      ordered = [for (final entry in scored) entry.tile];
    }
    final startCount = ordered.length < decodeStartBudget
        ? ordered.length
        : decodeStartBudget;
    for (var i = 0; i < startCount; i += 1) {
      tileImageCache.ensureDecoded(ordered[i], staleScope: staleScope);
    }
  }

  /// Fills [tile]'s rect with magenta when Settings ▸ Show Unpainted Tiles is
  /// on, so a coordinate the painter could not draw stops being silent.
  ///
  /// Inert otherwise: one bool read per undrawable coordinate, and those
  /// are the coordinates that were about to cost nothing anyway.
  void _markUnpainted(Canvas canvas, BitmapTile tile) {
    if (!MeasurementMode.showUnpaintedTiles.value) {
      return;
    }
    canvas.drawRect(
      tileOriginOffset(tile) & Size.square(tile.size.toDouble()),
      Paint()..color = const Color(0x99FF00FF),
    );
  }

  /// Draws [tile] a pixel at a time; true when it put anything on the
  /// canvas. The caller spends its budget on the answer, not on the
  /// attempt.
  bool _paintTilePixels(Canvas canvas, BitmapTile tile, Paint? layerPaint) {
    // `readPixels`, not the `pixels` getter: that getter is a defensive
    // 256 KB COPY per call, and this path already runs on the frames
    // where there is least room for it — the budget above is spent
    // exactly when nothing has decoded yet.
    return tile.readPixels(
      (_, pixels) => _paintTilePixelsFrom(canvas, tile, pixels, layerPaint),
    );
  }

  bool _paintTilePixelsFrom(
    Canvas canvas,
    BitmapTile tile,
    Uint8List pixels,
    Paint? layerPaint,
  ) {
    var drew = false;
    final pixelPaint = Paint()
      ..style = PaintingStyle.fill
      ..isAntiAlias = false;
    // 🚨THE ONE DRAW THAT CANNOT TAKE THE LAYER PAINT DIRECTLY. `Paint.color`
    // already carries the PIXEL's own colour here, so folding the layer's
    // alpha into it quantises to 8 bits BEFORE the composite where the
    // buffer quantises after — 🧪measured at 55 pixels of 4096, worst
    // channel 1. A tile-sized layer restores the buffer's order exactly,
    // and this path is the undecoded-tile fallback with a budget of four.
    if (layerPaint != null) {
      canvas.saveLayer(
        tileOriginOffset(tile) & Size.square(tile.size.toDouble()),
        layerPaint,
      );
    }
    final tileOriginX = tile.coord.x * tile.size;
    final tileOriginY = tile.coord.y * tile.size;

    for (var localY = 0; localY < tile.size; localY += 1) {
      final globalY = tileOriginY + localY;
      if (globalY < surface.canvasSize.pasteboardTop ||
          globalY >= surface.canvasSize.pasteboardBottomExclusive) {
        continue;
      }

      for (var localX = 0; localX < tile.size; localX += 1) {
        final globalX = tileOriginX + localX;
        if (globalX < surface.canvasSize.pasteboardLeft ||
            globalX >= surface.canvasSize.pasteboardRightExclusive) {
          continue;
        }

        final offset = (localY * tile.size + localX) * 4;
        final r = pixels[offset];
        final g = pixels[offset + 1];
        final b = pixels[offset + 2];
        final a = pixels[offset + 3];
        if (a == 0) {
          continue;
        }

        pixelPaint.color = Color.fromARGB(a, r, g, b);
        canvas.drawRect(
          Rect.fromLTWH(globalX.toDouble(), globalY.toDouble(), 1, 1),
          pixelPaint,
        );
        drew = true;
      }
    }
    if (layerPaint != null) {
      canvas.restore();
    }
    return drew;
  }

  @override
  bool shouldRepaint(covariant BitmapSurfacePainter oldDelegate) {
    // Identity comparison: BitmapSurface is immutable with structural tile
    // sharing, so a changed surface is always a new instance. The previous
    // deep `!=` compared every tile's pixel bytes on each rebuild (megabytes
    // per pointer move while drawing).
    return !identical(oldDelegate.surface, surface) ||
        oldDelegate.showTransparentBackground != showTransparentBackground ||
        oldDelegate.viewport != viewport ||
        // The pan-phase snap reads it — a monitor move must repaint, not
        // keep the old phase.
        oldDelegate.devicePixelRatio != devicePixelRatio ||
        !identical(oldDelegate.overlayModel, overlayModel);
  }
}
