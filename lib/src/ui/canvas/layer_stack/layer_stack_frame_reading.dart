part of '../canvas_layer_stack_view.dart';

/// What one SURFACE row shows — the live row's, or a row a folder's lift
/// holds (I-37): its painter, the float over it, and the way into its slot
/// from the canvas that float is told in.
///
/// ⛔One slot reads both ([_FrameReading._slotOf]): a lifted row is a
/// surface with a float over it in its own row's slot, which is what the
/// live row is while a box is open — two copies of that reading are what
/// would drift apart.
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

  /// Where the float draws as this row shows it ([shown]), in the slot's
  /// own space — null where nothing floats. What [extent] covers past the
  /// surface, and where a change of the float lands
  /// ([_FrameRows._floatTold]).
  late final Rect? floated = () {
    final shown = this.shown;
    final told = shown?.preview.drawnWorldRect;
    if (shown == null || told == null || told.isEmpty) {
      return null;
    }
    final intoSlot = shown.canvasToRow;
    return intoSlot == null ? told : MatrixUtils.transformRect(intoSlot, told);
  }();

  /// What the slot draws, in its own space — the law is
  /// [_FrameReading._activeSurfaceExtent]'s (F-85).
  late final Rect extent = () {
    final drawn = painter.drawnWorldRect;
    final floated = this.floated;
    if (floated == null) {
      return drawn;
    }
    // A slot that draws nothing answers [Rect.zero], and a union with it
    // would reach back to the origin.
    return drawn.isEmpty ? floated : drawn.expandToInclude(floated);
  }();
}

/// ONE READING OF A FRAME'S ROWS: the world it covers, its rows over the
/// paper, what each surface row shows and what each node shows — what the
/// engine lays it from (`EngineStackScreen`), with no screen around it.
///
/// ↩️It was one paint of the stack, the walk that drew the tree under the
/// viewport and the one buffer it resampled once (the audit's cognitive
/// cut, Round 6, 2026-09-03: `paint` was 784 lines scoring 105), until the
/// engine laid every frame (flip lane ⓑ).
class _FrameReading {
  _FrameReading(this._painter);

  final _FrameRows _painter;

  // Set by [_standInTheWorld], read by what stands on it.
  late final Rect _canvasRect;
  late final Rect _visibleCanvasRect;
  late final Rect _contentExtent;

  /// Where the frame lies in the world with no screen around it
  /// ([StackedFrame]): the rect the display buffer covers, the whole
  /// pasteboard on screen — the page and every row's content.
  Rect frameExtent() {
    _standInTheWorld();
    return wholeLevelPixelsOutward(_contentExtent, 0);
  }

  /// The geometry of the world a frame's picture holds: the whole
  /// pasteboard in view and no viewport.
  void _standInTheWorld() {
    _canvasRect = _painter.canvasSize.canvasRect;
    _visibleCanvasRect = _painter.canvasSize
        .pasteboardAt(_painter.pasteboardReach)
        .rect;
    _contentExtent = _compositeExtent();
  }

  /// 🚨★★★WHAT THE ACTIVE SLOT DRAWS, not what its surface holds (F-85,
  /// 2026-09-15): the painter's own answer, and the float drawn into the
  /// same slot. Read off the committed surface alone, a stroke in flight, a
  /// fill's stamp, the stamp ghost and a transform's float were all cut at
  /// the edge of the ink that had already landed — and came back the moment
  /// a commit put tiles there. What the frame covers.
  ///
  /// Read ONCE per reading ([_SurfaceSlot.extent]): the node walk asks per
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
  /// once per reading, as the live row's slot is.
  final Map<BitmapSurfacePainter, _SurfaceSlot> _rowSlots = Map.identity();

  /// What [row] shows: the live row's slot, or one of [_rowSlots].
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
    return extent.isEmpty
        ? _visibleCanvasRect
        : extent.intersect(_visibleCanvasRect);
  }

  /// The CANVAS-SPACE rect a buffer for [node] covers — what of it lies
  /// [within] what reads it: the view at the top, and under a folder that
  /// folder's buffer, which a blur on it reads past the view
  /// ([subtreeBufferBounds], the one law the camera's render keeps too).
  ///
  /// ↩️Bounded by `pasteboard ∩ visibleRect`, zoomed far enough out it ran
  /// past the buffer the stack composed into, and the paint fell to a
  /// fallback that stopped compositing the way playback, the camera and the
  /// export do (유저 2026-08-15 accepted it at the time: 「무릎 아래는
  /// 균일 필터, 겹침 색차 수용」 — accepted because bounding by the view was
  /// the only tool on the table). The engine keeps a frame in tiles: it has
  /// no such buffer and no fallback.
  ///
  /// ★Content is not the pasteboard. For a cached row it is
  /// [surfaceContentWorldRect]'s answer — the canvas rect unioned with the
  /// tiles that actually exist. For the ACTIVE row it is everything the
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
    final _PaintActiveSurface live => rowExtentWithItsReach(
      _activeSurfaceExtent(),
      live.effects,
      paper: _canvasRect,
    ),
    // What a row beside the live one draws — its surface, and a lift's
    // float — as the live row's extent is measured
    // ([_activeSurfaceExtent]).
    final _SurfaceRow surface => rowExtentWithItsReach(
      _slotOf(surface).extent,
      surface.effects,
      paper: _canvasRect,
    ),
    _PaintPaper() => _canvasRect,
  };

  /// Where [row] lies.
  LayerPlacement? _placementOf(_PaintRow row) => switch (row) {
    final _SurfaceRow surface => surface.placement,
    _PaintPaper() => null,
  };

  /// What the root target holds, bottom → top: the paper, as the bottom row
  /// of the root scope ([onUnderlay]) — inside the backdrop of a blend that
  /// composes over what lies below it, which reads the paper there as a GPU
  /// blend reads it off the target — and the rows over it.
  ///
  /// ↩️Each route laid the paper itself and the rows after it, until
  /// brush-fidelity-Q4 gave the stack rows that read their backdrop.
  late final List<CompositeNode<_PaintRow>> _rootNodes = _painter.paintPaper
      ? onUnderlay(_painter.nodes, const _PaintPaper())
      : _painter.nodes;

  /// What [node] draws, as a frame's picture is signed by it
  /// ([CutFrameCompositeSignature]) — null where a row of it is drawn live
  /// or stands for no cel: that node is drawn afresh each time. ⚠️A row
  /// with no signature would drop out of the signing ([mapCompositeLeaves])
  /// and leave a key that misses it — the first stroke on an empty cel, in
  /// a folder held with nothing of it.
  ///
  /// The paper draws what it is laid with, and where.
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
        ? (paper: _painter.paperBackground, on: _canvasRect)
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

  /// What [node]'s own picture holds: what it draws, at full strength
  /// ([CompositeNodeSignature.asItsPicture]). What the paper lies in has no
  /// picture of its own: a blend's backdrop ([onUnderlay]).
  Object? _pictureOf(CompositeNode<_PaintRow> node) => switch (_drawsOf(node)) {
    final CompositeNodeSignature rows => rows.asItsPicture,
    final drawn => drawn,
  };

  static CompositeLayerSignature? _signatureOf(_PaintRow row) => switch (row) {
    _PaintCelSurface(:final signature) => signature,
    _ => null,
  };
}
