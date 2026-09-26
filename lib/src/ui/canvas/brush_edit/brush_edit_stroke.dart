part of '../interactive_brush_edit_canvas_view.dart';

/// THE STROKE — beginning it under the press, advancing it to the next
/// point (through the guides that snap it), the spacing the active brush
/// wants, ending its input and committing it — as its own object.
///
/// 🚨A collaborator carved out of `_InteractiveBrushEditCanvasViewState`
/// (the audit's SRP cut, 2026-09-02). It reaches the State through
/// `_state` and rebuilds through `_rebuild`.
class _BrushEditStroke {
  _BrushEditStroke(this._state);

  final _InteractiveBrushEditCanvasViewState _state;

  /// Whether this contact has not read a pressure yet — what
  /// [_BrushEditPressure.noteSample] is told as `opening`.
  bool _opening = false;

  /// The samples a stroke took before its first pressure READING, in the
  /// order they came, each with what it will paint — null while nothing
  /// waits.
  ///
  /// 🚨★★★H43 (유저 2026-09-26, iPad: 「필압있는 브러시 쓸때 첫 펜다운한
  /// 부분? 만 입력한 필압보다 센게나와. 최대치가 나오는거같기도하고」). The
  /// first samples of a contact can carry a value the device has not
  /// measured yet ([_BrushEditPressure.pressureOf]), and the stroke painted
  /// it: UIKit's estimate on an iPad, a hovering packet under Wintab.
  ///
  /// ★THE STROKE WAITS FOR ITS FIRST READING, and every sample that waited
  /// is painted with it — the nearest measurement there is, exactly as a
  /// sample that cannot measure speed keeps the last one that could. The
  /// wait is the few samples it takes the device to catch up; nothing is
  /// on screen until then.
  ///
  /// ⚠️That pairs one sample's lean with another sample's pressure — what
  /// [_BrushEditPressure.noteSample] is one call to prevent — and it does
  /// so knowingly: those samples carry no pressure of their own, and the
  /// nearest measurement is closer to the hand than the stand-in the
  /// device put there.
  ///
  /// ⛔NOT 「paint the stand-in and repaint when the reading comes」 — what
  /// is shown once is seen ([[no-optimistic-commit-then-revert]]).
  ///
  /// Only a brush whose curves READ pressure waits: for any other the
  /// value changes nothing it draws.
  ({Duration since, List<_WaitingSample> samples})? _waiting;

  /// How long a stroke waits for its first reading before it takes the
  /// device's word.
  ///
  /// The longest wait on record is UIKit's: seven coalesced samples at
  /// 240 Hz, 29 ms (the 2018 CSV cited at `_isUIKitForceEstimate`), plus
  /// the one event interval it takes Flutter to deliver the next main touch.
  /// A pen that never measures — one without a force sensor may report the
  /// estimate for good — would otherwise hold its whole stroke off screen
  /// until it lifted; past this bound it paints what it reports, as it
  /// always did.
  static const Duration _patience = Duration(milliseconds: 50);

  /// A stroke begins under [event]: the pointer is ours, the settings are
  /// the tool's (or the eraser's on a mapped tail), the stabiliser, the
  /// snap session, the symmetry, the dynamics and the ground mixer are
  /// armed, the overlay opens, and the first dabs go out.
  void beginStroke(
    PointerDownEvent event,
    CanvasPoint canvasPosition, {
    required bool startsInsidePasteboard,
    required bool mappedErase,
  }) {
    _state._activeDrawingPointer = event.pointer;
    // PEN-12 #4: a TOUCH stroke starts UNCOMMITTED — until it crosses the
    // touch slop a simultaneous second finger may still turn the pair
    // into navigation (cancelling only an invisible dot); once committed
    // the stroke owns the screen and extra fingers are ignored.
    _state._touchStrokeDownPosition = event.kind == PointerDeviceKind.touch
        ? event.localPosition
        : null;
    _state._touchStrokeCommitted = false;
    // The stroke's settings snapshot — every downstream dab reads it, so
    // the mapped-eraser substitution here flips the WHOLE stroke. The
    // substitution forces the BLEND to erase too (R27 #4 in passing): the
    // eraser tool locks its mode, but this path kept the brush's — a
    // mapped-erase press with a separable brush blend would have taken
    // the commit's blend branch and PAINTED instead of erasing.
    final strokeSettings = mappedErase
        ? _state.widget.inputSettings().copyWith(
            erase: true,
            blendMode: BrushBlendMode.erase,
          )
        : _state.widget.inputSettings();
    _state._activeStrokeInputSettings = strokeSettings;
    final read = _state._pressure.noteSample(event, opening: true);
    _opening = !read;
    _state.widget.onActiveStrokeChanged?.call(true);
    _state._nextSequence = 0;
    _state._breakCurrentVisibleSegment = !startsInsidePasteboard;
    _state._previousRawCanvasPosition = canvasPosition;
    _state._lastPenPosition = canvasPosition;
    final stabilizerStrength = strokeSettings.stabilizerStrength;
    _state._stabilizer = stabilizerStrength > 0
        ? StrokeStabilizer(
            ropeLength: stabilizerStrength / _state.widget.viewport.zoom,
            start: canvasPosition,
          )
        : null;
    // Guides are read ONCE per stroke. Both are frozen here rather than
    // consulted per sample so an edit landing mid-stroke cannot bend the
    // line that is already down.
    _state._snapSession = PerspectiveSnapSession.maybeStart(
      guides: _state.widget.guides,
      start: canvasPosition,
      zoom: _state.widget.viewport.zoom,
    );
    final symmetry = _state.widget.guides.actingSymmetry;
    _state._symmetryTransforms = symmetry == null
        ? const []
        : symmetryTransforms(symmetry);
    // ONE PRESS, ONE ROLL OF THE DICE: the stroke's spacing, scatter and
    // jitter come from its press, so every view that hears the press rolls
    // the same numbers. A sheet's windows each draw their own slice of one
    // stroke (one paper, 유저 2026-09-25), and the pieces meet as the one
    // stroke they are — a scattered dab cut at a window edge goes on in the
    // window beside it — without any view being told who else heard it.
    final dice = Object.hash(event.pointer, event.timeStamp);
    _state._spacingRandom = math.Random(dice);
    _state._dualPhaseRandom = math.Random(dice + 1);
    _state._strokeDynamics = BrushStrokeDynamics(
      settings: strokeSettings,
      random: math.Random(dice + 2),
    );
    _state._lastDirectionDegrees = null;
    _state._previousBaseDab = null;
    _state._groundMixer = strokeSettings.shape.mixesGroundColor
        ? BrushGroundColorMixer(shape: strokeSettings.shape)
        : null;
    _state._overlay.beginStrokeOverlay();
    // Overlay stroke configuration AFTER the reset — reset() clears
    // preBlendBase, so setting it earlier silently disabled the whole
    // pre-blend pipeline for real pointer strokes (the R27 #4 ordering
    // bug: every parity test staged the model manually and never caught
    // it). The overlay must display in the stroke's blend mode from the
    // first dab.
    final strokeSurface = _state.widget.sessionState.canvasState.currentSurface;
    _state._groundSampler = _state._groundMixer == null
        ? null
        : bitmapSurfaceGroundSampler(strokeSurface);
    _state._overlay._overlayModel.configureTileSize(strokeSurface.tileSize);
    _state._overlay._overlayModel.erase = strokeSettings.erase;
    _state._overlay._overlayModel.blendMode = strokeSettings.blendMode;
    // R27 #4: EVERY stroke pre-blends its live tiles with the commit's
    // own kernels against the cel as it stands (user rule 07-23: ONE
    // display pipeline for all modes — color included). The GPU never
    // computes a pixel of the stroke composite, so pen-up cannot move a
    // byte in any mode. Revert switch if stroke feel regresses on
    // device: gate this on `blendMode != color` to give plain strokes
    // their classic stroke-only GPU-srcOver overlay back.
    _state._overlay._overlayModel.preBlendBase = strokeSurface;
    _state._collectedDabs.clear();
    _state._prepareLiveRasterizer();
    // A press off the pasteboard lays nothing down; the stroke's first dab
    // comes where a move crosses in.
    final paintPress = startsInsidePasteboard
        ? () => _paintPress(canvasPosition)
        : () {};
    if (!read && strokeSettings.shape.reads(BrushInputSource.pressure)) {
      _waiting = (
        since: event.timeStamp,
        samples: [_waitingSample(paintPress)],
      );
      return;
    }
    paintPress();
  }

  /// One pen sample for the stroke: painted now — or, while the stroke
  /// waits for its first pressure reading ([_waiting]), held with the
  /// others until one comes. [read] is what
  /// [_BrushEditPressure.noteSample] answered for it.
  void takeSample(
    CanvasPoint penPosition, {
    required Duration at,
    required bool read,
  }) {
    // The stabilizer smooths BEFORE clipping/interpolation, so every
    // downstream consumer (overlay, commit, replay) sees one chain — the
    // three-route parity holds by construction (P7). A held sample reaches
    // it when it is painted, in the order it came.
    void paint() => advanceStrokeThroughGuides(
      _state._stabilizer?.follow(penPosition) ?? penPosition,
    );
    final waiting = _waiting;
    if (waiting != null && !read && at - waiting.since <= _patience) {
      waiting.samples.add(_waitingSample(paint));
      return;
    }
    if (read) {
      _opening = false;
    }
    if (waiting != null) {
      _paintWaiting();
    }
    paint();
  }

  /// The contact ended before its first reading: what waited lands with
  /// what the device reported — a tap too short for the device to measure
  /// still leaves its dot.
  void stopWaiting() {
    if (_waiting != null) {
      _paintWaiting();
    }
  }

  /// Paints every sample that waited, each with its own lean and speed and
  /// the pressure the stroke holds now — the reading the current sample
  /// just brought or, when the stroke stops waiting without one, what the
  /// device last reported in its place — and leaves the current readings
  /// as they were.
  void _paintWaiting() {
    final samples = _waiting!.samples;
    _waiting = null;
    final tilt = _state._currentTilt;
    final speed = _state._currentSpeed;
    for (final sample in samples) {
      _state._currentTilt = sample.tilt;
      _state._currentSpeed = sample.speed;
      sample.paint();
    }
    _state._currentTilt = tilt;
    _state._currentSpeed = speed;
  }

  /// The sample just noted, as it waits: its own lean and speed, and what
  /// it paints.
  _WaitingSample _waitingSample(void Function() paint) => (
    tilt: _state._currentTilt,
    speed: _state._currentSpeed,
    paint: paint,
  );

  /// The stroke's FIRST dab, under the press.
  void _paintPress(CanvasPoint canvasPosition) {
    final initialDabs = _state._pressure.withPressureDynamics(
      const BrushDabInterpolator().interpolate(
        previous: null,
        nextRaw: _state._dabFromPosition(
          canvasPosition,
          sequence: _state._nextSequence,
        ),
        firstSequence: _state._nextSequence,
        spacingRatio: activeStrokeSpacing,
      ),
    );
    if (initialDabs.isNotEmpty) {
      _state._previousBaseDab = initialDabs.last;
    }
    // R20-B: dabs resolve through the tip-stamp cache HERE, at generation
    // — the overlay, the commit, undo replay and the .anicel all see the
    // same resolved (quantized, prerotated-mask) dabs.
    //
    // ⚠️ Symmetry replicates HERE TOO. This is the stroke's FIRST dab, laid
    // at pointer-down rather than through [advanceStrokeTo], and it is a
    // separate emission site — replicating only the move path left every
    // symmetric stroke's copies one dab short at the start, a notch right
    // where the pen landed.
    final emitted = BrushTipStampCache.instance.resolveDabs(
      replicateDabs(
        _state._withGroundMixing(
          _state._strokeDynamics!.apply(
            initialDabs,
            firstSequence: _state._nextSequence,
            directionDegrees: null,
          ),
        ),
        _state._symmetryTransforms,
        firstSequence: _state._nextSequence,
      ),
    );
    _state._collectedDabs.addAll(emitted);
    _state._overlay.queueOverlayDabs(emitted);
    _state._nextSequence += emitted.length;
  }

  /// Stabilized point → perspective snap → the stroke.
  ///
  /// Smoothing runs first because smoothing a snapped line would bend the
  /// straightness back out of it. The snap can return NOTHING while it is
  /// still deciding which ray this stroke belongs to; those points are held
  /// inside the session and arrive together the moment it locks.
  void advanceStrokeThroughGuides(CanvasPoint canvasPosition) {
    final session = _state._snapSession;
    if (session == null) {
      advanceStrokeTo(canvasPosition);
      return;
    }
    for (final snapped in session.follow(canvasPosition)) {
      advanceStrokeTo(snapped);
    }
  }

  void advanceStrokeTo(CanvasPoint canvasPosition) {
    final previousRaw = _state._previousRawCanvasPosition;
    _state._previousRawCanvasPosition = canvasPosition;
    if (previousRaw == null) {
      return;
    }

    final canvasSize =
        _state.widget.sessionState.canvasState.currentSurface.canvasSize;
    final clippedSegment = const CanvasSegmentClipper().clip(
      previous: previousRaw,
      current: canvasPosition,
      canvasSize: canvasSize,
    );
    if (clippedSegment == null) {
      _state._breakCurrentVisibleSegment = true;
      return;
    }

    final previousDab =
        _state._breakCurrentVisibleSegment ||
            clippedSegment.startsNewVisibleSegment ||
            _state._previousBaseDab == null
        ? null
        : _state._previousBaseDab;
    final segmentStartDabs =
        clippedSegment.startsNewVisibleSegment ||
            _state._breakCurrentVisibleSegment ||
            _state._previousBaseDab == null
        ? _state._pressure.withPressureDynamics(
            const BrushDabInterpolator().interpolate(
              previous: null,
              nextRaw: _state._dabFromPosition(
                clippedSegment.start,
                sequence: _state._nextSequence,
              ),
              firstSequence: _state._nextSequence,
              spacingRatio: activeStrokeSpacing,
            ),
          )
        : const <BrushDab>[];
    final firstEndSequence = _state._nextSequence + segmentStartDabs.length;
    final endPrevious = segmentStartDabs.isNotEmpty
        ? segmentStartDabs.last
        : previousDab;
    final segmentEndDabs = _state._pressure.withPressureDynamics(
      const BrushDabInterpolator().interpolate(
        previous: endPrevious,
        nextRaw: _state._dabFromPosition(
          clippedSegment.end,
          sequence: firstEndSequence,
        ),
        firstSequence: firstEndSequence,
        spacingRatio: activeStrokeSpacing,
      ),
    );
    final baseDabs = <BrushDab>[...segmentStartDabs, ...segmentEndDabs];
    if (baseDabs.isEmpty) {
      return;
    }
    _state._previousBaseDab = baseDabs.last;

    _state._lastDirectionDegrees =
        strokeDirectionDegrees(from: previousRaw, to: canvasPosition) ??
        _state._lastDirectionDegrees;
    // Symmetry copies the DABS, after interpolation, spacing and dynamics
    // have been computed once. The copy transforms are rigid, so distances
    // — and therefore spacing — survive them exactly, and every copy of the
    // stroke lands in the same batch as the original. That last part is why
    // the axis does not darken: the copies pre-blend together instead of
    // compositing over each other.
    final emitted = BrushTipStampCache.instance.resolveDabs(
      replicateDabs(
        _state._withGroundMixing(
          _state._strokeDynamics?.apply(
                baseDabs,
                firstSequence: _state._nextSequence,
                directionDegrees: _state._lastDirectionDegrees,
              ) ??
              baseDabs,
        ),
        _state._symmetryTransforms,
        firstSequence: _state._nextSequence,
      ),
    );

    // No setState: pointer moves only QUEUE the new dabs (this runs at
    // pointer-sample frequency); the per-frame flush rasterizes the batch
    // and repaints the overlay layer directly, skipping widget rebuilds.
    _state._collectedDabs.addAll(emitted);
    _state._overlay.queueOverlayDabs(emitted);
    _state._nextSequence += emitted.length;
    _state._breakCurrentVisibleSegment = false;
  }

  /// PROMOTION pen-up: the stroke is ALREADY blended into finished tiles
  /// (that is what has been on screen the whole time), so committing is
  /// installing them — no re-blend of the whole stroke, no second picture.
  ///
  /// The order is what makes it invisible: promote the tiles, hand each
  /// one the overlay image that shows exactly its pixels, commit, then
  /// drop the overlay — all inside this one pointer event, so the very
  /// next frame paints committed tiles that already have their pictures
  /// ([landPromoted]).
  ///
  /// 🪦THE SETTLE WINDOW, 2026-07-08 → 2026-09-17. While the overlay's
  /// pictures were decoded asynchronously, a tile the final flush touched
  /// could not have its picture at pen-up (the revision was written inside
  /// the decode callback, and the flush and the commit ran in one
  /// synchronous handler) — on an ordinary two-segment stroke 12 of 21
  /// promoted coordinates missed. The overlay then had to stay up as a
  /// stand-in until the committed tiles decoded, and every hole in that
  /// cover was a user report: a tile-shaped patch of the line missing for
  /// a frame, showing the pre-stroke pixels the painter's stale fallback
  /// answered with (the stale fallback landed 2026-07-05, the settle pin
  /// 2026-07-08, `ccafbd74` took the pin off this path 2026-07-23 — the
  /// "intermittent, since early July" of the report). The flush pictures
  /// every tile inside the call now, on every engine, so the handoff never
  /// misses and there is nothing to settle.
  void commitStroke() {
    final rasterizer = _state._liveRasterizer;
    final base = _state._overlay._overlayModel.preBlendBase;
    final blendMode =
        (_state._activeStrokeInputSettings ?? _state.widget.inputSettings())
            .blendMode;
    final erase = _state._overlay._overlayModel.erase;
    _state._liveRasterizer = null;
    if (rasterizer == null) {
      return;
    }
    final promotable = base != null && base.tileSize == rasterizer.tileSize;
    final sourceDabs = List.of(_state._collectedDabs);
    if (!promotable) {
      // Without promotion (a host whose overlay grid differs from its
      // surface's) the classic payload still commits correctly: a
      // bounds-local row-major stroke buffer the commit composites.
      _state.widget.onSourceStrokeCommitted(
        BrushStrokeCommitData(
          sourceDabs: sourceDabs,
          blendMode: blendMode,
          strokePixels: rasterizer.strokePixelsWithinBounds(),
          strokeBounds: rasterizer.strokeBounds,
          // F-12: the ceiling the live overlay has been drawing THROUGH —
          // the buffer route is exactly where it has not been applied yet.
          strokeOpacity: rasterizer.strokeOpacity,
        ),
      );
      rasterizer.clear();
      _state._overlay.resetOverlay();
      return;
    }
    final promoted = rasterizer.promoteStrokeTiles(
      base: base,
      mode: blendMode,
      erase: erase,
    );
    rasterizer.clear();
    landPromoted(
      promoted,
      BrushStrokeCommitData(
        sourceDabs: sourceDabs,
        // BB-1: the stroke's blend rides the payload — captured from the
        // stroke's settings SNAPSHOT, so a tool change can never flip a
        // committed stroke's mode.
        blendMode: blendMode,
        promotedBase: base,
        promotedTiles: [
          for (final entry in promoted) (coord: entry.coord, tile: entry.tile),
        ],
        // F-12: promoted tiles already carry the ceiling (it is folded into
        // the mask the pre-blend runs), and the commit's promotion path
        // installs them untouched.
        // ⚠️The payload carries it ALL THE SAME: every route that does not
        // install these tiles re-derives the stroke from its dabs — the
        // commit when the surface moved under it, and 확정 laying the stroke
        // down on another cel (confirm-button) — and a stroke re-derived
        // without its ceiling lands at full strength.
        strokeOpacity: rasterizer.strokeOpacity,
      ),
    );
  }

  /// 🚨★★★THE ONE LANDING OF PROMOTED TILES — a stroke's at pen-up, a
  /// fill's after its tap frame (`promoteFillDab`): hand each committed
  /// tile the overlay image that shows exactly its pixels, commit, drop
  /// the overlay — all in this one call, so the very next frame paints
  /// committed tiles that already have their pictures and not one byte on
  /// screen changes.
  ///
  /// The handoff is revision-gated (only an image at the promoted tile's
  /// own revision qualifies; a stale one would be pinned to that tile
  /// forever). The flush pictures every tile inside the call, so every
  /// promoted tile has one; a tile whose image is somehow not there — a
  /// coordinate the flush never touched at this revision — is pictured
  /// from its own bytes on the spot, through the same door. Either way the
  /// committed tile has its picture before the commit is announced, and
  /// the overlay is dropped in the same call.
  void landPromoted(
    List<PromotedStrokeTile> promoted,
    BrushStrokeCommitData data,
  ) {
    final overlay = _state._overlay._overlayModel;
    for (final entry in promoted) {
      final image = overlay.takeTileImageAt(
        entry.coord,
        revision: entry.revision,
      );
      if (image != null) {
        BitmapTileImageCache.instance.adoptDecoded(entry.tile, image);
      } else {
        BitmapTileImageCache.instance.pictureFor(entry.tile);
      }
    }
    _state.widget.onSourceStrokeCommitted(data);
    // Atomic: the overlay's remaining images retire in the same
    // notification that reveals the committed tiles.
    _state._overlay.resetOverlay();
  }

  /// Spacing for the segment about to be interpolated.
  ///
  /// Clip Studio rolls its interval randomness per dab. The interpolator is
  /// pure and shared, and a segment between two pointer samples almost
  /// always yields one or two dabs (it returns nothing at all when the move
  /// is shorter than one step), so rolling once per segment lands in the
  /// same place without threading a random source through it.
  double get activeStrokeSpacing {
    final settings =
        _state._activeStrokeInputSettings ?? _state.widget.inputSettings();
    final jitter = settings.spacingJitter;
    if (jitter <= 0.0) {
      return settings.spacing;
    }
    return settings.spacing *
        (1.0 - jitter * _state._spacingRandom.nextDouble());
  }

  void endStrokeInput() {
    _state.widget.onActiveStrokeChanged?.call(false);
    clearStrokeInputState();
  }

  /// State-only stroke teardown — safe inside the build phase (no
  /// callbacks). [endStrokeInput] is the pointer-event variant that also
  /// notifies synchronously.
  void clearStrokeInputState() {
    _state._activeDrawingPointer = null;
    _state._touchStrokeDownPosition = null;
    _state._touchStrokeCommitted = false;
    _state._nextSequence = 0;
    _state._breakCurrentVisibleSegment = false;
    _state._previousRawCanvasPosition = null;
    _state._activeStrokeInputSettings = null;
    _waiting = null;
    _state._pressure.restInput();
    _state._strokeDynamics = null;
    _state._lastDirectionDegrees = null;
    _state._previousBaseDab = null;
    // Guides are re-read at the next pointer-down, so an axis moved between
    // strokes takes effect on the next one and never on this one.
    _state._snapSession = null;
    _state._symmetryTransforms = const [];
    // The reservoir is per stroke: a new stroke starts with a clean brush.
    _state._groundMixer = null;
    _state._groundSampler = null;
    _state._stabilizer = null;
    _state._lastPenPosition = null;
    _state._collectedDabs.clear();
    _state._pendingOverlayDabs.clear();
  }
}

/// One sample a stroke holds while it waits for its first pressure reading
/// ([_BrushEditStroke._waiting]).
typedef _WaitingSample = ({
  ({double azimuthDegrees, double altitude})? tilt,
  double speed,
  void Function() paint,
});
