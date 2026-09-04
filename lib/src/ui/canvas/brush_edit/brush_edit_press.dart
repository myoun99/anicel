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

  /// 유저 확정 — one law for every dropper: 「클릭중이면 색 바뀌도록 …
  /// 같은법으로. 드래그중 계속샘플」. The mapped hold above has always done
  /// this ('누르는 동안 해당 색을 뽑는다', PEN-7a) and the eyedropper TOOL now
  /// does it on the tap layer; Alt was the third door, and it was the one
  /// still picking once per press.
  int? _altPickPointer;

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

  void pointerDown(PointerDownEvent event) {
    // (No deferred stroke commit to land first: pen-up commits inside its
    // own event now — R25-④'s one-frame deferral existed to hide a
    // synchronous re-materialize that the promotion round deleted.)
    if (event.kind == PointerDeviceKind.touch) {
      // PEN-12 #4: a finger draws exactly when the ONE-FINGER touch slot
      // says draw (the old control/draw mode collapsed into the slot);
      // otherwise the panel's gesture layer owns every touch.
      if (!AppInput.touchDraws) {
        return;
      }
      _activeTouchPointers.add(event.pointer);
      CanvasTouchContacts.add(event.pointer);
      // R26 #5: the census is APP-WIDE — the timesheet mounts one ink
      // view per sheet window, so the second finger often lands on a
      // SIBLING view. Counting locally let both of them draw.
      if (CanvasTouchContacts.count >= 2) {
        final drawingPointer = _state._activeDrawingPointer;
        final touchStroke =
            drawingPointer != null &&
            _activeTouchPointers.contains(drawingPointer);
        // PEN-12 #4: a COMMITTED stroke survives extra fingers — palm
        // rests and habitual pinches must never vanish a live line. The
        // newcomer is simply ignored (no navigation, no modifier).
        if (touchStroke && _state._touchStrokeCommitted) {
          return;
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
        return;
      }
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
    final mapping = _state._hold.mappedPointerActionFor(event);
    if (mapping != null) {
      if (_multiTouchNavigation ||
          _state._activeDrawingPointer != null ||
          _state._hold._mappedHoldPointer != null) {
        return;
      }
      switch (_pressAsMappedAction(mapping, event)) {
        case _MappedPress.consumed:
          return;
        case _MappedPress.erase:
          mappedErase = true;
      }
    }

    if (!mappedErase &&
        (_multiTouchNavigation ||
            _state._activeDrawingPointer != null ||
            !_isPrimaryButton(_state._hold.effectiveButtons(event)))) {
      return;
    }

    final canvasPosition = _state._canvasPositionFromLocal(event.localPosition);
    // The pasteboard is EVERY tool's input boundary (user feedback +
    // Flash parity): strokes, the eyedropper and fill taps all work on
    // off-canvas artwork; only the pasteboard wall stops them.
    final startsInsidePasteboard = _state._isInsidePasteboard(canvasPosition);

    // Alt+click = temporary eyedropper (P5): pick, never stroke.
    final onAltPick = _state.widget.onAltPick;
    if (onAltPick != null && HardwareKeyboard.instance.isAltPressed) {
      // TS7: remembered, so the drag that follows keeps sampling.
      _altPickPointer = event.pointer;
      if (startsInsidePasteboard) {
        onAltPick(canvasPosition);
      }
      return;
    }

    // FILL tap (R22-A / R23): the flood's stamp becomes ONE overlay
    // image at the commit's exact placement, and the commit itself
    // DEFERS past the tap frame — the finished fill shows while the
    // heavy commit (~0.5s at 8K) runs behind a complete-looking
    // picture; settling then holds the overlay until the committed
    // tiles decode. (The R22-A live-raster blend re-snapshotted and
    // re-decoded thousands of 128px overlay tiles — the 8K
    // settle-frame stall.)
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

  /// A press the pen tail or a mapped button turned into an action: pan
  /// and the history verbs consume it, the eyedropper hold consumes it
  /// after picking, and the eraser hold turns the stroke that follows into
  /// an erase — every mapped press is one of the two.
  _MappedPress _pressAsMappedAction(
    CanvasPointerMapping mapping,
    PointerDownEvent event,
  ) {
    switch (mapping.action) {
      case CanvasPointerAction.none:
      // Pan belongs to the panel's viewport gesture layer — this view
      // only stands down so no stroke competes with it.
      case CanvasPointerAction.pan:
        return _MappedPress.consumed;
      case CanvasPointerAction.undo:
        // Skip when the button press already fired during hover (the
        // hover edge below) and the tip then touched with it held.
        if (!_state._hold.mappedButtonHeldSinceHover(event)) {
          _state.widget.onInvokeAction?.call('edit-undo');
        }
        return _MappedPress.consumed;
      case CanvasPointerAction.redo:
        if (!_state._hold.mappedButtonHeldSinceHover(event)) {
          _state.widget.onInvokeAction?.call('edit-redo');
        }
        return _MappedPress.consumed;
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
          _state.widget.onAltPick?.call(pickPosition);
        }
        return _MappedPress.consumed;
      case CanvasPointerAction.eraser:
        _state._hold._mappedHoldPointer = event.pointer;
        _state._hold._mappedHoldRelease = mapping.release;
        _state._hold._mappedHoldIsEyedropper = false;
        _state.widget.onTemporaryToolHold?.call(CanvasTool.eraser);
        return _MappedPress.erase;
      // Falls through into the normal stroke start below with the
      // erase-substituted settings snapshot.
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
    // '누르는 동안 해당 색을 뽑는다').
    if (event.pointer == _state._hold._mappedHoldPointer &&
        _state._hold._mappedHoldIsEyedropper) {
      final pickPosition = _state._canvasPositionFromLocal(event.localPosition);
      if (_state._isInsidePasteboard(pickPosition)) {
        _state.widget.onAltPick?.call(pickPosition);
      }
      return;
    }
    // TS7: the ALT pick does the same. Alt is re-read rather than assumed —
    // letting go of the key mid-drag ends the sampling, which is the same
    // moment the crosshair goes away.
    if (event.pointer == _altPickPointer) {
      if (!HardwareKeyboard.instance.isAltPressed) {
        return;
      }
      final pickPosition = _state._canvasPositionFromLocal(event.localPosition);
      if (_state._isInsidePasteboard(pickPosition)) {
        _state.widget.onAltPick?.call(pickPosition);
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

    _state._currentPressure = _state._pressure.normalizedPressure(event);
    final penPosition = _state._canvasPositionFromLocal(event.localPosition);
    _state._lastPenPosition = penPosition;
    // The stabilizer smooths BEFORE clipping/interpolation, so every
    // downstream consumer (overlay, commit, replay) sees one chain — the
    // three-route parity holds by construction (P7).
    _state._stroke.advanceStrokeThroughGuides(
      _state._stabilizer?.follow(penPosition) ?? penPosition,
    );
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
    _state._hold._lastContactButtons.remove(event.pointer);
    _forgetTouchPointer(event.pointer);
    _state._hold.releaseMappedHold(event.pointer);
    if (event.pointer == _altPickPointer) {
      _altPickPointer = null;
    }
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
  }

  void pointerCancel(PointerCancelEvent event) {
    if (_state._celPress._pendingCelPress?.pointer == event.pointer) {
      _state._celPress._pendingCelPress = null;
    }
    if (!_state.widget.editable) {
      return;
    }
    _state._hold._lastContactButtons.remove(event.pointer);
    if (event.pointer == _state._fillTapPointer) {
      _state._fill.forgetFillTap();
    }
    _forgetTouchPointer(event.pointer);
    _state._hold.releaseMappedHold(event.pointer);
    if (event.pointer == _altPickPointer) {
      _altPickPointer = null;
    }
    if (event.pointer != _state._activeDrawingPointer) {
      return;
    }

    _state._stroke.endStrokeInput();
    _state._overlay.resetOverlay();
  }

  void _forgetTouchPointer(int pointer) {
    _activeTouchPointers.remove(pointer);
    CanvasTouchContacts.remove(pointer);
    if (_activeTouchPointers.isEmpty) {
      _multiTouchNavigation = false;
    }
  }

  /// The mapping a set of non-primary [bits] drives: the wheel click owns
  /// the tertiary bit, and everything else reads as the secondary — the
  /// barrel button, whichever bit the driver puts it on.
  CanvasPointerMapping? mappingForButtons(int bits) {
    // A live tail hold owns the tool: the two mappings share one hold
    // slot, and whichever engaged first keeps it. Letting a barrel press
    // take the tool mid-flip would leave the tail with nothing to spring
    // back to when the pen is finally turned upright.
    if (bits == 0 || _state._penTailActive) {
      return null;
    }
    final settings = AppInput.settings.value;
    if ((bits & kTertiaryButton) != 0) {
      return settings.canvasWheelClick;
    }
    return settings.canvasRightClick;
  }

  /// R28: a MASK test, not equality. A barrel button held while the tip
  /// touches down reports `primary | barrel`, and the old `== primary`
  /// test read that as "not drawing" — so on a driver that does ride the
  /// barrel bit into contact, the pen went dead instead of picking. The
  /// mapped-press path runs first and claims those pointers, so anything
  /// still reaching here with the primary bit down is a real stroke.
  bool _isPrimaryButton(int buttons) => (buttons & kPrimaryButton) != 0;

  /// R26 #5: a view disposed mid-touch never sees its pointer-up — its
  /// contacts must leave the app-wide census or ink stays blocked.
  void releaseTouchContacts() {
    CanvasTouchContacts.removeAll(_activeTouchPointers);
  }
}

/// What a mapped press did with the pointer-down (see
/// [_BrushEditPress._pressAsMappedAction]).
enum _MappedPress {
  /// The mapping ate the press: nothing else happens on this down.
  consumed,

  /// An eraser hold began: the stroke that follows erases.
  erase,
}
