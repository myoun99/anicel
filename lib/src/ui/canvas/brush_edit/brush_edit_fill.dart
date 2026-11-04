part of '../interactive_brush_edit_canvas_view.dart';

/// THE FILL — a press that holds its range, the dab that carries it, and
/// the pending commit that lands it — as its own object.
///
/// 🚨A collaborator carved out of `_InteractiveBrushEditCanvasViewState`
/// (the audit's SRP cut, 2026-09-02). It reaches the State through
/// `_state`.
class _BrushEditFill implements GradientRangeHold {
  _BrushEditFill(this._state);

  final _InteractiveBrushEditCanvasViewState _state;

  /// Whether [pointer] holds the fill.
  bool holds(int pointer) => _state._fillPress?.pointer == pointer;

  /// Whether one of [pointers] holds the fill.
  bool heldBy(Set<int> pointers) {
    final held = _state._fillPress;
    return held != null && pointers.contains(held.pointer);
  }

  /// [pointer] takes the fill at [at] (I-160-Q2 a): its range flooded and
  /// marked, laid at the lift ([lift]) — or, a range held for its gradient,
  /// the gradient dragged from here (I-160-Q5 「툭이던 뭐던 묻지않음 … 그냥
  /// 클릭시작하면 조작임」: whatever this press turns out to be).
  void press(int pointer, CanvasPoint at) {
    // 🚨The busy check lives HERE rather than at each caller. It used to sit
    // only in the pointer-down path, which was true while every fill ran
    // from there — a touch fill ran from the LIFT, so a pen fill and a
    // resting finger's lift could each pass a gate the other had already
    // walked through and land two commits for one intent.
    //
    // ⛔ONE PRESS HOLDS THE FILL, THE FIRST — a stroke's own law (a press
    // while `_activeDrawingPointer` is set draws nothing), now that a fill
    // is held as a stroke is: a later press retiring a held one would let
    // a palm landing on the glass take the pen's fill away. The one press
    // that retires another is a pen's or a mouse's over a finger's, and
    // the press reader does that before it gets here.
    if (_state._pendingFill != null || _state._fillPress != null) {
      return;
    }
    final held = _state._heldForGradient;
    if (held != null) {
      if (_gradientOn) {
        _state._fillPress = (pointer: pointer, range: held.range);
        _drag(held.range, from: at, to: at);
        return;
      }
      // The gradient was switched off since the range was picked: this
      // press picks anew — where the bucket is in hand to pick with.
      letGo();
    }
    if (_state.widget.fillRangeAt == null) {
      return;
    }
    _state._fillPress = (pointer: pointer, range: null);
    reach(at);
  }

  /// Whether the fill's gradient is on (`FloodFillOptions.gradient`).
  bool get _gradientOn =>
      _state.widget.fillGradient?.call().options.enabled ?? false;

  /// The held fill's press is at [at]: its range is the flood from there —
  /// flooded again only past what the range reached, so a press resting in
  /// one region floods it once (TVPaint's 「이동할때마다 그게 바뀌고」). A
  /// continuous fill's range takes the flood in beside what it holds
  /// ([FillRange.joining]) instead. A press dragging a held range's
  /// gradient takes the gradient's end there.
  void reach(CanvasPoint at) {
    final held = _state._fillPress;
    if (held == null) {
      return;
    }
    final gradient = _state._heldForGradient;
    final drag = gradient?.drag;
    if (gradient != null && drag != null) {
      _drag(gradient.range, from: drag.from, to: at);
      return;
    }
    final fillRangeAt = _state.widget.fillRangeAt;
    if (fillRangeAt == null || (held.range?.covers(at) ?? false)) {
      return;
    }
    // The seed and the axis come from the same pair the STROKE path uses —
    // this view's own position and its own guides. The seed is in the
    // space the pointer is in and the axis is the canvas's: the fill reads
    // one through the other ([fillRangeAt]'s `space`), as a stroke's
    // copies do.
    // ↩️The view's guides used to be carried into its own space, so both
    // were 「already in the space the pointer is in」.
    final found = _state._press.fillSpendsNothingAt(at)
        ? null
        : fillRangeAt(at, _state.widget.guides.actingSymmetry);
    final kept = held.range;
    final continuous = _state.widget.fillsContinuously?.call() ?? false;
    final range = !continuous || kept == null
        ? found
        : found == null
        ? kept
        : kept.joining(found);
    _state._fillPress = (pointer: held.pointer, range: range);
    // What the range lays is its region: one that did not change (an open
    // region joined, or none found) leaves the mark as it stands.
    if (!identical(range?.region, kept?.region)) {
      _mark(range);
    }
  }

  /// The held fill lands what its range showed — the flood the press made,
  /// in the colour in hand, through the stroke a fill is ([_handleFillDabs]),
  /// whose result takes the mark's place in one notification.
  ///
  /// With the gradient on, the range is not laid but held, marked, for the
  /// press that lays its gradient; and that press's lift lands the
  /// gradient as it shows — the road a dragged shape lands by
  /// ([ShapeShow.land]).
  void lift() {
    final held = _state._fillPress;
    _state._fillPress = null;
    final gradient = _state._heldForGradient;
    final drag = gradient?.drag;
    if (gradient != null && drag != null) {
      _state._heldForGradient = null;
      final area = _gradientArea(gradient.range, drag.from, drag.to);
      if (area == null) {
        _state._shapeShow.drop();
        _mark(null);
        return;
      }
      _state._shapeShow.land(area);
      return;
    }
    final range = held?.range;
    // ⚠️An open range is laid as ever, which lays nothing and says why: it
    // would hold a gradient over nothing.
    if (range != null && !range.open && _gradientOn) {
      _state._heldForGradient = (range: range, drag: null);
      return;
    }
    final dabs =
        held?.range?.dabsIn(_state.widget.inputSettings().color) ??
        const <BrushDab>[];
    // A range that lays nothing covers no pixel, so it never marked one:
    // nothing is left to take away.
    if (dabs.isNotEmpty) {
      _handleFillDabs(dabs);
    }
  }

  /// The press is not this fill's any more — a second finger joined, or the
  /// gesture was cancelled. ⛔Nothing to undo, because nothing was drawn.
  ///
  /// A gradient's drag given up gives up the drag, not the range: a pinch
  /// between picking a range and laying its gradient is the canvas moved
  /// to lay it, and the range waits for the next press, marked again.
  void forgetPress() {
    _state._fillPress = null;
    final held = _state._heldForGradient;
    if (held != null && held.drag != null) {
      _state._heldForGradient = (range: held.range, drag: null);
      _state._shapeShow.drop();
      _mark(held.range);
      return;
    }
    _mark(null);
  }

  /// [range] — an outline the shape fill closed — held for its gradient as
  /// the bucket's lift holds its flood ([lift]): marked, for the press that
  /// lays its gradient. Whatever the fill held before goes.
  @override
  void hold(FillRange range) {
    letGo();
    _state._heldForGradient = (range: range, drag: null);
    _mark(range);
  }

  @override
  bool get holdsARange => _state._heldForGradient != null;

  /// The fill lets go of all it holds — its press, and a range held for
  /// its gradient — laying nothing: the tool was put down, or the cel it
  /// held them on went, as a stroke in flight is let go then
  /// ([_InteractiveBrushEditCanvasViewState._endStrokeAfterTheFrame]).
  @override
  void letGo() {
    final holding =
        _state._fillPress != null || _state._heldForGradient != null;
    _state._fillPress = null;
    _state._heldForGradient = null;
    if (holding) {
      _state._shapeShow.drop();
      _mark(null);
    }
  }

  /// [range]'s gradient dragged [from] [to]: held so, and shown as it will
  /// land — laid a share of each frame by the dragged shape's own show,
  /// put up when it is whole ([ShapeShow.show]).
  void _drag(
    FillRange range, {
    required CanvasPoint from,
    required CanvasPoint to,
  }) {
    _state._heldForGradient = (range: range, drag: (from: from, to: to));
    final area = _gradientArea(range, from, to);
    if (area != null) {
      _state._shapeShow.show(area);
    }
  }

  /// [range] under the gradient from [from] to [to] in the colours in hand
  /// — as an area a dragged shape is ([ShapeArea]): the same range under
  /// the same gradient is the same shape, asked for again for nothing.
  ShapeArea? _gradientArea(FillRange range, CanvasPoint from, CanvasPoint to) {
    final inHand = _state.widget.fillGradient?.call();
    if (inHand == null) {
      return null;
    }
    final input = _state.widget.inputSettings();
    final gradient = inHand.options.between(
      from,
      to,
      main: input.color,
      sub: inHand.sub,
    );
    return (
      shape: (range, gradient),
      pieces: () => range.piecesUnder(gradient),
      blend: input.blendMode,
      selection: _state.widget.selectionNow?.call(),
    );
  }

  /// [range] marked over the row it lands on ([FillRangeMark]) — cut by the
  /// selection as the fill will be ([promoteFillDabs]'s `selection`).
  void _mark(FillRange? range) {
    final mark = range == null
        ? null
        : FillRangeMark(
            range.contoursWithin(_state.widget.selectionNow?.call()),
          );
    _state._overlay._overlayModel.showFillRange(
      mark == null || mark.isEmpty ? null : mark,
    );
  }

  /// 🚨★★★A FILL IS A STROKE OF ITS STAMP PIECES (유저 절대규칙 2026-09-17:
  /// 「보이는 중이랑 결과랑 절대로 다르면 안 되」). The tap makes the result
  /// tiles the commit will land (`promoteFillDabs`: the commit's own
  /// function, run now), shows them as the overlay's pre-blended tiles — a
  /// coordinate's picture, exact at every level — and commits them after
  /// the tap frame through the same landing a stroke takes at pen-up
  /// ([_BrushEditStroke.landPromoted]): the pictures hand over, nothing
  /// is decoded twice, nothing settles.
  void _handleFillDabs(List<BrushDab> rawDabs) {
    final blend = _state.widget.inputSettings().blendMode;
    final dabs = [for (final dab in rawDabs) dab.underBlend(blend)];
    final surface = _state.widget.celNow();
    final promoted = promoteFillDabs(
      surface: surface,
      dabs: dabs,
      blendMode: blend,
      selection: _state.widget.selectionNow?.call(),
      layerId: _state.widget.layerId,
      frameId: _state.widget.frameId,
    );
    if (promoted.isEmpty) {
      // Nothing to land: outside the selection, or a no-op on these
      // pixels.
      _state._overlay.resetOverlay();
      return;
    }
    _state._pendingFill = (dabs: dabs, base: surface, tiles: promoted);
    showResult(base: surface, blend: blend, tiles: promoted);
    // Commit AFTER the tap frame renders, so the reveal and the commit's
    // frame overlap instead of stacking; the commit is a tile PUT of the
    // objects made above.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _runPendingFillCommit();
    });
    SchedulerBinding.instance.ensureVisualUpdate();
  }

  void _runPendingFillCommit() {
    final pending = _state._pendingFill;
    _state._pendingFill = null;
    if (pending == null || !_state.mounted) {
      return;
    }
    landResult(
      tiles: pending.tiles,
      dabs: pending.dabs,
      blend: _state.widget.inputSettings().blendMode,
      base: pending.base,
    );
  }

  /// Shows [tiles] — a fill's result, made by the commit's own function
  /// ([promoteFillDabs]) against [base] — as the overlay's pictures, in
  /// place of whatever it showed.
  ///
  /// The fill composites like anything else (유저 확정: 버킷에도 블렌드를
  /// 깐다) — 뒤에 그리기 puts colour UNDER the line art already on the cel,
  /// which is the whole reason to want it. So the overlay is configured
  /// exactly as a stroke's: the surface's grid, the blend, and the surface
  /// as the pre-blend base, and its tiles REPLACE their coordinates.
  void showResult({
    required BitmapSurface base,
    required BrushBlendMode blend,
    required List<PromotedStrokeTile> tiles,
  }) {
    final overlay = _state._overlay._overlayModel;
    _state._overlay.resetOverlay();
    overlay.configureTileSize(base.tileSize);
    overlay.erase = blend == BrushBlendMode.erase;
    overlay.blendMode = blend;
    overlay.preBlendBase = base;
    overlay.showResultTiles(tiles);
  }

  /// Lands [tiles], the result of [dabs] on [base] that the overlay shows,
  /// through the landing a stroke takes at pen-up
  /// ([_BrushEditStroke.landPromoted]): the pictures hand over and the
  /// commit installs these very tiles.
  void landResult({
    required List<PromotedStrokeTile> tiles,
    required List<BrushDab> dabs,
    required BrushBlendMode blend,
    required BitmapSurface base,
  }) {
    _state._stroke.landPromoted(
      tiles,
      BrushStrokeCommitData(
        sourceDabs: dabs,
        blendMode: blend,
        promotedBase: base,
        promotedTiles: [
          for (final entry in tiles) (coord: entry.coord, tile: entry.tile),
        ],
      ),
    );
  }
}
