part of '../bitmap_surface_painter.dart';

/// ONE PAINT OF A BITMAP SURFACE'S CONTENT — the paper, the visible tiles
/// (a committed image, a held pre-stroke tile, or the live tile within its
/// upload and pixel-fallback budgets), the stroke overlay, the stamp preview.
/// 🚨Carved out of `BitmapSurfacePainter` (the audit's cognitive cut, Round
/// 6, 2026-09-03: `paintContentInto` was 418 lines scoring 80). Constructed
/// PER PAINT; it reaches the painter through `_painter`.
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
  late final int _level;
  late int _levelTileBudget;
  late final Rect _visibleRect;
  List<PlacedTile>? _pendingDecodes;

  /// The one answer to what a coordinate shows ([_CoordinatePicture]).
  late final _CoordinatePicture _coordinates = _CoordinatePicture(this);

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
  ///
  /// [level] is the display pyramid's level this paint composes at
  /// ([BitmapSurfacePainter.paintContentInto]).
  void paintContentInto(Canvas canvas, {Paint? layerPaint, int level = 0}) {
    _canvas = canvas;
    _layerPaint = layerPaint;
    _level = level;
    _painter.pictureBudget.paintBegan(_painter.staleScope);
    if (_level > 0) {
      TilePyramid.instance.paintBegan(_painter.staleScope);
    }
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
    // 4c: the level tiles made in this paint ([_LevelBlocks._mayMake]).
    _levelTileBudget = BitmapSurfacePainter.decodeStartBudget;
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
    // ⚠️ `tileAt`, NOT `surface.tiles[...]`. `tiles` WAS a getter copying
    // the cel's whole map per read (`Map.unmodifiable`), so this walk was
    // O(visible coords × cel tiles): 0.49 ms per paint at 70 tiles, 1.48 ms
    // at 88, 82.7 ms per walk at the 1024 tiles the _canvas dialog allows —
    // a cliff, not a smoothness question. 2d0478fb (2026-09-09) stopped the
    // copy, so both lookups are O(1) now; `tileAt` stays the one meant here.
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
    _painter.pictureBudget.paintEnded();
    if (_level > 0) {
      TilePyramid.instance.paintEnded(_painter.staleScope);
    }
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

  /// Every coordinate under the visible rect, drawn as what it shows
  /// ([_coordinate]) — the committed tiles, each stamped as shown for the
  /// picture budget ([TilePictureBudget.shown]), and the live stroke's
  /// coordinates that have no committed tile yet (ink on blank paper),
  /// which are coordinates like any other.
  ///
  /// Above level 0 the visible rect is walked in BLOCKS instead
  /// ([_LevelBlocks]): a block drawn as one level tile shows none of its
  /// tiles' pictures, so they are not stamped and the budget may let them
  /// go — zoomed out, the level tiles are the pictures the screen needs.
  void _paintVisibleTiles() {
    if (_level > 0) {
      _LevelBlocks(this).paint();
      return;
    }
    for (final covered in tilesUnderRect(_painter.surface, _visibleRect)) {
      _painter.pictureBudget.shown(_painter.staleScope, covered.tile);
      _coordinates.paint(covered.coord);
    }
    final overlay = _overlay;
    if (overlay == null || !_overlayReplacesCoords) {
      return;
    }
    for (final coord in overlay.tileImages.keys) {
      if (_painter.surface.tileAt(coord) == null && _coordIsVisible(coord)) {
        _coordinates.paint(coord);
      }
    }
  }

  /// 🚨★★★**THE SAME VISIBLE-RECT LAW THE TILE WALK KEEPS**
  /// (`tilesUnderRect` above), for coordinates the surface has no tile at.
  /// The overlay's tiles ACCUMULATE for the whole life of a stroke —
  /// nothing leaves the map until pen-up — so by the third dab that map is
  /// the bounding box of the WHOLE stroke, and a long line paid its full
  /// length in draws on every frame of every dab, off-screen coordinates
  /// included.
  bool _coordIsVisible(TileCoord coord) {
    final tileSize = _painter.surface.tileSize.toDouble();
    return _visibleRect.overlaps(
      Rect.fromLTWH(coord.x * tileSize, coord.y * tileSize, tileSize, tileSize),
    );
  }

  /// THE tile draw: [image], one tile's worth of pixels, at [coord]'s
  /// origin on the surface's grid — a coordinate's picture at level 0, a
  /// level tile under its block's scale above it ([_LevelBlocks]).
  void _drawImageAtTile(ui.Image image, TileCoord coord) =>
      _canvas.drawImage(
        image,
        tileCoordOriginOffset(coord, _painter.surface.tileSize),
        _tileImagePaint,
      );

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

  /// The live stroke's tiles and stamp over the committed tiles
  /// ([_OverlayPass]).
  void _paintOverlay() {
    if (_overlay != null) {
      _OverlayPass(this, _overlay).paint();
    }
  }

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
