part of '../interactive_brush_edit_canvas_view.dart';

/// THE FILL — a tap that floods, the dab that carries it, and the
/// pending commit that lands it — as its own object.
///
/// 🚨A collaborator carved out of `_InteractiveBrushEditCanvasViewState`
/// (the audit's SRP cut, 2026-09-02). It reaches the State through
/// `_state`.
class _BrushEditFill {
  _BrushEditFill(this._state);

  final _InteractiveBrushEditCanvasViewState _state;

  /// The fill tap itself: flood at [seed], reveal, and queue the commit.
  void runFillTap(CanvasPoint seed) {
    final fillDabAt = _state.widget.fillDabAt;
    // 🚨The busy check lives HERE rather than at each caller. It used to sit
    // only in the pointer-down path, which was true while every fill ran
    // from there — a touch fill now runs from the LIFT, so a pen fill and a
    // resting finger's lift could each pass a gate the other had already
    // walked through and land two commits for one intent.
    if (fillDabAt == null || _state._pendingFill != null) {
      return;
    }
    // 🚨A fill going out RETIRES any armed tap, whoever armed it. A pen can
    // fill while a finger rests on the glass — that finger armed a tap of
    // its own on touchdown, and without this its lift would land a SECOND
    // fill at wherever it happened to be resting. ⛔The busy check above
    // cannot cover that: it clears in the post-frame callback, and a lift
    // arrives frames later.
    forgetFillTap();
    // The seed and the axis come from the same pair the STROKE path uses —
    // this view's own position and its own guides, both already in the
    // space the pointer is in. Reading the symmetry from the project
    // instead would put the mirror where the pen is not under a pose.
    final dab = fillDabAt(
      seed,
      _state.widget.inputSettings.color,
      _state.widget.guides.actingSymmetry,
    );
    if (dab == null) {
      return;
    }
    _handleFillDab(dab);
  }

  /// The tap is not this fill's any more — a second finger joined, or the
  /// gesture was cancelled. ⛔Nothing to undo, because nothing was drawn.
  void forgetFillTap() {
    _state._fillTapPointer = null;
    _state._fillTapSeed = null;
  }

  /// 🚨★★★A FILL IS A STROKE OF ONE DAB (유저 절대규칙 2026-09-17: 「보이는
  /// 중이랑 결과랑 절대로 다르면 안 되」). The tap makes the result tiles the
  /// commit will land (`promoteFillDab`: the commit's own function, run
  /// now), shows them as the overlay's pre-blended tiles — a coordinate's
  /// picture, exact at every level — and commits them after the tap frame
  /// through the same landing a stroke takes at pen-up
  /// ([_BrushEditStroke.landPromoted]): the pictures hand over, nothing
  /// is decoded twice, nothing settles.
  void _handleFillDab(BrushDab rawDab) {
    final blend = _state.widget.inputSettings.blendMode;
    // ERASE is not carried by the blend mode at commit — it is a flag on
    // the DAB, read per dab by the materializer. A fill arrives as one
    // stamp dab built with no opinion about erasing, so handing the
    // kernels `blendMode: erase` alone would take the plain path with the
    // flag still false and PAINT the region instead of clearing it.
    final dab = blend == BrushBlendMode.erase
        ? rawDab.copyWith(erase: true)
        : rawDab;
    final surface = _state.widget.sessionState.canvasState.currentSurface;
    final overlay = _state._overlay._overlayModel;
    _state._overlay.resetOverlay();
    // The fill composites like anything else now (유저 확정: 버킷에도
    // 블렌드를 깐다) — 뒤에 그리기 puts colour UNDER the line art already
    // on the cel, which is the whole reason to want it. The overlay is
    // configured exactly as a stroke's: the surface's grid, the blend, and
    // the surface as the pre-blend base, so its tiles REPLACE their
    // coordinates.
    overlay.configureTileSize(surface.tileSize);
    overlay.erase = blend == BrushBlendMode.erase;
    overlay.blendMode = blend;
    overlay.preBlendBase = surface;
    final promoted = promoteFillDab(
      surface: surface,
      dab: dab,
      blendMode: blend,
      selection: _state.widget.selectionRegion,
      layerId: _state.widget.layerId,
      frameId: _state.widget.frameId,
    );
    if (promoted.isEmpty) {
      // Nothing to land: outside the selection, or a no-op on these
      // pixels.
      return;
    }
    _state._pendingFill = (dab: dab, base: surface, tiles: promoted);
    overlay.showResultTiles(promoted);
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
    _state._stroke.landPromoted(
      pending.tiles,
      BrushStrokeCommitData(
        sourceDabs: [pending.dab],
        blendMode: _state.widget.inputSettings.blendMode,
        promotedBase: pending.base,
        promotedTiles: [
          for (final entry in pending.tiles)
            (coord: entry.coord, tile: entry.tile),
        ],
      ),
    );
  }
}
