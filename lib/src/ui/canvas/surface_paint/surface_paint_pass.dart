part of '../bitmap_surface_painter.dart';

/// ONE PAINT OF A BITMAP SURFACE'S CONTENT — the paper, the visible
/// coordinates (each drawn as the one picture it shows, [_CoordinatePicture]),
/// the stroke overlay, the floats. 🚨Carved out of
/// `BitmapSurfacePainter` (the audit's cognitive cut, Round 6, 2026-09-03:
/// `paintContentInto` was 418 lines scoring 80). Constructed PER PAINT; it
/// reaches the painter through `_painter`.
class _SurfacePaintPass {
  _SurfacePaintPass(this._painter);

  final BitmapSurfacePainter _painter;

  late final Canvas _canvas;
  late final Paint? _layerPaint;
  late final double _canvasWidth;
  late final double _canvasHeight;
  late final Rect _storableRect;
  late final ActiveStrokeOverlayModel? _overlay;
  late final bool _overlayReplacesCoords;
  late final bool _overlayBlendsInLayer;
  late final Paint _tileImagePaint;

  /// Device pixels a canvas pixel lands on ([BitmapSurfacePainter
  /// .paintContentInto]), and whether that is a reduction.
  late final double _scale;
  late final bool _reduced = _scale < 1;
  late final Rect _visibleRect;

  /// Device pixels a unit of the canvas's space lands on past its transform
  /// ([cutOnThePixelGrid]) — the screen's ratio on screen, 1 into a raster.
  late final double _pixelRatio;

  /// Whether each coordinate's picture is laid with its edge cut on the
  /// pixel grid rather than where it falls ([_drawImageAtTile]).
  late final bool _tilesCutOnTheGrid;

  /// Whether the layer's paint goes around the cut coordinates as one layer
  /// rather than riding each of them ([paintContentInto]).
  late final bool _layerAroundTheCut;

  /// The slots of pages this paint lays a page at a time — null where they
  /// are laid one by one ([paintContentInto]).
  late final SlotsByPage? _slotsByPage;

  /// The float the caller handed in — a selection's, from the row's slot.
  late final RowFloat? _float;

  /// Every float this paint draws over the surface: the caller's, and the
  /// painter's own ([BitmapSurfacePainter.landingPreview]).
  late final List<RowFloat> _floats;

  /// The one answer to what a coordinate shows ([_CoordinatePicture]).
  late final _CoordinatePicture _coordinates = _CoordinatePicture(this);

  /// The surface + live _overlay, onto a _canvas the CALLER has already
  /// viewport-transformed and clipped to [_storableRect].
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
  /// [scale] is how many device pixels this paint lands on a canvas pixel,
  /// and [pixelRatio] how many a unit of [canvas]'s space lands on past its
  /// transform ([BitmapSurfacePainter.paintContentInto]).
  void paintContentInto(
    Canvas canvas, {
    Paint? layerPaint,
    double scale = 1,
    required double pixelRatio,
    RowFloat? float,
  }) {
    _canvas = canvas;
    _layerPaint = layerPaint;
    _scale = scale;
    _pixelRatio = pixelRatio;
    _float = float == null || float.preview.drawnWorldRect.isEmpty
        ? null
        : float;
    _floats = [?_float, ?_painter._ownFloat];
    _painter.pictureBudget.paintBegan(_painter.lineage);
    assert(
      _layerPaint == null || _painter.drawsDisjointCoverage,
      'A layer paint may only ride the individual draws when they cover '
      'each pixel once — see drawsDisjointCoverage.',
    );
    _canvasWidth = _painter.surface.canvasSize.width.toDouble();
    _canvasHeight = _painter.surface.canvasSize.height.toDouble();
    _storableRect = _painter.storableRect;

    _paintPaper();

    // An erasing _overlay draws destination-out against the committed tiles.
    // The tiles + _overlay MUST be isolated in their own layer: without it,
    // dstOut applies to the whole accumulated compositing buffer — the
    // painter's own background here, and in the production editing path
    // (paper in the separate underlay widget) the paper and panel chrome
    // BELOW this picture, which showed live erase strokes as dark
    // panel-background lines until the commit landed (R14-⑤). The layer
    // makes the hole transparent so whatever is underneath shows through.
    // ↩️BB-1 put a non-srcOver BRUSH BLEND drawn on the GPU in the same
    // isolation — to blend against the CEL's pixels only, never the paper
    // or panel chrome below — until brush-fidelity-Q9 left no brush blend
    // drawn on the GPU.
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
      _canvas.saveLayer(_storableRect, Paint());
    }

    // 🚨★★★T21 (유저 2026-08-13 「줌이 정한다」): the display's one law, read at
    // this paint's scale — `none` into a buffer at the canvas's resolution
    // (a tile is filtered with no neighbours to sample, so `low` there
    // would buy a seam at every tile edge); reduced, the filter, from each
    // picture's chain ([_CoordinatePicture]). ↩️Every paint drew `none`
    // until one-picture-per-frame ②-5b-2 — a reduced one from level tiles
    // at the level's residual, and between 50% and 100% the tiles
    // themselves, nearest.
    final filterQuality = filterQualityForDisplayScale(_scale);
    // 🚨★★★A COORDINATE'S EDGE IS ONE MORE TEXEL BOUNDARY
    // (the-walk-draws-off-the-grid-on-impeller, 2026-10-28). Under nearest
    // sampling on an axis-aligned space the boundary between two
    // coordinates is decided per pixel by its centre, as every boundary
    // inside a picture is ([displayEdgeAntiAliased]) — but each coordinate
    // is its own draw, and where the grid falls inside a pixel Impeller's
    // MSAA covers that pixel by both draws' samples, whatever the paint
    // says: 🔬150% on the walk, a line's pixels on the canvas's edge 64
    // grey for black, and 137% riding an add 129 pixels up to 23 apart from
    // the buffer (`--enable-impeller`). So there each edge is cut on the
    // grid, as the paper's and the buffer's blit are. ⛔Only there: the
    // cut lays the picture through a shader under a clip, and into a
    // buffer at the canvas's own resolution — every frame's picture and
    // every step's patch — the grid lands whole and `drawImage` is the
    // same pixels.
    _tilesCutOnTheGrid =
        filterQuality == FilterQuality.none &&
        cellsFallOffThePixelGrid(
          _canvas,
          _painter.surface.tileSize.toDouble(),
          pixelRatio,
        );
    // 🚨A COLOUR MATRIX DOES NOT RIDE A CUT (10-28). A coordinate cut on
    // the grid is laid through a shader, and Impeller applies a paint's
    // colour matrix to a shader's colours not as it does to an image's:
    // 🔬a ghost's tint and a brighten, 3,264–3,736 of 4,096 pixels apart up
    // to 223/255, where the same matrix on a layer around the shader is 0
    // apart (`--enable-impeller`). There the layer's paint goes around the
    // coordinates as one layer — the buffer a ride stands for, the same
    // pixels by their disjoint coverage (`the_layer_rides_the_draws_test`).
    _layerAroundTheCut =
        _tilesCutOnTheGrid && _layerPaint?.colorFilter != null;
    _tileImagePaint = Paint()
      ..filterQuality = filterQuality
      ..isAntiAlias = false;
    if (_layerPaint != null && !_layerAroundTheCut) {
      // The layer rides every draw instead of a buffer around them.
      _tileImagePaint
        ..color = _layerPaint.color
        ..blendMode = _layerPaint.blendMode
        ..colorFilter = _layerPaint.colorFilter
        ..imageFilter = _layerPaint.imageFilter;
    }
    // 🚨★★★A PAGE'S SLOTS IN ONE DRAW, WHERE THAT IS THE SAME PIXELS
    // (frame-composite-draws-each-tile-on-its-own, 2026-10-28) — [SlotsByPage]
    // has the measurement: not where a colour matrix rides, whose alpha
    // Impeller rounds apart in an atlas, nor where a coordinate is cut,
    // which lays each through a shader. There each slot is laid by itself,
    // as its own picture would be. ⛔An image filter is no answer measured:
    // it never rides (a spreading one buffers the layer), and one that did
    // would act on the page's draw as a whole.
    _slotsByPage =
        _tilesCutOnTheGrid ||
            _tileImagePaint.colorFilter != null ||
            _tileImagePaint.imageFilter != null
        ? null
        : SlotsByPage();
    // R27 #2: the walk below is visible-only, so every coordinate it
    // reaches already shows — no separate visibility test is needed.
    _visibleRect = _painter._visibleCanvasRect(_canvas, _storableRect);

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
    //
    // 🚨★★★F-240: reduced, what a landing preview covers is not drawn here
    // but made whole below ([_paintLandingReduced]).
    final landing = _reduced ? _landingRegion() : null;
    if (landing != null) {
      _canvas.save();
      _canvas.clipRect(
        landing,
        clipOp: ui.ClipOp.difference,
        doAntiAlias: false,
      );
    }
    if (_layerAroundTheCut) {
      _canvas.saveLayer(_visibleRect, _layerPaint!);
    }
    _paintVisibleTiles();

    _paintOverlay();

    if (_layerAroundTheCut) {
      _canvas.restore();
    }
    if (landing != null) {
      _canvas.restore();
    }
    if (_overlayBlendsInLayer) {
      _canvas.restore();
    }

    if (landing != null) {
      _paintLandingReduced(landing);
    } else {
      // ↩️🚨★★★F-33: the STAMP's ghost was drawn here, after the overlay's
      // restore (outside a stroke's isolation layer), so [_layerPaint]
      // reached it — the user's 「레이어 블렌드모드나 **합성같은게 다**
      // 반영되는」. Since brush-fidelity-Q9 (유저 2026-10-18 「통일하면 좋음」)
      // it is the OVERLAY's tiles — the click's own bytes, pre-blended on
      // the CPU — which this pass draws in the layer's paint, so F-33 holds
      // by construction.
      _paintLandingPreviews();
    }

    // No pasteboard dim (user decision, Flash-style): off-_canvas artwork
    // shows at full brightness — the paper edge against the backdrop is
    // the stage boundary.
    _painter.pictureBudget.paintEnded();
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

  /// Every coordinate under the visible rect, drawn as what it shows
  /// ([_coordinates]) — the committed tiles, each stamped as shown for the
  /// picture budget ([TilePictureBudget.shown]), and the live stroke's
  /// coordinates that have no committed tile yet (ink on blank paper),
  /// which are coordinates like any other.
  ///
  /// At every scale: reduced, the screen is fed from these same pictures,
  /// so they are the ones it needs. ↩️Below 100% a block was drawn as one
  /// level tile, which stamped none of the pictures under it and let the
  /// budget let them go — until one-picture-per-frame ②-5b-2.
  void _paintVisibleTiles() {
    for (final covered in tilesUnderRect(_painter.surface, _visibleRect)) {
      _painter.pictureBudget.shown(_painter.lineage, covered.tile);
      _coordinates.paint(covered.coord);
    }
    // The slots go down here, a page at a time, under nothing the walk
    // drew: the coordinates are disjoint, so the order among them is no
    // pixel's business.
    _slotsByPage?.drawInto(_canvas, _tileImagePaint);
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

  /// A committed tile's [picture] at [coord]: a texture of its own as any
  /// tile image ([_drawImageAtTile]); a slot of a page with the page's
  /// others where they go together ([_slotsByPage]), else by itself.
  void _drawPictureAtTile(TilePicture picture, TileCoord coord) {
    switch (picture) {
      case OwnTilePicture(:final image):
        _drawImageAtTile(image, coord);
      case final TileSlot slot:
        final together = _slotsByPage;
        if (together == null) {
          _lay(slot.image, slot.source, coord);
        } else {
          together.add(
            slot,
            tileCoordOriginOffset(coord, _painter.surface.tileSize),
          );
        }
    }
  }

  /// [image], one tile's worth of pixels — a coordinate's picture — at
  /// [coord]'s origin ([_lay]).
  void _drawImageAtTile(ui.Image image, TileCoord coord) =>
      _lay(image, null, coord);

  /// THE tile draw: [source] of [image] — the whole of it where null — at
  /// [coord]'s origin on the surface's grid, its edge cut on the pixel grid
  /// where the grid falls off it ([_tilesCutOnTheGrid]).
  void _lay(ui.Image image, Rect? source, TileCoord coord) {
    final origin = tileCoordOriginOffset(coord, _painter.surface.tileSize);
    if (!_tilesCutOnTheGrid) {
      if (source == null) {
        _canvas.drawImage(image, origin, _tileImagePaint);
      } else {
        _canvas.drawImageRect(
          image,
          source,
          origin & source.size,
          _tileImagePaint,
        );
      }
      return;
    }
    final from =
        source ??
        Offset.zero & Size(image.width.toDouble(), image.height.toDouble());
    drawImageRectOnThePixelGrid(
      _canvas,
      image,
      from,
      origin & from.size,
      filterQuality: FilterQuality.none,
      pixelRatio: _pixelRatio,
      paint: _tileImagePaint,
    );
  }

  /// The paint a LIVE PREVIEW OF A BRUSH LANDING draws with: a pre-blended
  /// overlay blits (src where it replaces the committed tiles), an erasing
  /// one cuts out (dstOut), else the tile paint.
  ///
  /// 🚨★★★ONE FUNCTION FOR EVERY PREVIEW OF A LANDING, not just the stroke
  /// overlay's (유저 2026-09-10, F-69: 「프리뷰 그냥 어차피 브러시랑 똑같은데
  /// 브러시랑 같은취급? 같은 로직 그대로 재사용하면 확실할거같은데」). The cut
  /// tool's hover ghost was drawing with a paint of its own that knew about
  /// opacity and nothing else, so 「불투명도같은건 커서 프리뷰에 반영되는데
  /// 합성모드가 반영안되고있음」. It is a `BrushDab` like any other
  /// (`buildCutPasteDab`), so it previews like one.
  ///
  /// ↩️The ghost shared only the DECISION, with facts of its own for the
  /// arguments — it borrowed an image the cut slot owned, so it kept a slot
  /// of its own rather than being an overlay — until brush-fidelity-Q9 (유저
  /// 2026-10-18 「통일하면 좋음」): it lays the click's own dab through the
  /// overlay now, and takes the pre-blended road exactly as a stroke does.
  Paint _livePreviewPaint({
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
        // ↩️BB-1 previewed a brush blend live on the GPU here, and the
        // stamp's ghost was its last rider (brush-fidelity-Q7: a mode the
        // GPU has no blend for drew as normal). Every stroke pre-blends
        // (R27 #4) and since brush-fidelity-Q9 so does the ghost, so only
        // R27 #4's revert switch — a plain stroke's classic overlay — is
        // left on this road.
        : _tileImagePaint;
  }

  /// The live stroke's tiles over the committed tiles ([_OverlayPass]).
  void _paintOverlay() {
    if (_overlay != null) {
      _OverlayPass(this, _overlay).paint();
    }
  }

  /// The floats, cut at the pasteboard as what they land as is: a landing
  /// is a tool's, and only a file's picture reaches past the wall
  /// (F-374-Q8) — which a surface clipped wider for it ([_storableRect])
  /// would otherwise let a preview do as well. ↩️The stamp's ghost was cut
  /// here too, until brush-fidelity-Q9 made it the overlay's tiles: the
  /// click's own landing, so cut wherever the landing is.
  void _paintLandingPreviews() {
    final wider = _painter.surface.laidBounds != null;
    if (wider) {
      _canvas.save();
      // Cut as a float's own edge is, on the grid (`CelTextLanding`) —
      // ↩️at a fraction of a pixel until
      // the-walk-family-cuts-the-rest-on-the-grid.
      clipToTheDisplayEdge(
        _canvas,
        _painter.surface.pasteboard.rect,
        antiAlias: false,
        pixelRatio: _pixelRatio,
      );
    }
    _paintFloat();
    if (wider) {
      _canvas.restore();
    }
  }

  /// The floats, over everything this surface drew. A selection's is
  /// CANVAS space, so into a posed row it goes through the row's matrix.
  void _paintFloat() {
    for (final float in _floats) {
      final toRow = float.canvasToRow;
      if (toRow == null) {
        float.preview.paintInto(_canvas, pixelRatio: _pixelRatio);
        continue;
      }
      _canvas.save();
      _canvas.transform(toRow.storage);
      float.preview.paintInto(_canvas, pixelRatio: _pixelRatio);
      _canvas.restore();
    }
  }

  /// Where this paint's landing preview — the float — draws, in this
  /// paint's own space and inside what it shows, grown out to whole tiles
  /// of the surface (the grid its landed pictures' chains are made on,
  /// [_paintLandingReduced]); null when none draws.
  Rect? _landingRegion() {
    Rect? covered;
    for (final float in _floats) {
      final toRow = float.canvasToRow;
      final drawn = float.preview.drawnWorldRect;
      final inRow = toRow == null
          ? drawn
          : MatrixUtils.transformRect(toRow, drawn);
      covered = covered?.expandToInclude(inRow) ?? inRow;
    }
    if (covered == null) {
      return null;
    }
    final shown = covered.intersect(_visibleRect);
    return shown.isEmpty
        ? null
        : rectOutwardOnGrid(shown, 1 / _painter.surface.tileSize);
  }

  /// 🚨★★★F-240 (유저 2026-09-29: 「변형툴 변형도중이랑 확정이랑 그림 바뀌는
  /// 문제. 100%줌일땐 괜찮은데 50%에서 변형중에 필터 없음으로 보임 …
  /// 변형중에도 필터 통일적용하도록 근본/구조적 해결」): what a landing
  /// preview covers, reduced, is made THE WAY ITS LANDING WILL BE SHOWN.
  ///
  /// A landed cel shows here as its tiles' pictures reduced from their
  /// chains, each the 100% picture of its coordinate ([_CoordinatePicture]).
  /// The float laid over the tiles, each reduced on its own, would blend
  /// its edge with nothing under it where the landed tile blends it with
  /// the cel. So each tile of [region] is painted by this same pass at
  /// 100% — the coordinates, the overlay and the float exactly as 100% shows
  /// them — into a render of its own, which the engine gives its chain, and
  /// drawn reduced at its coordinate as the tile it lands as is: a picture
  /// of the same size and bytes, the same chain, the same draw — so the
  /// same bytes at every scale.
  ///
  /// ⛔NOT ONE RENDER OF THE REGION. 🔬Drawn so (this pin, 10-25), it was
  /// apart from the landing wherever it is not a halving — on Skia on the
  /// band a tile's edge is filtered on (60%: 47 pixels), on Impeller Vulkan
  /// over most of the region (60%: 555), whose chain of a picture drifts
  /// with the picture's size. One render can also pass the texture cap the
  /// walk past it (`layer_stack_paint_pass.dart`) exists for; a tile cannot.
  ///
  /// ↩️The region was made at the display's level, halved from 100% one
  /// 2×2 box at a time, while a landed cel showed as level tiles — until
  /// one-picture-per-frame ②-5b-2.
  void _paintLandingReduced(Rect region) {
    final tileSize = _painter.surface.tileSize;
    final tiles = tileRangeCovering(
      left: region.left,
      top: region.top,
      right: region.right,
      bottom: region.bottom,
      tileSize: tileSize,
    );
    for (final coord in tileCoordsIn(tiles)) {
      final image = _rasterAtFullSize(
        tileCoordOriginOffset(coord, tileSize) &
            Size.square(tileSize.toDouble()),
      );
      _drawImageAtTile(image, coord);
      // Safe once drawn: the draw holds its own claim on the pixels.
      image.dispose();
    }
  }

  /// [region] as 100% shows it — this same pass, one canvas pixel to one
  /// raster pixel.
  ui.Image _rasterAtFullSize(Rect region) {
    final recorder = ui.PictureRecorder();
    final atFull = Canvas(recorder)
      ..translate(-region.left, -region.top)
      ..clipRect(region);
    _SurfacePaintPass(
      _painter,
    ).paintContentInto(atFull, pixelRatio: 1, float: _float);
    final picture = recorder.endRecording();
    try {
      return picture.toImageSync(region.width.round(), region.height.round());
    } finally {
      picture.dispose();
    }
  }
}
