part of '../canvas_layer_stack_view.dart';

/// A surface row's own paint: what its layer composites with.
typedef _SurfaceRowPaint = ({
  double opacity,
  LayerBlendMode blendMode,
  LayerPlacement? placement,
  List<ResolvedLayerEffect> effects,
  int? tint,
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

/// ONE PAINT OF THE LAYER STACK — the walk that draws the composite tree
/// under the viewport, the paper, and the one buffer at canvas resolution
/// that is resampled once.
///
/// ↩️It also painted the chain enclosing the active layer live and replayed
/// a recording for the rest (`StaticCompositeBake`), and kept the buffer
/// from paint to paint (`DisplayBufferCache`) — patched where a stroke
/// moved, carried by a pan — until a frame became one picture its strokes
/// are patched into (one-picture-per-frame ②-5a, 2026-10-25).
///
/// 🚨A collaborator carved out of `_LayerStackPainter` (the audit's
/// cognitive cut, Round 6, 2026-09-03): `paint` was 784 lines with six
/// local functions nested inside it, scoring 105 on the cognitive meter.
/// It reaches the painter through `_painter`.
class _LayerStackPaintPass {
  _LayerStackPaintPass(this._painter);

  final _LayerStackPainter _painter;

  /// Device pixels per artwork pixel ([displayScaleOf]) — the one quantity
  /// the display law, its edge, the sampling phase and a self-rasterising
  /// group's raster scale all read.
  double get _displayScale =>
      displayScaleOf(_painter.viewport.zoom, _painter.devicePixelRatio);

  /// The display law's edge ([displayEdgeAntiAliased]) for this paint's
  /// view: the paper rect cuts the canvas's edge by the same rule, inside
  /// the buffer and on the walk alike — the buffer is at the canvas's own
  /// resolution, and its blit is cut by it ([drawOnTheDisplay]).
  ///
  /// ↩️Below 100% the buffer was composed at the display's level and its
  /// paper cut by the residual the level was reduced by, until nothing drew
  /// at a level (one-picture-per-frame ②-5a · ②-5b-1).
  bool get _displayEdgeAntiAliased =>
      displayEdgeAntiAliased(_painter.viewport, _painter.devicePixelRatio);

  // One paint's geometry: set by [paint] before the walk below reads it.
  // The page rect, the on-screen part of the pasteboard and the content the
  // display buffer must cover, each read once.
  late final Rect _canvasRect;
  late final Rect _visibleCanvasRect;
  late final Rect _contentExtent;

  void paint(Canvas canvas, Size size) {
    // What this paint can show: the view, or what of it the canvas is
    // clipped to — read before the viewport transform, in the view's own
    // coordinates ([_reachOf]).
    final shown = _reachOf(canvas, Offset.zero & size);
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
      shown,
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
    //
    // 🚨Grown by what the display reads past the view
    // ([rectTheDisplayReads]): a pixel at the view's edge reads that far
    // past it, and a buffer cut at the edge reads its own edge texel again
    // there, where the frame's picture holds what lies past. 🔬A stroke's
    // step beside the view's edge at 20% and 10% under opaque line art of
    // no period, 2/255 to 3/255 down that edge (Impeller tester,
    // 2026-10-26, F-465 again). ↩️It was not grown: the ⛔ that stood here
    // measured a step at 25% on a 1.5 screen within 1/255 grown or not,
    // over translucent line art of period 8, which the levels average flat.
    _visibleCanvasRect = pasteboardRect.intersect(
      rectTheDisplayReads(visibleRect, _displayScale),
    );
    if (_visibleCanvasRect.isEmpty) {
      canvas.restore();
      return;
    }

    // What a group's buffer is sized by and, unioned, what the one display
    // buffer covers — the law is [_compositeExtent]'s.
    _contentExtent = _compositeExtent();
    if (_contentExtent.isEmpty) {
      canvas.restore();
      return;
    }

    // The geometry field probe — the numbers every buffer decision depends
    // on and nobody has ever measured on a device: the logical view, the
    // device pixel ratio, the zoom actually worked at, and what the buffer
    // costs there. ↩️The 1928×1200 that circulated was a comment in the
    // bake, not a measurement.
    //
    // Same shape as the T12 probe above: release-visible (reports come from
    // release builds), gated on the inspector, deduped through a static.
    // ⛔The zoom is a continuous double — raw in the dedupe key it would
    // emit on every drag frame, so it is bucketed to 10% steps.
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
    }

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
      case (:final image, :final rect):
        _blitBuffer(canvas, image, rect);
    }
    canvas.restore();
  }

  /// What of [rect] a paint into [canvas] can show — all of it, or what of
  /// it the canvas is clipped to — in [canvas]'s own coordinates.
  ///
  /// 🚨★★★HOLE ① AGAIN: NOT INSIDE THE CLIP MEANS NOT PAINTED. A patch on
  /// its way into a frame's picture is drawn as it stands under its own
  /// rects, on the screen and into the picture ([StackedFrame]) — and the
  /// walk under the clip composed everything in view: a stroke's step at
  /// 4K rastered the whole view's buffer, and the store's patch recorded
  /// every row of the whole pasteboard (one-picture-per-frame ②-5a,
  /// 2026-10-25). Cut to the clip, the same pixels inside it: what reads
  /// past where it lands reads past it as it reads past the view's edge —
  /// a group's buffer grows by its own spread ([effectBufferBounds]).
  static Rect _reachOf(Canvas canvas, Rect rect) =>
      rect.intersect(canvas.getLocalClipBounds());

  /// Where the frame lies in the world with no screen around it
  /// ([StackedFrame]): the rect the display buffer covers, the whole
  /// pasteboard on screen — the page and every row's content.
  Rect frameExtent() {
    _standInTheWorld();
    return wholeLevelPixelsOutward(_contentExtent, 0);
  }

  /// The frame over [frameExtent], in world coordinates, as the display
  /// buffer is composed at 100% ([_composeDisplayBuffer]) — the same body
  /// with no screen around it, and only where [into] is not clipped away
  /// ([_reachOf]).
  ///
  /// Drawn to keep its nodes' pictures, it is all that is held after
  /// ([HeldSubtreeRasters.holdOnly]).
  void paintFrame(Canvas into) {
    switch (_painter.held) {
      case (:final rasters, keeps: true, below: _):
        rasters.holdOnly(() => _paintFrame(into));
      case _:
        _paintFrame(into);
    }
  }

  void _paintFrame(Canvas into) {
    final reach = _reachOf(into, Rect.largest);
    // ⛔Not stood wider by what the chains read: each folder reads its
    // rows past this by its own spread, and its rows' buffers follow it
    // ([_slotBufferBounds]). ↩️Stood that much wider (`a97a2196c`), a
    // folder inside a blurred one rastered past the patch by the spread
    // twice (card a-step-drawn-in-place-reads-short-of-the-one-picture).
    _standInTheWorld(within: reach);
    final extent = wholeLevelPixelsOutward(_contentExtent, 0);
    if (extent.isEmpty) {
      return;
    }
    final held = _painter.held;
    if (held?.below == BelowThePen.inCells) {
      _LayerStackPaintPass(_painter)._paintCells(held!.rasters, under: reach);
    }
    _held = switch (held) {
      (:final rasters, :final keeps, :final below) => (
        rasters: rasters,
        keyOf: _drawsOf,
        drawnOn: _drawnOn,
        keeps: keeps,
        below: below,
        cells: null,
      ),
      null => null,
    };
    _paintCutWhereItEnds(into, extent, shownWithin: extent);
  }

  /// Draws the cells under [under] of what lies below the pen that are
  /// not held, and keeps them ([BelowThePen.cellsOnly]) — and nothing
  /// else: the frame stood in the world as far past them as its chains
  /// read ([readsPastOf]), so each is the pixels the frame's one picture of
  /// it holds there, wherever a step cut it.
  void _paintCells(HeldSubtreeRasters rasters, {required Rect under}) {
    final readsPast = readsPastOf(
      _rootNodes,
      paper: _painter.canvasSize.canvasRect,
    );
    _standInTheWorld(within: belowCellsCovering(under).inflate(readsPast));
    final extent = wholeLevelPixelsOutward(_contentExtent, 0);
    if (extent.isEmpty) {
      return;
    }
    _held = (
      rasters: rasters,
      keyOf: _drawsOf,
      drawnOn: _drawnOn,
      keeps: false,
      below: BelowThePen.cellsOnly,
      cells: (over: under, readsPast: readsPast),
    );
    final recorder = ui.PictureRecorder();
    _paintCutWhereItEnds(Canvas(recorder), extent, shownWithin: extent);
    recorder.endRecording().dispose();
  }

  /// The frame composed into [into] and cut where it ends — at [edge], the
  /// page and every row's content: an effect's spread past every row is cut
  /// there, in the frame's picture ([paintFrame]) and in the display buffer
  /// that draws it as it stands ([_composeDisplayBuffer]), whatever either
  /// image holds past it. 🚨ONE CUT FOR BOTH: the buffer that came to end
  /// on the picture's grid past the page ([frameGridOutward]) and kept no
  /// cut of its own laid a blurred row's spread there, which the picture
  /// does not hold (🔬a blur beside ink on the pasteboard, 9 pixels up to
  /// 50/255 at 100%, from F-465's grid on — 2026-10-26, bisected).
  void _paintCutWhereItEnds(
    Canvas into,
    Rect edge, {
    required Rect shownWithin,
  }) {
    _shownWithin = shownWithin;
    into
      ..save()
      ..clipRect(edge);
    _paintContent(into, intoTheBuffer: true, rasterScale: 1);
    into.restore();
    _shownWithin = null;
  }

  /// [paint]'s geometry with the whole pasteboard in view and no viewport:
  /// the world a frame's picture holds — what of it lies [within] what is
  /// drawn ([_reachOf]).
  void _standInTheWorld({Rect within = Rect.largest}) {
    _canvasRect = _painter.canvasSize.canvasRect;
    _visibleCanvasRect = _painter.canvasSize
        .pasteboardAt(_painter.pasteboardReach)
        .rect
        .intersect(within);
    _contentExtent = _compositeExtent();
  }

  /// The display buffer — [image], over [rect] in canvas space, whole-pixel
  /// aligned so the src/dst pair of the final draw is exact: the ONE
  /// resample the display is entitled to happens in the viewport transform
  /// and nowhere else.
  ///
  /// ⛔THE PIXEL SIZE IS THE IMAGE'S, NEVER THE RECT'S. Below 100% the two
  /// differ — the image is the rect over 2^level a side — and that is what
  /// the blit's source rect must say or the picture lands shrunk in the
  /// corner. This used to be two constructors, one reading the rect for the
  /// canvas-resolution path and one reading the image for the knee's scaled
  /// path, and 2026-09-04 the knee path was routed through the rect one by
  /// mistake: one wrong frame on every miss below the knee. Reading the
  /// image answers both, because at level 0 the rect is snapped and the
  /// raster is `toImageSync(rect.width.round(), …)` — the same number, by
  /// construction.
  void _blitBuffer(Canvas canvas, ui.Image image, Rect rect) {
    final source = Offset.zero &
        Size(image.width.toDouble(), image.height.toDouble());
    try {
      drawOnTheDisplay(
        canvas,
        image,
        source,
        rect,
        viewport: _painter.viewport,
        devicePixelRatio: _painter.devicePixelRatio,
      );
    } finally {
      // ⚠️Safe HERE and nowhere earlier: the draw above put the image into
      // this frame's display list, and the engine holds its own reference
      // to it from that moment. What `dispose` releases is this handle's
      // claim, not the pixels the list is going to replay.
      image.dispose();
    }
  }

  /// 🚨★★★WHAT THE ACTIVE SLOT DRAWS, not what its surface holds (F-85,
  /// 2026-09-15): the painter's own answer, and the float drawn into the
  /// same slot. Read off the committed surface alone, a stroke in flight, a
  /// fill's stamp, the stamp ghost and a transform's float were all cut at
  /// the edge of the ink that had already landed — and came back the moment
  /// a commit put tiles there. What the DISPLAY BUFFER covers.
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

  /// Each surface row's slot beside the live one — a row a lift holds (I-37
  /// · F-329), a frame's cel ([_PaintCelSurface]) — by its painter: read
  /// once per paint, as the live row's slot is.
  final Map<BitmapSurfacePainter, _SurfaceSlot> _rowSlots = Map.identity();

  /// What [row] draws, by the one body every surface row is drawn with
  /// ([_paintSurfaceRow]): the live row's slot, or one of [_rowSlots].
  _SurfaceSlot _slotOf(_SurfaceRow row) => switch (row) {
    _PaintActiveSurface() => _activeSlot!,
    _PaintLiftedSurface(:final lifted) => _rowSlots.putIfAbsent(
      lifted.surface,
      () => _SurfaceSlot(
        painter: lifted.surface,
        float: lifted.float,
        keys: row.keys,
        placement: row.placement,
      ),
    ),
    _PaintCelSurface(:final painter) => _rowSlots.putIfAbsent(
      painter,
      () => _SurfaceSlot(
        painter: painter,
        float: null,
        keys: row.keys,
        placement: row.placement,
      ),
    ),
  };

  /// What the live slot's own raster covers, in the SLOT's space: the rect
  /// the same layer drawn as an image covers, where [within] — what the
  /// buffer holding the row reads — can see it.
  ///
  /// 🚨[within], NOT THE VIEW: a folder that blurs reads its rows past what
  /// is shown by its spread, so a row's raster that stopped at the view
  /// stopped short of it — a row blurred on its own in a blurred folder
  /// beside a step's edge came out 12 to 47/255 off the frame laid whole.
  /// ↩️`a97a2196c` stood the whole walk that much wider instead, and a
  /// folder inside the blurred one then rastered past it by the spread
  /// twice (card a-step-drawn-in-place-reads-short-of-the-one-picture,
  /// 2026-10-29).
  ///
  /// 🚨★★★THE IMAGE ROW'S RECT, BY THE IMAGE ROW'S QUESTION (F-243). A
  /// row drawn as an image — the camera's, so the export's (↩️the playback
  /// cache's too, until ②-5b-1) — lays down its ink alone only where that is
  /// exact
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
  /// the slot and cut its drawing away (found in F-243's review, when every
  /// posed row in an advanced blend took this route — ↩️until such a row
  /// painted normal over its backdrop; a colour key below a painted effect
  /// and add's `plus` on a buffered row still take it).
  Rect _slotBufferBounds(
    _SurfaceSlot slot,
    _SurfaceRowPaint paint,
    Rect within,
  ) {
    final intoSlot = slot.canvasToSlot;
    final view = intoSlot == null
        ? within
        : MatrixUtils.transformRect(intoSlot, within);
    final drawn = slot.extent;
    final covered =
        inkCropDrawsTheSame(
          placement: paint.placement,
          effects: paint.effects,
          paper: _canvasRect,
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
        CompositeClip(:final children) => _activeRowIn(children),
        // The row drawn on, read by another's chain, is the same row
        // there — its keys, where it lies — and the one place it stands
        // where its eye is off (🗣️I-132-Q23 a).
        CompositeReadsRows(:final children) => _activeRowIn(children),
        // The base it paints again stands in the clip already, and the row
        // a cel number is written on as its own leaf.
        CompositeOpaque() || CompositeCelNumber() => null,
      };
      if (found != null) {
        return found;
      }
    }
    return null;
  }

  /// What the composite covers: the page and every row's buffer bounds,
  /// clamped to the view — and nothing for a stack of nothing. CONTENT,
  /// clamped to the storable universe; the pasteboard clamp is the backstop
  /// a pose needs, since a transform can push a layer anywhere and an
  /// unbounded rect is an unbounded offscreen.
  Rect _compositeExtent() {
    // 🚨A STACK OF NOTHING COMPOSES NOTHING — no row and no paper, no
    // buffer. The canvas's ghosts' view stays mounted standing with no
    // ghost, and through the seed below it rastered a page of nothing at
    // every paint and laid it over the frame: a scrub step on a 3840² page
    // took 150ms at 100% and 130–300ms at fit to reach the screen, 89 and
    // 72ms without it (D7-2, Surface Pro 11, 2026-10-25).
    if (_rootNodes.isEmpty) {
      return Rect.zero;
    }
    // 🚨SEEDED WITH THE PAGE, not with the nodes alone.
    //
    // The composite always covers the document: the paper is drawn over the
    // canvas rect whether or not any row has ink there, and a row's own
    // extent is measured against the SURFACE's canvas — which is not
    // necessarily this view's. Starting from the nodes alone shrank the
    // buffer below the page, and the paper went with it.
    //
    // ⚠️And a root row's SPREAD lies past its content: the blur of a folder
    // whose ink stops at the view's edge reaches into the view, which a
    // composite measured over the rows alone — the paper among them — cut
    // at the ink (2026-10-25,
    // `a_folder_in_a_blurred_folder_reads_past_the_view_test`).
    var extent = _canvasRect;
    for (final node in _painter.nodes) {
      final rect = _bufferBoundsFor(node, _visibleCanvasRect);
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

  /// The CANVAS-SPACE rect a buffer for [node] covers — what of it lies
  /// [within] what reads it: the view at the top, and under a folder that
  /// folder's buffer, which a blur on it reads past the view
  /// ([subtreeBufferBounds], the one law the camera's render keeps too).
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
  /// resolution serves every zoom. For the ACTIVE row it is everything the
  /// slot draws ([_activeSurfaceExtent]) — its committed surface alone cut
  /// every live draw at the edge of the ink already landed (F-85).
  Rect _bufferBoundsFor(
    CompositeNode<_PaintRow> node,
    Rect within,
  ) => subtreeBufferBounds(
    node,
    // ↩️The view at every depth until 2026-10-23: a blurred folder holding a
    // buffered one missed the inner folder's ink past the screen's edge, so
    // the blur there changed as the view moved (card
    // nested-folder-buffers-read-past-the-view).
    within: within,
    extentOf: _extentOf,
    placementOf: _placementOf,
  );

  /// The rect [row] stands for.
  Rect _extentOf(_PaintRow row) => switch (row) {
    _PaintActiveSurface() => _activeSurfaceExtent(),
    // What a row beside the live one draws — its surface, and a lift's
    // float — as the live row's extent is measured
    // ([_activeSurfaceExtent]).
    final _SurfaceRow surface => _slotOf(surface).extent,
    _PaintPaper() => _canvasRect,
  };

  /// Where [row] lies.
  LayerPlacement? _placementOf(_PaintRow row) => switch (row) {
    final _SurfaceRow surface => surface.placement,
    _PaintPaper() => null,
  };

  /// [list] painted by the one walk of a composite tree
  /// ([paintCompositeTree]), this stack's rows drawn by [_paintRow].
  void _paintNodes(
    Canvas canvas,
    List<CompositeNode<_PaintRow>> list,
    double rasterScale,
    Rect within,
  ) => paintCompositeTree(
    canvas,
    list,
    rasterScale: rasterScale,
    within: within,
    route: (
      paintRow: _paintRow,
      extentOf: _extentOf,
      placementOf: _placementOf,
      shownWithin: _shownWithin,
      held: _held,
      paper: _canvasRect,
    ),
  );

  /// [row] where it lies. Poses apply at composite time — the stack shows
  /// the same picture playback composes (route parity). The wrap straddles
  /// the live-surface node too, which HAS a placement and no image — that
  /// is why the wrap and the draw are separate helpers rather than one.
  void _paintRow(
    Canvas canvas,
    _PaintRow row,
    double rasterScale,
    RowPainter? rows,
    Rect within,
  ) => withLayerPlacement(
    canvas,
    placement: _placementOf(row),
    body: () {
      switch (row) {
        case _PaintPaper():
          _paintPaperInto(canvas);
        case final _SurfaceRow row:
          _paintSurfaceRow(
            canvas,
            _slotOf(row),
            row.paint,
            rasterScale,
            rows: rowsUnderPlacement(rows, row.placement),
            within: within,
          );
      }
    },
  );

  /// A surface layer — the live one, or one a lift holds beside it (I-37 ·
  /// F-329): drawn straight onto the canvas when its paint can ride the
  /// draws, through one buffer when it cannot (an outset effect,
  /// overlapping coverage, a float overlay, or pre-steps) — [rows] what
  /// paints the rows its chain reads in the slot, null for none, and
  /// [within] what of the canvas the buffer holding it reads.
  void _paintSurfaceRow(
    Canvas canvas,
    _SurfaceSlot slot,
    _SurfaceRowPaint paint,
    double rasterScale, {
    RowPainter? rows,
    required Rect within,
  }) {
    final (:opacity, :blendMode, :effects, :tint, placement: _) = paint;
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
    // Onion-skin Colors mode: the ghost CONVERTS fully to the tint — every
    // drawn pixel takes the tint's RGB, only alpha survives (TVPaint's look,
    // R11-①; modulate kept light artwork un-tinted). The paint alpha still
    // fades the whole ghost. Folded into the same matrix as the row's colour
    // effects (I-8-Q5: the ghost shows what the screen shows), as
    // [drawPosedLayerImage] folds it for a row's image.
    final activePlan = resolveCompositeEffectPlan(
      effects,
      tint: tint,
      paper: _canvasRect,
    );
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
    // drawn: a row's is `srcOver` or `plus`, an advanced blend
    // being composed over its backdrop, the row painting normal.
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
        //
        // ↩️🚨★★★F-243 (유저 2026-09-30): an advanced blend never rode
        // the tiles — per draw it was not per pixel, each tile blending
        // the whole screen by its edge colour on the Windows app
        // (`blendsInPlace` has the measurement) — so it was buffered and
        // blended once as one image, until every advanced blend went
        // over its backdrop in the shader
        // (a-blurred-folder-cut-by-the-view-moves-on-vulkan, 「골은 b」):
        // such a row paints normal now, the source of its blend.
        activePlan.preSteps.isNotEmpty;
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
    // ⛔Only that case, an advanced blend and a chain that spreads
    // (below) rasterise. A plainly buffered layer keeps the cheaper
    // `saveLayer`: 🧪measured, the image route costs 3.2x on the path a
    // stroke redraws every step.
    void paintLiveBody(Canvas into) {
      into.save();
      into.clipRect(slot.painter.storableRect);
        slot.painter.paintContentInto(
          into,
          layerPaint: ridingPaint,
          // Into the buffer — at the canvas's own resolution — the committed
          // tiles are drawn 1:1, at `none` on purpose: a tile is filtered
          // with no neighbours to sample, so `low` there buys a seam at
          // every tile boundary. The safety-net walk (rasterScale = the
          // device scale) draws them reduced by the display's filter, from
          // their pictures' chains. ↩️It drew level tiles — exact box means,
          // 1:1 in the level's pixels (4c) — until one-picture-per-frame
          // ②-5b-2.
          scale: rasterScale,
          pixelRatio: _pixelRatioOf(into),
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
    // ↩️Since F-243 an advanced blend on the row itself was buffered too,
    // so a multiply or screen row paid it on every paint — until such a
    // row painted normal over its backdrop
    // (a-blurred-folder-cut-by-the-view-moves-on-vulkan). The one blend
    // a buffered row still wears here is add's `plus`.
    final blendsAsImage =
        needsBuffer && activePaint.blendMode != BlendMode.srcOver;
    // 🚨★★★A CHAIN OF THE ROW'S OWN THAT SPREADS READS A RASTER ON THE
    // CANVAS'S GRID, as a folder's does ([rasterCellFor];
    // nested-folder-buffers-read-past-the-view-Q1 = c, 유저 2026-10-27
    // 「정확하게, 값은 줄여서」). A blur reduces what it reads on a grid
    // counted from that picture's corner, and the `saveLayer` it rode
    // starts where the clip cuts it: the same ink blurred another way at
    // each pixel of a pan, and another way than the frame's picture
    // (🔬Windows app: 3–4/255 pan to pan, 4–6/255 from the picture). On
    // the grid the row's step is told as a folder's is
    // (`_whereAChangeShows`), so a stroke patches the frame's picture
    // as far as its spread reaches and a pan draws the picture — where the
    // row drawn on had the whole view drawn as it stands at every paint.
    final spreads = activePlan.outsetPixels > 0;
    if (activePlan.preSteps.isNotEmpty || blendsAsImage || spreads) {
      drawSubtreeAsImage(
        canvas: canvas,
        bounds: effectBufferBounds(
          _slotBufferBounds(slot, paint, within),
          activePlan.outsetPixels,
        ),
        rasterScale: rasterScale,
        paintSubtree: (into, _) => paintLiveBody(into),
        compose: (blit) => blit(activePaint),
        steps: activePlan.preSteps,
        // The canvas, in the slot as it is in the canvas: the slot is the
        // row before its pose.
        paper: _canvasRect,
        cell: rasterCellFor(activePlan.outsetPixels),
        rows: rows,
      );
    } else {
      if (needsBuffer) {
        canvas.saveLayer(slot.painter.storableRect, activePaint);
      }
      paintLiveBody(canvas);
      if (needsBuffer) {
        canvas.restore();
      }
    }
  }

  /// The paper, into the buffer or straight onto the screen (the walk).
  void _paintPaperInto(Canvas into) {
    if (!_painter.paintPaper) {
      return;
    }
    final rect = _canvasRect;
    if (rect.isEmpty) {
      return;
    }
    paintProjectPaper(
      into,
      rect,
      _painter.paperBackground,
      // The display law's edge (F-67-paper-edge): on the buffer's own
      // pixels inside it, on the screen's on the walk.
      antiAlias: _displayEdgeAntiAliased,
      pixelRatio: _pixelRatioOf(into),
    );
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

  /// The screen the walk draws the content straight onto — null while the
  /// content is composed into the buffer or a frame's picture
  /// ([_paintContent]).
  Canvas? _screen;

  /// Device pixels a unit of [into]'s space lands on past its transform —
  /// the grid every edge the display law cuts is cut on
  /// ([cutOnThePixelGrid]): the screen's ratio on the screen, and 1 in every
  /// raster, whose transform lands on its own pixels — the buffer, a frame's
  /// picture, and a picture the walk draws a node in.
  ///
  /// ↩️It was the screen's ratio wherever the buffer was not being composed,
  /// in a picture the walk drew a folder in too, until
  /// the-walk-family-cuts-the-rest-on-the-grid: there a row's edges were
  /// cut on half its pixels at a ratio of 2 — 🔬at 137%, the ink of a row
  /// in a folder 5 pixels past the page, apart from the buffer.
  double _pixelRatioOf(Canvas into) =>
      identical(into, _screen) ? _painter.devicePixelRatio : 1;

  /// Where the recording being made is shown — whole, once, cut by nothing
  /// else: the display buffer's rect on the visible canvas while it is
  /// composed, and a frame's extent while its picture is drawn; null
  /// otherwise. A blend is read in the frame only inside it
  /// ([drawBlendOverBackdrop]): the engine cuts the layer a blend reads to
  /// the clip it is DRAWN under, and the source would then be sampled off
  /// the backdrop — under Impeller (`--enable-impeller`), a recording the
  /// bake replayed into a stroke's patch laid a multiply row's ink over
  /// paper it does not cover, 261 pixels a step (↩️the bake went with
  /// one-picture-per-frame ②-5a).
  Rect? _shownWithin;

  /// Where the nodes of the frame's picture find their pictures drawn
  /// before ([HeldNodePictures]) — while [paintFrame] draws it, and only
  /// then: what the screen draws as it stands has rows not in hand.
  SubtreeHolding<_PaintRow>? _held;

  /// What [node] draws, as a frame's picture is signed by it
  /// ([CutFrameCompositeSignature]) — null where a row of it is drawn live
  /// or stands for no cel: that node is drawn afresh each time. ⚠️A row
  /// with no signature would drop out of the signing ([mapCompositeLeaves])
  /// and leave a key that misses it — the first stroke on an empty cel, in
  /// a folder held with nothing of it.
  ///
  /// The paper draws what it is laid with, where, on which edge
  /// ([_paintPaperInto]) — at the buffer's own ratio, as a frame's picture
  /// is drawn: what lies below a pen holds it ([SubtreeHolding.drawnOn]).
  ///
  /// 🚨A NODE THE PAPER LIES IN draws its rows and the paper: a blend at
  /// the bottom of the frame reads the paper in its backdrop
  /// ([onUnderlay]), the one place it can lie, so the rows signed and the
  /// paper say all it draws. ↩️It stood for no cel there, and what lies
  /// below a pen over such a row had no key: 🔬S5_BA cut 352 (67 rows, a
  /// multiply row under the one drawn on) drew three pictures again each
  /// step — p50 28.7ms from step to screen against 6.6 with only the drawn
  /// row on (10-28, the whole app, Windows, profile).
  Object? _drawsOf(CompositeNode<_PaintRow> node) {
    if (holdsRow(
      node,
      (row) => row is! _PaintPaper && _signatureOf(row) == null,
    )) {
      return null;
    }
    final paper = holdsRow(node, (row) => row is _PaintPaper)
        ? (
            paper: _painter.paperBackground,
            on: _canvasRect,
            antiAlias: _displayEdgeAntiAliased,
          )
        : null;
    return switch ((
      paper,
      CutFrameCompositeSignature.of(
        mapCompositeLeaves([node], _signatureOf),
        canvasSize: _painter.canvasSize,
      ).nodes,
    )) {
      (final paper?, []) => paper,
      (null, [final only]) => only,
      (final paper?, [final only]) => (paper: paper, rows: only),
      _ => null,
    };
  }

  static CompositeLayerSignature? _signatureOf(_PaintRow row) => switch (row) {
    _PaintCelSurface(:final signature) => signature,
    _ => null,
  };

  /// Whether [row] is the one a pen draws on — live, or drawn from what is
  /// stored as the frame is laid ([_PaintCelSurface.drawnOn]).
  static bool _drawnOn(_PaintRow row) => switch (row) {
    _PaintActiveSurface() => true,
    _PaintCelSurface(:final drawnOn) => drawnOn,
    _PaintLiftedSurface() || _PaintPaper() => false,
  };

  /// Everything this stack is, in CANVAS space: the paper and then the
  /// layers over it — against the screen directly (the walk) or into the
  /// display buffer's recorder ([intoTheBuffer]). Those are the two halves
  /// of stage 2 and they must be the same body — a second copy is how "the
  /// buffer path draws something slightly different" starts.
  void _paintContent(
    Canvas into, {
    required bool intoTheBuffer,
    required double rasterScale,
  }) {
    _screen = intoTheBuffer ? null : into;
    _paintNodes(into, _rootNodes, rasterScale, _visibleCanvasRect);
  }

  /// Rasterises [_paintContent] over [bounds] at CANVAS resolution, whatever
  /// the zoom — or null when the stack should just paint itself onto the
  /// screen.
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
  ({ui.Image image, Rect rect})? _composeDisplayBuffer(Rect bounds) {
    if (_painter.debugDisableSingleBuffer || bounds.isEmpty) {
      return null;
    }
    // Whole pixels, and the DESTINATION is the rounded rect too — a src/dst
    // pair that disagree by a fraction of a pixel would resample the buffer
    // a second time and undo the point of having it. Whole texels of every
    // level the display reads, too ([levelsReadAt]): the buffer's chain
    // halves on the grid the frame's one picture's does. ↩️Cut where the
    // view cut it, a stroke's step drawn as it stands under its patch's
    // clip read its ink off another chain than the picture's at 25% on a
    // 1.5 screen, up to 8/255 (F-465). And where the frame ends in view, it
    // ends where the frame's picture does ([frameGridOutward]): each samples
    // its own edge again past it, so two that end apart show apart there.
    final rect = frameGridOutward(bounds).intersect(
      wholeLevelPixelsOutward(_visibleCanvasRect, levelsReadAt(_displayScale)),
    );
    final width = rect.width.round();
    final height = rect.height.round();
    if (width <= 0 || height <= 0) {
      return null;
    }
    if (width > _LayerStackPainter._maxBufferSide ||
        height > _LayerStackPainter._maxBufferSide) {
      // 🚨THE SAFETY NET, AND NOTHING ELSE (유저 결정 2026-09-16: 「안전망만
      // 존재하면 문제없고」). The buffer is the canvas in view at its own
      // resolution, so it reaches the cap where more than 8192 canvas
      // pixels a side are in view. There the direct walk draws — T21
      // territory, every layer resampled separately, which the walk was
      // before any buffer existed and is always correct. The knee that used
      // to compose a screen-scale buffer here (ⓔ 5단계, 2026-08-16 →
      // 2026-09-16) is gone: it cost 488MB and 300ms a stroke batch on a
      // large page. ↩️Below 100% the buffer was a level, at most 4× the
      // screen, until nothing drew at a level (one-picture-per-frame ②-5a ·
      // ②-5b-1): what draws here is a frame — or its ghosts — as it stands
      // until its picture is there.
      debugCappedFallbacks += 1;
      return null;
    }
    // Composed whole at every paint: nothing is kept from one to the next.
    // ↩️The display buffer was kept while nothing changed, patched where a
    // stroke step moved the live row and carried by a pan
    // (`DisplayBufferCache` — ⛔one image, never a tiled one: a cold tile
    // cache rasterised the composite once per tile, so panning cost N times
    // what it did), until a standing canvas showed the frame's one picture
    // and patched its strokes into that (one-picture-per-frame ②-5a,
    // 2026-10-25): what composes here now is a frame as it stands where a
    // stroke's patch is still on its way — or ghosts whose picture is not
    // there yet.
    final edge = wholeLevelPixelsOutward(bounds, 0);
    final recorder = ui.PictureRecorder();
    labProbe(
      'displayBuffer.recordWhole',
      () => _paintCutWhereItEnds(
        _bufferCanvas(recorder, rect),
        edge,
        shownWithin: rect.intersect(_visibleCanvasRect),
      ),
    );
    final image = labProbe(
      'displayBuffer.raster',
      () => rasterPicture(recorder, width, height),
    );
    return (image: image, rect: rect);
  }

  /// A canvas onto the buffer over [rect], in the buffer's own pixels —
  /// canvas pixels — so every draw lands 1:1. Bounded by those pixels, so a
  /// draw into it can ask what it can land on.
  Canvas _bufferCanvas(ui.PictureRecorder recorder, Rect rect) => Canvas(
    recorder,
    Rect.fromLTWH(
      0,
      0,
      rect.width.roundToDouble(),
      rect.height.roundToDouble(),
    ),
  )..translate(-rect.left, -rect.top);
}
