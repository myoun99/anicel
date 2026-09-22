part of '../brush_canvas_panel.dart';

/// A TAP ON THE CANVAS — the press that may become a tool tap or a stamp,
/// the slop that decides it, the pointers holding an aim, and the drag
/// that carries a stamp along. The panel stays the widget that mounts
/// them.
///
/// 🚨A collaborator carved out of `_BrushCanvasPanelState` (the audit's SRP
/// cut, Round 6, 2026-09-03). Measured before cutting: four fields of its
/// own and eight methods that are their only readers. It reaches the
/// panel through `_state`.
class _CanvasPanelTap {
  _CanvasPanelTap(this._state);

  final _BrushCanvasPanelState _state;

  /// Pointers that are DOWN and could drive a tool — the census's own
  /// count of who is holding the aim up.
  ///
  /// A press is a SPAN, not a moment, and several can overlap. The aim
  /// belongs to the span, so it survives until the last holder lifts:
  /// without this a second finger's up blanked the ring the first was
  /// still drawing with, and it returned only on that finger's next move
  /// — one flicker per staggered lift-off.
  final Set<int> _pointersHoldingAim = <int>{};

  /// Whether ANY holder still has the aim — pressed or merely present.
  /// One test for both kinds, so a departure of either sort cannot decide
  /// on its own that nobody is left.
  bool get aimIsHeld =>
      _pointersHoldingAim.isNotEmpty || _state._hoverDevicesInside.isNotEmpty;

  void beginCanvasPointer(PointerDownEvent event) {
    if (!AppInput.toolAcceptsPointer(event.kind)) {
      return;
    }
    _pointersHoldingAim.add(event.pointer);
  }

  /// A pointer's contact ended. For a pointer that reports its own exit,
  /// that means nothing — a mouse is still on the glass after a click,
  /// and forgetting here would blank its cursor until it moved again.
  /// For every other kind the contact WAS the presence.
  void endCanvasPointer(PointerEvent event) {
    // ⛔A pointer that may not WRITE the census may not erase it either —
    // and MEMBERSHIP is how we know that, not a fresh look at the setting.
    //
    // [AppInput.toolAcceptsPointer] reads the LIVE one-finger slot, so
    // re-asking it here puts a question about the PAST to a value that
    // can have moved since. Change the slot while a finger is down and
    // its id never leaves this set, which makes the clear below
    // unreachable for the life of the panel — D34 back, and silently.
    // The mirror order is no better: a finger that was never admitted
    // becomes acceptable on the way out and deletes the ring a hovering
    // pen owns.
    //
    // The set was written at DOWN, when the question was actually being
    // asked, so a navigating finger is simply not in it and the
    // standdown holds by construction.
    if (!_pointersHoldingAim.remove(event.pointer)) {
      return;
    }
    if (AppInput.pointerReportsItsOwnExit(event.kind)) {
      return;
    }
    if (aimIsHeld) {
      return;
    }
    _state._forgetCanvasPointer();
  }

  Positioned toolTapLayer() {
    return Positioned.fill(
      child: Listener(
        key: const ValueKey<String>('canvas-tool-tap-layer'),
        behavior: HitTestBehavior.opaque,
        onPointerDown: _toolTapDown,
        // TS7 (유저: 클릭중이면
        // 색 바뀌도록 — 규칙
        // 간단하게): a MOVE is
        // the press verb
        // CONTINUING. The stamp
        // lays its next dab
        // where the spacing says;
        // the eyedropper samples
        // again, which is what
        // dragging a dropper
        // means everywhere else.
        //
        // The bucket cannot get
        // here — its tap handler
        // is null (R22-A sends
        // the dab through the
        // stroke pipeline), so
        // this layer is not even
        // _state.mounted for it and
        // "one fill per move
        // event" is structurally
        // impossible.
        onPointerMove: _toolTapMove,
        onPointerUp: _toolTapUp,
        onPointerCancel: _toolTapCancel,
      ),
    );
  }

  void _toolTapCancel(PointerCancelEvent event) {
    _tapLayerTouches.remove(event.pointer);
    _touchTap = null;
    _lastStampCenter = null;
  }

  void _toolTapUp(PointerUpEvent event) {
    // A tap that stayed
    // put resolves when
    // the finger leaves.
    if (_touchTap?.pointer == event.pointer) {
      _resolveTouchTap();
    }
    _tapLayerTouches.remove(event.pointer);
    _touchTap = null;
    _lastStampCenter = null;
  }

  void _toolTapMove(PointerMoveEvent event) {
    // The gesture
    // declares itself by
    // MOVING: crossing
    // the slop resolves
    // the waiting tap
    // where it was
    // pressed, and the
    // drag carries on
    // from there — the
    // stamp trails its
    // row, the dropper
    // keeps sampling.
    if (_touchTapPassedSlop(event)) {
      _resolveTouchTap();
    }
    if (_touchTap != null) {
      // Still undecided —
      // a sub-slop wobble
      // is not a drag.
      return;
    }
    _state._continuePressVerb(event);
  }

  void _toolTapDown(PointerDownEvent event) {
    // 🚨★★★**A PRESS THAT LANDED ON A CONTROL IS THAT CONTROL'S** — 유저
    // 2026-09-22: 「버튼에 오는 동작은 **무조건 버튼꺼야**」. The selection
    // layer above learned this the same day; this surface is the other
    // half of the canvas and answers it the same way, rather than waiting
    // for a control to float over IT and be reported separately.
    if (controlOwnsTap(event.pointer)) {
      return;
    }
    // PRIMARY contact only (R22-B):
    // the middle-button pan (the
    // ancestor gesture layer) used
    // to ALSO fire the tool here —
    // every pan click deposited a
    // stray fill, which is why one
    // fill sometimes took two undos.
    //
    // R28 #8: the EYEDROPPER is
    // exempt. Its whole point under a
    // mapped hold (pen barrel /
    // right-click) is that the held
    // NON-primary button is what
    // picks — the strict test meant
    // the mapping switched the tool
    // and then refused every press,
    // so it "제대로 작동하지도않고".
    // A pick writes no pixels, so
    // there is no stray-edit hazard
    // to guard against here.
    if (_state.widget.brushToolState.tool != CanvasTool.eyedropper &&
        event.buttons != kPrimaryButton) {
      return;
    }
    // TS9: and a finger
    // only drives a tool
    // while the one-finger
    // slot says draw. This
    // layer takes the pick
    // and the stamp, and
    // both were acting on
    // fingers in flip mode.
    if (!AppInput.toolAcceptsPointer(event.kind)) {
      return;
    }
    // 🚨A TOUCH WAITS —
    // see [_touchTap].
    // A SECOND finger
    // arriving while one
    // waits is the pinch
    // this exists for.
    if (event.kind == PointerDeviceKind.touch) {
      _tapLayerTouches.add(event.pointer);
      if (_tapLayerTouches.length > 1) {
        _touchTap = null;
        return;
      }
      _touchTap = (
        pointer: event.pointer,
        canvas: _state._viewportState.canvasPointOf(event),
        local: event.localPosition,
      );
      return;
    }
    toolTapHandler()!(_state._viewportState.canvasPointOf(event));
  }

  /// The tap action for the active NON-PAINTING tool; null while a
  /// painting tool is active, and while the content takes no tool input
  /// ([BrushCanvasPanel.toolInputEnabled]) — no tap layer mounts then.
  void Function(CanvasPoint point)? toolTapHandler() {
    if (!_state.widget.toolInputEnabled) {
      return null;
    }
    switch (_state.widget.brushToolState.tool) {
      case CanvasTool.brush:
      case CanvasTool.eraser:
      // The selection/move tools mount their own drag layer, not the tap
      // layer. The CUT variants ride that same layer (canvasToolSelects),
      // and the STAMP variant paints, so none of them want a tap handler
      // here either.
      case CanvasTool.select:
      case CanvasTool.move:
      case CanvasTool.cut:
      // The shape fill rides the same drag layer as select and cut — one
      // outline, three things to do with it.
      case CanvasTool.fillShape:
        return null;
      case CanvasTool.cutStamp:
        // Click = drop the held piece, centred here, committed at once.
        // Photoshop, Clip Studio and TVPaint agree on the immediate part:
        // none of them float a pasted or stamped piece behind a confirm
        // step. That is also what keeps this tool out of the confirm
        // button's state machine.
        final slot = _state.widget.cutPieceSlot;
        if (slot == null || _state.widget._editableCoordinator == null) {
          return null;
        }
        return (point) {
          final piece = slot.piece;
          if (piece == null) {
            return;
          }
          _state._commitStampDabs([
            buildCutStampDab(
              piece: piece,
              center: point,
              opacity: _state.widget.brushToolState.cutStampOpacity,
            ),
          ]);
          // A press is also the start of a possible drag, and the drag
          // measures its spacing from the stamp that just landed.
          _lastStampCenter = point;
        };
      case CanvasTool.eyedropper:
        final sample = _state.widget.sampleColorAt;
        final pick = _state.widget.onEyedropperPick;
        if (sample == null || pick == null) {
          return null;
        }
        return (point) {
          final color = sample(point);
          if (color != null) {
            pick(color);
          }
        };
      case CanvasTool.fill:
        // R22-A: fill taps are handled by the interactive view's stroke
        // pipeline (fillDabAt) — the result tiles on the tap frame, and the
        // same primary-button discipline as strokes. No tap layer.
        return null;
      case CanvasTool.guide:
        // The guide tool drags HANDLES, not points on the cel — it mounts
        // its own layer in the viewport overlay, like the selection tools.
        return null;
    }
  }

  /// Where the last stamp of the current drag landed. Null between drags.
  CanvasPoint? _lastStampCenter;

  /// 🚨★★★A TOUCH TAP RESOLVES ON THE LIFT OR ON THE SLOP, NEVER ON THE
  /// TOUCH — the fill's law (#1277), now the tap layer's too.
  ///
  /// 유저 2026-08-27: 「1핑거 드로잉모드일때 다른 툴도 비슷한 문제 있을거
  /// 같은데 … **손가락이 동시에 착지하는게 불가능하니까** … 그런 비슷한
  /// 방식으로 통일하는게 **근본통일**같은데」.
  ///
  /// Two fingers never land on the same millisecond, so a pinch begins as a
  /// lone contact. The app's answer to that has never been a timer — a
  /// gesture DECLARES ITSELF BY MOVING, and a touch stroke owns the screen
  /// only once it crosses [InteractiveBrushEditCanvasView
  /// .kTouchStrokeCommitSlop]. The stamp and the eyedropper fired on the
  /// press instead, so the first finger of every two-finger undo dropped a
  /// piece or repainted the colour.
  ///
  /// ⛔Not 「fire, then take it back when the second finger shows」 —
  /// [[no-optimistic-commit-then-revert]], 유저: 「한 프레임 보이는 건 무조건
  /// 걸린다」. Nothing happens until the gesture has said what it is.
  ///
  /// ★ONE RULE FOR BOTH TOOLS, which is the 근본통일 asked for: a tap that
  /// stays put resolves when the finger leaves, and one that moves resolves
  /// the moment it crosses the slop — so the eyedropper still samples all
  /// the way along a drag (TS7) and the stamp still trails a row of pieces.
  /// Pen and mouse never wait: they cannot be half of a pinch.
  ({int pointer, CanvasPoint canvas, Offset local})? _touchTap;

  /// The fingers this layer is holding right now.
  ///
  /// 🚨THE ONE ANSWER to 「is this still the user's own single gesture」, and
  /// it has to be a COUNT rather than 「is a tap already waiting」. Measured:
  /// with the waiting-tap flag as the only guard, the second finger cleared
  /// the pending tap and the THIRD armed a fresh one — a three-finger redo
  /// stamped a piece on its way past. The view's stroke path words it the
  /// same way: no new gesture starts until every finger lifts, so a quick
  /// pinch never leaves marks.
  ///
  /// ⛔This layer absorbs its pointers above the canvas, so the ink census
  /// ([CanvasTouchContacts]) never sees them — asking it here would be a
  /// second answer that reads zero through the very gesture it is meant to
  /// catch. Measured too: removing that check changed no behaviour at all.
  final Set<int> _tapLayerTouches = <int>{};

  /// Runs the waiting tap at the point it was pressed. Harmless when
  /// nothing is waiting — a tap that turned out to be a pinch was dropped
  /// when the second finger landed, so there is nothing left to refuse.
  void _resolveTouchTap() {
    final pending = _touchTap;
    if (pending == null) {
      return;
    }
    _touchTap = null;
    toolTapHandler()?.call(pending.canvas);
  }

  /// Whether [event] has carried the waiting tap far enough to have
  /// declared itself a drag rather than half of a pinch.
  bool _touchTapPassedSlop(PointerEvent event) {
    final pending = _touchTap;
    return pending != null &&
        pending.pointer == event.pointer &&
        (event.localPosition - pending.local).distance >=
            InteractiveBrushEditCanvasView.kTouchStrokeCommitSlop;
  }

  void dragStampTo(CanvasPoint point) {
    if (!canvasToolStamps(_state.widget.brushToolState.tool)) {
      return;
    }
    final piece = _state.widget.cutPieceSlot?.piece;
    final from = _lastStampCenter;
    if (piece == null || from == null) {
      return;
    }
    final centers = cutStampCentersAlong(piece: piece, from: from, to: point);
    if (centers.isEmpty) {
      return;
    }
    for (final center in centers) {
      _state._commitStampDabs([
        buildCutStampDab(
          piece: piece,
          center: center,
          opacity: _state.widget.brushToolState.cutStampOpacity,
        ),
      ]);
    }
    _lastStampCenter = centers.last;
  }
}
