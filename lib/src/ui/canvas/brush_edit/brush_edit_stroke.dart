part of '../interactive_brush_edit_canvas_view.dart';

/// THE STROKE — advancing it to the next point (through the guides that
/// snap it), the spacing the active brush wants, ending its input and
/// committing it — as its own object.
///
/// 🚨A collaborator carved out of `_InteractiveBrushEditCanvasViewState`
/// (the audit's SRP cut, 2026-09-02). It reaches the State through
/// `_state` and rebuilds through `_rebuild`.
class _BrushEditStroke {
  _BrushEditStroke(this._state);

  final _InteractiveBrushEditCanvasViewState _state;

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
    final clippedSegment = _state.widget.segmentClipper.clip(
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
            _state.widget.dabInterpolator.interpolate(
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
      _state.widget.dabInterpolator.interpolate(
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
  /// installing them — no re-blend of the whole stroke, no re-decode.
  ///
  /// The order is what makes it invisible: promote the tiles, hand each
  /// one the overlay image that shows exactly its pixels, commit, then
  /// drop the overlay — all inside this one pointer event, so the very
  /// next frame paints committed tiles that already have their pictures.
  ///
  /// ⚠️ EXCEPT for the tiles whose image is not there to hand over, and
  /// there are always some. The handoff is revision-gated, the revision is
  /// written inside the decode callback, and `_flushPendingOverlayDabs()`
  /// runs in this same synchronous handler — so a tile the final flush
  /// touched cannot have recorded its new revision yet. For those the
  /// settle window is still needed and still exists. Dropping the overlay
  /// for them instead is what left a tile-shaped patch of the line missing
  /// for a frame, showing the pre-stroke pixels the painter's stale
  /// fallback answers with.
  ///
  /// ⚠️ "Only on a rare miss" would be the comfortable thing to write here
  /// and it is false: on an ordinary two-segment stroke, 12 of 21 promoted
  /// coordinates miss. A stroke with nothing pending at pen-up does take
  /// the synchronous path, and that is pinned by a test — but the settle
  /// window is the common case, not the exception.
  ///
  /// ⚠️ And it covers only PART of the hole. What the overlay still holds
  /// is exactly the missed-WITH-an-older-image set, because
  /// `takeTileImageAt` removes the ones it hands over. A coordinate the
  /// final flush touched for the FIRST time was never decoded by the
  /// overlay either, so if the cel already had artwork there the stale
  /// fallback still answers with the pre-stroke tile: measured on a wide
  /// in-canvas fixture, 62 promoted and 50 still painting pre-stroke
  /// pixels. Closing that needs the painter to stop borrowing for the
  /// settling coordinates — a change to a painter three surfaces share.
  ///
  /// ⚠️ The dates, because they say this IS the user's report rather than
  /// a neighbour of it. The stale fallback landed 2026-07-05; the settle
  /// pin that covered pen-up landed 2026-07-08; `ccafbd74` took the pin
  /// off this path on 2026-07-23. So the hole existed for three days in
  /// early July, went away, and came back in late July — which is exactly
  /// the shape of "intermittent, since early July" that was reported. An
  /// earlier version of this comment said the report "goes back years" and
  /// concluded this was a different bug; the repository's first commit is
  /// 2026-06-02, so that was never possible.
  ///
  /// It only bites where the coordinate ALREADY holds decoded content —
  /// drawing over existing ink, or a second pass through the same tile. On
  /// blank paper the painter's per-pixel fallback draws the correct pixels.
  void commitStroke() {
    final rasterizer = _state._liveRasterizer;
    final base = _state._overlay._overlayModel.preBlendBase;
    final blendMode =
        (_state._activeStrokeInputSettings ?? _state.widget.inputSettings)
            .blendMode;
    final erase = _state._overlay._overlayModel.erase;
    _state._liveRasterizer = null;
    if (rasterizer == null) {
      return;
    }
    // Captured before `rasterizer.clear()`, which is what the settle
    // window needs to know WHICH tiles to wait on. Null there means every
    // tile of the cel.
    final strokeBounds = rasterizer.strokeBounds;
    var missedHandoff = false;
    final promotable = base != null && base.tileSize == rasterizer.tileSize;
    final promoted = promotable
        ? rasterizer.promoteStrokeTiles(
            base: base,
            mode: blendMode,
            erase: erase,
          )
        : const <PromotedStrokeTile>[];
    if (promotable) {
      // Hand the decoded images over BEFORE the commit: the painter must
      // never see an adopted tile without a picture (that is a frame of
      // stale content — the flicker the settle machinery existed for).
      // Only images at the promoted tile's own revision qualify; a
      // stale one would be pinned to that tile forever.
      for (final entry in promoted) {
        final image = _state._overlay._overlayModel.takeTileImageAt(
          entry.tile.coord,
          revision: entry.revision,
        );
        if (image != null) {
          BitmapTileImageCache.instance.adoptDecoded(
            entry.tile,
            image,
            staleScope: (_state.widget.layerId, _state.widget.frameId),
          );
        } else {
          // Its decode never landed (or landed a revision behind): start
          // one now, and REMEMBER, because the overlay must not be dropped
          // while this coordinate has no picture.
          //
          // ⚠️ The sentence that used to be here — "the coordinate was
          // showing base pixels anyway, so this is a continuation, not a
          // regression" — is the false step that made this look benign.
          // Once `_resetOverlay()` runs, base pixels ARE the regression:
          // the committed tile has no image, so the painter's stale
          // fallback answers with the PRE-STROKE tile and the stroke is
          // missing in a tile-shaped patch.
          //
          // And this is not a rare race. `_flushPendingOverlayDabs()` and
          // `commitStroke()` run in one synchronous handler, and the
          // revision is recorded inside the decode CALLBACK, so a tile the
          // final flush touched cannot possibly have recorded its new
          // revision by the time `takeTileImageAt` compares — the miss is
          // guaranteed for exactly those tiles. With a stabilizer the
          // catch-up segment guarantees that flush has fresh dabs, so it
          // is guaranteed to happen at all.
          missedHandoff = true;
          // What the overlay still holds here is covering for a COMMITTED
          // tile now, not for the stroke. Saying so is what lets it
          // outlive the stroke: the next pen-down must not take it away
          // before its committed tile can paint.
          _state._overlay._overlayModel.markStandIn(entry.tile.coord);
          BitmapTileImageCache.instance.ensureDecoded(
            entry.tile,
            staleScope: (_state.widget.layerId, _state.widget.frameId),
          );
        }
      }
    }
    _state.widget.onSourceStrokeCommitted(
      BrushStrokeCommitData(
        sourceDabs: List.of(_state._collectedDabs),
        // BB-1: the stroke's blend rides the payload — captured from the
        // stroke's settings SNAPSHOT, so a tool change can never flip a
        // committed stroke's mode.
        blendMode: blendMode,
        promotedBase: promotable ? base : null,
        promotedTiles: promotable
            ? [for (final entry in promoted) entry.tile]
            : null,
        // Without promotion (a host whose overlay grid differs from its
        // surface's) the classic payload still commits correctly: a
        // bounds-local row-major stroke buffer the commit composites.
        strokePixels: promotable ? null : rasterizer.strokePixelsWithinBounds(),
        strokeBounds: promotable ? null : rasterizer.strokeBounds,
        // F-12: the ceiling the live overlay has been drawing THROUGH.
        // Promoted tiles already carry it (it is folded into the mask the
        // pre-blend runs), and the commit's promotion path installs them
        // untouched — so this reaches the buffer route only, which is
        // exactly where the ceiling has not been applied yet.
        strokeOpacity: rasterizer.strokeOpacity,
      ),
    );
    rasterizer.clear();
    if (missedHandoff) {
      // At least one promoted tile went to the committed surface without a
      // picture, so dropping the overlay now would show the pre-stroke
      // tile in its place. The overlay STILL HOLDS that coordinate's image
      // — `takeTileImageAt` removes only the ones that matched — one
      // revision behind, which is the stroke minus its last few dabs
      // rather than nothing. Keep it up until the committed tiles decode;
      // `_onTileImagesChanged` releases on `allDecoded`, and the 2s
      // deadline is the backstop.
      //
      // Bounds passed EXPLICITLY: `_settlingTiles()` falls back to every
      // tile of the cel when `_settlingBounds` is null, which would make a
      // one-tile stroke wait on the whole canvas.
      _state._settlingBounds = strokeBounds;
      _state._beginSettling();
      return;
    }
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
        _state._activeStrokeInputSettings ?? _state.widget.inputSettings;
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
    _state._currentPressure = 1.0;
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
