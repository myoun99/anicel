part of '../interactive_brush_edit_canvas_view.dart';

/// WHAT A POINTER MEANS HERE — the touch census that turns a second
/// finger into navigation, the mapped button that pans or undoes or holds
/// a tool, the Alt pick, the fill tap, and the press that is none of
/// those and therefore starts a stroke.
///
/// 🚨A collaborator carved out of `_InteractiveBrushEditCanvasViewState`
/// (the audit's SRP cut, Round 7, 2026-09-05). The four `Listener`
/// callbacks and the shared multi-touch listener are its entry points; it
/// reaches the view through `_state`.
///
/// ⚠️It owns the three fields NOTHING else read — the live touch
/// contacts, the navigation latch and the Alt-pick pointer. The rest
/// (`_activeDrawingPointer`, the touch-stroke pair, the fill tap slot)
/// stay on the State because the stroke, overlay and fill collaborators
/// read them too.
class _BrushEditPress {
  _BrushEditPress(this._state);

  final _InteractiveBrushEditCanvasViewState _state;

  /// Live touch contacts. A second finger switches the interaction to
  /// viewport navigation (handled by the panel's gesture layer): the
  /// in-progress stroke is cancelled without committing, and no new stroke
  /// starts until every finger lifts — a quick pinch never leaves marks.
  final Set<int> _activeTouchPointers = <int>{};
  bool _multiTouchNavigation = false;

  /// R26 #5: a second finger landed SOMEWHERE on the ink surfaces — maybe
  /// on a sibling view, whose pointer this view will never see. A live
  /// sub-slop touch stroke here is really the first half of a pinch, so
  /// it stands down exactly as it would for a local second contact.
  void handleSharedMultiTouch() {
    final drawingPointer = _state._activeDrawingPointer;
    if (drawingPointer == null ||
        !_activeTouchPointers.contains(drawingPointer)) {
      return; // No touch stroke here (a pen stroke keeps drawing).
    }
    if (_state._touchStrokeCommitted) {
      return; // A committed line survives extra fingers (PEN-12 #4).
    }
    _multiTouchNavigation = true;
    _state._stroke.endStrokeInput();
    _state._overlay.resetOverlay();
  }

  /// The APP-WIDE touch census's verdict on this press: true when it takes
  /// the press and nothing further down happens.
  bool _touchCensusTakesThePress(PointerDownEvent event) {
    if (event.kind != PointerDeviceKind.touch) {
      return false;
    }
    // PEN-12 #4: a finger draws exactly when the ONE-FINGER touch slot
    // says draw (the old control/draw mode collapsed into the slot);
    // otherwise the panel's gesture layer owns every touch.
    if (!AppInput.touchDraws) {
      return true;
    }
    _activeTouchPointers.add(event.pointer);
    CanvasTouchContacts.add(event.pointer);
    // R26 #5: the census is APP-WIDE — the timesheet mounts one ink
    // view per sheet window, so the second finger often lands on a
    // SIBLING view. Counting locally let both of them draw.
    if (CanvasTouchContacts.count < 2) {
      return false;
    }
    final drawingPointer = _state._activeDrawingPointer;
    final touchStroke =
        drawingPointer != null && _activeTouchPointers.contains(drawingPointer);
    // PEN-12 #4: a COMMITTED stroke survives extra fingers — palm
    // rests and habitual pinches must never vanish a live line. The
    // newcomer is simply ignored (no navigation, no modifier).
    if (touchStroke && _state._touchStrokeCommitted) {
      return true;
    }
    _multiTouchNavigation = true;
    // A waiting FILL tap goes with them, and for the same reason: the
    // first finger turned out to be the start of a pinch. Nothing was
    // drawn and nothing entered history, so this is a forget rather
    // than an undo — which is the whole point of making the fill wait.
    _state._fill.forgetFillTap();
    // Discard only a SUB-SLOP touch stroke — the first finger turned
    // out to be the start of a pinch, not a stroke (both fingers
    // landed together). A stylus/mouse stroke keeps drawing: extra
    // touch contacts alongside it are palm rests.
    if (touchStroke) {
      _state._stroke.endStrokeInput();
      _state._overlay.resetOverlay();
    }
    return true;
  }

  void pointerDown(PointerDownEvent event) {
    // (No deferred stroke commit to land first: pen-up commits inside its
    // own event now — R25-④'s one-frame deferral existed to hide a
    // synchronous re-materialize that the promotion round deleted.)
    if (_touchCensusTakesThePress(event)) {
      return;
    }

    if (!_state.widget.editable) {
      _state._celPress.pressAsksForACel(event);
      return;
    }

    // PEN-7a: the CANVAS mapping for standard secondary inputs. Pen
    // side/barrel buttons, the S-Pen button and the mouse right button
    // all arrive as the RIGHT-CLICK bit; the pen upper button and the
    // wheel click as the MIDDLE bit. On canvas the user assigns what
    // they do (Input Settings ▸ Canvas); everywhere else the OS meaning
    // of the input rules untouched. The hold temporarily switches the
    // TOOL (the shared tool-switch path — cursor/panels follow free);
    // release springs back or keeps it per the mapping.
    // The pen TAIL settles first: it is a state rather than a press, and
    // a live tail hold suppresses the button rows below. Its erase has to
    // reach this stroke's settings snapshot directly — the tool switch it
    // requests is asynchronous, and the stroke starts now.
    _state._overlay.syncPenTailMapping();
    var mappedErase = _state._overlay.penTailErases;
    final mapping = canvasMappingFor(
      event,
      penTailActive: _state._penTailActive,
    );
    if (mapping != null) {
      if (_multiTouchNavigation ||
          _state._activeDrawingPointer != null ||
          _state._hold._mappedHoldPointer != null) {
        return;
      }
      _actOnMappedPress(mapping, event);
      if (!canvasMappedActionDraws(mapping.action)) {
        return;
      }
      mappedErase = true;
    }

    if (!mappedErase &&
        (_multiTouchNavigation ||
            _state._activeDrawingPointer != null ||
            !canvasPrimaryDown(canvasPressButtons(event)))) {
      return;
    }

    final canvasPosition = _state._canvasPositionFromLocal(event.localPosition);
    // The pasteboard is EVERY tool's input boundary (user feedback +
    // Flash parity): strokes, the eyedropper and fill taps all work on
    // off-canvas artwork; only the pasteboard wall stops them.
    final startsInsidePasteboard = _state._isInsidePasteboard(canvasPosition);

    // FILL tap (R22-A / R23, a stroke of one dab since 2026-09-17): the
    // flood's result tiles become the overlay's pictures on the tap frame,
    // and the commit itself DEFERS past it — the finished fill shows while
    // the commit's tile put runs behind a complete picture, and lands the
    // same tile objects with their pictures already made. (The R22-A
    // live-raster blend re-snapshotted and re-decoded thousands of 128px
    // overlay tiles — the 8K settle-frame stall.)
    if (_pressAsFillTap(
      event,
      canvasPosition,
      startsInsidePasteboard: startsInsidePasteboard,
    )) {
      return;
    }

    _state._stroke.beginStroke(
      event,
      canvasPosition,
      startsInsidePasteboard: startsInsidePasteboard,
      mappedErase: mappedErase,
    );
  }

  /// What a mapped button's press DOES on its way down: the history verbs
  /// fire, the eyedropper hold picks, the eraser hold takes the tool, and
  /// the pan is the panel's gesture layer's. Whether a stroke follows is
  /// not decided here — [canvasMappedActionDraws] says, for this press and
  /// for the empty cel that asks whether the press will draw.
  void _actOnMappedPress(
    CanvasPointerMapping mapping,
    PointerDownEvent event,
  ) {
    switch (mapping.action) {
      case CanvasPointerAction.none:
      // Pan belongs to the panel's viewport gesture layer — this view
      // only stands down so no stroke competes with it.
      case CanvasPointerAction.pan:
        break;
      case CanvasPointerAction.undo:
        // Skip when the button press already fired during hover (the
        // hover edge below) and the tip then touched with it held.
        if (!_state._hold.mappedButtonHeldSinceHover(event)) {
          _state.widget.onInvokeAction?.call('edit-undo');
        }
      case CanvasPointerAction.redo:
        if (!_state._hold.mappedButtonHeldSinceHover(event)) {
          _state.widget.onInvokeAction?.call('edit-redo');
        }
      case CanvasPointerAction.eyedropper:
        _state._hold._mappedHoldPointer = event.pointer;
        _state._hold._mappedHoldRelease = mapping.release;
        _state._hold._mappedHoldIsEyedropper = true;
        // The contact takes over a hover-engaged hold (R26 #19/#20):
        // one hold session, one release.
        _state._hold._hoverToolHoldActive = false;
        _state._hold._hoverToolHoldRelease = null;
        _state._hold._hoverToolHoldButton = 0;
        _state.widget.onTemporaryToolHold?.call(CanvasTool.eyedropper);
        final pickPosition = _state._canvasPositionFromLocal(
          event.localPosition,
        );
        // The eyedropper picks anywhere on the pasteboard, like Flash
        // (off-canvas artwork is real artwork).
        if (_state._isInsidePasteboard(pickPosition)) {
          _state.widget.onHoldPick?.call(pickPosition);
        }
      case CanvasPointerAction.eraser:
        _state._hold._mappedHoldPointer = event.pointer;
        _state._hold._mappedHoldRelease = mapping.release;
        _state._hold._mappedHoldIsEyedropper = false;
        _state.widget.onTemporaryToolHold?.call(CanvasTool.eraser);
    }
  }

  /// With the fill tool armed the press IS the fill: off the pasteboard
  /// it does nothing, on touch it waits for the release (a two-finger
  /// navigation may follow), else it runs at once. True when consumed.
  bool _pressAsFillTap(
    PointerDownEvent event,
    CanvasPoint canvasPosition, {
    required bool startsInsidePasteboard,
  }) {
    final fillDabAt = _state.widget.fillDabAt;
    if (fillDabAt != null) {
      // Off-canvas fill taps flow through: the default (stage-bounded)
      // raster answers null for them, the extended raster fills — the
      // fill's own boundary options decide, not the pointer.
      // The busy half of this used to be here too; it now lives in
      // [_runFillTap], which is the only place that can be sure.
      if (!startsInsidePasteboard) {
        return true;
      }
      // The seed and the axis come from the same pair the STROKE path uses
      // — this view's own position and its own guides, both already in the
      // space the pointer is in. Reading the symmetry from the project
      // instead would put the mirror where the pen is not under a pose.
      // 🚨★★★A TOUCH FILL RESOLVES ON THE LIFT, NOT ON THE TOUCH.
      //
      // 유저 2026-08-27, iPhone: 「필 툴인 채로 … undo가 작동안함. 브러시툴
      // 에서는 잘 작동함. 1핑거 플립모드로 전환하면 또 잘 작동함」 — a
      // two-finger undo tap put its FIRST finger down, the fill committed a
      // history entry nobody asked for, and the undo that followed spent
      // itself on that instead of on the user's work.
      //
      // ★The law is already here, thirty lines up: when a second finger
      // arrives, a touch stroke that has not passed slop is DISCARDED —
      // "the first finger turned out to be the start of a pinch, not a
      // stroke". That branch is exactly why the brush tool works and this
      // one did not: a zero-length stroke has nothing to commit, while the
      // fill had already flooded, revealed and queued its commit.
      //
      // ⛔The fix cannot be 「commit, then undo it when the second finger
      // shows」 — [[no-optimistic-commit-then-revert]], 유저: 「한 프레임
      // 보이는 건 무조건 걸린다」. So the REVEAL waits with the commit; a
      // tap that turns out to be a pinch never draws anything at all.
      //
      // Pen and mouse are untouched: they cannot be half of a pinch, and
      // the instant reveal is the whole point of R22-A.
      if (event.kind == PointerDeviceKind.touch) {
        _state._fillTapPointer = event.pointer;
        _state._fillTapSeed = canvasPosition;
        return true;
      }
      _state._fill.runFillTap(canvasPosition);
      return true;
    }
    return false;
  }

  void pointerMove(PointerMoveEvent event) {
    _state._celPress.resumePressThatMadeTheCel(event.pointer);
    if (!_state.widget.editable) {
      return; // Standing down: inert, exactly as when nothing was built.
    }
    // R27 #17: a mapped button can also rise DURING contact — some pen
    // drivers report the barrel bit a moment after the tip lands rather
    // than on the down event, and the hover edge above never sees it
    // then. Only picked up while nothing is drawing yet, so a live
    // stroke is never hijacked mid-line.
    _state._hold.handleMappedButtonRiseDuringContact(event);
    // A held eyedropper mapping picks LIVE along the whole drag (PEN-7a:
    // '누르는 동안 해당 색을 뽑는다'). 유저 확정 — one law for every dropper:
    // 「클릭중이면 색 바뀌도록 … 같은법으로. 드래그중 계속샘플」 — the tool
    // does it on the tap layer and a held button does it here. Alt was a
    // third door until I-15 made it the tool itself.
    if (event.pointer == _state._hold._mappedHoldPointer &&
        _state._hold._mappedHoldIsEyedropper) {
      final pickPosition = _state._canvasPositionFromLocal(event.localPosition);
      if (_state._isInsidePasteboard(pickPosition)) {
        _state.widget.onHoldPick?.call(pickPosition);
      }
      return;
    }
    if (event.pointer != _state._activeDrawingPointer) {
      return;
    }
    final touchStrokeDown = _state._touchStrokeDownPosition;
    if (!_state._touchStrokeCommitted &&
        touchStrokeDown != null &&
        (event.localPosition - touchStrokeDown).distance >=
            InteractiveBrushEditCanvasView.kTouchStrokeCommitSlop) {
      _state._touchStrokeCommitted = true;
    }

    final read = _state._pressure.noteSample(
      event,
      opening: _state._stroke._opening,
    );
    final penPosition = _state._canvasPositionFromLocal(event.localPosition);
    _state._lastPenPosition = penPosition;
    _state._stroke.takeSample(penPosition, at: event.timeStamp, read: read);
  }

  void pointerUp(PointerUpEvent event) {
    // A TAP on an empty cel is a dot, so the press still begins here — and
    // then this same event ends it: one dab, one undo entry.
    _state._celPress.resumePressThatMadeTheCel(event.pointer);
    if (_state._celPress._pendingCelPress?.pointer == event.pointer) {
      _state._celPress._pendingCelPress =
          null; // Never resumed; nothing is left to draw.
    }
    if (!_state.widget.editable) {
      return;
    }
    _releasePointer(event.pointer);
    // The lone finger lifted with nobody having joined it: the tap was this
    // fill's after all. ⛔BEFORE the drawing-pointer gate below — a fill tap
    // never becomes the drawing pointer, so that gate would drop it.
    final fillSeed = _state._fillTapSeed;
    if (event.pointer == _state._fillTapPointer && fillSeed != null) {
      _state._fill.runFillTap(fillSeed);
      return;
    }
    if (event.pointer != _state._activeDrawingPointer) {
      return;
    }

    landActiveStroke();
  }

  /// Ends whatever the pen is in the middle of and puts it on the cel —
  /// the landing a pen-up performs. Answers whether anything landed.
  /// Published as a [StrokeLander] while the view is mounted.
  ///
  /// 🚨★★★**THE ORDER IS THE WHOLE THING, WHICH IS WHY IT HAS A NAME.**
  /// Four steps that each depend on the one before, and every one of them
  /// was a bug once: the stabilizer trails the pen so the catch-up has to
  /// run or the line stops short of where the hand is; the snap settles
  /// AFTER that catch-up so the extra travel counts towards its decision;
  /// the commit reads the rasterizer's tiles so dabs still waiting on the
  /// per-frame flush must be blended first; and the input teardown comes
  /// last because the steps above read the state it clears.
  ///
  /// ⛔**So a second caller must not re-write these four — it calls THIS.**
  /// A save that landed the stroke its own way would be the same algorithm
  /// implemented twice, and the copy would drift on the first of those four
  /// that anybody improved. That is not hypothetical here: this sequence
  /// already carries three separate fixes in its ordering.
  ///
  /// ⚠️Safe to call with no stroke in flight — it answers false and
  /// touches nothing, so a caller never has to ask first (and cannot ask
  /// wrongly).
  bool landActiveStroke() {
    if (_state._activeDrawingPointer == null) {
      return false;
    }
    // Whatever still waits for the contact's first pressure reading lands
    // before the catch-up that follows it (H43).
    _state._stroke.stopWaiting();
    // Stabilizer catch-up (P7): the brush trails the pen by up to a rope
    // length — pen-up closes the gap with one straight segment through
    // the normal pipeline, so line ends land where the pen lifted.
    final lastPen = _state._lastPenPosition;
    if (_state._stabilizer != null && lastPen != null) {
      _state._stroke.advanceStrokeThroughGuides(lastPen);
    }
    // A stroke can lift before it travelled far enough to name a ray; the
    // snap settles on the best guess it has rather than swallowing a short
    // flick. Runs AFTER the catch-up so the extra travel counts towards the
    // decision.
    final session = _state._snapSession;
    if (session != null) {
      for (final snapped in session.finish()) {
        _state._stroke.advanceStrokeTo(snapped);
      }
    }

    final hadDabs = _state._collectedDabs.isNotEmpty;
    if (hadDabs) {
      // The commit reads the rasterizer's tiles — blend any dabs still
      // waiting on the per-frame flush first.
      _state._overlay.flushPendingOverlayDabs();
      _state._stroke.commitStroke();
    }

    _state._stroke.endStrokeInput();
    if (!hadDabs) {
      _state._overlay.resetOverlay();
    }
    return hadDabs;
  }

  void pointerCancel(PointerCancelEvent event) {
    if (_state._celPress._pendingCelPress?.pointer == event.pointer) {
      _state._celPress._pendingCelPress = null;
    }
    if (!_state.widget.editable) {
      return;
    }
    // A cancelled fill tap is a fill that never runs — the lift's branch
    // runs it instead. Ordering against the release below is free: this
    // writes only the fill-tap slots, which none of the release steps read.
    if (event.pointer == _state._fillTapPointer) {
      _state._fill.forgetFillTap();
    }
    _releasePointer(event.pointer);
    if (event.pointer != _state._activeDrawingPointer) {
      return;
    }

    _state._stroke.endStrokeInput();
    _state._overlay.resetOverlay();
  }

  /// THIS POINTER IS GONE — the bookkeeping both endings of a press owe,
  /// whether the pointer lifted or was cancelled: its contact buttons, its
  /// place in the touch census, and the tool mapping it was holding. What
  /// each ending does BESIDES this (a lift
  /// runs the fill tap and commits the dabs; a cancel forgets the tap and
  /// discards) is the two laws, and they stay at the callers.
  void _releasePointer(int pointer) {
    _state._hold._lastContactButtons.remove(pointer);
    _forgetTouchPointer(pointer);
    _state._hold.releaseMappedHold(pointer);
  }

  void _forgetTouchPointer(int pointer) {
    _activeTouchPointers.remove(pointer);
    CanvasTouchContacts.remove(pointer);
    if (_activeTouchPointers.isEmpty) {
      _multiTouchNavigation = false;
    }
  }

  /// R26 #5: a view disposed mid-touch never sees its pointer-up — its
  /// contacts must leave the app-wide census or ink stays blocked.
  void releaseTouchContacts() {
    CanvasTouchContacts.removeAll(_activeTouchPointers);
  }
}
