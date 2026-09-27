import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

/// 🚨★★★**A PRESS THAT LANDS IN A SCROLLER IS THAT SCROLLER'S** — the
/// scroller's turn of the law a bar and a canvas already keep.
///
/// 🗣️F-202 (유저 2026-09-27): 「띠가 스크롤되는거, 같은상황에서 뷰어패널
/// 스크롤바 조절할때도 밖의 다중패널 스크롤바 작동하던거같은데」, and then the
/// law itself: 「**안에서 동작하는 스크롤이나 드래그는 절대 밖으로
/// 안새게**가 심플한 근본적인 규칙인거같다」.
///
/// ## Where a scroller leaked
///
/// Two scrollers that run the SAME way never leak: the arena offers each
/// move deepest-first, so the inner one crosses the slop in the same event
/// as the outer and is asked first. Two that run ACROSS each other race on
/// different numbers — the inner one counts only its own axis, the outer
/// one only its — and whichever axis the hand moved along first won. A
/// sideways list in the strip of panels, pulled with a first step that went
/// a little down, scrolled the STRIP (🧪measured 09-27: 24px, all three
/// devices).
///
/// ## How it is held
///
/// The inner scroller is given a second recogniser for the other axis, one
/// that counts the outer's own distance on the outer's own slop — the SAME
/// question the outer asks, asked by something deeper, so it is answered
/// first. When it wins it drives the inner scroller, with the part of the
/// movement that runs the inner scroller's way. ⛔No new number: the
/// distance and the threshold are the outer's (「거리(px)로 판단하지
/// 않는다」 is about a press deciding what it is — this decides nothing the
/// outer did not already decide, only who answers). ⛔It does not accept on
/// the first movement, as a bar does: a scroller's content still waits for
/// the slop to tell a tap from a scroll, and taking that away would be a
/// new rule the law never asked for.
///
/// Held only when a scroller running across could take the drag right now —
/// with nothing to race there is nothing to hold, and the inner scroller
/// keeps answering exactly as it always has.
///
/// ⚠️What offers the press is `AppScrollBehavior.velocityTrackerBuilder`:
/// the one call the framework makes per scroller per press that no
/// `copyWith` switches off, made while the scroller's own recogniser takes
/// the pointer — innermost scroller first, before any scroller around it has
/// even been offered the press.
///
/// ⚠️Every scroller the press lands in is offered it, and each one with a
/// live scroller across it holds it — which costs nothing, because the
/// innermost one's own recogniser and hold between them answer both axes
/// before anything outside it is asked.
void holdThePressForItsScroller(
  BuildContext scrollableContext,
  PointerDownEvent event,
  GestureVelocityTrackerBuilder velocityTracker,
) {
  final scroller = _scrollerAt(scrollableContext);
  if (scroller == null) {
    return;
  }
  final across = _liveScrollerAcross(scroller);
  // Its other half answers the pull across by itself: it is deeper than
  // anything further out that runs its way.
  if (across == null || _scrolledTogether(scroller, across)) {
    return;
  }
  final recognizer = _PressHold(scroller, across, velocityTracker).recognizer;
  if (recognizer.isPointerAllowed(event)) {
    recognizer.addPointer(event);
  } else {
    recognizer.dispose();
  }
}

/// Declares [a] and [b] ONE surface scrolled two ways: a press in whichever
/// sits inside the other is not held against it.
///
/// 🚨The grids and the dock's floor are built this way — a vertical
/// viewport inside a horizontal one, or the other way round — and what the
/// hand pulls there is ONE thing: a panel under its floor (F-103), the
/// timeline's rows and frames, the x-sheet, the storyboard. Held apart, the
/// inner of the two would answer every pull across it with its hold, and
/// none of them could be dragged that way again (🧪pinned for the panel in
/// `an_inner_drag_never_leaks_out_test`).
///
/// ⚠️Declared on the CONTROLLERS, so it names those two scrollers and no
/// other: a list inside the panel is inside the pair, not one of it, and is
/// held against both — as a list inside the media pool's or the import
/// table's sideways escape is held against it.
void scrollTogether(ScrollController a, ScrollController b) {
  _together[a] = b;
  _together[b] = a;
}

final Expando<ScrollController> _together = Expando<ScrollController>(
  'scrolled together',
);

bool _scrolledTogether(ScrollableState a, ScrollableState b) {
  final controller = a.widget.controller;
  return controller != null &&
      identical(_together[controller], b.widget.controller);
}

/// The scroller the framework handed the press to. `Scrollable` passes its
/// OWN context when it asks for a tracker, and its own state is the only
/// thing that context can find without looking past it.
ScrollableState? _scrollerAt(BuildContext context) {
  if (context is! StatefulElement) {
    return null;
  }
  final state = context.state;
  return state is ScrollableState ? state : null;
}

/// The nearest scroller around [scroller] that runs across it and could
/// take a drag right now.
ScrollableState? _liveScrollerAcross(ScrollableState scroller) {
  final axis = scroller.widget.axis;
  for (
    var outer = scroller.context.findAncestorStateOfType<ScrollableState>();
    outer != null;
    outer = outer.context.findAncestorStateOfType<ScrollableState>()
  ) {
    if (outer.widget.axis == axis) {
      continue;
    }
    final position = outer.position;
    if (position.hasContentDimensions &&
        position.physics.shouldAcceptUserOffset(position)) {
      return outer;
    }
  }
  return null;
}

/// One press, held for [scroller] against [across].
class _PressHold {
  _PressHold(
    this.scroller,
    ScrollableState across,
    GestureVelocityTrackerBuilder velocityTracker,
  ) : _axis = scroller.widget.axis {
    final physics = scroller.position.physics;
    recognizer = _HeldAcross(across.widget.axis, _done)
      ..gestureSettings = across.context
          .getInheritedWidgetOfExactType<MediaQuery>()
          ?.data
          .gestureSettings
      ..velocityTrackerBuilder = velocityTracker
      ..dragStartBehavior = scroller.widget.dragStartBehavior
      ..minFlingDistance = physics.minFlingDistance
      ..minFlingVelocity = physics.minFlingVelocity
      ..maxFlingVelocity = physics.maxFlingVelocity
      ..onStart = _start
      ..onUpdate = _update
      ..onEnd = _end
      ..onCancel = _cancel;
  }

  final ScrollableState scroller;
  final Axis _axis;
  late final _HeldAcross recognizer;
  Drag? _drag;

  double _along(Offset offset) =>
      _axis == Axis.horizontal ? offset.dx : offset.dy;

  Offset _onTheAxis(double value) =>
      _axis == Axis.horizontal ? Offset(value, 0) : Offset(0, value);

  // What `Scrollable` does with its own recogniser's callbacks, fed the part
  // of each movement that runs this scroller's way.
  void _start(DragStartDetails details) {
    if (scroller.mounted) {
      _drag = scroller.position.drag(details, _dropDrag);
    }
  }

  void _update(DragUpdateDetails details) {
    final along = _along(details.delta);
    _drag?.update(
      DragUpdateDetails(
        sourceTimeStamp: details.sourceTimeStamp,
        delta: _onTheAxis(along),
        primaryDelta: along,
        globalPosition: details.globalPosition,
        localPosition: details.localPosition,
      ),
    );
  }

  void _end(DragEndDetails details) {
    final along = _along(details.velocity.pixelsPerSecond);
    _drag?.end(
      DragEndDetails(
        velocity: Velocity(pixelsPerSecond: _onTheAxis(along)),
        primaryVelocity: along,
        globalPosition: details.globalPosition,
        localPosition: details.localPosition,
      ),
    );
  }

  void _cancel() => _drag?.cancel();

  void _dropDrag() => _drag = null;

  // Not from inside the recogniser's own event handling.
  void _done() => scheduleMicrotask(recognizer.dispose);
}

/// A pan that waits for exactly what a drag across it would wait for: the
/// movement along [across], on the device's own slop.
class _HeldAcross extends PanGestureRecognizer {
  _HeldAcross(this.across, this._done);

  final Axis across;
  final VoidCallback _done;
  double _moved = 0;

  @override
  void handleEvent(PointerEvent event) {
    if (event is PointerMoveEvent) {
      _moved += across == Axis.horizontal ? event.delta.dx : event.delta.dy;
    }
    super.handleEvent(event);
  }

  @override
  bool hasSufficientGlobalDistanceToAccept(
    PointerDeviceKind pointerDeviceKind,
    double? deviceTouchSlop,
  ) => _moved.abs() > computeHitSlop(pointerDeviceKind, gestureSettings);

  @override
  void didStopTrackingLastPointer(int pointer) {
    super.didStopTrackingLastPointer(pointer);
    _done();
  }
}
