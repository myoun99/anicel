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
    if (fillDabAt == null || _state._pendingFillCommitDab != null) {
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
    final stamp = dab.stamp;
    _state._resetOverlay();
    // The fill composites like anything else now (유저 확정: 버킷에도
    // 블렌드를 깐다) — 뒤에 그리기 puts colour UNDER the line art already
    // on the cel, which is the whole reason to want it.
    //
    // Preview and commit read the SAME value, one line apart: the overlay
    // pre-blends with the commit's own kernels (R27 #4), so agreeing here
    // is all it takes for what is shown to be what lands. Setting one and
    // not the other is the way this goes wrong.
    _state._overlayModel.erase = blend == BrushBlendMode.erase;
    _state._overlayModel.blendMode = blend;
    final surface = _state.widget.sessionState.canvasState.currentSurface;
    if (stamp != null) {
      final stampLeft = (dab.center.x - stamp.width / 2).round();
      final stampTop = (dab.center.y - stamp.height / 2).round();
      _state._settlingBounds = DirtyRegion(
        left: math.max(0, stampLeft),
        top: math.max(0, stampTop),
        rightExclusive: math.min(
          surface.canvasSize.width,
          stampLeft + stamp.width,
        ),
        bottomExclusive: math.min(
          surface.canvasSize.height,
          stampTop + stamp.height,
        ),
      );
      // R26 #18: a fill previews as ONE stamp image, so it does not pass
      // through the stroke pre-blend where the selection mask lives — the
      // mask goes onto the stamp's own bytes instead, once, before the
      // upload. The commit clips the same fill on its own buffer
      // (clipStrokePixelsToSelection), and both read the SAME scanline
      // mask, so the preview and the landed pixels agree at the boundary.
      final stampRgba = _state._pressure._maskedStampRgba(
        rgba: stamp.rgba,
        left: stampLeft,
        top: stampTop,
        width: stamp.width,
        height: stamp.height,
        opacity: dab.opacity,
      );
      // The stamp is straight-alpha; the overlay pipeline (like the
      // tile images) uploads premultiplied. The fused C kernel does
      // 64MP in one pass — the same loop in Dart was seconds. The
      // scratch buffer is fresh per fill; the decode callback frees it.
      final engine = QaNativeEngine.instance;
      final Uint8List premultiplied;
      QaStampScratch? scratch;
      if (engine != null) {
        scratch = engine.premultipliedStampCopy(stampRgba);
        premultiplied = scratch.view;
      } else {
        premultiplied =
            _InteractiveBrushEditCanvasViewState._premultipliedCopyDart(
              stampRgba,
            );
      }
      final token = _state._fillOverlayToken;
      ui.decodeImageFromPixels(
        premultiplied,
        stamp.width,
        stamp.height,
        ui.PixelFormat.rgba8888,
        (image) {
          scratch?.free();
          if (!_state.mounted || token != _state._fillOverlayToken) {
            // The overlay was reset (settle handoff, frame switch, next
            // fill) before this decode landed — never painted, safe to
            // dispose directly.
            image.dispose();
            return;
          }
          _state._overlayModel.setStampOverlay(
            image,
            Offset(stampLeft.toDouble(), stampTop.toDouble()),
          );
        },
      );
    } else {
      // A stampless fill dab (synthetic/test): no overlay preview —
      // the deferred commit below still lands it identically.
      _state._settlingBounds = null;
    }
    // Pin the pre-fill tiles NOW: until the stamp image decodes the
    // canvas keeps showing the pre-fill picture (no flash), then the
    // overlay pops in complete.
    _state._overlayModel.holdPreStrokeTiles(
      preStrokeHoldTiles(surface: surface, bounds: _state._settlingBounds),
    );

    // Commit AFTER the tap frame renders: unconditional (never gated on
    // the decode callback — a fill must land even if the engine drops
    // the image), so the reveal and the commit jank overlap instead of
    // stacking.
    _state._pendingFillCommitDab = dab;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _runPendingFillCommit();
    });
    SchedulerBinding.instance.ensureVisualUpdate();
  }

  void _runPendingFillCommit() {
    final dab = _state._pendingFillCommitDab;
    _state._pendingFillCommitDab = null;
    if (dab == null || !_state.mounted) {
      return;
    }
    _state.widget.onSourceStrokeCommitted(
      BrushStrokeCommitData(
        sourceDabs: [dab],
        blendMode: _state.widget.inputSettings.blendMode,
      ),
    );
    _state._beginSettling();
  }
}
