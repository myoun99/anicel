import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

/// 🚨★★★ ONE NOTCH, ONE CONSUMER (H23, 유저 2026-08-23: 「휠 줌이 패널과 띠에서
/// 동시 발동」).
///
/// A `Listener`'s `onPointerSignal` does **not** consume the event. Flutter
/// offers a pointer signal to EVERY listener in the hit path — that is the
/// framework's design, not a bug in it — so two surfaces stacked over the same
/// pixel each acted on the same turn of the wheel: the control moved and the
/// view zoomed, from one notch.
///
/// [PointerSignalResolver] is the one mechanism that makes a signal exclusive,
/// and nothing in this app was using it. Whoever registers FIRST for an event
/// gets it, and dispatch runs deepest-first — so the surface under the pointer
/// wins, which is the surface the pointer is pointing at. Flutter's own
/// `Scrollable` registers too, so a scroll view and one of ours can no longer
/// both answer.
///
/// ⛔**Register, do not handle.** A handler that acts immediately has already
/// taken the notch by the time anything deeper is offered it — which is the
/// bug, spelled with the resolver present.
///
/// ⚠️Two surfaces deliberately stay OUT of this and must keep passing null-ish
/// observers instead of registering:
/// * the input inspector, which is a debug READOUT — a reader that competed
///   for the event would change what it is reading;
/// * [PlaybackActuationGate], whose whole law is that the first actuation of
///   any kind STOPS playback. It has to see every notch, including the ones a
///   deeper surface is about to win.
void handleWheelExclusively(
  PointerSignalEvent event,
  void Function(PointerScrollEvent event) handle,
) {
  if (event is! PointerScrollEvent) {
    return;
  }
  GestureBinding.instance.pointerSignalResolver.register(event, (resolved) {
    if (resolved is PointerScrollEvent) {
      handle(resolved);
    }
  });
}

/// [handleWheelExclusively] for a CONTROL that may find itself inside a list.
///
/// 🚨A wheel over a bar inside a scroll view scrolls the LIST, everywhere —
/// that is the desktop convention and it is what this app already assumed (the
/// timeline's own window test wheels over the grid and expects the rows to
/// move). A bar that took the notch there would make the rail unscrollable
/// wherever a slider sits under the pointer, which is most of it.
///
/// So the bar competes only where nothing is going to scroll: panel chrome —
/// the canvas's zoom bar and panbars, which is exactly the pair the report
/// named (「휠 줌이 패널과 띠에서 동시 발동」).
///
/// ⚠️[axis] is the direction the NOTCH pushes, not the bar's own direction: a
/// horizontal bar in a vertical list still has to let the list scroll.
void handleWheelUnlessScrolling(
  PointerSignalEvent event,
  BuildContext context,
  void Function(PointerScrollEvent event) handle, {
  Axis axis = Axis.vertical,
}) {
  if (Scrollable.maybeOf(context, axis: axis) != null) {
    return;
  }
  handleWheelExclusively(event, handle);
}
