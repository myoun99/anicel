import 'package:flutter/material.dart';

import '../../core/floor_math.dart';

import '../../models/bitmap_surface.dart';
import '../../models/bitmap_tile.dart';
import '../../models/tile_coord.dart';

import '../../models/canvas_viewport.dart';
import '../../models/pasteboard_bounds.dart';
import '../../models/project_background.dart';
import 'active_stroke_overlay.dart';
import 'bitmap_tile_image_cache.dart';
import 'viewport_canvas_transform.dart';

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
    this.showTransparentBackground = true,
    this.staleScope,
    BitmapTileImageCache? tileImageCache,
  }) : tileImageCache = tileImageCache ?? BitmapTileImageCache.instance,
       super(
         repaint: Listenable.merge([
           tileImageCache ?? BitmapTileImageCache.instance,
           ?overlayModel,
         ]),
       );

  final BitmapSurface surface;

  /// Zoom/pan applied inside the picture; `null` paints at identity.
  final CanvasViewport? viewport;

  /// Live in-progress stroke; drawn above the committed tiles with plain
  /// source-over. Its notifications repaint this painter directly.
  final ActiveStrokeOverlayModel? overlayModel;

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
      applyViewportTransform(canvas, resolvedViewport);
    }
    // The clip is the PASTEBOARD: artwork past the canvas edge stays
    // visible while editing (dimmed below); composite/export raster at
    // canvas size, so output still crops to the stage.
    canvas.clipRect(pasteboardRect);
    paintContentInto(canvas);
    canvas.restore();
  }

  /// The surface + live overlay, onto a canvas the CALLER has already
  /// viewport-transformed and clipped to [pasteboardRect].
  ///
  /// Split out so the editing canvas's merged stack painter can draw the
  /// ACTIVE layer inside the composite tree — a folder's group buffer is
  /// one `saveLayer`, and a saveLayer cannot span three sibling painters.
  /// [paint] above is this same body with the transform/clip around it, so
  /// the standalone route is byte-identical.
  ///
  /// Takes no `Size`: what this body needs is the visible CANVAS rect, and
  /// the widget size is a screen quantity that only coincides with it at
  /// identity. Reading the canvas's clip instead is what makes the merged
  /// route right (see [_visibleCanvasRect]).
  void paintContentInto(Canvas canvas) {
    final canvasWidth = surface.canvasSize.width.toDouble();
    final canvasHeight = surface.canvasSize.height.toDouble();
    final pasteboardRect = this.pasteboardRect;

    if (showTransparentBackground) {
      // R28 #9: the one paper constant, not a repeated literal.
      final backgroundPaint = Paint()
        ..color = const Color(ProjectBackground.defaultPaperArgb);
      canvas.drawRect(
        Rect.fromLTWH(0, 0, canvasWidth, canvasHeight),
        backgroundPaint,
      );
    }

    // An erasing overlay draws destination-out against the committed tiles.
    // The tiles + overlay MUST be isolated in their own layer: without it,
    // dstOut applies to the whole accumulated compositing buffer — the
    // painter's own background here, and in the production editing path
    // (paper in the separate underlay widget) the paper and panel chrome
    // BELOW this picture, which showed live erase strokes as dark
    // panel-background lines until the commit landed (R14-⑤). The layer
    // makes the hole transparent so whatever is underneath shows through.
    // BB-1: a non-srcOver BRUSH BLEND needs the same isolation — the
    // mode must blend against the CEL's pixels only, never the paper or
    // panel chrome below.
    //
    // PROMOTION round: a PRE-BLENDED overlay on the SAME grid as the
    // surface needs neither a layer nor a clip. A result tile carries
    // the commit's finished pixels for its whole coordinate (base
    // included), so the base pass simply SKIPS the committed tile where
    // an overlay image exists and the overlay pass lays the result tile
    // with plain srcOver — one draw per coordinate, structurally the
    // idle frame's cost however long the stroke gets. The isolation
    // layer + src-replacement route stays for pre-blended overlays on a
    // MISMATCHED grid (hosts/tests with their own tile sizes); both
    // routes are display-parity-pinned.
    final overlay = overlayModel;
    final overlayReplacesCoords =
        overlay != null &&
        overlay.preBlended &&
        overlay.hasStrokeContent &&
        overlay.tileSize == surface.tileSize;
    final overlayBlendsInLayer =
        overlay != null &&
        !overlayReplacesCoords &&
        overlay.hasStrokeContent &&
        (overlay.preBlended ||
            overlay.erase ||
            overlay.blendMode.previewBlendMode != BlendMode.srcOver);
    if (overlayBlendsInLayer) {
      canvas.saveLayer(pasteboardRect, Paint());
    }

    final tileImagePaint = Paint()
      ..filterQuality = FilterQuality.none
      ..isAntiAlias = false;
    // While a stroke settles, coordinates it touched draw their pinned
    // PRE-stroke tile (or nothing if the coordinate was empty) instead of
    // the committed tile: post-commit decodes land one by one, and drawing
    // them under the still-visible overlay flashed the stroke at double
    // density in tile-shaped patches. The pin and the overlay clear in one
    // notification, so the swap to committed pixels is atomic.
    final settleHold = overlayModel?.settleHoldTiles;
    // Per-pixel fallback budget (R17 measured): the first paint after a
    // FULL-CANVAS commit (a fill/lift stamp) used to draw ~130 undecoded
    // tiles pixel-by-pixel — 65k rects per tile, the multi-second "first
    // fill" freeze. A few tiles are fine; past the budget the tile waits
    // for its decode (it lands within a few frames — the repaint hook
    // brings it in).
    var pixelFallbackBudget = 4;
    // R27 #2: the budget goes to tiles the user can actually SEE. Since
    // the walk below is now visible-only, every coordinate it reaches
    // already shows — no separate visibility test is needed.
    final visibleRect = _visibleCanvasRect(canvas, pasteboardRect);
    // Decode-start chunking (R18 B-1): STARTING a decode costs a
    // synchronous tile copy + 65k-pixel premultiply on the UI thread, and
    // a full-canvas commit used to start every changed tile in one paint
    // (~130+ tiles — the post-commit hitch the R17 probe measured).
    // Pending tiles are collected here and at most [decodeStartBudget]
    // start per paint, visible tiles center-out first; each completion
    // notifies (coalesced per frame), which repaints this painter and
    // starts the next chunk, so the surface converges over a few frames
    // while the stale/settle-hold fallbacks keep on-screen content stable.
    // Decode STARTS are collected across the WHOLE cel (cheap: an Expando
    // lookup per tile), so off-screen tiles keep pre-warming in the
    // background and scroll in already decoded — the visibility priority
    // lives in _startPrioritizedDecodes.
    List<BitmapTile>? pendingDecodes;
    for (final tile in surface.tiles.values) {
      if (tileImageCache.needsDecodeStart(tile)) {
        (pendingDecodes ??= <BitmapTile>[]).add(tile);
      }
    }

    // DRAWING walks only the tile COORDINATES the view covers, not every
    // committed tile. This paint runs per stroke frame (the overlay's
    // repaint hook), and a big cel drawn all over holds far more tiles
    // than fit a zoomed-in view — the old draw-everything walk issued a
    // drawImage per committed tile (~2.2ms at 1024 tiles, growing
    // linearly) for pixels the pasteboard clip drops anyway. The tile map
    // is a coordinate hash, so each lookup is O(1) and the draw cost is
    // O(visible tiles).
    final tileSize = surface.tileSize;
    final firstTileX = floorDiv(visibleRect.left.floor(), tileSize);
    final lastTileX = floorDiv(visibleRect.right.ceil() - 1, tileSize);
    final firstTileY = floorDiv(visibleRect.top.floor(), tileSize);
    final lastTileY = floorDiv(visibleRect.bottom.ceil() - 1, tileSize);
    for (var tileY = firstTileY; tileY <= lastTileY; tileY += 1) {
      for (var tileX = firstTileX; tileX <= lastTileX; tileX += 1) {
        final tile = surface.tiles[TileCoord(x: tileX, y: tileY)];
        if (tile == null) {
          continue;
        }
        // The overlay's result tile REPLACES this coordinate outright (it
        // already contains the committed pixels blended with the stroke) —
        // the committed tile is not drawn at all. The decode start ran in
        // the collect pass above, so a freshly adopted tile's image is
        // ready by the time the override releases.
        if (overlayReplacesCoords &&
            overlay.tileImages.containsKey(tile.coord)) {
          continue;
        }
        if (settleHold != null && settleHold.containsKey(tile.coord)) {
          final preTile = settleHold[tile.coord];
          if (preTile != null) {
            final preImage = tileImageCache.imageFor(preTile);
            if (preImage != null) {
              canvas.drawImage(
                preImage,
                Offset(
                  (preTile.coord.x * preTile.size).toDouble(),
                  (preTile.coord.y * preTile.size).toDouble(),
                ),
                tileImagePaint,
              );
            } else {
              _paintTilePixels(canvas, preTile);
            }
          }
          continue;
        }
        // While this tile version's decode is pending, show the latest
        // decoded image at the same coordinate (slightly stale content)
        // instead of a per-pixel redraw: scanning up to 65k pixels per
        // changed tile froze the UI after large strokes. The active
        // overlay keeps the in-progress stroke visible until the new tiles
        // are decoded.
        //
        // What makes "slightly stale" true rather than a guess is the
        // SCOPE: it must name a lineage in which this coordinate's last
        // decode really is an older version of this tile. A surface whose
        // content gets replaced empties its scope at that moment instead
        // of borrowing across the replacement.
        final tileImage =
            tileImageCache.imageFor(tile) ??
            tileImageCache.latestImageForCoord(tile.coord, scope: staleScope);
        if (tileImage != null) {
          canvas.drawImage(
            tileImage,
            Offset(
              (tile.coord.x * tile.size).toDouble(),
              (tile.coord.y * tile.size).toDouble(),
            ),
            tileImagePaint,
          );
        } else if (pixelFallbackBudget > 0) {
          // First-ever content at this coordinate and not decoded yet:
          // draw per pixel for this frame only — within the budget. Every
          // coordinate here is visible, so the budget spends only where it
          // shows (R27 #2).
          pixelFallbackBudget -= 1;
          _paintTilePixels(canvas, tile);
        }
      }
    }
    if (pendingDecodes != null) {
      _startPrioritizedDecodes(pendingDecodes, visibleRect);
    }

    if (overlay != null) {
      // The live stroke renders through the EXACT pipeline the committed
      // tiles use — premultiplied bytes decoded to images, drawn with
      // nearest sampling — so live and committed pixels rasterize
      // identically at any zoom (one code path; rect-geometry replay
      // diverged from image sampling at fractional zoom). Overlay tiles
      // never overlap, so plain source-over per tile is exact. An ERASE
      // stroke draws destination-out instead: the accumulated stroke alpha
      // removes committed pixels exactly like the commit pass will.
      // PROMOTION round: pre-blended tiles carry the COMMIT's finished
      // pixels for their whole coordinate (base included). On the
      // aligned-grid route the base pass SKIPPED those coordinates, so
      // plain srcOver composes them over the paper exactly like the
      // committed tiles will after pen-up; on a mismatched grid the
      // isolation layer is up and the tiles REPLACE (BlendMode.src)
      // instead. The erase/blend paints below serve only overlays that
      // don't pre-blend (the fill stamp, and hosts driving the model
      // directly).
      final overlayPaint = overlay.preBlended
          ? (overlayReplacesCoords
                ? tileImagePaint
                : (Paint()
                    ..filterQuality = FilterQuality.none
                    ..isAntiAlias = false
                    ..blendMode = BlendMode.src))
          : overlay.erase
          ? (Paint()
              ..filterQuality = FilterQuality.none
              ..isAntiAlias = false
              ..blendMode = BlendMode.dstOut)
          : overlay.blendMode.previewBlendMode != BlendMode.srcOver
          // BB-1: the brush blend previews live (tiles never overlap,
          // so per-tile draws blend each pixel exactly once).
          ? (Paint()
              ..filterQuality = FilterQuality.none
              ..isAntiAlias = false
              ..blendMode = overlay.blendMode.previewBlendMode)
          : tileImagePaint;
      // R26 #18 (the selection) is NOT clipped here any more: the
      // selection mask rides the pre-blend kernel, so a tile's result
      // already equals the base wherever the selection excludes it. The
      // painter draws the same bytes the commit will hold — which is
      // also what lets a selected stroke keep the whole-coordinate
      // replacement path below instead of an isolation layer.
      final overlayTileSize = overlay.tileSize.toDouble();
      for (final entry in overlay.tileImages.entries) {
        canvas.drawImage(
          entry.value,
          Offset(entry.key.x * overlayTileSize, entry.key.y * overlayTileSize),
          overlayPaint,
        );
      }
      // R23: a fill tap's overlay is ONE pre-decoded stamp image at the
      // commit's exact placement (never coexists with stroke tiles).
      final stampImage = overlay.stampImage;
      if (stampImage != null) {
        canvas.drawImage(stampImage, overlay.stampOffset, overlayPaint);
      }
    }

    if (overlayBlendsInLayer) {
      canvas.restore();
    }

    // No pasteboard dim (user decision, Flash-style): off-canvas artwork
    // shows at full brightness — the paper edge against the backdrop is
    // the stage boundary.
  }

  /// Maximum decode STARTS per paint. Completions notify → repaint → the
  /// next chunk starts, so pending tiles always drain; the value trades
  /// per-frame UI-thread cost (copy + premultiply per start) against how
  /// many frames a full-canvas convergence takes.
  static const int decodeStartBudget = BitmapTileImageCache.decodeStartBudget;

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

  void _paintTilePixels(Canvas canvas, BitmapTile tile) {
    final pixelPaint = Paint()..style = PaintingStyle.fill;
    final pixels = tile.pixels;
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
      }
    }
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
        !identical(oldDelegate.overlayModel, overlayModel);
  }
}
