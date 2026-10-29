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

  /// A stroke begins under [event]: the pointer is ours, the settings are
  /// the tool's (or the eraser's on a mapped tail), the stabiliser, the
  /// snap session, the symmetry, the dynamics and the ground mixer are
  /// armed, the overlay opens, and the first dabs go out — from
  /// [_onTheShiftLine] of [pressed].
  void beginStroke(
    PointerDownEvent event,
    CanvasPoint pressed, {
    required bool mappedErase,
  }) {
    _state._activeDrawingPointer = event.pointer;
    final canvasPosition = _onTheShiftLine(pressed);
    final startsInsidePasteboard = _state._isInsidePasteboard(canvasPosition);
    // PEN-12 #4: a TOUCH stroke starts UNCOMMITTED — until it crosses the
    // touch slop a simultaneous second finger may still turn the pair
    // into navigation (cancelling only an invisible dot); once committed
    // the stroke owns the screen and extra fingers are ignored.
    _state._touchStrokeDownPosition = event.kind == PointerDeviceKind.touch
        ? event.localPosition
        : null;
    _state._touchStrokeCommitted = false;
    final strokeSettings = _settingsOfAPress(mappedErase: mappedErase);
    _state._activeStrokeInputSettings = strokeSettings;
    _state._opening.startContact(
      _state._pressure.noteSample(event, opening: true),
    );
    _arm(
      strokeSettings,
      at: canvasPosition,
      startsInsidePasteboard: startsInsidePasteboard,
      // ONE PRESS, ONE ROLL OF THE DICE: the stroke's spacing, scatter and
      // jitter come from its press, so every view that hears the press
      // rolls the same numbers. ↩️Written for a sheet's windows each
      // drawing their own slice of one stroke (one paper, 유저 2026-09-25);
      // a stroke is one window's now (H49, 09-30), and the press still
      // decides its dice.
      dice: Object.hash(event.pointer, event.timeStamp),
    );
    // A press off the pasteboard lays nothing down; the stroke's first dab
    // comes where a move crosses in. The line starts steadying either way,
    // when the press is painted: with the readings it is painted with, the
    // first a held press waited for and not the stand-in it was taken with
    // — and the line the pen draws starts there with them.
    _state._opening.press(
      () {
        _startSteadying(
          strokeSettings,
          at: canvasPosition,
          startedAt: event.timeStamp,
        );
        _state._drawn = [(position: canvasPosition, readings: _readings)];
        if (startsInsidePasteboard) {
          _paintPress(canvasPosition);
        }
      },
      at: event.timeStamp,
      position: canvasPosition,
    );
  }

  /// The stroke's settings snapshot — every downstream dab reads it, so
  /// the mapped-eraser substitution here flips the WHOLE stroke. The
  /// substitution forces the BLEND to erase too (R27 #4 in passing): the
  /// eraser tool locks its mode, but this path kept the brush's — a
  /// mapped-erase press with a separable brush blend would have taken
  /// the commit's blend branch and PAINTED instead of erasing.
  BrushEditCanvasInputSettings _settingsOfAPress({required bool mappedErase}) {
    final settings = _state.widget.inputSettings();
    return mappedErase
        ? settings.copyWith(erase: true, blendMode: BrushBlendMode.erase)
        : settings;
  }

  /// [pressed] on the line the hold kept, where the pen's press falls across
  /// it ([ShiftLine], I-121) — or as it is, with Shift let go or no line
  /// kept. Asked once the pen is the stroke's, so the finger drawing it is
  /// no Shift.
  CanvasPoint _onTheShiftLine(CanvasPoint pressed) {
    final line = _state.widget.shiftLine?..heldNow(_state._press.shiftHeld);
    return line?.onTheLine(pressed, space: _state.widget.guideSpace) ??
        pressed;
  }

  /// The pointer a stroke the TOOL lays wears: none of a real pointer's
  /// numbers, which count up from zero.
  static const int _toolsOwnStroke = -1;

  /// A stroke the TOOL lays (I-69) OPENS: the brush's settings are taken,
  /// and the overlay opens in its blend. No pointer is under it and no pen:
  /// it is laid at the one pressure its start is given ([startToolStrokeAt]).
  ///
  /// 🚨Open is not IN FLIGHT. A shape the hand is still dragging is laid
  /// under its outline as this stroke ([_BrushEditShapeShow]) and is no
  /// stroke yet — the host hears nothing, and a save lands nothing of it,
  /// as it lands nothing of a dragged area — until it lands
  /// ([flyToolStroke]).
  void openToolStroke() {
    final strokeSettings = _state.widget.inputSettings();
    _state._activeStrokeInputSettings = strokeSettings;
    _openOverlay(strokeSettings);
  }

  /// The open stroke STARTS at [canvasPosition] — and starts again from
  /// nothing there for a dragged shape's newest path, while its last is
  /// still on screen (I-69-Q4ⓒ): what it stands on is made afresh
  /// ([_armItsOwn]) and what it laid goes — its dabs, those queued, its
  /// rasterized tiles. Nothing on screen does.
  ///
  /// Nothing is laid here. Its first dab is its first advance's, which
  /// finds no dab before it and lays the start of its segment, turned the
  /// way the segment runs ([advanceStrokeTo]). A pen's press lays a dab of
  /// its own because a pen that never moves has still pressed; a path
  /// always goes on.
  ///
  /// ⚠️Nothing steadies it and nothing snaps it, and not because anything
  /// here says so: its points go straight to [advanceStrokeTo], past the
  /// stabiliser and the perspective snap a pen's samples pass through
  /// ([takeSample], [advanceStrokeThroughGuides]). A stroke the tool lays
  /// goes where it was told.
  ///
  /// Every dab of it reads [pressure], as a pen held at it the whole way
  /// would: full for a shape, which no pen pressed, and the last stroke's
  /// for the line from it ([ShapeShow.landStroke]).
  void startToolStrokeAt(
    CanvasPoint canvasPosition, {
    required int dice,
    required double pressure,
  }) {
    _armItsOwn(
      _state._activeStrokeInputSettings!,
      at: canvasPosition,
      startsInsidePasteboard: _state._isInsidePasteboard(canvasPosition),
      dice: dice,
    );
    _state._readings = _state._readings.withPressure(pressure);
    _state._pendingOverlayDabs.clear();
    _state._prepareLiveRasterizer();
  }

  /// The tool's stroke goes IN FLIGHT: [_toolsOwnStroke] stands in for the
  /// pointer and the host hears of it — for the length of the ONE call
  /// that lands it ([_BrushEditPress.landActiveStroke], which asks whether
  /// a stroke is in flight by asking for its pointer; no pointer event is
  /// heard in between).
  void flyToolStroke() {
    _state._activeDrawingPointer = _toolsOwnStroke;
    _state._touchStrokeDownPosition = null;
    _state._touchStrokeCommitted = false;
    _state.widget.onActiveStrokeChanged?.call(
      StrokeInFlight.of(_state._activeStrokeInputSettings!),
    );
  }

  /// THE PEN'S STROKE IS ARMED — everything it stands on before its first
  /// dab: the host hears that one is in flight, the snap, the symmetry, the
  /// dynamics and the ground mixer are made for it from [strokeSettings],
  /// and the overlay opens in its blend. The stabiliser starts on the press
  /// ([_startSteadying]).
  void _arm(
    BrushEditCanvasInputSettings strokeSettings, {
    required CanvasPoint at,
    required bool startsInsidePasteboard,
    required int dice,
  }) {
    _state.widget.onActiveStrokeChanged?.call(
      StrokeInFlight.of(strokeSettings),
    );
    _armAfresh(
      strokeSettings,
      at: at,
      startsInsidePasteboard: startsInsidePasteboard,
      dice: dice,
    );
  }

  /// The pen's stroke stands on nothing yet at [at]: what is its own is made
  /// afresh, the overlay opens on the cel as it stands, and the live tiles
  /// and the dabs queued for them go — at the press, and again for a line
  /// laid anew along its 後補正 ([postCorrect]), which the host still sees
  /// as the one stroke it heard of.
  void _armAfresh(
    BrushEditCanvasInputSettings strokeSettings, {
    required CanvasPoint at,
    required bool startsInsidePasteboard,
    required int dice,
  }) {
    _armItsOwn(
      strokeSettings,
      at: at,
      startsInsidePasteboard: startsInsidePasteboard,
      dice: dice,
    );
    _openOverlay(strokeSettings);
    _state._pendingOverlayDabs.clear();
    _state._prepareLiveRasterizer();
  }

  /// The overlay opened for a stroke in [strokeSettings]' blend, on the cel
  /// as it stands.
  void _openOverlay(BrushEditCanvasInputSettings strokeSettings) {
    _state._overlay.beginStrokeOverlay();
    // Overlay stroke configuration AFTER the reset — reset() clears
    // preBlendBase, so setting it earlier silently disabled the whole
    // pre-blend pipeline for real pointer strokes (the R27 #4 ordering
    // bug: every parity test staged the model manually and never caught
    // it). The overlay must display in the stroke's blend mode from the
    // first dab.
    final strokeSurface = _state.widget.celNow();
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
  }

  /// What a stroke stands on that is its OWN — the snap, the symmetry, the
  /// dice, the dynamics, the ground mixer, the dabs laid so far — made
  /// afresh from [strokeSettings]. The stabiliser is the pen's
  /// ([_startSteadying]).
  void _armItsOwn(
    BrushEditCanvasInputSettings strokeSettings, {
    required CanvasPoint at,
    required bool startsInsidePasteboard,
    required int dice,
  }) {
    final canvasPosition = at;
    _state._strokeDice = dice;
    _state._nextSequence = 0;
    _state._breakCurrentVisibleSegment = !startsInsidePasteboard;
    _state._previousRawCanvasPosition = canvasPosition;
    // Guides are read ONCE per stroke. Both are frozen here rather than
    // consulted per sample so an edit landing mid-stroke cannot bend the
    // line that is already down.
    _state._strokeLock = StrokeLock(
      guides: _state.widget.guides,
      start: canvasPosition,
      zoom: _state.widget.viewport.zoom,
      space: _state.widget.guideSpace,
      line: _state.widget.shiftLine,
    );
    final symmetry = _state.widget.guides.actingSymmetry;
    _state._symmetryTransforms = symmetry == null
        ? const []
        : symmetryCopiesIn(_state.widget.guideSpace, symmetry);
    _state._spacingRandom = math.Random(dice);
    _state._secondStroke = BrushSecondStroke.of(strokeSettings.shape);
    _state._inputRandom = math.Random(dice + 3);
    _state._strokeDynamics = BrushStrokeDynamics(
      settings: strokeSettings,
      random: math.Random(dice + 2),
      tipRandom: math.Random(dice + 4),
    );
    _state._lastDirectionDegrees = null;
    _state._previousBaseDab = null;
    final mixer = BrushGroundColorMixer(shape: strokeSettings.shape);
    _state._groundMixer = mixer.isActive ? mixer : null;
    _state._groundSampler = _state._groundMixer == null
        ? null
        : bitmapSurfaceGroundSampler(_state.widget.celNow());
    _state._collectedDabs.clear();
  }

  /// One pen sample for the stroke: painted now — or, while the stroke
  /// waits for its first readings ([_BrushEditOpening.holds]), held with
  /// the others until they come. [read] is what
  /// [_BrushEditPressure.noteSample] answered for it.
  void takeSample(
    CanvasPoint penPosition, {
    required Duration at,
    required ({bool pressure, bool speed}) read,
  }) {
    // The stabilizer smooths BEFORE clipping/interpolation, so every
    // downstream consumer (overlay, commit, replay) sees one chain — the
    // three-route parity holds by construction (P7). A held sample reaches
    // it when it is painted, in the order it came, at the time it came,
    // with the readings it is painted with.
    void paint() {
      final stabilizer = _state._stabilizer;
      if (stabilizer == null) {
        advanceStrokeThroughGuides(penPosition);
        return;
      }
      _paintSteadied(stabilizer.follow(penPosition, _readings, at: at));
      _keepSteadying();
    }
    if (_state._opening.holds(
      paint,
      penPosition: penPosition,
      at: at,
      read: read,
    )) {
      return;
    }
    paint();
  }

  /// The pen's line starts steadying at [at], on the press — or steadies
  /// nothing, for a brush that corrects nothing (F-418).
  void _startSteadying(
    BrushEditCanvasInputSettings strokeSettings, {
    required CanvasPoint at,
    required Duration startedAt,
  }) {
    final correction = strokeSettings.shape.correction;
    _state._stabilizer = correction.steadies
        ? StrokeStabilizer(
            lagAt: correction.lagAt,
            start: (position: at, readings: _readings),
            at: startedAt,
            keepsCorners: correction.sharpenCorners,
          )
        : null;
  }

  /// What the pen reads now.
  PenReadings get _readings => _state._readings;

  /// Runs [paint] with [readings] standing for the pen's, and puts the
  /// pen's own back after — THE way a stroke lays what was read elsewhere
  /// than where the pen is now: a sample that waited for its first readings
  /// ([_BrushEditOpening._paintWaiting]), the steadied line behind the pen
  /// ([_paintSteadied]), the line its 後補正 lays anew ([postCorrect]).
  void paintReading(PenReadings readings, void Function() paint) {
    final pen = _state._readings;
    _state._readings = readings;
    paint();
    _state._readings = pen;
  }

  /// Lays the line the [way] it went, with what it reads along it.
  void _paintSteadied(List<PenPoint> way) {
    for (final point in way) {
      paintReading(
        point.readings,
        () => advanceStrokeThroughGuides(point.position),
      );
    }
  }

  /// While the line has not reached the pen, frames move it on — Clip
  /// Studio's line keeps going while the pen rests (F-418).
  void _keepSteadying() {
    if (_state._steadyingFrameAsked || (_state._stabilizer?.settled ?? true)) {
      return;
    }
    _state._steadyingFrameAsked = true;
    SchedulerBinding.instance.scheduleFrameCallback(_steadyOneFrame);
  }

  void _steadyOneFrame(Duration frameAt) {
    _state._steadyingFrameAsked = false;
    final stabilizer = _state._stabilizer;
    if (!_state.mounted || stabilizer == null) {
      return;
    }
    final moved = stabilizer.lookAtFrame(frameAt);
    if (moved.isNotEmpty) {
      _paintSteadied(moved);
      // On screen THIS frame: the queue's own flush may have run already.
      _state._overlay.flushPendingOverlayDabs();
    }
    _keepSteadying();
  }

  /// The pen lifted: the line goes straight to where it was (F-418-Q2).
  void finishSteadying() {
    _paintSteadied(_state._stabilizer?.finish() ?? const []);
  }

  /// 後補正: the line the pen drew, its wobble taken out, laid again as this
  /// same stroke — from nothing, on its own dice, so its scatter and jitter
  /// roll as they did — before it lands.
  ///
  /// 🗣️유저 2026-10-20 (F-418-Q7 「뗄 때 다듬은 선으로 바뀐다」): the line
  /// on screen while it is drawn is the steadied one, and the pen-up puts
  /// the smoothed one in its place. ⚠️The one stroke that lands other than
  /// it was shown, by that answer — and still in one turn: what is shown
  /// next is what landed.
  ///
  /// Nothing happens for a brush that takes nothing out, nor for a stroke
  /// the tool lays — it draws no line of the pen's ([_state._drawn]).
  void postCorrect() {
    final drawn = _state._drawn;
    _state._drawn = null;
    final settings = _state._activeStrokeInputSettings;
    if (drawn == null || settings == null) {
      return;
    }
    final correction = settings.shape.correction;
    final within = correction.postWithin(
      zoom: _state.widget.viewport.zoom,
      speed:
          drawn.fold(0.0, (sum, point) => sum + point.readings.speed) /
          drawn.length,
    );
    if (within == null) {
      return;
    }
    final line = postCorrected(
      drawn,
      within: within,
      bezier: correction.postBezier,
      keepCorners: correction.sharpenCorners,
    );
    if (identical(line, drawn)) {
      return;
    }
    final start = line.first;
    final startsInsidePasteboard = _state._isInsidePasteboard(start.position);
    _armAfresh(
      settings,
      at: start.position,
      startsInsidePasteboard: startsInsidePasteboard,
      dice: _state._strokeDice,
    );
    if (startsInsidePasteboard) {
      paintReading(start.readings, () => _paintPress(start.position));
    }
    for (final point in line.skip(1)) {
      paintReading(point.readings, () => advanceStrokeTo(point.position));
    }
  }

  /// The stroke's FIRST dab, under the press.
  void _paintPress(CanvasPoint canvasPosition) {
    final initialDabs = _state._pressure.withPressureDynamics(
      _interpolateTo(
        null,
        canvasPosition,
        sequence: _state._nextSequence,
      ),
    );
    if (initialDabs.isNotEmpty) {
      _state._previousBaseDab = initialDabs.last;
    }
    // R20-B: dabs resolve through the tip-stamp cache HERE, at generation
    // — the overlay, the commit, undo replay and the .anicel all see the
    // same resolved dabs (an analytic tip quantized into a prerotated mask,
    // a raster tip as it is — F-251).
    //
    // ⚠️ Symmetry replicates HERE TOO. This is the stroke's FIRST dab, laid
    // at pointer-down rather than through [advanceStrokeTo], and it is a
    // separate emission site — replicating only the move path left every
    // symmetric stroke's copies one dab short at the start, a notch right
    // where the pen landed.
    final emitted = BrushTipStampCache.instance.resolveDabs(
      replicateDabs(
        _withSecondTip(
          _state._withGroundMixing(
            _state._strokeDynamics!.apply(
              initialDabs,
              firstSequence: _state._nextSequence,
              // Which way the stroke set off, once a move has said so; a tap
              // that never moved has no direction to follow.
              directionDegrees: _state._opening.pressDirection,
            ),
          ),
          path: initialDabs,
        ),
        _state._symmetryTransforms,
        firstSequence: _state._nextSequence,
      ),
    );
    _lay(emitted);
  }

  /// [firstTip] with the second tip's stroke along [path] behind it — the
  /// first tip's dabs before the dynamics placed them ([BrushSecondStroke]).
  /// Symmetry copies both, as one emission.
  List<BrushDab> _withSecondTip(
    List<BrushDab> firstTip, {
    required List<BrushDab> path,
  }) {
    final second = _state._secondStroke;
    if (second == null) {
      return firstTip;
    }
    return [
      ...firstTip,
      ...second.follow(
        path,
        firstSequence: _state._nextSequence + firstTip.length,
      ),
    ];
  }

  /// Puts [emitted] on the stroke: collected for the commit, queued for the
  /// overlay, numbered.
  void _lay(List<BrushDab> emitted) {
    _state._collectedDabs.addAll(emitted);
    debugStrokeDabsLaid?.addAll(emitted);
    _state._overlay.queueOverlayDabs(emitted);
    _state._nextSequence += emitted.length;
  }

  /// Stabilized point → the stroke's lock → the stroke.
  ///
  /// Smoothing runs first because smoothing a snapped line would bend the
  /// straightness back out of it. The lock can return NOTHING while it is
  /// still deciding which ray this stroke belongs to; those points are held
  /// inside it and arrive together the moment it locks.
  ///
  /// 🗣️I-61: Shift held is the stroke's 45° lock (I-61-Q1 · Q2) — asked
  /// HERE as the stroke goes, and at its press only for the line a hold
  /// kept ([beginStroke], I-121): of the keyboard, and of a finger resting
  /// on the glass where the switch says so (I-61-Q3,
  /// [_BrushEditPress.shiftHeld]).
  ///
  /// 🚨The keyboard through [ModifierKeys], whatever draws: a pen's stroke
  /// on Windows never locked while the engine's own record said Shift was
  /// let go at its first move (유저 2026-10-16: 「마우스로는 작동하는거
  /// 확인했는데 왜 펜으로는 작동안하는지?」).
  void advanceStrokeThroughGuides(CanvasPoint canvasPosition) {
    final lock = _state._strokeLock;
    if (lock == null) {
      advanceStrokeTo(canvasPosition);
      return;
    }
    for (final locked in lock.follow(
      canvasPosition,
      shift: _state._press.shiftHeld,
    )) {
      advanceStrokeTo(locked);
    }
  }

  void advanceStrokeTo(CanvasPoint canvasPosition) {
    _state._drawn?.add((position: canvasPosition, readings: _readings));
    final previousRaw = _state._previousRawCanvasPosition;
    _state._previousRawCanvasPosition = canvasPosition;
    if (previousRaw == null) {
      return;
    }

    final clippedSegment = const CanvasSegmentClipper().clip(
      previous: previousRaw,
      current: canvasPosition,
      wall: _state.widget.celNow().pasteboard,
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
            _interpolateTo(
              null,
              clippedSegment.start,
              sequence: _state._nextSequence,
            ),
          )
        : const <BrushDab>[];
    final firstEndSequence = _state._nextSequence + segmentStartDabs.length;
    final endPrevious = segmentStartDabs.isNotEmpty
        ? segmentStartDabs.last
        : previousDab;
    final segmentEndDabs = _state._pressure.withPressureDynamics(
      _interpolateTo(
        endPrevious,
        clippedSegment.end,
        sequence: firstEndSequence,
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
        _withSecondTip(
          _state._withGroundMixing(
            _state._strokeDynamics?.apply(
                  baseDabs,
                  firstSequence: _state._nextSequence,
                  directionDegrees: _state._lastDirectionDegrees,
                ) ??
                baseDabs,
          ),
          path: baseDabs,
        ),
        _state._symmetryTransforms,
        firstSequence: _state._nextSequence,
      ),
    );

    // No setState: pointer moves only QUEUE the new dabs (this runs at
    // pointer-sample frequency); the per-frame flush rasterizes the batch
    // and repaints the overlay layer directly, skipping widget rebuilds.
    _lay(emitted);
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
    // Where the line went last — through the lock, the stabiliser's catch-up
    // and the tool's waypoints alike — and so where the next line from the
    // last stroke starts (I-119).
    final end = _state._previousRawCanvasPosition;
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
          end: end,
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
        end: end,
      ),
    );
  }

  /// 🚨★★★THE ONE LANDING OF PROMOTED TILES — a stroke's at pen-up, a
  /// fill's after its tap frame (`promoteFillDabs`): hand each committed
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
      // ★The tile the coordinate SHOWS once this lands — the committed tile,
      // or it with the cel's texts laid over (R9-rest): the overlay has
      // been showing exactly that tile's pixels, so that is the tile its
      // picture belongs to. Handed to the committed tile instead, a picture
      // holding letters would stand for the bare drawing — and go on
      // showing them after the text was moved or deleted.
      final shown = overlay.tileShownFor(entry.coord, entry.tile);
      final image = overlay.takeTileImageAt(
        entry.coord,
        revision: entry.revision,
      );
      if (image != null) {
        BitmapTileImageCache.instance.adoptDecoded(shown, image);
      } else {
        BitmapTileImageCache.instance.pictureFor(shown);
      }
    }
    _state.widget.onSourceStrokeCommitted(data);
    // Atomic: the overlay's remaining images retire in the same
    // notification that reveals the committed tiles.
    _state._overlay.resetOverlay();
  }

  /// The base dabs from [previous] to a reading at [at], stepped by the
  /// spacing that reading asks for ([spacingAt]).
  List<BrushDab> _interpolateTo(
    BrushDab? previous,
    CanvasPoint at, {
    required int sequence,
  }) {
    final reading = _state._dabFromPosition(at, sequence: sequence);
    return const BrushDabInterpolator().interpolate(
      previous: previous,
      nextRaw: reading,
      firstSequence: sequence,
      spacingRatio: spacingAt(reading),
    );
  }

  /// Spacing for the segment that ends at [reading] ([brushSpacingFor]),
  /// thrown with the stroke's spacing dice.
  ///
  /// Clip Studio rolls its interval randomness per dab. The interpolator is
  /// pure and shared, and a segment between two pointer samples almost
  /// always yields one or two dabs (it returns nothing at all when the move
  /// is shorter than one step), so rolling once per segment lands in the
  /// same place without threading a random source through it.
  double spacingAt(BrushDab reading) => brushSpacingFor(
    reading,
    (_state._activeStrokeInputSettings ?? _state.widget.inputSettings())
        .shape,
    random: _state._spacingRandom,
  );

  void endStrokeInput() {
    _state.widget.onActiveStrokeChanged?.call(StrokeInFlight.none);
    _state._pressure.reportReadings();
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
    _state._opening.clear();
    _state._pressure.restInput();
    _state._strokeDynamics = null;
    _state._secondStroke = null;
    _state._lastDirectionDegrees = null;
    _state._previousBaseDab = null;
    // Guides are re-read at the next pointer-down, so an axis moved between
    // strokes takes effect on the next one and never on this one.
    _state._strokeLock = null;
    _state._symmetryTransforms = const [];
    // The reservoir is per stroke: a new stroke starts with a clean brush.
    _state._groundMixer = null;
    _state._groundSampler = null;
    _state._stabilizer = null;
    _state._drawn = null;
    _state._collectedDabs.clear();
    _state._pendingOverlayDabs.clear();
  }
}
