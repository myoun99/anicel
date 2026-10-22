part of '../canvas_layer_stack_view.dart';

/// What a display-buffer miss can start from — the carried base to patch
/// (with the live dirty rect), the previous buffer to scroll, or neither —
/// and what the live surface looks like now, stored with the buffer this
/// miss makes so the NEXT miss can measure from it.
/// A base to start a miss from: the image, the rect its pixels cover, the
/// tokens the dirty rect is measured from, and whether drawing it forms a
/// link in the deferred chain (only the cache's HEAD does; its real base
/// does not — `DisplayBufferCache` says why).
typedef _Base = ({
  ui.Image image,
  Rect rect,
  LiveSurfaceTokens tokens,
  bool deferred,
});

typedef _MissPlan = ({
  _Base? base,
  Rect? dirty,
  _Base? scroll,
  bool canScroll,
  LiveSurfaceTokens? tokens,
});

/// A surface row's own paint: what its layer composites with.
typedef _SurfaceRowPaint = ({
  double opacity,
  LayerBlendMode blendMode,
  LayerPlacement? placement,
  List<ResolvedLayerEffect> effects,
});

/// What one SURFACE row's paint reads — the live row's, or a row a folder's
/// lift holds (I-37): its painter, the float drawn into it, and the way into
/// its slot from the canvas that float is told in.
///
/// ⛔One body draws both ([_LayerStackPaintPass._paintSurfaceRow]): a lifted
/// row is a surface with a float over it in its own row's slot, which is
/// what the live row is while a box is open — two copies of that body are
/// what would drift apart.
class _SurfaceSlot {
  _SurfaceSlot({
    required this.painter,
    required this.float,
    required this.keys,
    required LayerPlacement? placement,
  }) : canvasToSlot = _undoneWrap(placement);

  final BitmapSurfacePainter painter;
  final SelectionFloatOverlay? float;

  /// The row's leading colour keys — the half its surface already went
  /// through, which a float over it is shown through as well ([shown]).
  final List<ResolvedLayerEffect> keys;

  /// What takes the float — CANVAS space, by its contract
  /// ([SelectionFloatPaint]) — into the slot, which is drawn under its row's
  /// pose wrap: that wrap, undone. Null for an unplaced row, whose slot IS
  /// the canvas.
  ///
  /// 🚨a-marquee-on-a-posed-row (2026-09-25): the lift takes a posed row's
  /// pixels out through its placement onto the canvas, where the box moves
  /// them (`stampOnCanvas`). Drawn inside the wrap as they came, the float
  /// of a row moved right by 100 showed 100 further right than its box.
  final Matrix4? canvasToSlot;

  static Matrix4? _undoneWrap(LayerPlacement? placement) {
    if (placement == null) {
      return null;
    }
    final wrap = placementMatrix(placement);
    return wrap.invert() == 0 ? null : wrap;
  }

  /// The float as this row shows it ([SelectionFloatPaint.shownOn]), or
  /// null when nothing floats — read ONCE per paint, as [extent] is: on a
  /// keyed row the answer can be a landing.
  late final RowFloat? shown = switch (float?.value) {
    null => null,
    final value when value.isEmpty => null,
    final value => value.shownOn(keys, canvasToRow: canvasToSlot),
  };

  /// What the slot draws, in its own space — the law is
  /// [_LayerStackPaintPass._activeSurfaceExtent]'s (F-85).
  late final Rect extent = () {
    final drawn = painter.drawnWorldRect;
    final shown = this.shown;
    final told = shown?.preview.drawnWorldRect;
    if (shown == null || told == null || told.isEmpty) {
      return drawn;
    }
    final intoSlot = shown.canvasToRow;
    final floated = intoSlot == null
        ? told
        : MatrixUtils.transformRect(intoSlot, told);
    // A slot that draws nothing answers [Rect.zero], and a union with it
    // would reach back to the origin.
    return drawn.isEmpty ? floated : drawn.expandToInclude(floated);
  }();
}

/// Who paints a node's children under a walk — the plain walk, or the split
/// walk that descends the chain enclosing the active layer and replays a
/// recording for the rest.
typedef _ChildPainter =
    void Function(
      Canvas canvas,
      List<CompositeNode<_PaintRow>> children,
      double rasterScale,
    );

/// ONE PAINT OF THE LAYER STACK — the walk that draws the composite tree
/// under the viewport, the split that paints the chain enclosing the active
/// layer live and replays a recording for the rest, the paper and the
/// backdrop, and the one buffer at canvas resolution that is resampled
/// once.
///
/// 🚨A collaborator carved out of `_LayerStackPainter` (the audit's
/// cognitive cut, Round 6, 2026-09-03): `paint` was 784 lines with six
/// local functions nested inside it, scoring 105 on the cognitive meter.
/// It reaches the painter through `_painter`.
class _LayerStackPaintPass {
  _LayerStackPaintPass(this._painter);

  final _LayerStackPainter _painter;

  /// How THIS view samples artwork — the T21 / D14 display law, asked once
  /// so the walk cannot disagree with the buffer.
  ///
  /// 🚨★★★SAMPLING IS A PROPERTY OF THE DISPLAY, NOT OF THE LAYER (유저 확정
  /// T21, 2026-08-13: 「줌이 정한다 — 확대는 `none`, 축소는 필터, 액티브인지는
  /// 안 묻는다」; the whole law and its reasons are in
  /// [filterQualityForDisplayScale]).
  ///
  /// ⛔The buffered route has read it since it was written. The WALK — the
  /// safety net past the buffer cap — was still handing every cached image
  /// a flat `low`, which filtered a MAGNIFIED view. Two routes sampling
  /// differently is the T21 defect wearing a different hat: the artwork
  /// changed depending on which one the frame happened to take.
  ///
  /// The active layer's TILES draw through `BitmapSurfacePainter` at `none`
  /// on purpose — a tile is filtered with no neighbours to sample, so `low`
  /// there buys a seam at every tile boundary — and below 100% they reach
  /// the buffer as LEVEL TILES (4c, [TilePyramid]): exact box means drawn
  /// 1:1 in the level's pixels, so the layer being drawn on and the layers
  /// around it are the same picture at every zoom. Only the LIVE stroke's
  /// overlay tiles still meet the recorder's scale directly, for the
  /// frames of the stroke.
  ui.FilterQuality get _displayQuality =>
      filterQualityForDisplayScale(_displayScale);

  /// Device pixels per artwork pixel ([displayScaleOf]) — the one quantity
  /// the display law, its edge, the sampling phase and a self-rasterising
  /// group's raster scale all read.
  double get _displayScale =>
      displayScaleOf(_painter.viewport.zoom, _painter.devicePixelRatio);

  /// The display law's edge ([displayEdgeAntiAliased]) for this paint's
  /// view: the walk's paper rect cuts the canvas's edge by the same rule.
  bool get _displayEdgeAntiAliased =>
      displayEdgeAntiAliased(_painter.viewport, _painter.devicePixelRatio);

  /// The level the display buffer is composed at this paint
  /// ([displayLevelOf]): 0 at or above 100%, where the buffer is at canvas
  /// resolution and its bytes are what they always were; below, the
  /// artwork halved this many times, so the buffer is the screen's size
  /// (to within a factor of two) and not the visible canvas's.
  int get _level => displayLevelOf(_displayScale);

  /// One buffer pixel in canvas pixels at [_level].
  double get _levelStep => (1 << _level).toDouble();

  /// How the buffer's blit samples: the residual the level image is
  /// reduced by ([displayResidualOf]) — `none` where a level lands 1:1.
  ui.FilterQuality get _bufferQuality =>
      filterQualityForDisplayScale(displayResidualOf(_displayScale));

  /// The display law's edge for the buffer's blit and the paper inside it,
  /// cut by the residual the level is reduced by.
  bool get _bufferEdgeAntiAliased => displayEdgeAntiAliased(
    _painter.viewport,
    _painter.devicePixelRatio,
    level: _level,
  );

  // One paint's geometry: set by [paint] before the walk below reads it.
  // The page rect, the on-screen part of the pasteboard, the content the
  // display buffer must cover, the part of it the bake records over, and
  // the active slot's two extents, each read once.
  late final Rect _canvasRect;
  late final Rect _visibleCanvasRect;
  late final Rect _contentExtent;
  late final Rect _bakeExtent;
  Rect? _memoCommittedExtent;

  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    applyViewportTransform(
      canvas,
      _painter.viewport,
      devicePixelRatio: _painter.devicePixelRatio,
    );

    _canvasRect = _painter.canvasSize.canvasRect;
    // T12 field probe, one floor DOWN from the canvas area's.
    //
    // That one measures what the WIDGET decided; this measures what the
    // paint actually did, and the difference between them is the whole
    // question: past the cut's end line the paper is gone from the screen
    // while the widget above still answers `paper=true`. Only a probe here
    // can say whether this painter ran, what it was told, and whether the
    // paper it was told to draw is even visible ink — `paintProjectPaper`
    // returns without drawing when the colour's alpha is zero, and that is
    // an answer no widget-level value can show.
    //
    // Static because a `CustomPainter` is rebuilt every frame: an instance
    // field would compare against itself and print every time. ⚠️Not behind
    // an `assert` for the reason the sibling probe carries — release builds
    // are the ones that get reported. The visibility flag is the guard.
    if (InputInspector.visible.value) {
      // ⛔`${_painter.paintPaper}`, braces and all. Without them (until
      // 2026-09-13) this printed the PAINTER — `paper=_LayerStackPainter#
      // 2445e(…).paintPaper` — so the flag it exists to show was never
      // shown, and the painter's hash in the key made every rebuild a new
      // line: a pan or a zoom, which rebuilds per frame, wrote a line per
      // frame into a five-note ring. Found because that flood evicted the
      // buffer counters line in `paint_geometry_probe_test`.
      final probe =
          'stack paint paper=${_painter.paintPaper}'
          ' alpha=${Color(_painter.paperBackground.paintedArgb).a.toStringAsFixed(2)}'
          ' nodes=${_painter.nodes.length}'
          ' rect=${_canvasRect.width.round()}x${_canvasRect.height.round()}';
      if (probe != _LayerStackPainter._lastStackProbe) {
        _LayerStackPainter._lastStackProbe = probe;
        InputInspector.note(probe);
      }
    }
    // The group buffer's bounds are a SIZE HINT to the engine: it
    // allocates an offscreen that big. The pasteboard is up to 3×3
    // canvases — 9× the area (5×5 and 25× until H2, 2026-08-22) at its 3x
    // size (I-109) — so handing it over
    // verbatim would make every folder buffer 9× more expensive than the
    // picture it holds. Only what is ON SCREEN can matter, so intersect
    // with the visible canvas-space rect (the same rect the surface painter
    // walks its tiles under).
    final visibleRect = MatrixUtils.transformRect(
      // The inverse of the transform APPLIED above — the SNAPPED one.
      // Pulled back through the raw viewport, the coverage rect could stop
      // a sub-pixel short of the screen edge the snap shifted content
      // toward, and the buffer would clip a sliver the CTM shows.
      viewportInverseTransformMatrix(
        renderSnappedViewport(_painter.viewport, _painter.devicePixelRatio),
      ),
      Offset.zero & size,
    );
    final pasteboardRect = _painter.canvasSize
        .pasteboardAt(_painter.pasteboardReach)
        .rect;
    // Hole ① of the clamp plan: NOT ON SCREEN means NOT PAINTED, and one
    // law covers both ways off-screen happens — a degenerate view
    // (collapsed panel: empty visibleRect, which used to substitute the
    // WHOLE pasteboard, 25× the page then) and a parked-away viewport
    // (huge visibleRect that misses the pasteboard entirely, which used to
    // walk the full stack into a clip that discards every op). The
    // intersection is empty in both, nothing intersects the screen, and
    // drawing nothing is pixel-identical on it.
    _visibleCanvasRect = pasteboardRect.intersect(visibleRect);
    if (_visibleCanvasRect.isEmpty) {
      canvas.restore();
      return;
    }

    // What a group's buffer is sized by and, unioned, what the one display
    // buffer covers — the law is [_compositeExtentWith]'s.
    _contentExtent = _compositeExtentWith(_activeSurfaceExtent);
    if (_contentExtent.isEmpty) {
      canvas.restore();
      return;
    }
    // A3: the recordings depend on this rect and the build-time key cannot
    // carry it (it is a layout fact). Declared HERE, before any slot is
    // consulted, so a resized panel re-records instead of replaying
    // closures that captured the old bounds — or worse, blitting the old
    // raster with a src rect computed from the new dimensions.
    //
    // 🚨★★★WITHOUT THE LIVE DRAWS (review 2026-09-15). F-85 made the buffer
    // cover everything the active slot draws, and this declared THAT extent:
    // a stamp ghost hovering past the ink, a stroke entering a new pasteboard
    // tile, a float dragged across the pasteboard — every such frame dropped
    // every recording and rasterised the whole backdrop again under the
    // pointer. Nothing the bake records draws the live slot (the backdrop is
    // the paper and the rows below it, every other slot a sibling), so it
    // records over the same composite measured with the active row at its
    // COMMITTED surface, which no hover and no stroke in flight moves. The
    // band a live draw adds lies outside every row the bake holds; the only
    // backdrop pixels it could have shown are an effect's spread past its own
    // row, cut there just as the idle buffer's edge cuts them.
    _bakeExtent = _compositeExtentWith(_committedSurfaceExtent);
    _painter.bake?.ensureExtent(_bakeExtent);

    // The geometry field probe — the numbers every buffer decision depends
    // on and nobody has ever measured on a device: the logical view, the
    // device pixel ratio, the zoom actually worked at, and what the buffer
    // costs there. The 1928×1200 that circulates is a comment in the bake,
    // not a measurement.
    //
    // Same shape as the T12 probe above: release-visible (reports come from
    // release builds), gated on the inspector, deduped through a static.
    // ⛔The zoom is a continuous double — raw in the dedupe key it would
    // emit on every drag frame, so it is bucketed to 10% steps, and the
    // counters stay OUT of the key (they change on every stroke step).
    if (InputInspector.visible.value) {
      final bufWidth =
          (_visibleCanvasRect.right.ceilToDouble() -
                  _visibleCanvasRect.left.floorToDouble())
              .round();
      final bufHeight =
          (_visibleCanvasRect.bottom.ceilToDouble() -
                  _visibleCanvasRect.top.floorToDouble())
              .round();
      final capped =
          bufWidth > _LayerStackPainter._maxBufferSide ||
          bufHeight > _LayerStackPainter._maxBufferSide;
      final zoomBucket =
          ((_painter.viewport.zoom.abs() * 100) / 10).round() * 10;
      CanvasPaintGeometryProbe.zoomHistogram[zoomBucket] =
          (CanvasPaintGeometryProbe.zoomHistogram[zoomBucket] ?? 0) + 1;
      // The painter's OWN ratio, not the raw view singleton: every buffer
      // decision this probe exists to explain is computed against that
      // field, and once a UI scale is in force the two differ.
      final dpr = _painter.devicePixelRatio;
      final key =
          'geom view=${size.width.round()}x${size.height.round()}'
          ' dpr=${dpr.toStringAsFixed(2)}'
          ' zoom~$zoomBucket%'
          ' buf=${(bufWidth * bufHeight * 4 / (1024 * 1024)).round()}MB'
          ' capped=$capped';
      if (key != CanvasPaintGeometryProbe.lastLine) {
        CanvasPaintGeometryProbe.lastLine = key;
        final top =
            (CanvasPaintGeometryProbe.zoomHistogram.entries.toList()
                  ..sort((a, b) => b.value.compareTo(a.value)))
                .take(3)
                .map((entry) => '${entry.key}%:${entry.value}')
                .join(' ');
        InputInspector.note('$key hist $top');
      }
      final cache = _painter.bufferCache;
      if (cache != null) {
        // ⛔THE BUFFER COUNTERS ARE THEIR OWN LINE, ON THEIR OWN CADENCE.
        // Appended to the geometry line they fell off the inspector's right
        // edge (유저 스샷 2026-09-13: `…capped=` and nothing after), and
        // they refreshed only when the GEOMETRY changed, so a stroke could
        // not be watched at all — the one thing they exist for.
        //
        // ⛔ALL THREE COUNTS ARE BUCKETED, NOT JUST THE PATCHES. Keyed raw,
        // a pan emitted a line PER PAINT (every paint of a pan carries) —
        // and a line that moves every paint cannot be READ mid-stroke,
        // which is the one thing it exists for. (While the inspector was a
        // five-line ring it also evicted the geometry line beside it —
        // `paint_geometry_probe_test` went red on master, 2026-09-13; the
        // ring holds one slot per emitter since that day, so eviction is
        // gone and readability is the reason that remains.) Every 32
        // patches or carries and every 8 full composes: a paint is ~16ms,
        // so mid-stroke and mid-pan the line moves about twice a second,
        // and a zoom that composes whole a few times does not move it at
        // all.
        //
        // ⛔THE CARRY BELONGS BESIDE THE OTHER TWO. A pan that stopped
        // carrying looks exactly like one that never could, and this line
        // is what a hands-on report can show.
        // ⛔`chain` AND `real` BELONG BESIDE THEM FOR THE SAME REASON.
        // `chain` is how deep the deferred-image chain is NOW — with the
        // real base landing it should read 0 or 1 mid-stroke; stuck high
        // it says the snapshots stopped landing and the head is being
        // derived from under budget. `real` is how many snapshots became
        // the base — a promotion that never lands looks exactly like one
        // that works. See [DisplayBufferCache.derivedDepth] and
        // [DisplayBufferCache.promotedCount]. `drawn` — how many of the
        // patches rastered no head ([DisplayBufferCache.drawnCount]) — for
        // the same reason again, and `apart` — how many recomposes went
        // apart ([DisplayBufferCache.composedApartCount]) — too.
        final cadence =
            'full~${cache.fullCount ~/ 8}'
            ' patched~${cache.patchedCount ~/ 32}'
            ' carried~${cache.scrolledCount ~/ 32}';
        if (cadence != CanvasPaintGeometryProbe.lastCounters) {
          CanvasPaintGeometryProbe.lastCounters = cadence;
          InputInspector.note(
            'buf full=${cache.fullCount}'
            ' patched=${cache.patchedCount}'
            ' drawn=${cache.drawnCount}'
            ' apart=${cache.composedApartCount}'
            ' carried=${cache.scrolledCount}'
            ' chain=${cache.derivedDepth}'
            ' real=${cache.promotedCount}',
          );
        }
      }
    }

    /// 🚨(v) — the body, with WHO PAINTS THE CHILDREN left open.
    ///
    /// It was `_paintNodes` recursing straight into itself. The static bake
    /// needs the same body with a different child strategy (descend into
    /// the chain enclosing the active layer, replay a recording for
    /// everything else), and copying it would have split the folder
    /// `saveLayer` rules into two versions that then drift apart. One body,
    /// two strategies.

    /// 🚨★★★ (v) 1단계 — paint the chain that ENCLOSES the active layer live,
    /// and replay a recording for everything else.
    ///
    /// ★The split axis is not "below / above". That was the flat pair this
    /// tree was built to replace: with the active layer inside a blended
    /// folder, three sibling painters could not share one `saveLayer` and
    /// the canvas disagreed with playback (see the file's own header).
    ///
    /// There is exactly ONE [_PaintActiveSurface] in the tree, so the path
    /// from the root to it is a chain of enclosing folders G1…Gn. At every
    /// level, the siblings BEFORE and AFTER the chain's child are static for
    /// the whole stroke — the stroke's pixels never pass through them — so
    /// they bake. The folders ON the chain stay live, because the stroke's
    /// pixels do go through their buffers.
    ///
    /// ⇒ 2n+2 recordings, and n is 0 or 1 in almost every project. At n=0
    /// that is precisely "one below, one above" — the naive split was not
    /// wrong, it was this rule's simplest case.
    ///
    /// ⚠️Depth identifies a level uniquely BECAUSE the chain is unique;
    /// that is what makes a bare depth a sound slot id.

    /// Everything this stack is, in CANVAS space: the paper and then the
    /// layers over it.
    ///
    /// Pulled out of `paint` so it can be run against the screen directly OR
    /// into a recorder. Those are the two halves of stage 2 and they must be
    /// the same body — a second copy is how "the buffer path draws something
    /// slightly different" starts.

    /// 🚨★★★ (v) 2단계 후반부 — THE BOTTOM OF THE STACK IS ONE BLIT,
    /// WHEN THE BLIT PAYS.
    ///
    /// Stage 1 stopped the DART walk; the engine still replayed every draw
    /// in the recording, so a stroke on top of 500 layers re-executed 500
    /// draws and every folder's `saveLayer` per step. Rasterising the
    /// bottom collapses all of it to one image, and the raster is redone
    /// only when the bake key moves — which a stroke step never does.
    ///
    /// ★S7 — the raster is a TRADE and the predicate is its price check.
    /// It swaps N replay ops for one blit, at the cost of a visible-rect
    /// image resident (4·area bytes, ~9MB at a 1928×1200 view) plus a
    /// re-rasterisation every time the key moves. Per step, BOTH sides of
    /// the comparison scale with the same visible area — N draws over the
    /// rect versus one blit of the rect — so the area term cancels and
    /// the judgment is the op count alone, decidable statically from the
    /// node tree with no clock. Below the threshold (a paper-and-two-
    /// layers document) the picture already replays within a handful of
    /// engine ops of the blit itself, and the image would buy that
    /// nothing at megabytes each and a re-raster per key change.
    ///
    /// ⛔The BOTTOM only. Everything above the live surface stays a picture:
    /// a multiply up there has to blend against the stroke, and an image
    /// drawn `srcOver` cannot. Below the live surface the destination is
    /// empty, so flattening and replaying are the same picture — which is
    /// exactly what the parity suite pins.

    /// `intoTheBuffer` is true only when this is composing the display
    /// buffer. The direct walk deliberately does NOT take the backdrop
    /// raster: it draws in screen space, so a flattened backdrop would be
    /// resampled by the CTM as one image while the rest of the stack was
    /// resampled layer by layer — a third sampling behaviour, in the
    /// fallback path, for no gain.

    // 🚨★★★ (v) 2단계 — ONE BUFFER AT CANVAS RESOLUTION, RESAMPLED ONCE.
    //
    // Above this line every layer was drawn straight under the viewport
    // transform, so the CTM resampled each of them SEPARATELY and each one
    // brought its own `filterQuality`. That is why becoming the active
    // layer changed how a layer looked (T21): the live surface draws its
    // tiles at `none` and a cached layer image draws at `low`.
    //
    // Compositing at canvas resolution first makes the question disappear
    // rather than answering it consistently: there is exactly one image to
    // resample, so [filterQualityForDisplayScale] is the whole policy and
    // no layer is ever asked what it is.
    //
    // 📐The buffer is the VISIBLE canvas-space rect, not the pasteboard —
    // the pasteboard is up to 3×3 canvases (5×5 until H2) and rasterising
    // all of it would cost 9× what is on screen. It is not the canvas rect
    // either:
    // artwork parked on the pasteboard is visible and must composite with
    // the rest (유저 2026-08-15, 「페이스트보드도 룰러할때 보이게」).
    switch (_composeDisplayBuffer(_contentExtent)) {
      case null:
        _paintContent(
          canvas,
          // The direct walk draws under the viewport transform, so a group
          // that rasterises itself has to match the CTM it is drawn into.
          intoTheBuffer: false,
          rasterScale: _displayScale,
        );
      case final _BufferImage buffer:
        _blitBuffer(canvas, buffer);
      case _BufferPicture(:final picture, :final rect):
        try {
          // Recorded in the buffer's own pixels, which at level 0 are canvas
          // pixels less the rect's corner.
          canvas.save();
          canvas.translate(rect.left, rect.top);
          canvas.drawPicture(picture);
          canvas.restore();
        } finally {
          // Safe once drawn, for the reason the image's disposal below is.
          picture.dispose();
        }
    }
    canvas.restore();
  }

  void _blitBuffer(Canvas canvas, _BufferImage buffer) {
    try {
      canvas.drawImageRect(
        buffer.image,
        Offset.zero & Size(buffer.pixelWidth, buffer.pixelHeight),
        buffer.rect,
        Paint()
          // The residual, not the device scale: below 100% the buffer is
          // a level, and this blit reduces it by (0.5, 1] — `none` where
          // the level lands 1:1 (안 1, 2026-09-16).
          ..filterQuality = _bufferQuality
          // The buffer's edge IS the canvas's edge on screen, cut by the
          // same law as the paper's (F-67-paper-edge): under nearest on
          // an axis-aligned view it is one more texel boundary, decided
          // by pixel centres, not a blended line.
          ..isAntiAlias = _bufferEdgeAntiAliased,
      );
    } finally {
      // ⚠️Safe HERE and nowhere earlier: the draw above put the image into
      // this frame's display list, and the engine holds its own reference
      // to it from that moment. What `dispose` releases is this handle's
      // claim, not the pixels the list is going to replay.
      if (buffer.owned) {
        buffer.image.dispose();
      }
    }
  }

  /// 🚨★★★WHAT THE ACTIVE SLOT DRAWS, not what its surface holds (F-85,
  /// 2026-09-15): the painter's own answer, and the float drawn into the
  /// same slot. Read off the committed surface alone, a stroke in flight, a
  /// fill's stamp, the stamp ghost and a transform's float were all cut at
  /// the edge of the ink that had already landed — and came back the moment
  /// a commit put tiles there. What the DISPLAY BUFFER covers; the bake
  /// measures by [_committedSurfaceExtent].
  ///
  /// Read ONCE per paint ([_SurfaceSlot.extent]): the node walk asks per
  /// group, and the answer walks every tile and overlay tile the slot holds.
  Rect _activeSurfaceExtent() => _activeSlot?.extent ?? Rect.zero;

  /// The live row's slot — its painter, its float and its pose — or null
  /// when nothing is live.
  late final _SurfaceSlot? _activeSlot =
      switch (_painter.activeSurfacePainter) {
        null => null,
        final painter => () {
          final row = _activeRowIn(_painter.nodes);
          return _SurfaceSlot(
            painter: painter,
            float: _painter.floatOverlay,
            keys: row?.keys ?? const [],
            placement: row?.placement,
          );
        }(),
      };

  /// Each row a lift holds beside the live one, by its surface (I-37 ·
  /// F-329) — read once per paint, as the live row's slot is.
  final Map<BitmapSurfacePainter, _SurfaceSlot> _liftedSlots = Map.identity();

  _SurfaceSlot _liftedSlotOf(_PaintLiftedSurface row) =>
      _liftedSlots.putIfAbsent(
        row.lifted.surface,
        () => _SurfaceSlot(
          painter: row.lifted.surface,
          float: row.lifted.float,
          keys: row.keys,
          placement: row.placement,
        ),
      );

  /// What a lifted row draws: its surface and its float, as the live row's
  /// extent is measured ([_activeSurfaceExtent]).
  Rect _liftedExtent(_PaintLiftedSurface row) => _liftedSlotOf(row).extent;

  /// What the live slot's own raster covers, in the SLOT's space: the rect
  /// the same layer drawn as an image covers, where the view can see it.
  ///
  /// 🚨★★★THE IMAGE ROW'S RECT, BY THE IMAGE ROW'S QUESTION (F-243). A
  /// cached row lays down its ink alone only where that is exact
  /// ([inkCropDrawsTheSame]) and otherwise its whole image, the page
  /// included; this asks the same. 🔬On Impeller Vulkan an advanced blend
  /// rounds by the area it blends through: rastered to its ink, a multiply
  /// row being drawn on came out up to 14/255 off the same row drawn as an
  /// image in 109 pixels of one scene; over the page, not one byte in any
  /// of 20 (blends × zooms × inks), as on the Windows app and the test
  /// runner already. Where a crop is exact the ink is all there is to
  /// raster, and a colour key keeps its smaller raster.
  ///
  /// 🚨Not [_bufferBoundsFor], which answers in CANVAS space — the extent
  /// taken through the row's pose — for the buffers the walk opens around
  /// nodes. The slot's own route runs INSIDE the pose wrap, so the view is
  /// brought into the slot instead ([_SurfaceSlot.canvasToSlot]). Read as
  /// slot coordinates, a posed row's canvas rect rastered the wrong part of
  /// the slot and cut its drawing away (found in F-243's review: every posed
  /// row in an advanced blend takes this route since).
  Rect _slotBufferBounds(_SurfaceSlot slot, _SurfaceRowPaint paint) {
    final intoSlot = slot.canvasToSlot;
    final view = intoSlot == null
        ? _visibleCanvasRect
        : MatrixUtils.transformRect(intoSlot, _visibleCanvasRect);
    final drawn = slot.extent;
    final covered =
        inkCropDrawsTheSame(
          placement: paint.placement,
          blendMode: paint.blendMode,
          effects: paint.effects,
        )
        ? drawn
        : drawn.expandToInclude(_canvasRect);
    return view.intersect(covered);
  }

  /// The one active slot in [nodes], wherever the folders put it.
  static _PaintActiveSurface? _activeRowIn(
    List<CompositeNode<_PaintRow>> nodes,
  ) {
    for (final node in nodes) {
      final found = switch (node) {
        CompositeLeaf(payload: final _PaintActiveSurface active) => active,
        CompositeLeaf() => null,
        CompositeGroup(:final children) => _activeRowIn(children),
        CompositeAdjustment(:final children) => _activeRowIn(children),
        CompositeBackdropBlend(:final children) => _activeRowIn(children),
      };
      if (found != null) {
        return found;
      }
    }
    return null;
  }

  /// The active row at its COMMITTED surface alone, measured as a cached row
  /// is — what the bake records over, since nothing it records draws the
  /// live slot (the bake's extent in [paint] says why). Read once, like
  /// [_activeSurfaceExtent].
  Rect _committedSurfaceExtent() =>
      _memoCommittedExtent ??= switch (_painter.activeSurfacePainter) {
        null => Rect.zero,
        final painter => surfaceContentWorldRect(painter.surface),
      };

  /// What the composite covers with the active row measured by
  /// [activeSurfaceExtent]: the page and every row's buffer bounds, clamped
  /// to the view. CONTENT, clamped to the storable universe; the pasteboard
  /// clamp is the backstop a pose needs, since a transform can push a layer
  /// anywhere and an unbounded rect is an unbounded offscreen.
  Rect _compositeExtentWith(Rect Function() activeSurfaceExtent) {
    // 🚨SEEDED WITH THE PAGE, not with the nodes alone.
    //
    // The composite always covers the document: the paper is drawn over the
    // canvas rect whether or not any row has ink there, and a row's own
    // extent is measured against the SURFACE's canvas — which is not
    // necessarily this view's. Starting from the nodes alone shrank the
    // buffer below the page, and the paper went with it.
    var extent = _canvasRect;
    for (final node in _painter.nodes) {
      final rect = _bufferBoundsFor(node, activeSurfaceExtent);
      if (rect.isEmpty) {
        continue;
      }
      extent = extent.isEmpty ? rect : extent.expandToInclude(rect);
    }
    // 🚨CONTENT **AND** VIEW, and each guards a different cliff.
    //
    // Bounded by the VIEW alone (the old `pasteboard ∩ visibleRect`), zooming
    // out until the pasteboard fits hands the buffer 9× the page — past the
    // cap, and the paint drops to the SCREEN-resolution fallback, which is
    // the one place the editing canvas stops matching playback, the camera
    // and the export.
    //
    // Bounded by CONTENT alone, a page wider than the cap (a 12000px sheet)
    // exceeds it at EVERY zoom, including the close-ups that sit comfortably
    // inside it today — the same cliff approached from the other side.
    //
    // The intersection is under the cap whenever either one is, which is what
    // keeps a single resolution reachable at every zoom and every page size.
    return extent.isEmpty
        ? _visibleCanvasRect
        : extent.intersect(_visibleCanvasRect);
  }

  /// The CANVAS-SPACE rect a buffer for [node] covers — what of it is on
  /// screen ([subtreeBufferBounds], the one law the camera's walk keeps
  /// too).
  ///
  /// 🚨THIS IS WHAT KEEPS THE COMPOSITE AT CANVAS RESOLUTION AT EVERY ZOOM.
  ///
  /// The buffers used to be bounded by `pasteboard ∩ visibleRect`. Zoom out
  /// far enough and that rect spans the whole pasteboard — 5×5 canvases
  /// then, 11700×8270 on a 2340×1654 page — which blew past [_maxBufferSide]
  /// and dropped the paint onto the fallback past the cap (since H2's 3×3,
  /// 2026-08-22, that page's pasteboard is 7020×4962 and fits; a page more
  /// than 2730 on a side still does not). That fallback is how the editing
  /// canvas stopped compositing the way playback, the camera and the export
  /// do (유저 2026-08-15 accepted it at the time: 「무릎 아래는
  /// 균일 필터, 겹침 색차 수용」 — accepted because bounding by the view was
  /// the only tool on the table; the screen-resolution "knee" that served
  /// the fallback from 2026-08-16 went with the level buffer on 2026-09-16,
  /// and past the cap the direct walk is the net).
  ///
  /// ★Content is not the pasteboard. For a cached row it is
  /// [surfaceContentWorldRect]'s answer — the canvas rect unioned with the
  /// tiles that actually exist — so an ordinary page bounds to 2340×1654 and
  /// never reaches the cap. The fallback stops being reachable, and one
  /// resolution serves every zoom. For the ACTIVE row it is whatever the
  /// caller measures it by ([activeSurfaceExtent]): everything the slot
  /// draws for the display buffer — its committed surface alone cut every
  /// live draw at the edge of the ink already landed (F-85) — and that
  /// committed surface for the bake, which never records the live slot
  /// (review 2026-09-15).
  Rect _bufferBoundsFor(
    CompositeNode<_PaintRow> node,
    Rect Function() activeSurfaceExtent,
  ) => subtreeBufferBounds(
    node,
    // ⚠️The view at every depth, where the law asks for the buffer of the
    // folder that holds [node]: a blurred folder holding a buffered one
    // misses the inner folder's ink past the screen's edge, so the blur
    // there changes as the view moves (card
    // nested-folder-buffers-read-past-the-view).
    within: _visibleCanvasRect,
    extentOf: (row) => switch (row) {
      _PaintImage(:final extent) => extent,
      _PaintActiveSurface() => activeSurfaceExtent(),
      final _PaintLiftedSurface lifted => _liftedExtent(lifted),
      _PaintPaper() => _canvasRect,
    },
    placementOf: (row) => switch (row) {
      _PaintImage(:final placement) => placement,
      final _SurfaceRow surface => surface.placement,
      _PaintPaper() => null,
    },
  );

  void _paintNodesWith(
    Canvas canvas,
    List<CompositeNode<_PaintRow>> list,
    // The scale the CTM this walk draws under is at. A group that
    // rasterises ITSELF needs it, and a `Canvas` will not tell anyone.
    double rasterScale,
    _ChildPainter paintChildren,
  ) {
    for (final node in list) {
      // Poses apply at composite time — the stack shows the same picture
      // playback composes (route parity).
      final nodePlacement = switch (node) {
        CompositeLeaf(payload: _PaintImage(:final placement)) => placement,
        CompositeLeaf(payload: _PaintActiveSurface(:final placement)) =>
          placement,
        CompositeLeaf(payload: _PaintLiftedSurface(:final placement)) =>
          placement,
        CompositeLeaf(payload: _PaintPaper()) ||
        CompositeGroup() ||
        CompositeAdjustment() ||
        CompositeBackdropBlend() => null,
      };
      // The wrap straddles the live-surface node too, which HAS a placement
      // and no image — that is why the wrap and the draw are separate
      // helpers rather than one.
      withLayerPlacement(
        canvas,
        placement: nodePlacement,
        body: () {
          switch (node) {
            case final CompositeGroup<_PaintRow> group:
              _paintGroupNode(canvas, group, rasterScale, paintChildren);
            case final CompositeAdjustment<_PaintRow> adjustment:
              _paintAdjustmentNode(
                canvas,
                adjustment,
                rasterScale,
                paintChildren,
              );
            case final CompositeBackdropBlend<_PaintRow> blend:
              _paintBackdropBlendNode(
                canvas,
                blend,
                rasterScale,
                paintChildren,
              );
            case CompositeLeaf(payload: _PaintPaper()):
              _paintPaperInto(canvas, intoTheBuffer: _composingTheBuffer);
            case CompositeLeaf(payload: final _PaintActiveSurface active):
              _paintSurfaceRow(canvas, _activeSlot!, active.paint, rasterScale);
            case CompositeLeaf(payload: final _PaintLiftedSurface lifted):
              _paintSurfaceRow(
                canvas,
                _liftedSlotOf(lifted),
                lifted.paint,
                rasterScale,
              );
            case CompositeLeaf(payload: final _PaintImage image):
              _paintImageNode(canvas, image, rasterScale);
          }
        },
      );
    }
  }

  /// A folder: its children buffered as one image, blended once with the
  /// folder's paint.
  void _paintGroupNode(
    Canvas canvas,
    CompositeGroup<_PaintRow> node,
    double rasterScale,
    _ChildPainter paintChildren,
  ) {
    final CompositeGroup<_PaintRow>(:children, :opacity, :blendMode, :effects) =
        node;
    // R27 #29: one buffer for the group, one blend on it — and
    // because the ACTIVE layer is a node in here, a stroke drawn
    // inside a blended folder finally reads the way it will play
    // back. R6: the folder's effect chain lands on the same buffer.
    final groupPlan = resolveCompositeEffectPlan(effects);
    final groupPaint = layerCompositePaint(
      opacity: opacity,
      blendMode: blendMode,
      effects: groupPlan.finalPaint,
    );
    // 🚨A GROUP'S BUFFER CANNOT EXCEED THE ONE THAT HOLDS IT.
    // Bounded by the view, a folder asked Skia for the whole
    // pasteboard (9× the page) at far zoom-out — an offscreen
    // that the enclosing canvas-resolution buffer then clipped
    // away. Content bounds keep it inside by construction, and
    // this says so where it can fail.
    //
    // ⚠️It is the CONTENT that must sit inside, before the effect
    // grows it. The spread the size hint adds below is deliberate
    // — artwork just outside the view has to reach the blur at the
    // view's edge — so there the buffer lies past the composite by
    // exactly that spread, off screen. ↩️This asserted the grown
    // rect, and a blurred folder whose ink crossed the view's edge
    // stopped every debug build at any zoom (board
    // `a-blurred-folder-outgrows-the-composite`).
    final contentRect = _bufferBoundsFor(node, _activeSurfaceExtent);
    assert(
      _contentExtent.expandToInclude(contentRect) == _contentExtent,
      'a group buffer must sit inside the composite it is part '
      'of: $contentRect is not within $_contentExtent',
    );
    final groupRect = effectBufferBounds(
      contentRect,
      groupPlan.outsetPixels,
    );
    // 🚨★★★ONE PICTURE PER NODE — a group IS an image, not a
    // `saveLayer`. [drawSubtreeAsImage] holds the arithmetic and
    // the reason, and the test that certifies it against the
    // saveLayer it replaced calls THAT function, not a copy.
    drawSubtreeAsImage(
      canvas: canvas,
      // The size hint grows by the blur's spread, so artwork just
      // OUTSIDE the visible rect still bleeds in — without this the
      // blur at the screen edge would change as you scroll.
      bounds: groupRect,
      rasterScale: rasterScale,
      paintSubtree: (into, scale) => paintChildren(into, children, scale),
      compose: (blit) => blit(groupPaint),
      steps: groupPlan.preSteps,
    );
  }

  /// An adjustment scope: the rows under it buffered and graded as one.
  void _paintAdjustmentNode(
    Canvas canvas,
    CompositeAdjustment<_PaintRow> node,
    double rasterScale,
    _ChildPainter paintChildren,
  ) {
    final CompositeAdjustment<_PaintRow>(:children, :effects, :mix) = node;
    // R6b: the scope into one buffer, the row's chain onto it —
    // which is what lets a stroke drawn UNDER an adjustment read
    // through the grade while you draw it.
    final pass = resolveAdjustmentScopePass(
      bounds: _bufferBoundsFor(node, _activeSurfaceExtent),
      effects: effects,
      mix: mix,
    );
    // 🚨★★★ONE RASTER, TWO BLITS. The scope used to be PAINTED
    // twice below full strength — a mix is a crossfade, not a
    // fade-out — and it is the same picture both times. The
    // passes keep their layers; what changed is that they now
    // contain a blit of one raster instead of a second walk of
    // the scope.
    drawSubtreeAsImage(
      canvas: canvas,
      bounds: pass.bufferBounds,
      rasterScale: rasterScale,
      paintSubtree: (into, scale) => paintChildren(into, children, scale),
      compose: composeAdjustmentScope(canvas, pass),
      steps: pass.preSteps,
    );
  }

  /// A row in an advanced blend, composed over a picture of what lies
  /// below it in its scope ([drawBlendOverBackdrop], brush-fidelity-Q4) —
  /// the camera's walk calls the same function.
  void _paintBackdropBlendNode(
    Canvas canvas,
    CompositeBackdropBlend<_PaintRow> node,
    double rasterScale,
    _ChildPainter paintChildren,
  ) {
    final CompositeBackdropBlend<_PaintRow>(:backdrop, :source, :blendMode) =
        node;
    drawBlendOverBackdrop(
      canvas: canvas,
      bounds: _bufferBoundsFor(node, _activeSurfaceExtent),
      rasterScale: rasterScale,
      paintBackdrop: (into, scale) => paintChildren(into, backdrop, scale),
      paintSource: (into, scale) => paintChildren(into, [source], scale),
      blendMode: blendMode,
      shownWithin: _shownWithin,
    );
  }

  /// A surface layer — the live one, or one a lift holds beside it (I-37 ·
  /// F-329): drawn straight onto the canvas when its paint can ride the
  /// draws, through one buffer when it cannot (an outset effect,
  /// overlapping coverage, a float overlay, or pre-steps).
  void _paintSurfaceRow(
    Canvas canvas,
    _SurfaceSlot slot,
    _SurfaceRowPaint paint,
    double rasterScale,
  ) {
    final (:opacity, :blendMode, :effects, placement: _) = paint;
    // The live surface, drawn by the SAME painter the standalone
    // interactive view uses — the canvas is already
    // viewport-transformed, so only the content body runs.
    //
    // R6: the row's own effects need a buffer here, because the
    // surface painter draws MANY tiles and a filter must see the
    // assembled picture (a per-tile blur would show seams).
    //
    // ㊱: the OPACITY rides that same buffer — one alpha over the
    // assembled picture, exactly as a group node applies its own
    // (`alphaOnly` builds it, and clamps what the model does not).
    // The panel's content-opacity wrap cannot do this job in
    // merged mode: there the interactive view is input-only, so
    // the wrap dims a widget that paints nothing and the layer
    // you are drawing on stayed at full strength.
    //
    // The BLEND rides the same buffer for a reason of its own: the
    // surface painter draws many separate tiles, and a non-srcOver
    // blend applied per tile would compose each tile against the
    // rows below it independently — overlapping coverage inside one
    // row would then darken at the seams. One buffer, one blend, is
    // the same answer [CompositeGroup] already gives for a folder.
    final activePlan = resolveCompositeEffectPlan(effects);
    final activeEffects = activePlan.finalPaint;
    final activePaint = layerCompositePaint(
      opacity: opacity,
      blendMode: blendMode,
      effects: activeEffects,
    );
    // 🚨★★★THE LAYER RIDES THE DRAWS, NOT A BUFFER AROUND THEM.
    //
    // A layer's opacity and blend have to apply to the LAYER
    // once. A buffer is one way; handing the same paint to each
    // draw is another, and they are the same pixels exactly when
    // no two draws land on the same pixel — which is what
    // [BitmapSurfacePainter.drawsDisjointCoverage] answers, and
    // the law the overlay's own blend already rides one level
    // down ("tiles never overlap, so per-tile draws blend each
    // pixel exactly once") — and the blend acts where it is
    // drawn, which F-243 (the last clause below) showed an
    // advanced blend does not.
    //
    // What is left for a buffer is what a per-draw paint cannot
    // do: a filter that SPREADS has to see across the tile
    // boundaries, so it needs the layer assembled first.
    // `outsetPixels` is exactly that question — a colour matrix
    // is per-pixel and rides along fine.
    final needsBuffer =
        activeEffects.outsetPixels > 0 ||
        !slot.painter.drawsDisjointCoverage ||
        // The selection FLOAT is this layer's pixels lifted out
        // and drawn back on top of it — the one overlap the
        // painter cannot see, because it is not the painter's.
        // ⛔`isEmpty`, not `!= null`: an overlay mounted with
        // nothing in it draws nothing and overlaps nothing.
        !(slot.float?.value?.isEmpty ?? true) ||
        // 🚨A SHADER CANNOT SAMPLE A saveLayer. A colour key
        // BELOW a painted effect keys what that effect made, so
        // the layer has to be assembled into an image first —
        // the one thing a buffer cannot hand it.
        activePlan.preSteps.isNotEmpty ||
        // 🚨★★★F-243: AN ADVANCED BLEND NEVER RIDES THE TILES. Per
        // draw it is not per pixel — each tile blended the whole
        // screen by its edge colour on the Windows app ([blendsInPlace]
        // has the measurement). Buffered, the blend takes the image
        // route below: the layer assembled into one image and blended
        // once, which is what every other row in that blend already is.
        !blendsInPlace(activePaint.blendMode);
    // Null when the buffer carries it, so nothing applies twice.
    final ridingPaint = needsBuffer ? null : activePaint;
    assert(() {
      // The probe is the LIVE row's — the row a stroke draws into.
      if (identical(slot, _activeSlot)) {
        debugLiveLayerRodeTheDraws = !needsBuffer;
      }
      return true;
    }());
    // 🚨THE LIVE LAYER'S OWN CONTENT, AS A CLOSURE — because a
    // colour key BELOW a painted effect has to key what that
    // effect made, and a shader cannot sample a `saveLayer`.
    // ⛔Only that case and an advanced blend (below) rasterise. A
    // plainly buffered layer keeps the cheaper `saveLayer`:
    // 🧪measured, the image route costs 3.2x on the path a stroke
    // redraws every step.
    void paintLiveBody(Canvas into) {
      into.save();
      into.clipRect(slot.painter.storableRect);
        slot.painter.paintContentInto(
          into,
          layerPaint: ridingPaint,
          // 4c: into a level buffer the committed tiles are drawn as level
          // tiles, 1:1 in the buffer's own pixels ([TilePyramid]); the
          // safety-net walk (rasterScale = the device scale) draws the
          // level its residual leaves.
          level: displayLevelOf(rasterScale),
          // 🚨TS1: the selection's FLOAT belongs here, right on top of
          // the surface it was lifted out of and UNDER everything
          // above that row. Drawn inside this slot's clip and its
          // effects/opacity buffer, because the pixels are that
          // layer's pixels — 유저 확정 A: 「프리뷰는 원래 그런거」, so a
          // half-opacity row previews a transform at half opacity,
          // which is what the commit will look like.
          //
          // ⚠️Inside the POSE wrap as well (the whole switch is) — and the
          // float is CANVAS space, so for a posed row the wrap is undone
          // for it ([_SurfaceSlot.canvasToSlot]). ↩️It used to ride the
          // wrap, which was right only while the lift took canvas
          // coordinates as the row's own and moved the wrong pixels
          // (a-marquee-on-a-posed-row).
          //
          // ↩️F-240: it is handed to the surface's own paint rather than
          // drawn here after it — below 100% the surface draws level
          // tiles, and a float laid over them 1:1 at `none` was sampled one
          // pixel in two, so it looked sharper than what it landed as.
          //
          // 🚨transform-float-skips-colour-key: on a keyed row the float is
          // shown through the row's keys, as what it lands as
          // ([_SurfaceSlot.shown]) — not as the unkeyed pixels it holds.
          float: slot.shown,
        );
      into.restore();
    }

    // 🚨★★★F-172 (유저 2026-09-20: 「다른 레이어에 곱하기 레이어가
    // 있을때, 잘라내기의 스탬프 사용시 해당 레이어가 뭔가 색이 진해짐 …
    // 스탬프의 사각형 실루엣만큼 흰 색이 생기고」): AN ADVANCED BLEND
    // NEVER RIDES A `saveLayer`. On Impeller, a layer restored through
    // multiply, screen and the rest composited the rows ABOVE this one a
    // second time, everywhere outside what the layer itself drew —
    // measured on the Windows app (2026-09-24): with B at 24% above, every
    // pixel came out as the right picture with B laid over it once more.
    // The test VM rasters with Skia and never showed it.
    // 🧪Splitting the layer — the blend outside at full alpha, the
    // opacity inside — still doubled: it is the blend on a `saveLayer`,
    // not the opacity riding with it. Blending an IMAGE with the same
    // paint, which every other row and every group already does, did
    // not. The price is this route's, paid only while a buffered row
    // wears a blend that is not srcOver (a lifted float, the text in hand;
    // ↩️a stamp ghost too, until brush-fidelity-Q9 made it the overlay's
    // tiles): a brush or eraser stroke on the same row showed nothing
    // either way and its frame cost did not move (median UI 1.6 vs 1.4 ms).
    // ⚠️Since F-243 an advanced blend on the row itself is buffered too
    // (see `needsBuffer`), so a multiply or screen row pays it on every
    // paint — the price of being the one image every other such row is.
    final blendsAsImage =
        needsBuffer && activePaint.blendMode != BlendMode.srcOver;
    if (activePlan.preSteps.isNotEmpty || blendsAsImage) {
      drawSubtreeAsImage(
        canvas: canvas,
        bounds: effectBufferBounds(
          _slotBufferBounds(slot, paint),
          activePlan.outsetPixels,
        ),
        rasterScale: rasterScale,
        paintSubtree: (into, _) => paintLiveBody(into),
        compose: (blit) => blit(activePaint),
        steps: activePlan.preSteps,
      );
    } else {
      if (needsBuffer) {
        canvas.saveLayer(
          effectBufferBounds(
            slot.painter.storableRect,
            activeEffects.outsetPixels,
          ),
          activePaint,
        );
      }
      paintLiveBody(canvas);
      if (needsBuffer) {
        canvas.restore();
      }
    }
  }

  /// A cel or a cached row image, drawn into a canvas at [rasterScale]; the
  /// pose is applied by the wrap around the walk, so the draw itself is
  /// unposed.
  void _paintImageNode(Canvas canvas, _PaintImage node, double rasterScale) {
    final _PaintImage(
      :pieces,
      :extent,
      :laidBack,
      :placement,
      :opacity,
      :blendMode,
      :tint,
      :effects,
    ) = node;
    // Dest = the image's WORLD rect: where its pixels belong — the ink
    // alone, or the whole content, off-canvas artwork of non-active layers
    // included ([extent]). The placement is already applied by the wrap
    // above, which this node shares with the live surface — hence
    // placement: null here rather than a second save/restore around the
    // same matrix.
    drawPosedLayerImage(
      canvas,
      pieces: pieces,
      extent: extent,
      placement: null,
      opacity: opacity,
      blendMode: blendMode,
      effects: effects,
      // The canvas is an aligned raster at [rasterScale] only while the
      // display buffer is composed — the buffer itself, a sub-tree raster in
      // it, the backdrop raster on its grid — and a pose wrapped round this
      // draw (invisible from in here) transforms it. The walk draws onto the
      // screen: never a texel copy.
      texelScale: _composingTheBuffer && placement == null ? rasterScale : null,
      // 🚨THE ZOOM DECIDES, HERE TOO (T21 / D14). This used to be a
      // flat `low` — 「the same sampling every non-active layer has
      // always taken on this route」 — and that is exactly half of
      // the law: it filtered a REDUCED view, which is right, and it
      // also filtered a MAGNIFIED one, which is not. 유저 확정
      // (T21): 「줌이 정한다 — 확대는 `none`, 축소는 필터, 액티브인지는
      // 안 묻는다」.
      //
      // The buffered route above has read [filterQualityForDisplayScale]
      // since it was written; this WALK is the fallback it leaves
      // behind (rotation/flip — and, until the knee's flat projection
      // went on 2026-09-16, an active layer that projection refused),
      // and a fallback that samples differently is a second answer to
      // the same question.
      filterQuality: _displayQuality,
      // Onion-skin Colors mode: the ghost CONVERTS fully to the
      // tint — every drawn pixel takes the tint's RGB, only alpha
      // survives (TVPaint's look, R11-①; modulate kept light
      // artwork un-tinted). The paint alpha still fades the whole
      // ghost.
      tint: tint,
      // The held image's own: a slot recorded again — every frame a zoom
      // moves the buffer — lays a crop's whole back once, not per record.
      laidBack: laidBack,
    );
  }

  void _paintNodes(
    Canvas canvas,
    List<CompositeNode<_PaintRow>> list,
    double rasterScale,
  ) => _paintNodesWith(canvas, list, rasterScale, _paintNodes);

  /// [_paintNodes] into a recording the bake keeps — replayed by later
  /// paints under whatever clip each of them has, so no blend in it is read
  /// in the frame ([_shownWithin]).
  void _paintBaked(
    Canvas canvas,
    List<CompositeNode<_PaintRow>> list,
    double rasterScale,
  ) {
    final shown = _shownWithin;
    _shownWithin = null;
    try {
      _paintNodes(canvas, list, rasterScale);
    } finally {
      _shownWithin = shown;
    }
  }

  void _paintSplit(
    Canvas canvas,
    List<CompositeNode<_PaintRow>> list,
    int depth,
    double rasterScale,
  ) {
    final at = list.indexWhere(_LayerStackPainter._enclosesActiveSurface);
    // Inside the buffer a slot's texel copies are copies at [rasterScale]
    // only — and a sub-tree raster's scale is its own (a capped one is
    // smaller) — so the scale is part of what the slot IS. The walk copies
    // nothing, and names its slots as it always did.
    final slot = _composingTheBuffer ? 'd$depth@$rasterScale' : 'd$depth';
    if (at < 0) {
      _painter.bake!.draw(
        canvas,
        '$slot:all',
        (into) => _paintBaked(into, list, rasterScale),
      );
      return;
    }
    if (at > 0) {
      _painter.bake!.draw(
        canvas,
        '$slot:before',
        (into) => _paintBaked(into, list.sublist(0, at), rasterScale),
      );
    }
    _paintNodesWith(canvas, [list[at]], rasterScale, (into, children, scale) {
      _paintSplit(into, children, depth + 1, scale);
    });
    if (at < list.length - 1) {
      _painter.bake!.draw(
        canvas,
        '$slot:after',
        (into) => _paintBaked(into, list.sublist(at + 1), rasterScale),
      );
    }
  }

  /// The paper, [intoTheBuffer] or straight onto the screen (the walk).
  void _paintPaperInto(Canvas into, {required bool intoTheBuffer}) {
    if (!_painter.paintPaper) {
      return;
    }
    // #15: inside a LEVEL buffer the paper yields one buffer pixel to the
    // reduced resample ([paperRectAtLevel]) — and so does a film's, which
    // lays its paper with its rows as this buffer does.
    final rect = intoTheBuffer
        ? paperRectAtLevel(_canvasRect, _level)
        : _canvasRect;
    if (rect.isEmpty) {
      return;
    }
    paintProjectPaper(
      into,
      rect,
      _painter.paperBackground,
      // The display law's edge (F-67-paper-edge): inside the buffer, cut
      // by the residual the buffer is blitted with; on screen — the walk —
      // by the device scale.
      antiAlias: intoTheBuffer ? _bufferEdgeAntiAliased : _displayEdgeAntiAliased,
    );
  }

  /// Where the live surface splits the stack (−1 when nothing encloses it),
  /// whether the backdrop below it pays for a raster, and the rect that
  /// raster is made over.
  ({int at, bool rasterPays, Rect rasterRect}) _backdropPlan() {
    final at = _rootNodes.indexWhere(
      _LayerStackPainter._enclosesActiveSurface,
    );
    final below = at < 0 ? _rootNodes : _rootNodes.sublist(0, at);
    final rasterPays =
        _replayOpsOf(below) >= _LayerStackPainter._backdropRasterMinReplayOps;
    // 🚨THE BAKE'S RECT, NOT THE BUFFER'S (review 2026-09-15). `drawRaster`
    // keeps one image per slot and does not key it by the rect, which is why
    // the extent it is declared under has to move whenever that rect does.
    // The buffer's rect moves with every live draw past the ink and the
    // bake's extent deliberately does not ([paint]), so the raster is made
    // over the bake's extent on the buffer's own pixel grid and lands back
    // on it inside whichever buffer is being composed. Handed the buffer's
    // rect, a held raster stretched across the grown one.
    return (
      at: at,
      rasterPays: rasterPays,
      rasterRect: wholeLevelPixelsOutward(_bakeExtent, _level),
    );
  }

  void _paintBackdropSplit(Canvas into, double rasterScale) {
    final plan = _backdropPlan();
    final at = plan.at;
    // One body, two mechanisms: the record closure is identical either
    // way, so the fallback cannot drift from the raster — `drawRaster`
    // records the same ops shifted into the rect and blits them back to
    // it, which lands pixel-for-pixel where the replay would have. The one
    // thing the raster leaves out is a replay's spread past that rect: an
    // effect bleeding past its own row into a band only a live draw opened.
    // The raster is made at the buffer's own scale — level pixels below
    // 100% — so its blit back is 1:1 in the buffer whatever the level.
    void drawBackdrop(String id, void Function(Canvas c) record) {
      if (plan.rasterPays) {
        _painter.bake!.drawRaster(
          into,
          id,
          plan.rasterRect,
          record,
          rasterScale: rasterScale,
        );
      } else {
        _painter.bake!.draw(into, id, record);
      }
    }

    if (at < 0) {
      drawBackdrop(
        'd0:backdrop-all',
        (c) => _paintBaked(c, _rootNodes, rasterScale),
      );
      return;
    }
    drawBackdrop(
      'd0:backdrop',
      (c) => _paintBaked(c, _rootNodes.sublist(0, at), rasterScale),
    );
    _paintNodesWith(into, [_rootNodes[at]], rasterScale, (
      c,
      children,
      scale,
    ) {
      _paintSplit(c, children, 1, scale);
    });
    if (at < _rootNodes.length - 1) {
      _painter.bake!.draw(
        into,
        'd0:after',
        (c) => _paintBaked(c, _rootNodes.sublist(at + 1), rasterScale),
      );
    }
  }

  /// What the root target holds, bottom → top: the paper, as the bottom row
  /// of the root scope ([onUnderlay]) — inside the backdrop of a blend that
  /// composes over what lies below it, which reads the paper there as a GPU
  /// blend reads it off the target — and the rows over it.
  ///
  /// ↩️Each walk laid the paper itself and the rows after it, until
  /// brush-fidelity-Q4 gave the stack rows that read their backdrop.
  late final List<CompositeNode<_PaintRow>> _rootNodes = _painter.paintPaper
      ? onUnderlay(_painter.nodes, const _PaintPaper())
      : _painter.nodes;

  /// Whether the content being painted is the display buffer's — a raster
  /// aligned to canvas space, where a level image lands texel for texel —
  /// rather than the walk's screen ([_paintImageNode]).
  bool _composingTheBuffer = false;

  /// Where the recording being made is shown — whole, once, cut by nothing
  /// else: the display buffer's rect on the visible canvas, while a miss
  /// composes it; null otherwise. A blend is read in the frame only inside
  /// it ([drawBlendOverBackdrop]): the engine cuts the layer a blend reads
  /// to the clip it is DRAWN under, and the source would then be sampled
  /// off the backdrop — under Impeller (`--enable-impeller`), a recording
  /// the bake replayed into a stroke's patch laid a multiply row's ink over
  /// paper it does not cover, 261 pixels a step.
  Rect? _shownWithin;

  void _paintContent(
    Canvas into, {
    required bool intoTheBuffer,
    required double rasterScale,
  }) {
    _composingTheBuffer = intoTheBuffer;
    // A recording made for the buffer draws its texel copies unfiltered and
    // the walk's resamples them on screen, so neither may replay the other.
    _painter.bake?.ensureIntoTheBuffer(intoTheBuffer);
    // ⛔No bake handed down (a host that does not own one, or a tree with
    // no live surface at all) keeps the original walk. The bake is an
    // optimisation, never a second way to be correct.
    //
    // ⛔Nor while a lift holds rows beside the live one (I-37 · F-329): the
    // bake records the rows a stroke cannot change, and a lifted row's
    // float moves under the hand.
    if (_painter.bake == null ||
        _painter.activeSurfacePainter == null ||
        _painter.liftedRows.isNotEmpty) {
      _paintNodes(into, _rootNodes, rasterScale);
      return;
    }
    if (intoTheBuffer) {
      _paintBackdropSplit(into, rasterScale);
      return;
    }
    _paintSplit(into, _rootNodes, 0, rasterScale);
  }

  /// Rasterises [_paintContent] over [bounds] at CANVAS resolution — at the
  /// display's level below 100% ([_level]) — or null when the stack should
  /// just paint itself onto the screen.
  ///
  /// Null is not a failure: an empty viewport (nothing on screen yet) and a
  /// buffer too large to be worth allocating are both cases where the
  /// direct walk is the better answer, and the direct walk is the one that
  /// was always correct.
  ///
  /// 🚨`toImageSync`, not `toImage`. The design said stage 2 needed a native
  /// surface because "Skia has no synchronous bytes-to-image path" — true,
  /// and about the wrong conversion. What this needs is DISPLAY LIST to
  /// image, which is synchronous from Dart and leaves the rasterisation
  /// deferred on the GPU. The repo already leans on that in the tile
  /// compose (`tiled_surface_compose`) and, until 2026-09-17, leaned on it
  /// in the provisional tile pictures, measured at 26-38us for a 256px tile.
  _DisplayBuffer? _composeDisplayBuffer(Rect bounds) {
    if (_painter.debugDisableSingleBuffer || bounds.isEmpty) {
      return null;
    }
    // Whole pixels, and the DESTINATION is the rounded rect too — a src/dst
    // pair that disagree by a fraction of a pixel would resample the buffer
    // a second time and undo the point of having it.
    final rect = wholeLevelPixelsOutward(bounds, _level);
    final width = (rect.width / _levelStep).round();
    final height = (rect.height / _levelStep).round();
    if (width <= 0 || height <= 0) {
      return null;
    }
    if (width > _LayerStackPainter._maxBufferSide ||
        height > _LayerStackPainter._maxBufferSide) {
      // 🚨THE SAFETY NET, AND NOTHING ELSE (유저 결정 2026-09-16: 「안전망만
      // 존재하면 문제없고」). Below 100% the buffer is a level, at most 4×
      // the screen, so it reaches the cap only on a window wider than
      // 8192·2 device pixels; at or above 100% only on one wider than the
      // cap itself. There the direct walk draws — T21 territory, every
      // layer resampled separately, which the walk was before any buffer
      // existed and is always correct. The knee that used to compose a
      // screen-scale buffer here (ⓔ 5단계, 2026-08-16 → 2026-09-16) is
      // gone: it cost 488MB and 300ms a stroke batch on a large page, and
      // the level buffer answers every view it answered, sharper.
      debugCappedFallbacks += 1;
      return null;
    }
    // 🚨(v) — KEEP IT WHILE NOTHING HAS CHANGED. Every paint used to
    // rasterise this again, including the ones where nothing had moved: a
    // hover, a cursor blink, a neighbouring panel rebuilding.
    //
    // ⛔A miss costs exactly what the uncached path cost, which is the
    // property that makes this safe. The TILED buffer failed on the other
    // side of that line — a cold tile cache rasterised the composite once
    // per tile, so the thing meant to make strokes cheap made panning N
    // times dearer. One image cannot do that.
    final cache = _painter.bufferCache;
    final key = cache == null ? null : _painter._bufferKey();
    final kept = _keptBuffer(cache, key, rect);
    if (kept != null) {
      return kept;
    }
    return _composeMiss(rect, cache, key);
  }

  /// The display buffer for [image] over [rect]. [owned] says whether the
  /// caller disposes the image after drawing it (false while the cache
  /// keeps it for the next paint).
  ///
  /// ⛔THE PIXEL SIZE IS THE IMAGE'S, NEVER THE RECT'S. Below 100% the two
  /// differ — the image is the rect over 2^level a side — and that is what
  /// the blit's source rect must say or the picture lands shrunk in the
  /// corner. This used to be two constructors, one reading the rect for the
  /// canvas-resolution path and one reading the image for the knee's scaled
  /// path, and 2026-09-04 the knee path was routed through the rect one by
  /// mistake: one wrong frame on every miss below the knee. Reading the
  /// image answers both, because at level 0 the rect is snapped and the raster is
  /// `toImageSync(rect.width.round(), …)` — the same number, by
  /// construction.
  _DisplayBuffer _bufferOf(ui.Image image, Rect rect, {required bool owned}) =>
      _BufferImage(
        image: image,
        rect: rect,
        pixelWidth: image.width.toDouble(),
        pixelHeight: image.height.toDouble(),
        owned: owned,
      );

  /// The buffer the cache still holds for [key] over [rect], or null.
  _DisplayBuffer? _keptBuffer(
    DisplayBufferCache? cache,
    Object? key,
    Rect rect,
  ) {
    if (cache != null && key != null) {
      final kept = cache.imageFor(key, rect);
      if (kept != null) {
        return _bufferOf(kept, rect, owned: false);
      }
    }
    return null;
  }

  /// A canvas onto the buffer over [rect], in the buffer's own pixels:
  /// canvas pixels at level 0, 2^level canvas pixels below 100% — one
  /// scale, then the translate, so every draw (the carried base, the paper,
  /// the level images) lands 1:1. Bounded by those pixels, so a draw into
  /// it can ask what it can land on (`drawPosedLayerImage`, a picture in
  /// pieces).
  Canvas _bufferCanvas(ui.PictureRecorder recorder, Rect rect) =>
      Canvas(
          recorder,
          Rect.fromLTWH(
            0,
            0,
            (rect.width / _levelStep).roundToDouble(),
            (rect.height / _levelStep).roundToDouble(),
          ),
        )
        ..scale(1 / _levelStep)
        ..translate(-rect.left, -rect.top);

  /// A miss: the buffer recomposed — patched over the carried base, scrolled
  /// from the previous buffer, or rastered whole — and stored when the
  /// cache can keep it.
  _DisplayBuffer _composeMiss(
    Rect rect,
    DisplayBufferCache? cache,
    Object? key,
  ) {
    final miss = _planMiss(rect, cache, key);
    final base = miss.base;
    final dirty = miss.dirty;
    final scroll = miss.scroll;
    final canScroll = miss.canScroll;
    _shownWithin = rect.intersect(_visibleCanvasRect);
    final recorder = ui.PictureRecorder();
    final into = _bufferCanvas(recorder, rect);
    // ⛔SET AT THE BRANCH THAT DECIDES IT. Two of these three draw a base
    // into this recorder; when that base is the cache's deferred HEAD the
    // new image retains it (`DisplayBufferCache._derivedDepth` says what
    // that costs and why it is bounded), when it is the REAL base it does
    // not, and the base itself says which. The third starts from nothing.
    // Re-deriving the answer next to `store` is how the scrolled carry
    // came to be counted as a fresh compose in the first place.
    final bool derived;
    var drawn = false;
    if (base != null && dirty != null) {
      _blitPatched(into, base.image, rect, dirty);
      derived = base.deferred;
      drawn = !derived && _pictureDrawsTheSame(dirty);
    } else if (scroll != null && canScroll) {
      cache!.lastComposedArea = _blitScrolled(into, scroll, rect, dirty);
      derived = scroll.deferred;
    } else {
      labProbe(
        'displayBuffer.recordWhole',
        () => _paintContent(
          into,
          intoTheBuffer: true,
          rasterScale: 1 / _levelStep,
        ),
      );
      derived = false;
    }
    _shownWithin = null;
    return _keepMiss(
      recorder,
      rect,
      cache,
      key,
      patched: base != null && dirty != null,
      derived: derived,
      carried: canScroll,
      tokens: miss.tokens,
      drawn: drawn,
    );
  }

  /// Whether a patch's picture drawn straight onto the screen lands the
  /// bytes its rastered head, blitted there, would — so the head need not
  /// be rastered at all: one render pass fewer a stroke step, and a
  /// snapshot costs the same whatever its size (measured 2026-09-25 on the
  /// real Windows app, 1.6–2.0 ms from 32×32 to a whole window).
  ///
  /// The picture blits the real base 1:1 and recomposes [dirty] over it;
  /// on the screen those are the same draws under the viewport transform,
  /// and they land the same bytes exactly when —
  /// · the display scale is a WHOLE number and the view is not rotated:
  ///   every canvas pixel is then a whole block of device pixels
  ///   ([renderSnappedViewport] puts the translation on whole pixels), so
  ///   no sample falls on a texel boundary and no tile or raster edge cuts
  ///   a device pixel. ⛔Between whole scales a tile edge splits a pixel,
  ///   and on a multisampled screen (Impeller Vulkan) that pixel averages
  ///   two tiles' samples where the head had one texel;
  /// · [dirty] lies on opaque paper: the recompose CLEARS first, which on
  ///   the screen clears the pasteboard under it too, and only an opaque
  ///   draw over it puts back exactly what the head was blitted over;
  /// · every draw the recompose makes is a texel copy blended pixel by
  ///   pixel ([_drawsTexelForTexel]). ↩️A stamp ghost was the exception —
  ///   drawn where the pointer was, off the texel grid — until
  ///   brush-fidelity-Q9 made it the overlay's tiles, on the grid;
  /// · the screen is 8-bit. iOS draws to a wide-gamut surface by default,
  ///   where blending rounds differently from the 8-bit head.
  bool _pictureDrawsTheSame(Rect dirty) {
    // A whole scale is never below 100%, so the buffer is at level 0.
    if (!debugDrawBufferPictures ||
        defaultTargetPlatform == TargetPlatform.iOS ||
        _painter.viewport.rotationDegrees != 0 ||
        _displayScale != _displayScale.roundToDouble()) {
      return false;
    }
    final region = wholeLevelPixelsOutward(dirty, _level);
    final onPaper =
        _painter.paintPaper &&
        _painter.paperBackground.paintedArgb >>> 24 == 0xFF &&
        region.left >= _canvasRect.left &&
        region.top >= _canvasRect.top &&
        region.right <= _canvasRect.right &&
        region.bottom <= _canvasRect.bottom;
    return onPaper && _drawsTexelForTexel(_painter.nodes);
  }

  /// Whether every draw [nodes] make is a texel copy blended pixel by pixel
  /// — then laying them down at canvas resolution and magnifying the result
  /// by a whole number is the same as laying them down magnified. A draw
  /// that does not qualify: a pose (it resamples), a blend that does not
  /// work in place or an effect that spreads ([inkCropDrawsTheSame], which
  /// has the measurements — an advanced blend rounds by the area drawn), a
  /// layer image that is not a texel copy, and an adjustment scope — its
  /// crossfade goes through `saveLayer`s nobody has measured this way yet.
  /// The paper is a fill on whole canvas pixels, and qualifies.
  ///
  /// A row blended over its backdrop qualifies when what it composes does:
  /// its shader runs over two rasters made as the picture is recorded, and
  /// what the picture draws is the result's blit — 1:1, as a group's is.
  /// ↩️It never did ("nobody has measured"), and a blend row anywhere in the
  /// tree, baked or not, cost every stroke step a head: 🔬on the Windows app
  /// (10-22, r10 · r11) a stroke over a multiply row went from 19.2ms input
  /// to screen to 14.0, the 14.4 of a normal one.
  bool _drawsTexelForTexel(List<CompositeNode<_PaintRow>> nodes) {
    for (final node in nodes) {
      final inPlace = switch (node) {
        CompositeLeaf(payload: final _PaintImage row) =>
          inkCropDrawsTheSame(
                placement: row.placement,
                blendMode: row.blendMode,
                effects: row.effects,
              ) &&
              row.pieces.every(
                (piece) => drawsAsTexelCopy(piece.image, piece.worldRect),
              ),
        CompositeLeaf(payload: final _SurfaceRow row) => inkCropDrawsTheSame(
          placement: row.placement,
          blendMode: row.blendMode,
          effects: row.effects,
        ),
        CompositeLeaf(payload: _PaintPaper()) => true,
        CompositeGroup(:final blendMode, :final effects, :final children) =>
          inkCropDrawsTheSame(
                placement: null,
                blendMode: blendMode,
                effects: effects,
              ) &&
              _drawsTexelForTexel(children),
        // Not on a flipped view: read in the frame, a blend reads its
        // backdrop in the space it is drawn in — the screen's, which a flip
        // runs the other way from the picture's ([drawBlendOverBackdrop]).
        CompositeBackdropBlend(:final backdrop, :final source) =>
          !_painter.viewport.flipHorizontal &&
              !_painter.viewport.flipVertical &&
              _drawsTexelForTexel(backdrop) &&
              _drawsTexelForTexel([source]),
        CompositeAdjustment() => false,
      };
      if (!inPlace) {
        return false;
      }
    }
    return true;
  }

  /// Rasters the recorded miss and, when the cache can keep it, stores the
  /// head and offers its snapshot as the next real base.
  ///
  /// 🎯THE SNAPSHOT THAT ENDS THE CHAIN: the same picture, rasterized once
  /// more as a plain image, becomes the base the NEXT paint derives from —
  /// so the deferred image made here is only ever drawn, never drawn from.
  /// Asked of the cache, which knows whether one is still in flight.
  ///
  /// [drawn]: the picture goes to the screen as it is and no head is
  /// rastered ([_pictureDrawsTheSame]); only the snapshot, when asked for.
  _DisplayBuffer _keepMiss(
    ui.PictureRecorder recorder,
    Rect rect,
    DisplayBufferCache? cache,
    Object? key, {
    required bool patched,
    required bool derived,
    required bool carried,
    required LiveSurfaceTokens? tokens,
    required bool drawn,
  }) {
    final width = (rect.width / _levelStep).round();
    final height = (rect.height / _levelStep).round();
    final snapshot =
        cache != null &&
        key != null &&
        _painter._drawsLive &&
        cache.wantsPromotionFor(patchedOverRealBase: patched && !derived);
    if (drawn) {
      // Only a patch over the cache's own real base is drawn, so the cache
      // and its key are there.
      final picture = recorder.endRecording();
      cache!.store(
        key!,
        _painter.compositeKey,
        rect,
        null,
        patched: true,
        tokens: tokens,
      );
      if (snapshot) {
        cache.promote(picture.toImage(width, height));
      }
      return _BufferPicture(picture: picture, rect: rect);
    }
    final made = labProbe(
      'displayBuffer.raster',
      () => rasterPictureAndSnapshot(
        recorder,
        width,
        height,
        snapshot: snapshot,
      ),
    );
    final image = made.deferred;
    if (cache == null || key == null) {
      return _bufferOf(image, rect, owned: true);
    }
    cache.store(
      key,
      _painter.compositeKey,
      rect,
      image,
      patched: patched,
      derived: derived,
      tokens: tokens,
    );
    cache.lastBufferLevel = _level;
    if (carried) {
      cache.scrolledCount += 1;
    }
    final real = made.real;
    if (real != null) {
      cache.promote(real);
    }
    return _bufferOf(image, rect, owned: false);
  }

  /// What a miss can start from: the carried base to patch (with the live
  /// dirty rect), or the previous buffer to scroll; both null means a
  /// full raster. Records the live dirty rect on the cache as it asks.
  _MissPlan _planMiss(Rect rect, DisplayBufferCache? cache, Object? key) {
    // 🚨★★★A MISS DOES NOT HAVE TO START FROM NOTHING. When the only thing
    // that moved is the LIVE surface — which is every step of a stroke —
    // the previous buffer is right everywhere the stroke did not touch, so
    // the recomposite is confined to the dirty rect and the rest is one
    // opaque blit.
    //
    // ⛔This is what replaced the TILE GRID. Tiling split the buffer for the
    // same reason and paid for it twice: a seam at every boundary at
    // fractional scale, and a cold cache costing N rasters instead of one.
    // Patching keeps ONE image — there is no boundary to seam — and leaves
    // the cold path exactly as it was.
    final base = cache == null || key == null
        ? null
        : cache.patchBaseFor(_painter.compositeKey, rect);
    // 🚨★★★A PAN CARRIES WHAT IT ALREADY HAD. A moved extent is not a wrong
    // buffer, it is an OFFSET one: the buffer is canvas resolution, so one
    // buffer pixel is one canvas pixel at every zoom and the overlap belongs
    // exactly where the new rect says. What is left is the band the pan
    // exposed — and, because the live surface is deliberately absent from
    // [compositeKey], whatever the live layer changed since.
    //
    // ⛔ONE IMAGE STILL: the blit and the band land in this same recorder and
    // come out of one `toImageSync`. A base drawn beside a patch at paint
    // time would seam at fractional scale, which is what the tile grid was
    // rejected for.
    final scroll = base != null || cache == null || key == null
        ? null
        : cache.scrollBaseFor(_painter.compositeKey, rect);
    // ⛔ALWAYS, even with no base to patch: this call is also what SEES
    // what the live surface looks like now, and that goes into the store
    // with the buffer this miss makes. Asking it only when a patch was
    // already possible left the first buffer without a snapshot, so the
    // first real stroke step compared against nothing and fell back to a
    // full raster — measured, with the counter reading zero.
    //
    // 🚨★★★SEEN here, RECORDED only by `store` (F-68 ③). Recording on every
    // call — including the paints a floating selection keeps uncacheable —
    // moved the snapshot ahead of the image it described, and the patch
    // after a confirm then carried the ring the lift had erased back from
    // the buffer made before it.
    //
    // 🎯MEASURED FROM THE BASE THAT WILL BE DRAWN, not from the head: the
    // real base is a paint or three older than the head, and a dirty rect
    // measured from the head's tokens would miss the steps between — a
    // stroke with holes in it, on every platform.
    final change = cache == null
        ? (located: false, dirty: null, now: null)
        : _painter._liveDirtyCanvasRect(
            since: (base ?? scroll)?.tokens ?? cache.keptTokens,
          );
    // ⛔TWO ANSWERS, NOT ONE. `located: false` is "cannot say where"; a null
    // rect with `located: true` is "nothing changed", which is the BEST case
    // for a carry and used to be indistinguishable from the worst.
    final dirty = change.dirty;
    cache?.lastDirtyRect = dirty;
    // ⚠️REFUSED WHEN THE LIVE SURFACE CANNOT SAY WHERE IT CHANGED. Carrying
    // the overlap would carry a stale live layer with it, and nothing else
    // in the key would notice.
    final canScroll = scroll != null && change.located;
    return (
      base: base,
      dirty: dirty,
      scroll: scroll,
      canScroll: canScroll,
      tokens: change.now,
    );
  }

  /// Recomposes [region] of the buffer over pixels a carry already put in
  /// [into] — the one step the patch and the scroll carry share.
  ///
  /// ⛔CLEAR first. The composite is drawn OVER the old pixels otherwise,
  /// and ink that is not fully opaque would blend with its own previous
  /// frame — a stroke would darken as it was redrawn.
  ///
  /// 🚨★★★AND WHERE THE NEW COMPOSITE DRAWS NOTHING, THE OLD PIXELS SIMPLY
  /// STAY (F-104, 유저 2026-09-12: 「페이스트 보드에 이전 프레임의 그림이
  /// 남아있음 … 그 위치에 선을 그리면 사라짐」). The patch cleared; the scroll
  /// carry wrote the same steps out again without the clear, so switching to
  /// a frame whose extent differed kept the frame before wherever the new
  /// one had nothing. One step now, so a carry cannot be written without it.
  ///
  /// ⛔NO ANTIALIAS on the clip: a soft edge would blend the region into the
  /// carried pixels and leave a seam of its own.
  ///
  /// 🚨★★★F-287 — THE CLIP DOES NOT HOLD A BLEND THAT IS NOT IN PLACE (유저
  /// 2026-10-04 · 10-05 · 10-12, 실기: 「곱하기레이어가 두개이상있을때, 세번째
  /// 일반 레이어에서 그리면 선을 긋거나 캔버스 줌인 줌아웃할때마다 그림
  /// 이상한곳이 진해짐. 현재 레이어 바꾸거나 하면 초기화됨 … 이 문제는 고쳐도
  /// 3번째 발생이니 다양한 각도에서 확인하고 해결」 — the family of F-172 and
  /// F-243). 🔬Measured on the Windows app (Impeller GLES, 2026-10-08): A and
  /// B both multiply, every stroke on B patched three times, and each patch
  /// multiplied B's colour in once more OUTSIDE the patch — wherever B lay
  /// (f0d060 → c87105 → a73d00 …), A alone and the paper untouched; one
  /// blend alone changed nothing. The carried pixels already hold the
  /// composite, so a draw that escapes the clip lays a second copy of itself
  /// over them, on every patch and every carry until a full composite —
  /// switching the row — draws it once again.
  /// 🔬Again on the same app (2026-10-19), on dark paper so that any mode
  /// could show it, each stroke's dabs counted: a stroke on a NORMAL row
  /// above both blends or between them — the user's case — laid B in three
  /// times more, as one on B did, while one on A, or over a single blend,
  /// did nothing. A notch of the wheel OUT within a level laid it in once
  /// more, at levels 2, 1 and 0 alike (multiply and screen; the notch back
  /// in, and a notch out of the fitted view with the whole page in sight,
  /// changed nothing). Every mode that shows being laid twice did it —
  /// multiply, color burn, screen, color dodge, overlay, soft and hard
  /// light, difference, exclusion; darken and lighten laid twice are what
  /// they are laid once. Composed apart, not one of them moved a pixel. The
  /// same draws on the engine alone (200+ stacks, the clip and all) never
  /// escaped, so WHERE the app lets them out is still not known — and
  /// composing apart does not need to know it.
  /// ⇒ When anything in the stack does not blend in place, the region is
  /// composed APART ([_drawComposedApart]): on nothing, in an image of its
  /// own, and laid onto the carried pixels by a draw that does — what a lost
  /// clip lets through lands on that image's margin, which is not copied.
  /// ⛔ONLY THEN. The image is a render pass a step (a snapshot costs the
  /// same 1.6–2.0 ms whatever its size, measured 2026-09-25), which a stack
  /// of in-place draws does not need and still draws as a picture
  /// ([_pictureDrawsTheSame]). The question is [blendsInPlace]'s, the one
  /// every other site asks of a blend ([_everyDrawBlendsInPlace]) — a mode
  /// left out costs time, never a pixel.
  void _recomposeOverCarried(Canvas into, List<Rect> region) {
    // ⛔NO REGION, NO RECOMPOSE: a carry into a rect inside the one it had
    // — a zoom in on the same level — with nothing live changed has no
    // band, a patch whose change lies wholly outside the buffer has no part
    // in it, and the carried pixels are the whole buffer.
    if (region.isEmpty) {
      return;
    }
    final clip = Path();
    for (final part in region) {
      clip.addRect(part);
    }
    into.save();
    into.clipPath(clip, doAntiAlias: false);
    if (!debugRecomposeApart || _everyDrawBlendsInPlace()) {
      into.drawPaint(Paint()..blendMode = BlendMode.clear);
      _paintContent(into, intoTheBuffer: true, rasterScale: 1 / _levelStep);
    } else {
      _drawComposedApart(into, region, clip);
    }
    into.restore();
  }

  /// [region] composed apart — in an image of its own over the parts'
  /// bounds, on nothing — and laid onto [into], already held to [clip],
  /// `src`: where the composite draws nothing the carried pixels go too
  /// (F-104), with no clear before it.
  void _drawComposedApart(Canvas into, List<Rect> region, Path clip) {
    final bounds = region.reduce((a, b) => a.expandToInclude(b));
    final recorder = ui.PictureRecorder();
    final apart = Canvas(recorder)
      ..scale(1 / _levelStep)
      ..translate(-bounds.left, -bounds.top)
      // Only to spare the margin's pixels: whatever gets past it lands on
      // the margin, and the blit leaves the margin behind.
      ..clipPath(clip, doAntiAlias: false);
    _paintContent(apart, intoTheBuffer: true, rasterScale: 1 / _levelStep);
    final picture = recorder.endRecording();
    final ui.Image image;
    try {
      image = picture.toImageSync(
        (bounds.width / _levelStep).round(),
        (bounds.height / _levelStep).round(),
      );
    } finally {
      picture.dispose();
    }
    _layLevelPixels(into, image, bounds, blendMode: BlendMode.src);
    // The recording holds its own reference to what it draws.
    image.dispose();
    _painter.bufferCache?.composedApartCount += 1;
  }

  /// Whether every draw the stack makes blends in place ([blendsInPlace]) —
  /// what a recompose over carried pixels may stand its clip on. A folder's
  /// children count although the folder composes them in an image of its
  /// own. ↩️A stamp ghost counted too, whatever its blend — until
  /// brush-fidelity-Q9 made it the overlay's tiles, pre-blended and laid
  /// in place of the cel's as a stroke's are.
  bool _everyDrawBlendsInPlace() => _nodesBlendInPlace(_painter.nodes);

  bool _nodesBlendInPlace(List<CompositeNode<_PaintRow>> nodes) {
    for (final node in nodes) {
      final inPlace = switch (node) {
        CompositeLeaf(payload: final _PaintImage row) => blendsInPlace(
          row.blendMode.paintBlendMode,
        ),
        CompositeLeaf(payload: final _SurfaceRow row) => blendsInPlace(
          row.blendMode.paintBlendMode,
        ),
        CompositeGroup(:final blendMode, :final children) =>
          blendsInPlace(blendMode.paintBlendMode) &&
              _nodesBlendInPlace(children),
        // Its own passes are `srcOver` and `plus`.
        CompositeAdjustment(:final children) => _nodesBlendInPlace(children),
      };
      if (!inPlace) {
        return false;
      }
    }
    return true;
  }

  /// Recomposes only [dirty] over the carried [base]: the old pixels are
  /// blitted 1:1, the dirty rect cleared and repainted.
  ///
  /// ⛔THE SOURCE RECT IS THE IMAGE'S PIXELS, never the rect's size: below
  /// 100% the base is a level image, 2^level canvas pixels to each of its
  /// own, and the recorder's scale maps it back onto [rect] 1:1. And the
  /// dirty rect is grown to whole buffer pixels first — a level pixel the
  /// stroke touched by a third would otherwise be kept as it was, its
  /// centre outside the clip.
  ///
  /// ⛔HELD TO [rect], as the carry's bands are: the dirty rect is the live
  /// tiles a step changed, and those reach past the view — by up to a tile
  /// for a dab at its edge, by the whole canvas for a fill or an undo made
  /// zoomed in. A region composed apart (F-287) is an image of what it is
  /// given, every pixel of which outside [rect] would be thrown away — and
  /// on a large canvas one past the side the buffer itself is capped at
  /// ([_LayerStackPainter._maxBufferSide]).
  void _blitPatched(Canvas into, ui.Image base, Rect rect, Rect dirty) {
    _layLevelPixels(into, base, rect);
    final part = wholeLevelPixelsOutward(dirty, _level).intersect(rect);
    _recomposeOverCarried(into, [if (!part.isEmpty) part]);
  }

  /// Lays [image] — pixels made at this buffer's level, the whole of it or
  /// its [source] — onto [target] one texel to a pixel: the patch's base,
  /// the scroll carry's overlap and a region composed apart (F-287) are
  /// all laid so. A COPY, so `none` — a filter would resample what is
  /// already aligned — and no antialias at edges that lie on the level's
  /// grid. `src` lays it in place of what is there.
  void _layLevelPixels(
    Canvas into,
    ui.Image image,
    Rect target, {
    Rect? source,
    BlendMode blendMode = BlendMode.srcOver,
  }) {
    into.drawImageRect(
      image,
      source ??
          Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      target,
      Paint()
        ..blendMode = blendMode
        ..filterQuality = ui.FilterQuality.none
        ..isAntiAlias = false,
    );
  }

  /// Carries the overlap of the previous buffer ([scroll]) into [rect]
  /// and repaints only the bands the pan exposed, plus [dirty]; answers
  /// the area repainted.
  double _blitScrolled(Canvas into, _Base scroll, Rect rect, Rect? dirty) {
    final was = scroll.rect;
    final overlap = was.intersect(rect);
    _layLevelPixels(
      into,
      scroll.image,
      overlap,
      // The overlap in the OLD image's own pixels: the offset between the
      // two rects, in buffer pixels — both rects lie on the same level's
      // grid (the level is in the key), so it is whole.
      source: Rect.fromLTWH(
        (overlap.left - was.left) / _levelStep,
        (overlap.top - was.top) / _levelStep,
        overlap.width / _levelStep,
        overlap.height / _levelStep,
      ),
    );
    // ⛔THE BANDS, LISTED. Up to four of them — the strips of the new rect
    // the old one did not reach — plus the live dirty rect, because the
    // carried pixels are as old as the last composite.
    //
    // 🚨A LIST RATHER THAN AN EVEN-ODD PATH, and a mutation is why: with
    // the path form, dropping the subtraction left the clip covering the
    // whole rect — correct pixels, no saving, and every test green. The
    // clip and the AREA now come from the same list, so a band that stops
    // being excluded stops being counted.
    final bands = <Rect>[
      if (overlap.top > rect.top)
        Rect.fromLTRB(rect.left, rect.top, rect.right, overlap.top),
      if (overlap.bottom < rect.bottom)
        Rect.fromLTRB(rect.left, overlap.bottom, rect.right, rect.bottom),
      if (overlap.left > rect.left)
        Rect.fromLTRB(rect.left, overlap.top, overlap.left, overlap.bottom),
      if (overlap.right < rect.right)
        Rect.fromLTRB(overlap.right, overlap.top, rect.right, overlap.bottom),
      if (dirty != null && !dirty.intersect(overlap).isEmpty)
        wholeLevelPixelsOutward(dirty, _level).intersect(overlap),
    ];
    var area = 0.0;
    for (final band in bands) {
      area += band.width * band.height;
    }
    _recomposeOverCarried(into, bands);
    return area;
  }
}
