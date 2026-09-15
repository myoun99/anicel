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
  /// fallback for a rotated/flipped view, or an active layer the flat
  /// projection refuses — was still handing every cached image a flat
  /// `low`, which filtered a MAGNIFIED view. Two routes sampling differently
  /// is the T21 defect wearing a different hat: the artwork changed
  /// depending on which one the frame happened to take.
  ///
  /// 🔜ONE RESIDUE, NAMED RATHER THAN FORGOTTEN. When the walk reaches the
  /// active layer's TILES — the last fallback of the last fallback, after
  /// the flat projection and the stand-in have both refused — those draw
  /// through `BitmapSurfacePainter` at `none`, so a reduced view still
  /// aliases them beside filtered neighbours. It is not a constant to
  /// change: a tile is filtered with no neighbours to sample, so `low`
  /// there buys a seam at every tile boundary instead. The buffered route
  /// is what actually solves it (composite at canvas resolution, resample
  /// once), and that route already runs everywhere it can.
  ui.FilterQuality get _displayQuality =>
      filterQualityForDisplayScale(displayScaleOf(_painter.viewport.zoom));

  // One paint's geometry: set by [paint] before the walk below reads it.
  // The page rect, the on-screen part of the pasteboard, the content the
  // display buffer must cover, the part of it the bake records over, and
  // the active slot's two extents, each read once.
  late final Rect _canvasRect;
  late final Rect _visibleCanvasRect;
  late final Rect _contentExtent;
  late final Rect _bakeExtent;
  Rect? _memoActiveExtent;
  Rect? _memoCommittedExtent;

  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    applyViewportTransform(
      canvas,
      _painter.viewport,
      devicePixelRatio: _painter.devicePixelRatio,
    );

    _canvasRect = Rect.fromLTWH(
      0,
      0,
      _painter.canvasSize.width.toDouble(),
      _painter.canvasSize.height.toDouble(),
    );
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
          ' alpha=${Color(_painter.paperBackground.argb).a.toStringAsFixed(2)}'
          ' nodes=${_painter.nodes.length}'
          ' rect=${_canvasRect.width.round()}x${_canvasRect.height.round()}';
      if (probe != _LayerStackPainter._lastStackProbe) {
        _LayerStackPainter._lastStackProbe = probe;
        InputInspector.note(probe);
      }
    }
    // The group buffer's bounds are a SIZE HINT to the engine: it
    // allocates an offscreen that big. The pasteboard is 3×3 canvases —
    // 9× the area (5×5 and 25× until H2, 2026-08-22) — so handing it over
    // verbatim would make every folder buffer 9× more expensive than the
    // picture it holds. Only what is ON SCREEN can matter, so intersect
    // with the visible canvas-space rect (the same rect the surface painter
    // uses to prioritise decodes).
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
    final pasteboardRect = _painter.canvasSize.pasteboardRect;
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
        // [DisplayBufferCache.promotedCount].
        final cadence =
            'full~${cache.fullCount ~/ 8}'
            ' patched~${cache.patchedCount ~/ 32}'
            ' carried~${cache.scrolledCount ~/ 32}';
        if (cadence != CanvasPaintGeometryProbe.lastCounters) {
          CanvasPaintGeometryProbe.lastCounters = cadence;
          InputInspector.note(
            'buf full=${cache.fullCount}'
            ' patched=${cache.patchedCount}'
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
    // the pasteboard is 3×3 canvases (5×5 until H2) and rasterising all of
    // it would cost 9× what is on screen. It is not the canvas rect either:
    // artwork parked on the pasteboard is visible and must composite with
    // the rest (유저 2026-08-15, 「페이스트보드도 룰러할때 보이게」).
    final buffer = _composeDisplayBuffer(_contentExtent);
    if (buffer == null) {
      _paintContent(
        canvas,
        // The direct walk draws under the viewport transform, so a group
        // that rasterises itself has to match the CTM it is drawn into.
        intoTheBuffer: false,
        rasterScale: _painter.viewport.zoom.abs() * _painter.devicePixelRatio,
      );
    } else {
      try {
        canvas.drawImageRect(
          buffer.image,
          Offset.zero & Size(buffer.pixelWidth, buffer.pixelHeight),
          buffer.rect,
          Paint()
            ..filterQuality = filterQualityForDisplayScale(
              displayScaleOf(_painter.viewport.zoom),
            )
            // The buffer's edge IS the canvas's edge on screen, cut by the
            // same law as the paper's (F-67-paper-edge): under nearest on
            // an axis-aligned view it is one more texel boundary, decided
            // by pixel centres, not a blended line.
            ..isAntiAlias = displayEdgeAntiAliased(_painter.viewport),
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
    canvas.restore();
  }

  /// 🚨★★★WHAT THE ACTIVE SLOT DRAWS, not what its surface holds (F-85,
  /// 2026-09-15): the painter's own answer, and the float drawn into the
  /// same slot. Read off the committed surface alone, a stroke in flight, a
  /// fill's stamp, the stamp ghost and a transform's float were all cut at
  /// the edge of the ink that had already landed — and came back the moment
  /// a commit put tiles there. What the DISPLAY BUFFER covers; the bake
  /// measures by [_committedSurfaceExtent].
  ///
  /// Read ONCE per paint: the node walk asks per group, and the answer walks
  /// every tile and overlay tile the slot holds.
  Rect _activeSurfaceExtent() =>
      _memoActiveExtent ??= switch (_painter.activeSurfacePainter) {
        null => Rect.zero,
        final painter => _withTheFloat(painter.drawnWorldRect),
      };

  Rect _withTheFloat(Rect drawn) {
    final float = _painter.floatOverlay?.value?.drawnWorldRect;
    if (float == null || float.isEmpty) {
      return drawn;
    }
    // A slot that draws nothing answers [Rect.zero], and a union with it
    // would reach back to the origin.
    return drawn.isEmpty ? float : drawn.expandToInclude(float);
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

  Rect _bufferBoundsFor(
    CompositeNode<_PaintRow> node,
    Rect Function() activeSurfaceExtent,
  ) => _visibleCanvasRect.intersect(
    _paintNodeExtent(
      node,
      canvasSize: _painter.canvasSize,
      activeSurfaceExtent: activeSurfaceExtent,
    ),
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
      final nodePose = switch (node) {
        CompositeLeaf(payload: _PaintImage(:final pose)) => pose,
        CompositeLeaf(payload: _PaintActiveSurface(:final pose)) => pose,
        CompositeGroup() || CompositeAdjustment() => null,
      };
      final nodeAnchor = switch (node) {
        CompositeLeaf(payload: _PaintImage(:final anchorPoint)) => anchorPoint,
        CompositeLeaf(payload: _PaintActiveSurface(:final anchorPoint)) =>
          anchorPoint,
        CompositeGroup() || CompositeAdjustment() => null,
      };
      // The wrap straddles the live-surface node too, which HAS a pose
      // and no image — that is why the pose and the draw are separate
      // helpers rather than one.
      withLayerPose(
        canvas,
        pose: nodePose,
        canvasSize: _painter.canvasSize,
        anchorPoint: nodeAnchor,
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
            case CompositeLeaf(payload: final _PaintActiveSurface active):
              _paintActiveSurfaceNode(canvas, node, active, rasterScale);
            case CompositeLeaf(payload: final _PaintImage image):
              _paintImageNode(canvas, image);
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
    final groupRect = effectBufferBounds(
      _bufferBoundsFor(node, _activeSurfaceExtent),
      groupPlan.outsetPixels,
    );
    assert(
      _contentExtent.expandToInclude(groupRect) == _contentExtent,
      'a group buffer must sit inside the composite it is part '
      'of: $groupRect is not within $_contentExtent',
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

  /// The live layer: drawn straight onto the canvas when its paint can
  /// ride the draws, through one buffer when it cannot (an outset effect,
  /// overlapping coverage, a float overlay, or pre-steps).
  void _paintActiveSurfaceNode(
    Canvas canvas,
    CompositeNode<_PaintRow> node,
    _PaintActiveSurface row,
    double rasterScale,
  ) {
    final _PaintActiveSurface(:opacity, :blendMode, :effects, :standIn) = row;
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
    // pixel exactly once").
    //
    // What is left for a buffer is the one thing a per-draw
    // paint cannot do: a filter that SPREADS has to see across
    // the tile boundaries, so it needs the layer assembled
    // first. `outsetPixels` is exactly that question — a colour
    // matrix is per-pixel and rides along fine.
    final needsBuffer =
        activeEffects.outsetPixels > 0 ||
        !_painter.activeSurfacePainter!.drawsDisjointCoverage ||
        // The selection FLOAT is this layer's pixels lifted out
        // and drawn back on top of it — the one overlap the
        // painter cannot see, because it is not the painter's.
        // ⛔`isEmpty`, not `!= null`: an overlay mounted with
        // nothing in it draws nothing and overlaps nothing.
        !(_painter.floatOverlay?.value?.isEmpty ?? true) ||
        // 🚨A SHADER CANNOT SAMPLE A saveLayer. A colour key
        // BELOW a painted effect keys what that effect made, so
        // the layer has to be assembled into an image first —
        // the one thing a buffer cannot hand it.
        activePlan.preSteps.isNotEmpty;
    // Null when the buffer carries it, so nothing applies twice.
    final ridingPaint = needsBuffer ? null : activePaint;
    assert(() {
      debugLiveLayerRodeTheDraws = !needsBuffer;
      return true;
    }());
    // 🚨THE LIVE LAYER'S OWN CONTENT, AS A CLOSURE — because a
    // colour key BELOW a painted effect has to key what that
    // effect made, and a shader cannot sample a `saveLayer`.
    // ⛔Only that case rasterises. A plainly buffered layer keeps
    // the cheaper `saveLayer`: 🧪measured, the image route costs
    // 3.2x on the path a stroke redraws every step.
    void paintLiveBody(Canvas into) {
      into.save();
      into.clipRect(_painter.activeSurfacePainter!.pasteboardRect);
      final flat = _painter._activeFlatForRecording;
      if (flat != null) {
        assert(() {
          debugActiveSlotDraw = ActiveSlotDraw.flat;
          return true;
        }());
        // ⓔ 5단계: under the scaled recording the active layer is
        // ONE image like every other layer, resampled by the
        // recording's transform under the SAME filter — that
        // uniformity is what closes T21 below the knee. 1:1
        // src/dst; the one resample comes from the CTM.
        into.drawImageRect(
          flat.image,
          Rect.fromLTWH(
            0,
            0,
            flat.image.width.toDouble(),
            flat.image.height.toDouble(),
          ),
          flat.worldRect,
          _withLayerPaint(
            Paint()..filterQuality = _displayQuality,
            ridingPaint,
          ),
        );
        // 🚨F-33 / F-130: the projection is the tiles and the stroke — the
        // stamp's ghost is drawn by the walk, which this blit replaced, so
        // it vanished past the cap and under `QA_KNEE_AT_ONE` (adversarial
        // review, 2026-09-15). Drawn here over the image, as the walk
        // draws it over everything; the slot's buffer (a ghost opens one:
        // `drawsDisjointCoverage` says false) carries the layer over both.
        _painter.activeSurfacePainter!.paintStampPreviewInto(into);
      } else if (standIn != null &&
          standIn.shouldStandInFor(_painter.activeSurfacePainter!)) {
        assert(() {
          debugActiveSlotDraw = ActiveSlotDraw.standIn;
          return true;
        }());
        // The FIRST-ACTIVATION swap window: while any of the
        // promoted surface's tiles is still undecoded, the walk
        // could show only its budgets' worth and leave the rest
        // silent — the blank (whole on the swap frame, per-tile
        // once the first decodes landed). The held image is the
        // SAME pixels the previous frame drew for this cel at
        // the same rect with the same sampling, so standing in
        // is seamless; the paint-time predicate above hands
        // back to the walk once every tile can speak for itself
        // — and instantly the moment an edit could exist.
        if (_painter.activeSurfacePainter!.showTransparentBackground) {
          // Parity with [BitmapSurfacePainter.paintContentInto]'s
          // own opening block (the merged stack passes false and
          // paints paper itself; standalone hosts rely on this).
          into.drawRect(
            Rect.fromLTWH(
              0,
              0,
              _painter.canvasSize.width.toDouble(),
              _painter.canvasSize.height.toDouble(),
            ),
            Paint()..color = const Color(ProjectBackground.defaultPaperArgb),
          );
        }
        into.drawImageRect(
          standIn.image,
          Rect.fromLTWH(
            0,
            0,
            standIn.image.width.toDouble(),
            standIn.image.height.toDouble(),
          ),
          standIn.worldRect,
          // The display law, exactly like the cached-image route this
          // image was drawn by one frame ago — the handoff into
          // the stand-in must be byte-identical.
          _withLayerPaint(
            Paint()..filterQuality = _displayQuality,
            ridingPaint,
          ),
        );
        // ⛔The stand-in can only hand off if the decodes it is
        // waiting on actually start — the walk's collect pass is
        // skipped this frame, so its decode starts must not be.
        _painter.activeSurfacePainter!.startPendingDecodes(into);
        // 🚨F-33 / F-130: the ghost, over the held image — the same
        // reason as on the flat route above. A hover during the swap
        // window is not an edit, so the window stays open.
        _painter.activeSurfacePainter!.paintStampPreviewInto(into);
      } else {
        assert(() {
          debugActiveSlotDraw = ActiveSlotDraw.tiles;
          return true;
        }());
        _painter.activeSurfacePainter!.paintContentInto(
          into,
          layerPaint: ridingPaint,
        );
      }
      // 🚨TS1: the selection's FLOAT belongs here, right on top of
      // the surface it was lifted out of and UNDER everything
      // above that row. Drawn inside this slot's clip and its
      // effects/opacity buffer, because the pixels are that
      // layer's pixels — 유저 확정 A: 「프리뷰는 원래 그런거」, so a
      // half-opacity row previews a transform at half opacity,
      // which is what the commit will look like.
      //
      // ⚠️Inside the POSE wrap as well (the whole switch is). For
      // an unposed row that changes nothing; for a posed one the
      // float now travels with its layer instead of ignoring the
      // pose, but the drag delta rides through the pose matrix
      // with it — fine for translation, and worth an eye on a
      // scaled or rotated row.
      _painter.floatOverlay?.value?.paintInto(into);
      into.restore();
    }

    if (activePlan.preSteps.isNotEmpty) {
      drawSubtreeAsImage(
        canvas: canvas,
        bounds: effectBufferBounds(
          _bufferBoundsFor(node, _activeSurfaceExtent),
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
            _painter.activeSurfacePainter!.pasteboardRect,
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

  /// A cel or a cached row image; the pose is applied by the wrap around
  /// the walk, so the draw itself is unposed.
  void _paintImageNode(Canvas canvas, _PaintImage node) {
    final _PaintImage(
      :image,
      :worldRect,
      :opacity,
      :blendMode,
      :tint,
      :effects,
    ) = node;
    // Dest = the image's WORLD rect: the canvas rect for plain
    // cels, grown for pasteboard content so off-canvas artwork of
    // non-active layers shows at its position. The pose is already
    // applied by the wrap above, which this node shares with the
    // live surface — hence pose: null here rather than a second
    // save/restore around the same matrix.
    drawPosedLayerImage(
      canvas,
      image: image,
      worldRect: worldRect,
      canvasSize: _painter.canvasSize,
      pose: null,
      opacity: opacity,
      blendMode: blendMode,
      effects: effects,
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
      // behind (rotation/flip, or an active layer the flat projection
      // refuses), and a fallback that samples differently is a second
      // answer to the same question.
      filterQuality: _displayQuality,
      // Onion-skin Colors mode: the ghost CONVERTS fully to the
      // tint — every drawn pixel takes the tint's RGB, only alpha
      // survives (TVPaint's look, R11-①; modulate kept light
      // artwork un-tinted). The paint alpha still fades the whole
      // ghost.
      tint: tint,
    );
  }

  void _paintNodes(
    Canvas canvas,
    List<CompositeNode<_PaintRow>> list,
    double rasterScale,
  ) => _paintNodesWith(canvas, list, rasterScale, _paintNodes);

  void _paintSplit(
    Canvas canvas,
    List<CompositeNode<_PaintRow>> list,
    int depth,
    double rasterScale,
  ) {
    final at = list.indexWhere(_LayerStackPainter._enclosesActiveSurface);
    if (at < 0) {
      _painter.bake!.draw(
        canvas,
        'd$depth:all',
        (into) => _paintNodes(into, list, rasterScale),
      );
      return;
    }
    if (at > 0) {
      _painter.bake!.draw(
        canvas,
        'd$depth:before',
        (into) => _paintNodes(into, list.sublist(0, at), rasterScale),
      );
    }
    _paintNodesWith(canvas, [list[at]], rasterScale, (into, children, scale) {
      _paintSplit(into, children, depth + 1, scale);
    });
    if (at < list.length - 1) {
      _painter.bake!.draw(
        canvas,
        'd$depth:after',
        (into) => _paintNodes(into, list.sublist(at + 1), rasterScale),
      );
    }
  }

  void _paintPaperInto(Canvas into) {
    if (!_painter.paintPaper) {
      return;
    }
    // #15 — under a scaled recording the paper yields one buffer pixel
    // to the reduced resample (see [_paperInsetForRecording]); on every
    // s=1 path the inset is null and the paper is the exact canvas rect.
    final inset = _painter._paperInsetForRecording;
    final rect = inset == null ? _canvasRect : _canvasRect.deflate(inset);
    if (rect.isEmpty) {
      return;
    }
    paintProjectPaper(
      into,
      rect,
      _painter.paperBackground,
      // The display law's edge (F-67-paper-edge). On screen — the walk —
      // this rect is the canvas's edge; inside the s=1 buffer it is whole
      // and the flag cannot matter; under the scaled recording the view is
      // reduced and the law says anti-aliased, as it always was.
      antiAlias: displayEdgeAntiAliased(_painter.viewport),
    );
  }

  void _paintBackdropSplit(Canvas into, double rasterScale) {
    final at = _painter.nodes.indexWhere(
      _LayerStackPainter._enclosesActiveSurface,
    );
    final below = at < 0 ? _painter.nodes : _painter.nodes.sublist(0, at);
    final rasterPays =
        (_painter.paintPaper ? 1 : 0) + _replayOpsOf(below) >=
        _LayerStackPainter._backdropRasterMinReplayOps;
    // 🚨THE BAKE'S RECT, NOT THE BUFFER'S (review 2026-09-15). `drawRaster`
    // keeps one image per slot and does not key it by the rect, which is why
    // the extent it is declared under has to move whenever that rect does.
    // The buffer's rect moves with every live draw past the ink and the
    // bake's extent deliberately does not ([paint]), so the raster is made
    // over the bake's extent on the buffer's own pixel grid and lands back
    // on it inside whichever buffer is being composed. Handed the buffer's
    // rect, a held raster stretched across the grown one.
    final rasterRect = _wholePixelsOutward(_bakeExtent);
    // One body, two mechanisms: the record closure is identical either
    // way, so the fallback cannot drift from the raster — `drawRaster`
    // records the same ops shifted into the rect and blits them back to
    // it, which lands pixel-for-pixel where the replay would have. The one
    // thing the raster leaves out is a replay's spread past that rect: an
    // effect bleeding past its own row into a band only a live draw opened.
    void drawBackdrop(String id, void Function(Canvas c) record) {
      if (rasterPays) {
        _painter.bake!.drawRaster(into, id, rasterRect, record);
      } else {
        _painter.bake!.draw(into, id, record);
      }
    }

    if (at < 0) {
      drawBackdrop('d0:backdrop-all', (c) {
        _paintPaperInto(c);
        _paintNodes(c, _painter.nodes, rasterScale);
      });
      return;
    }
    drawBackdrop('d0:backdrop', (c) {
      _paintPaperInto(c);
      _paintNodes(c, _painter.nodes.sublist(0, at), rasterScale);
    });
    _paintNodesWith(into, [_painter.nodes[at]], rasterScale, (
      c,
      children,
      scale,
    ) {
      _paintSplit(c, children, 1, scale);
    });
    if (at < _painter.nodes.length - 1) {
      _painter.bake!.draw(
        into,
        'd0:after',
        (c) => _paintNodes(c, _painter.nodes.sublist(at + 1), rasterScale),
      );
    }
  }

  void _paintContent(
    Canvas into, {
    required bool intoTheBuffer,
    required double rasterScale,
  }) {
    // ⛔No bake handed down (a host that does not own one, or a tree with
    // no live surface at all) keeps the original walk. The bake is an
    // optimisation, never a second way to be correct.
    if (_painter.bake == null || _painter.activeSurfacePainter == null) {
      _paintPaperInto(into);
      _paintNodes(into, _painter.nodes, rasterScale);
      return;
    }
    if (intoTheBuffer) {
      _paintBackdropSplit(into, rasterScale);
      return;
    }
    _paintPaperInto(into);
    _paintSplit(into, _painter.nodes, 0, rasterScale);
  }

  /// [bounds] grown out to whole canvas pixels: the grid the display buffer
  /// is made on, and the backdrop raster inside it with it — so the raster
  /// lands 1:1 on the buffer's pixels whichever of the two rects is larger.
  static Rect _wholePixelsOutward(Rect bounds) => Rect.fromLTRB(
    bounds.left.floorToDouble(),
    bounds.top.floorToDouble(),
    bounds.right.ceilToDouble(),
    bounds.bottom.ceilToDouble(),
  );

  /// Rasterises [_paintContent] over [bounds] at CANVAS resolution, or null
  /// when the stack should just paint itself onto the screen.
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
  /// compose (`tiled_surface_compose`) and in the provisional tile pictures,
  /// where it is measured at 26-38us for a 256px tile.
  _DisplayBuffer? _composeDisplayBuffer(Rect bounds) {
    if (_painter.debugDisableSingleBuffer || bounds.isEmpty) {
      return null;
    }
    // Whole pixels, and the DESTINATION is the rounded rect too — a src/dst
    // pair that disagree by a fraction of a pixel would resample the buffer
    // a second time and undo the point of having it.
    final rect = _wholePixelsOutward(bounds);
    final width = rect.width.round();
    final height = rect.height.round();
    if (width <= 0 || height <= 0) {
      return null;
    }
    if (width > _LayerStackPainter._maxBufferSide ||
        height > _LayerStackPainter._maxBufferSide) {
      return _pastTheCap(rect);
    }
    // ⓔ 6단계 A/B ([MeasurementMode.kneeAtOne]) — the knee moved from the
    // cap to 1: WITHIN the cap, any view where the artwork has more
    // pixels than the screen composes at screen scale too. A refusal
    // here falls THROUGH to the canvas-resolution buffer below — inside
    // the cap that buffer is legal and strictly better than the walk
    // (the above-cap arm has no such floor, which is why it returns).
    // At `s >= 1` this gate never fires, and that non-firing IS the
    // above-100% byte-invariance check-point: same code, same bytes.
    if (MeasurementMode.kneeAtOne.value &&
        _painter.viewport.zoom.abs() * _painter.devicePixelRatio < 1) {
      final scaled = _composeScaledBuffer(rect);
      if (scaled != null) {
        return scaled;
      }
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
  /// ⛔THE PIXEL SIZE IS THE IMAGE'S, NEVER THE RECT'S. Below the knee the
  /// two differ — the image is `ceil(rect · s)` a side — and that is what
  /// the blit's source rect must say or the picture lands shrunk in the
  /// corner. This used to be two constructors, one reading the rect for the
  /// s=1 path and one reading the image for the knee path, and 2026-09-04
  /// the knee path was routed through the rect one by mistake: one wrong
  /// frame on every miss below the knee. Reading the image answers both,
  /// because at s=1 the rect is floor/ceil-snapped and the raster is
  /// `toImageSync(rect.width.round(), …)` — the same number, by
  /// construction.
  _DisplayBuffer _bufferOf(ui.Image image, Rect rect, {required bool owned}) =>
      _DisplayBuffer(
        image: image,
        rect: rect,
        pixelWidth: image.width.toDouble(),
        pixelHeight: image.height.toDouble(),
        owned: owned,
      );

  /// Past the cap: the screen-space buffer, or null to keep the walk.
  _DisplayBuffer? _pastTheCap(Rect rect) {
    // 🚨THE ONE PLACE THE EDITING CANVAS STOPS COMPOSITING AT CANVAS
    // RESOLUTION. Counted so a test can say whether a view still reaches
    // it: bounding the buffer by CONTENT instead of by the view is what
    // keeps an ordinary page (2340×1654) under the cap no matter how far
    // you zoom out, and the count is how that claim is checked rather
    // than argued.
    debugCappedFallbacks += 1;
    // ⓔ 5단계 — the region past the old cap is the KNEE'S UNDERSIDE. The
    // direct-walk fallback here was T21 territory: each layer resampled
    // separately, the active one at nearest beside its neighbours at
    // bilinear. A SCREEN-SPACE buffer draws every layer as one image
    // under one filter and costs what the screen costs, not what the
    // canvas costs (유저 확정 ①: 무릎 아래는 균일 필터, 겹침 색차 수용).
    // Null keeps the walk — rotation/flip, or an active layer the flat
    // projection refuses (settling, stand-ins, stamp, cold truth). The
    // walk was always correct; the buffer is only ever an optimisation.
    return _composeScaledBuffer(rect);
  }

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
    final recorder = ui.PictureRecorder();
    final into = Canvas(recorder);
    into.translate(-rect.left, -rect.top);
    // ⛔SET AT THE BRANCH THAT DECIDES IT. Two of these three draw a base
    // into this recorder; when that base is the cache's deferred HEAD the
    // new image retains it (`DisplayBufferCache._derivedDepth` says what
    // that costs and why it is bounded), when it is the REAL base it does
    // not, and the base itself says which. The third starts from nothing.
    // Re-deriving the answer next to `store` is how the scrolled carry
    // came to be counted as a fresh compose in the first place.
    final bool derived;
    if (base != null && dirty != null) {
      _blitPatched(into, base.image, rect, dirty);
      derived = base.deferred;
    } else if (scroll != null && canScroll) {
      cache!.lastComposedArea = _blitScrolled(into, scroll, rect, dirty);
      derived = scroll.deferred;
    } else {
      // The canvas-resolution buffer records with a translate only.
      _paintContent(into, intoTheBuffer: true, rasterScale: 1);
      derived = false;
    }
    return _keepMiss(
      recorder,
      rect,
      cache,
      key,
      patched: base != null && dirty != null,
      derived: derived,
      carried: canScroll,
      tokens: miss.tokens,
    );
  }

  /// Rasters the recorded miss and, when the cache can keep it, stores the
  /// head and offers its snapshot as the next real base.
  ///
  /// 🎯THE SNAPSHOT THAT ENDS THE CHAIN: the same picture, rasterized once
  /// more as a plain image, becomes the base the NEXT paint derives from —
  /// so the deferred image made here is only ever drawn, never drawn from.
  /// Asked of the cache, which knows whether one is still in flight.
  _DisplayBuffer _keepMiss(
    ui.PictureRecorder recorder,
    Rect rect,
    DisplayBufferCache? cache,
    Object? key, {
    required bool patched,
    required bool derived,
    required bool carried,
    required LiveSurfaceTokens? tokens,
  }) {
    final made = rasterPictureAndSnapshot(
      recorder,
      rect.width.round(),
      rect.height.round(),
      snapshot: cache != null && key != null && cache.wantsPromotion,
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
  void _recomposeOverCarried(Canvas into, List<Rect> region) {
    final clip = Path();
    for (final part in region) {
      clip.addRect(part);
    }
    into.save();
    into.clipPath(clip, doAntiAlias: false);
    into.drawPaint(Paint()..blendMode = BlendMode.clear);
    // The canvas-resolution buffer records with a translate only.
    _paintContent(into, intoTheBuffer: true, rasterScale: 1);
    into.restore();
  }

  /// Recomposes only [dirty] over the carried [base]: the old pixels are
  /// blitted 1:1, the dirty rect cleared and repainted.
  void _blitPatched(Canvas into, ui.Image base, Rect rect, Rect dirty) {
    into.drawImageRect(
      base,
      Rect.fromLTWH(0, 0, rect.width, rect.height),
      rect,
      Paint()
        ..filterQuality = ui.FilterQuality.none
        ..isAntiAlias = false,
    );
    _recomposeOverCarried(into, [dirty]);
  }

  /// Carries the overlap of the previous buffer ([scroll]) into [rect]
  /// and repaints only the bands the pan exposed, plus [dirty]; answers
  /// the area repainted.
  double _blitScrolled(Canvas into, _Base scroll, Rect rect, Rect? dirty) {
    final was = scroll.rect;
    final overlap = was.intersect(rect);
    into.drawImageRect(
      scroll.image,
      // The overlap in the OLD image's own pixels: 1:1, so this is just
      // the offset between the two rects.
      Rect.fromLTWH(
        overlap.left - was.left,
        overlap.top - was.top,
        overlap.width,
        overlap.height,
      ),
      overlap,
      Paint()
        ..filterQuality = ui.FilterQuality.none
        ..isAntiAlias = false,
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
        dirty.intersect(overlap),
    ];
    var area = 0.0;
    for (final band in bands) {
      area += band.width * band.height;
    }
    _recomposeOverCarried(into, bands);
    return area;
  }

  /// ⓔ 5단계 — the buffer BELOW the knee: [rect] rendered at
  /// `s = min(1, zoom·dpr)` instead of canvas resolution, every layer one
  /// image under one uniform filter.
  ///
  /// What makes this legal where every scale-in-the-recorder design died:
  /// the s=1 path above the knee is UNTOUCHED (same code, same bytes),
  /// and below the knee the user closed the color question (결정 ① —
  /// uniform filtering, overlap tint accepted). The active layer enters
  /// as [ActiveLayerFlatProjection]'s single image; when the projection
  /// refuses (settling, stand-ins, stamp, missing truth) this returns
  /// null and the caller keeps the direct walk — correctness never
  /// depends on this path.
  ///
  /// 구멍 대응: ① lives in `paint` (empty visible = nothing painted);
  /// ② `s` folds zoom AND dpr into the cache key, so a monitor/DPR move
  /// re-rasters instead of stretching the old image; ③ there is NO patch
  /// down here — a change re-rasters the whole SCREEN-RES buffer, which
  /// is the cheap direction (결정 ⑤: 무릎 아래 획 정밀도 불요), so the
  /// fractional-grid AA family never gets a foothold; ④ the recording
  /// takes the PICTURE route (`intoTheBuffer: false`), never the backdrop
  /// raster — a 1:1 `none` blit under scale would nearest-downsample the
  /// whole backdrop.
  ///
  /// ⏸5b: per-dab strokes below the knee currently rebuild flat+buffer
  /// per batch (correct, unpatched). The flat's patch mechanism exists
  /// ([ActiveLayerFlatProjection.patchOrNull]) and lands with the dirty
  /// channel wiring.
  /// The scale the knee path renders [rect] at — min(1, zoom · dpr),
  /// shrunk further when even that overflows the buffer cap — or null
  /// when the view is rotated or flipped (the walk draws those).
  double? _kneeScale(Rect rect) {
    if (_painter.viewport.rotationDegrees != 0 ||
        _painter.viewport.flipHorizontal ||
        _painter.viewport.flipVertical) {
      return null;
    }
    var s = _painter.viewport.zoom.abs() * _painter.devicePixelRatio;
    if (s >= 1) {
      s = 1;
    }
    // A screen so large even zoom·dpr overflows the cap: shrink further.
    // Still one uniform resample — softer, never seamed.
    return scaleFittingSide(
      scale: s,
      bounds: rect.size,
      maxSide: _LayerStackPainter._maxBufferSide.toDouble(),
    );
  }

  /// [rect] recorded at scale [s] into a [size] image — the PICTURE route
  /// through the very same walk the s=1 buffer records, with [flat] as
  /// the active layer's one image.
  ui.Image _recordScaled(
    Rect rect,
    double s,
    ActiveLayerFlatImage? flat,
    ({int width, int height}) size,
  ) {
    final recorder = ui.PictureRecorder();
    final into = Canvas(recorder);
    into.scale(s);
    into.translate(-rect.left, -rect.top);
    _painter._activeFlatForRecording = flat;
    // #15 — one buffer pixel, expressed in the canvas units the paper
    // draws in.
    _painter._paperInsetForRecording = 1 / s;
    try {
      // The PICTURE route through the very same walk the s=1 buffer
      // records — one body, so folders, adjustments, effects and the
      // float cannot drift between the two resolutions.
      _paintContent(into, intoTheBuffer: false, rasterScale: s);
    } finally {
      _painter._activeFlatForRecording = null;
      _painter._paperInsetForRecording = null;
    }
    return rasterPicture(recorder, size.width, size.height);
  }

  _DisplayBuffer? _composeScaledBuffer(Rect rect) {
    final s = _kneeScale(rect);
    if (s == null) {
      return null;
    }
    final width = (rect.width * s).ceil();
    final height = (rect.height * s).ceil();
    if (width <= 0 || height <= 0) {
      return null;
    }
    final cache = _painter.bufferCache;
    final baseKey = cache == null ? null : _painter._bufferKey();
    // ② `s` is in the key: zoom already rides [compositeKey], but dpr does
    // not exist anywhere else — fold the resolved scale itself.
    final key = baseKey == null ? null : Object.hash(baseKey, s);
    final kept = _keptBuffer(cache, key, rect);
    if (kept != null) {
      return kept;
    }
    ActiveLayerFlatImage? flat;
    if (_painter.activeSurfacePainter != null) {
      flat = ActiveLayerFlatProjection.buildOrNull(
        surface: _painter.activeSurfacePainter!.surface,
        tileImages: BitmapTileImageCache.instance,
        overlay: _painter.activeSurfacePainter!.overlayModel,
      );
      if (flat == null) {
        return null;
      }
    }
    // The probe writes HERE — after the refusal gate, before any raster —
    // so it means "the knee path actually drew", including the uncached
    // composes a null buffer key forces (settling would be one, if the
    // projection ever let one through). A refusal must leave it untouched
    // or the probe claims a run that fell back to the walk.
    _painter.bufferCache?.lastBufferScale = s;
    final image = _recordScaled(rect, s, flat, (width: width, height: height));
    if (flat != null) {
      // The recording holds its reference through the deferred raster;
      // direct dispose is the one-frame black-flash race.
      DeferredImageDisposer.instance.retire(flat.image);
    }
    if (cache != null && key != null) {
      cache.store(
        key,
        _painter.compositeKey,
        rect,
        image,
        patched: false,
        tokens: _painter._liveSurfaceTokens(),
      );
      return _bufferOf(image, rect, owned: false);
    }
    return _bufferOf(image, rect, owned: true);
  }
}
