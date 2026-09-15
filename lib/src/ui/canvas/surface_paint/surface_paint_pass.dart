part of '../bitmap_surface_painter.dart';

/// ONE PAINT OF A BITMAP SURFACE'S CONTENT — the paper, the visible
/// tiles (a committed image, a held pre-stroke tile, or the live tile with
/// its upload and pixel-fallback budgets), the stroke overlay, and the
/// stamp preview.
///
/// 🚨A collaborator carved out of `BitmapSurfacePainter` (the audit's
/// cognitive cut, Round 6, 2026-09-03): `paintContentInto` was 418 lines
/// scoring 80 on the meter. Constructed PER PAINT; it reaches the painter
/// through `_painter`.
class _SurfacePaintPass {
  _SurfacePaintPass(this._painter);

  final BitmapSurfacePainter _painter;

  late final Canvas _canvas;
  late final Paint? _layerPaint;
  late final double _canvasWidth;
  late final double _canvasHeight;
  late final Rect _pasteboardRect;
  late final ActiveStrokeOverlayModel? _overlay;
  late final bool _overlayReplacesCoords;
  late final bool _overlayBlendsInLayer;
  late final Paint _tileImagePaint;
  late final Map<TileCoord, BitmapTile?>? _settleHold;
  late int _pixelFallbackBudget;
  late int _syncUploadBudget;
  late int _predecessorRectBudget;
  late int _predecessorTileBudget;
  late final Rect _visibleRect;
  Set<TileCoord>? _committedWins;
  List<PlacedTile>? _pendingDecodes;

  /// The surface + live _overlay, onto a _canvas the CALLER has already
  /// viewport-transformed and clipped to [_pasteboardRect].
  ///
  /// Split out so the editing _canvas's merged stack painter can draw the
  /// ACTIVE layer inside the composite tree — a folder composites into one
  /// offscreen (a `ui.Image` its own walk rasters), and one offscreen cannot
  /// span three sibling painters.
  /// [_painter.paint] above is this same body with the transform/clip around it, so
  /// the standalone route is byte-identical.
  ///
  /// Takes no `Size`: what this body needs is the visible CANVAS rect, and
  /// the widget size is a screen quantity that only coincides with it at
  /// identity. Reading the _canvas's clip instead is what makes the merged
  /// route right (see [_painter._visibleCanvasRect]).
  ///
  /// [_layerPaint] is the LAYER's own opacity/blend/colour chain, handed to
  /// every draw instead of being wrapped around them.
  ///
  /// ⛔Only legal when [_painter.drawsDisjointCoverage] — see its contract. Passing
  /// it otherwise applies the layer twice wherever two draws overlap, which
  /// looks like a darkened seam rather than an error.
  void paintContentInto(Canvas canvas, {Paint? layerPaint}) {
    _canvas = canvas;
    _layerPaint = layerPaint;
    assert(
      _layerPaint == null || _painter.drawsDisjointCoverage,
      'A layer paint may only ride the individual draws when they cover '
      'each pixel once — see drawsDisjointCoverage.',
    );
    _canvasWidth = _painter.surface.canvasSize.width.toDouble();
    _canvasHeight = _painter.surface.canvasSize.height.toDouble();
    _pasteboardRect = _painter.pasteboardRect;

    _paintPaper();

    // An erasing _overlay draws destination-out against the committed tiles.
    // The tiles + _overlay MUST be isolated in their own layer: without it,
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
    // PROMOTION round: a PRE-BLENDED _overlay on the SAME grid as the
    // surface needs neither a layer nor a clip. A result tile carries
    // the commit's finished pixels for its whole coordinate (base
    // included), so the base pass simply SKIPS the committed tile where
    // an _overlay image exists and the _overlay pass lays the result tile
    // with plain srcOver — one draw per coordinate, structurally the
    // idle frame's cost however long the stroke gets. The isolation
    // layer + src-replacement route stays for pre-blended overlays on a
    // MISMATCHED grid (hosts/tests with their own tile sizes); both
    // routes are display-parity-pinned.
    _overlay = _painter.overlayModel;
    _overlayReplacesCoords = _painter._overlayReplacesCoords;
    _overlayBlendsInLayer = _painter._overlayBlendsInLayer;
    if (_overlayBlendsInLayer) {
      _canvas.saveLayer(_pasteboardRect, Paint());
    }

    _tileImagePaint = Paint()
      ..filterQuality = FilterQuality.none
      ..isAntiAlias = false;
    if (_layerPaint != null) {
      // The layer rides every draw instead of a buffer around them.
      _tileImagePaint
        ..color = _layerPaint.color
        ..blendMode = _layerPaint.blendMode
        ..colorFilter = _layerPaint.colorFilter
        ..imageFilter = _layerPaint.imageFilter;
    }
    // While a stroke settles, coordinates it touched draw their pinned
    // PRE-stroke tile (or nothing if the coordinate was empty) instead of
    // the committed tile: post-commit decodes land one by one, and drawing
    // them under the still-visible _overlay flashed the stroke at double
    // density in tile-shaped patches. The pin and the _overlay clear in one
    // notification, so the swap to committed pixels is atomic.
    _settleHold = _painter.overlayModel?.settleHoldTiles;
    // Per-pixel fallback budget (R17 measured): the first paint after a
    // FULL-CANVAS commit (a fill/lift stamp) used to draw ~130 undecoded
    // tiles pixel-by-pixel — 65k rects per tile, the multi-second "first
    // fill" freeze. A few tiles are fine; past the budget the tile waits
    // for its decode (it lands within a few frames — the repaint hook
    // brings it in).
    _pixelFallbackBudget = 4;
    // N4 ⑤: the SAME rationing for synchronous uploads, and for the same
    // reason. An upload costs the tile copy + premultiply a decode START
    // costs, plus the upload itself — so doing it for every undrawable
    // visible coordinate would rebuild, inside one frame, exactly the
    // burst [decodeStartBudget] exists to spread over several. Zoomed out
    // on a large cel that is the whole visible grid at once.
    //
    // Same number as the decode-start budget, because it is the same cost
    // being rationed and the two are alternatives for one coordinate. Any
    // tile that misses out is not lost: it keeps today's answer for this
    // frame, its decode was already started by the collect pass, and the
    // next paint offers it the upload again.
    //
    // ⚠️ Skia never reaches this — `adoptSyncUpload` returns on a cached
    // bool before the budget is consulted — so nothing here changes the
    // renderer this is developed on. That is precisely why it needs to be
    // reasoned about rather than measured here.
    _syncUploadBudget = BitmapSurfacePainter.decodeStartBudget;
    // The truthful stand-in's budgets (F-68 root fix). RECTS, because that
    // is what the composition costs: an erase is a few hundred long runs,
    // a soft gradient laid on nothing is tens of thousands of one-pixel
    // ones. 32k rects is an eighth of what the per-pixel fallback below
    // already spends on its four tiles, so nothing here is a new cost
    // ceiling — it is a cheaper answer tried first. And a tile cap, because
    // the byte walk is ~1 ms a tile in Dart and a whole-canvas commit is a
    // thousand tiles: the walk is visible-first, so the tiles that miss
    // out are off-screen ones, and they keep today's answer this frame.
    _predecessorRectBudget = BitmapSurfacePainter.debugPredecessorRectBudget;
    _predecessorTileBudget = 16;
    // R27 #2: the budget goes to tiles the user can actually SEE. Since
    // the walk below is now visible-only, every coordinate it reaches
    // already shows — no separate visibility test is needed.
    _visibleRect = _painter._visibleCanvasRect(_canvas, _pasteboardRect);
    // Decode-start chunking (R18 B-1): STARTING a decode costs a
    // synchronous tile copy + 65k-pixel premultiply on the UI thread, and
    // a full-_canvas commit used to start every changed tile in one paint
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
    // Coordinates the base pass drew from the COMMITTED tile even though
    // the _overlay holds a stand-in for them; the _overlay pass leaves
    // these alone.
    _collectPendingDecodes();

    // DRAWING walks only the tile COORDINATES the view covers, not every
    // committed tile. This paint runs per stroke frame (the _overlay's
    // repaint hook), and a big cel drawn all over holds far more tiles
    // than fit a zoomed-in view — the old draw-everything walk issued a
    // drawImage per committed tile (~2.2ms at 1024 tiles, growing
    // linearly) for pixels the pasteboard clip drops anyway.
    //
    // ⚠️ `tileAt`, NOT `surface.tiles[...]`. The comment here used to say
    // "the tile map is a coordinate hash, so each lookup is O(1)" and that
    // was false: `tiles` is `Map.unmodifiable(_tiles)`, a getter that
    // COPIES the cel's whole tile map on every read, so the walk below
    // was O(visible coords × cel tiles) map entries. Measured 0.49 ms per
    // paint at 70 tiles and 1.48 ms at 88 — and the same shape was
    // measured at 82.7 ms per walk at the 1024 tiles the _canvas dialog
    // allows, which is a cliff, not a smoothness question.
    // (2d0478fb, 2026-09-09: the getter stopped copying — `tiles` hands
    // over the stored unmodifiable view, so either lookup is O(1) now, and
    // `tileAt` stays the one this walk means.)
    _paintVisibleTiles();
    final pendingDecodes = _pendingDecodes;
    if (pendingDecodes != null) {
      _painter._startPrioritizedDecodes(pendingDecodes, _visibleRect);
    }

    _paintOverlay();

    if (_overlayBlendsInLayer) {
      _canvas.restore();
    }

    // 🚨★★★F-33: the STAMP's ghost, and it is drawn HERE rather than in a
    // widget above the _canvas so [_layerPaint] reaches it — the layer's
    // opacity, its blend and its group buffer, which is the whole of the
    // user's ask (「레이어 블렌드모드나 **합성같은게 다** 반영되는」).
    //
    // ⚠️AFTER the _overlay's restore on purpose. `_overlayBlendsInLayer`
    // opens an isolation layer for the STROKE's own blend; a ghost that
    // is not part of that stroke must not be inside it, or the stroke's
    // brush blend would apply to the preview as well.
    _paintStampPreview();

    // No pasteboard dim (user decision, Flash-style): off-_canvas artwork
    // shows at full brightness — the paper edge against the backdrop is
    // the stage boundary.
  }

  /// The paper under a surface that shows no transparency.
  void _paintPaper() {
    if (_painter.showTransparentBackground) {
      // R28 #9: the one paper constant, not a repeated literal.
      final backgroundPaint = Paint()
        ..color = const Color(ProjectBackground.defaultPaperArgb);
      _canvas.drawRect(
        Rect.fromLTWH(0, 0, _canvasWidth, _canvasHeight),
        backgroundPaint,
      );
    }
  }

  /// The tiles whose decode has not started yet — started after the
  /// paint, nearest to the visible rect first.
  ///
  /// ⛔The walk itself is the painter's ([BitmapSurfacePainter
  /// .tilesAwaitingDecode]) — it was written out here AND there, same
  /// iteration and same predicate, and a converged cel now stops paying
  /// for either.
  void _collectPendingDecodes() {
    _pendingDecodes = _painter.tilesAwaitingDecode();
  }

  /// Every tile under the visible rect: a committed image, a held
  /// pre-stroke tile, or the live tile within the upload and pixel
  /// budgets.
  void _paintVisibleTiles() {
    for (final covered in tilesUnderRect(_painter.surface, _visibleRect)) {
      _paintTile((coord: covered.coord, tile: covered.tile));
    }
  }

  /// The stroke overlay's tiles and stamp over the committed tiles —
  /// except where a committed tile already won (a settled overlay tile).
  /// One tile under the visible rect. Three ways to paint it, in order
  /// of who owns the pixels right now: the overlay's settled image where
  /// the overlay replaces the tile, the held pre-stroke tile while the
  /// stroke settles, else the committed image — through a sync upload
  /// or the pixel fallback while their budgets last, and marked unpainted
  /// past them.
  void _paintTile(PlacedTile placed) {
    // The _overlay's result tile REPLACES this coordinate outright (it
    // already contains the committed pixels blended with the stroke) —
    // the committed tile is not drawn at all. The decode start ran in
    // the collect pass above, so a freshly adopted tile's image is
    // ready by the time the override releases.
    if (_overlayReplacesCoords &&
        _overlay != null &&
        _overlay.tileImages.containsKey(placed.coord)) {
      // While the _overlay is LIVE its image IS the stroke and the
      // committed tile is still the pre-stroke surface, so the
      // _overlay must win. Once it is SETTLING the commit has landed:
      // a committed tile that has its OWN image holds the finished
      // picture, and this _overlay is at best a revision behind it.
      //
      // The invariant that makes preferring the committed tile
      // truthful rather than hopeful: images are keyed by tile
      // OBJECT, a promoted tile is a fresh object, and only two
      // things can give it one — a decode of its own bytes, or an
      // adoption the handoff already revision-matched. There is no
      // third path, so an image here is always the final picture.
      //
      // ⚠️ `imageFor`, deliberately: a stand-in WOULD be a third path
      // and it is the weaker picture here. The _overlay tile this would
      // displace holds the commit's own bytes exactly, so a composed
      // approximation must never take its place — the stand-in exists
      // for coordinates that have no such answer.
      //
      // Drawn HERE and skipped in the _overlay pass, never both: two
      // draws of the same coordinate is the double-density ghost.
      _paintReplacedTile(placed);
      return;
    }
    if (_settleHold != null && _settleHold.containsKey(placed.coord)) {
      _paintHeldTile(placed);
      return;
    }
    // While this tile version's decode is pending, show the latest
    // decoded image at the same coordinate (slightly stale content)
    // instead of a per-pixel redraw: scanning up to 65k pixels per
    // changed tile froze the UI after large strokes. The active
    // _overlay keeps the in-progress stroke visible until the new tiles
    // are decoded.
    //
    // What makes "slightly stale" true rather than a guess is the
    // SCOPE: it must name a lineage in which this coordinate's last
    // decode really is an older version of this tile. A surface whose
    // content gets replaced empties its scope at that moment instead
    // of borrowing across the replacement.
    //
    // N4: `displayImageFor`, so a picture OF THIS TILE outranks a
    // picture of a DIFFERENT one. A stand-in is composed from what the
    // screen already held, so it is at worst a rounding step away from
    // this tile's own bytes; the coordinate fallback below is a
    // previous GENERATION, which is where "the stroke landed and the
    // artwork that was there before it appeared" comes from. Truth
    // still wins over both — `displayImageFor` reads the real image
    // first — and this order also keeps the stand-in out of the
    // per-pixel budget, which is spent on coordinates that have
    // nothing at all.
    //
    // N4 ⑤: and where the engine can upload bytes synchronously, the
    // tile's OWN bytes become its picture right here — no borrow, no
    // per-pixel path, no waiting a decode round. It costs 30-49 us
    // for a 256 px tile against 24-103 ms for four tiles of the
    // per-pixel fallback, and it ADOPTS, so a coordinate pays it
    // once. Null on Skia (probed once per run), where the two
    // fallbacks below stay the whole answer.
    _paintLiveTile(placed);
  }

  /// A tile the overlay replaces: its settled image, if the overlay is
  /// settling and the image has landed; nothing otherwise (the overlay's
  /// own tile draws later). A drawn image wins over the overlay tile.
  void _paintReplacedTile(PlacedTile placed) {
    final settledImage = _overlay!.settling
        ? _painter.tileImageCache.imageFor(placed.tile)
        : null;
    if (settledImage == null) {
      return;
    }
    _drawTileImage(settledImage, placed);
    (_committedWins ??= <TileCoord>{}).add(placed.coord);
  }

  /// [image] at [at]'s own origin, with the tile image paint.
  void _drawTileImage(ui.Image image, PlacedTile at) =>
      _canvas.drawImage(image, tileOriginOffset(at), _tileImagePaint);

  /// A tile the settling stroke holds: the pre-stroke tile, its image or
  /// its pixels.
  void _paintHeldTile(PlacedTile placed) {
    final preTile = _settleHold![placed.coord];
    if (preTile != null) {
      final preImage = _painter.tileImageCache.imageFor(preTile);
      if (preImage != null) {
        _drawTileImage(preImage, (coord: placed.coord, tile: preTile));
      } else {
        _painter._paintTilePixels(
          _canvas,
          (coord: placed.coord, tile: preTile),
          _layerPaint,
        );
      }
    }
  }

  /// The committed tile: its display image, a sync upload while that
  /// budget lasts, the latest image of the coord, the pixel fallback
  /// while its budget lasts — else marked unpainted.
  void _paintLiveTile(PlacedTile placed) {
    final tile = placed.tile;
    var tileImage = _painter.tileImageCache.displayImageFor(tile);
    if (tileImage == null && _syncUploadBudget > 0) {
      tileImage = _painter.tileImageCache.adoptSyncUpload(
        placed,
        staleScope: _painter.staleScope,
      );
      // Spent on the ANSWER, not the attempt — the same correction
      // the per-pixel budget needed. On Skia every call declines, and
      // charging for a decline would be charging for nothing.
      if (tileImage != null) {
        _syncUploadBudget -= 1;
      }
    }
    // 🚨★★★A KNOWN PREDECESSOR FORBIDS THE COORDINATE FALLBACK. The tile
    // the commit replaced, plus the bytes that differ, is exact whichever
    // way the edit went; the coordinate fallback is the last picture
    // DECODED here, and for an edit that removed ink that is the removed
    // ink — F-68 ①②③, every one. So a tile whose commit announced its
    // predecessor composes from it, and when that does not fit this
    // paint's budget it falls to the per-pixel path (exact, four a paint)
    // and then to NOTHING — a blank tile for a frame is a gap, the old
    // picture is a lie, and only one of those was a bug report. The
    // coordinate fallback remains for tiles nobody announced: an import,
    // a cold activation — content that ADDS, where it was always right.
    final predecessor = tileImage == null
        ? TilePredecessors.instance.of(tile)
        : null;
    if (predecessor != null) {
      tileImage = _composeFromPredecessor(placed, predecessor);
    } else {
      tileImage ??= _painter.tileImageCache.latestImageForCoord(
        placed.coord,
        scope: _painter.staleScope,
      );
    }
    if (tileImage != null) {
      _drawTileImage(tileImage, placed);
    } else if (_pixelFallbackBudget > 0) {
      // First-ever content at this coordinate and not decoded yet:
      // draw per pixel for this frame only — within the budget. Every
      // coordinate here is visible, so the budget spends only where it
      // shows (R27 #2).
      //
      // ⚠️ Spent only where it DREW. The walk is raster order, so a
      // commit whose landing sits below empty rows hands the first
      // four slots to tiles with no ink in them and the picture gets
      // none: measured on a Ctrl+T confirm, all four went to the blank
      // pasteboard row above the artwork and the float contributed
      // zero pixels. A transparent tile costs the same scan either
      // way — it just no longer costs a slot.
      if (_painter._paintTilePixels(_canvas, placed, _layerPaint)) {
        _pixelFallbackBudget -= 1;
      }
    } else {
      // Nothing to draw with: no image, nothing to borrow, no budget
      // left. This branch is the whole stale-tile family's event, and
      // it is invisible because its answer is silence — see
      // [MeasurementMode.showUnpaintedTiles].
      _painter._markUnpainted(_canvas, placed);
    }
  }

  /// [placed]'s stand-in composed from its predecessor, put in the cache
  /// and returned — or null when there is no predecessor, its picture is
  /// not on screen, or the composition would exceed what is left of this
  /// paint's budgets (spent on the answer, not the attempt).
  ui.Image? _composeFromPredecessor(
    PlacedTile placed,
    TilePredecessor predecessor,
  ) {
    if (_predecessorTileBudget <= 0 || _predecessorRectBudget <= 0) {
      return null;
    }
    final cache = _painter.tileImageCache;
    final composed = composePredecessorStandIn(
      cache: cache,
      tile: placed.tile,
      predecessor: predecessor,
      rectBudget: _predecessorRectBudget,
    );
    if (composed.image == null) {
      return null;
    }
    _predecessorTileBudget -= 1;
    _predecessorRectBudget -= composed.rects;
    return composed.image;
  }

  /// The paint a LIVE PREVIEW OF A BRUSH LANDING draws with: a pre-blended
  /// overlay blits (src where it replaces the committed tiles), an erasing
  /// one cuts out (dstOut), a blend-mode preview blends, else the tile
  /// paint.
  ///
  /// 🚨★★★ONE FUNCTION FOR EVERY PREVIEW OF A LANDING, not just the stroke
  /// overlay's (유저 2026-09-10, F-69: 「프리뷰 그냥 어차피 브러시랑 똑같은데
  /// 브러시랑 같은취급? 같은 로직 그대로 재사용하면 확실할거같은데」). The cut
  /// tool's hover ghost was drawing with a paint of its own that knew about
  /// opacity and nothing else, so 「불투명도같은건 커서 프리뷰에 반영되는데
  /// 합성모드가 반영안되고있음」. It is a `BrushDab` like any other
  /// (`buildCutPasteDab`), so it previews like one.
  ///
  /// ⚠️THE ARGUMENTS ARE THE FOUR FACTS, not the overlay — the ghost is not
  /// one and never will be (it borrows an image the cut slot owns, which is
  /// why it has a slot of its own; see [CutStampPreview]). What it shares is
  /// the DECISION, and that is what lives here.
  Paint _livePreviewPaint({
    required BrushBlendMode blendMode,
    required bool erase,
    required bool preBlended,
    required bool replacesCoords,
  }) {
    return preBlended
        ? (replacesCoords
              ? _tileImagePaint
              : (Paint()
                  ..filterQuality = FilterQuality.none
                  ..isAntiAlias = false
                  ..blendMode = BlendMode.src))
        : erase
        ? (Paint()
            ..filterQuality = FilterQuality.none
            ..isAntiAlias = false
            ..blendMode = BlendMode.dstOut)
        : blendMode.previewBlendMode != BlendMode.srcOver
        // BB-1: the brush blend previews live (tiles never overlap,
        // so per-tile draws blend each pixel exactly once).
        ? (Paint()
            ..filterQuality = FilterQuality.none
            ..isAntiAlias = false
            ..blendMode = blendMode.previewBlendMode)
        : _tileImagePaint;
  }

  Paint _overlayPaintFor(ActiveStrokeOverlayModel overlay) => _livePreviewPaint(
    blendMode: overlay.blendMode,
    erase: overlay.erase,
    preBlended: overlay.preBlended,
    replacesCoords: _overlayReplacesCoords,
  );

  void _paintOverlay() {
    if (_overlay != null) {
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
      final overlayPaint = _overlayPaintFor(_overlay);
      // R26 #18 (the selection) is NOT clipped here any more: the
      // selection mask rides the pre-blend kernel, so a tile's result
      // already equals the base wherever the selection excludes it. The
      // painter draws the same bytes the commit will hold — which is
      // also what lets a selected stroke keep the whole-coordinate
      // replacement path below instead of an isolation layer.
      final overlayTileSize = _overlay.tileSize.toDouble();
      for (final entry in _overlay.tileImages.entries) {
        if (_committedWins?.contains(entry.key) ?? false) {
          // The base pass already drew this coordinate's finished tile.
          continue;
        }
        final origin = Offset(
          entry.key.x * overlayTileSize,
          entry.key.y * overlayTileSize,
        );
        if (!_overlayTileIsVisible(origin, overlayTileSize)) {
          continue;
        }
        _canvas.drawImage(entry.value, origin, overlayPaint);
      }
      // R23: a fill tap's _overlay is ONE pre-decoded stamp image at the
      // commit's exact placement (never coexists with stroke tiles).
      final stampImage = _overlay.stampImage;
      if (stampImage != null) {
        _canvas.drawImage(stampImage, _overlay.stampOffset, overlayPaint);
      }
    }
  }

  /// 🚨★★★**THE SAME VISIBLE-RECT LAW THE BASE PASS KEEPS**
  /// (`tilesUnderRect` at [_paintVisibleTiles]), and the overlay pass was
  /// the one place it was not applied. Overlay tiles ACCUMULATE for the
  /// whole life of a stroke — nothing leaves the map until pen-up — so by
  /// the third dab that map is the bounding box of the WHOLE stroke, and
  /// a long line paid its full length in draws on every frame of every
  /// dab, off-screen coordinates included.
  bool _overlayTileIsVisible(Offset origin, double tileSize) =>
      _visibleRect.overlaps(
        Rect.fromLTWH(origin.dx, origin.dy, tileSize, tileSize),
      );

  /// The cut-piece stamp preview, over everything.
  void _paintStampPreview() {
    final preview = _painter.stampPreview?.value;
    if (preview != null) {
      paintCutPiece(
        _canvas,
        preview.canvasRect,
        preview.piece,
        preview.image,
        opacity: preview.opacity,
        // F-69: the ghost's composite comes out of the SAME function the
        // stroke overlay's does.
        //
        // ⛔`preBlended: false` is not a shortcut. Pre-blending is what buys
        // a live STROKE its byte-exact preview (R27 #4), and it buys it by
        // running the commit's CPU kernels over the overlay's tiles against
        // the cel. A hover ghost has no committed tiles to stand for: it is
        // redrawn on every pointer move, never committed, and gone the
        // moment the click lands — at which point the real stroke overlay
        // takes over and IS pre-blended.
        blendMode: _livePreviewPaint(
          blendMode: preview.blendMode,
          erase: preview.blendMode == BrushBlendMode.erase,
          preBlended: false,
          replacesCoords: false,
        ).blendMode,
      );
    }
  }
}
