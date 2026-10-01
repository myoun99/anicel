import 'dart:collection' show SetBase;

import 'package:flutter/gestures.dart'
    show
        GestureArenaEntry,
        GestureArenaMember,
        GestureBinding,
        GestureDisposition,
        PointerDeviceKind;
import 'package:flutter/widgets.dart';

import '../../models/app_input_settings.dart'
    show AppInput, CanvasTouchDragAction;
import '../canvas/canvas_pan_hold.dart';
import '../canvas/canvas_press.dart' show canvasPressButtons, canvasPressPans;
import 'value_control_pointers.dart';

/// The canvas's pan on a panel that SCROLLS: Space held, or a mouse button
/// Input Settings maps to 「손바닥」, grabs the panel and moves its content
/// with the hand — and a FINGER moves it as the canvas's own setting for
/// that many fingers says.
///
/// 🗣️R26 #34 (유저 2026-07-20): 「팬이 발동하는 숏컷(현 기본값인 2핑거
/// 드래그나 휠클릭)의 경우, 타임라인에서는 팬으로 작동하도록 로직공통화」 —
/// answered R26-rest-Q2 (2026-09-30): 「캔버스 설정을 그대로 따른다 —
/// 「없음」이면 거기서도 안 움직인다」. ONE predicate per device, the
/// canvas's own — [canvasPressPans] for a button, [AppInput.touchDragActionFor]
/// for a finger, never a copy — and ONE stand-down, [PanHoldGate].
///
/// It hears the press ABOVE the panel (translucent), so it still hears it
/// while the gate below has every tool standing down, and it claims the
/// pointer at its down: a control the pan starts over or crosses never fires
/// ([claimPointerForValueControl]). A finger still scrolls through the
/// panel's own scrollers — native feel, fling included — unless its count
/// is set to 「없음」 ([_FingerGatedDevices], [_fingerDown]).
class PanelPanDriver extends StatefulWidget {
  const PanelPanDriver({
    super.key,
    required this.controllers,
    required this.child,
  });

  /// The panel's scroll controllers: every attached position moves along its
  /// own axis.
  final List<ScrollController> controllers;
  final Widget child;

  @override
  State<PanelPanDriver> createState() => _PanelPanDriverState();
}

class _PanelPanDriverState extends State<PanelPanDriver>
    implements GestureArenaMember {
  int? _pointer;
  Offset _last = Offset.zero;

  /// The fingers down on this panel, each with its hold in its arena while
  /// a finger landing after it could still make the gesture a 「없음」 count.
  final Map<int, GestureArenaEntry?> _fingers = {};

  /// The panel's drag devices with a finger asked per press.
  late final _FingerGatedDevices _devices = _FingerGatedDevices(
    () => _fingers.length,
  );

  void _down(PointerDownEvent event) {
    if (event.kind == PointerDeviceKind.touch) {
      _fingerDown(event);
      return;
    }
    if (_pointer != null || !canvasPressPans(canvasPressButtons(event))) {
      return;
    }
    _pointer = event.pointer;
    _last = event.position;
    claimPointerForValueControl(event.pointer);
  }

  /// A finger lands: the count it makes is asked of the canvas's setting.
  ///
  /// ⛔Nothing here runs while no count is set to 「없음」 — the scrollers
  /// take their fingers exactly as before, so the defaults (flip · navigate ·
  /// brush size) move the panel as they always did.
  ///
  /// 🚨★**FINGERS THAT LAND TOGETHER ARE ONE GESTURE**, the canvas's law
  /// (PEN-12 #4): a finger that makes a 「없음」 count holds every finger
  /// already down whose scroll has not started, so a two-finger drag set to
  /// 「없음」 cannot creep with the finger that landed first. A scroll that
  /// HAS started keeps its finger — the arena has already answered for it.
  ///
  /// ⚠️A lone finger set to 「없음」 holds nothing: the scrollers never take
  /// it ([_FingerGatedDevices]), and a TAP — a cell picked, a button pressed
  /// — is not a drag, which is all the setting names.
  void _fingerDown(PointerDownEvent event) {
    final count = _fingers.length + 1;
    if (count > 1 && _isNone(count)) {
      _fingers[event.pointer] = _enter(event.pointer);
      for (final entry in _fingers.values) {
        entry?.resolve(GestureDisposition.accepted);
      }
      return;
    }
    _fingers[event.pointer] = _laterCountIsNone(count)
        ? _enter(event.pointer)
        : null;
  }

  GestureArenaEntry _enter(int pointer) =>
      GestureBinding.instance.gestureArena.add(pointer, this);

  static bool _isNone(int count) =>
      AppInput.touchDragActionFor(count) == CanvasTouchDragAction.none;

  /// Whether a finger landing after [count] could make a 「없음」 count —
  /// three and more share the three-finger slot.
  static bool _laterCountIsNone(int count) {
    for (var fingers = count + 1; fingers <= 3; fingers += 1) {
      if (_isNone(fingers)) {
        return true;
      }
    }
    return false;
  }

  void _fingerUp(PointerEvent event) {
    // A hold still waiting gives way: a finger that lifts with nothing
    // decided is a tap, and the tap is not this driver's.
    _fingers.remove(event.pointer)?.resolve(GestureDisposition.rejected);
  }

  /// Holding the finger IS the job: a held finger moves nothing.
  @override
  void acceptGesture(int pointer) {}

  @override
  void rejectGesture(int pointer) {}

  void _move(PointerMoveEvent event) {
    if (event.pointer != _pointer) {
      return;
    }
    final delta = event.position - _last;
    _last = event.position;
    for (final controller in widget.controllers) {
      for (final position in controller.positions) {
        final along = position.axis == Axis.horizontal ? delta.dx : delta.dy;
        // The content goes WITH the hand: dragging down shows what was above.
        final to = (position.pixels - along).clamp(
          position.minScrollExtent,
          position.maxScrollExtent,
        );
        if (to != position.pixels) {
          position.jumpTo(to);
        }
      }
    }
  }

  void _end(PointerEvent event) {
    if (event.kind == PointerDeviceKind.touch) {
      _fingerUp(event);
      return;
    }
    if (event.pointer != _pointer) {
      return;
    }
    _pointer = null;
    releasePointerForValueControl(event.pointer);
  }

  @override
  void dispose() {
    if (_pointer case final pointer?) {
      releasePointerForValueControl(pointer);
    }
    for (final entry in _fingers.values) {
      entry?.resolve(GestureDisposition.rejected);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final behavior = ScrollConfiguration.of(context);
    _devices.base = behavior.dragDevices;
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: _down,
      onPointerMove: _move,
      onPointerUp: _end,
      onPointerCancel: _end,
      child: ScrollConfiguration(
        behavior: behavior.copyWith(dragDevices: _devices),
        child: PanHoldGate(child: widget.child),
      ),
    );
  }
}

/// A panel's scroll drag devices with the FINGER asked at each press: it
/// joins a scroll unless the count it makes is set to 「없음」 on the canvas
/// (R26-rest-Q2).
///
/// ⚠️Asked at the press, before the driver above has counted it: a scroller
/// sits deeper and is offered the down first, so the finger being asked
/// about is the one after those already down — hence the `+ 1`.
class _FingerGatedDevices extends SetBase<PointerDeviceKind> {
  _FingerGatedDevices(this._fingersDown);

  final int Function() _fingersDown;

  /// The devices the panel's scroll behaviour already takes.
  Set<PointerDeviceKind> base = const {};

  @override
  bool contains(Object? element) {
    if (!base.contains(element)) {
      return false;
    }
    return element != PointerDeviceKind.touch ||
        AppInput.touchDragActionFor(_fingersDown() + 1) !=
            CanvasTouchDragAction.none;
  }

  @override
  PointerDeviceKind? lookup(Object? element) =>
      contains(element) ? element as PointerDeviceKind : null;

  @override
  Iterator<PointerDeviceKind> get iterator => base.iterator;

  @override
  int get length => base.length;

  @override
  Set<PointerDeviceKind> toSet() => {...base};

  @override
  bool add(PointerDeviceKind value) => throw UnsupportedError('read-only');

  @override
  bool remove(Object? value) => throw UnsupportedError('read-only');
}
