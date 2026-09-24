import 'dart:async';

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/gestures.dart' show PointerDeviceKind, kTouchSlop;
import 'package:flutter/widgets.dart';

/// The multi-finger touch gesture vocabulary (R11-⑨, user-picked: taps +
/// holds). Every registry action can bind ONE of these in the Shortcuts
/// dialog, exactly like a key binding.
enum TouchGesture {
  twoFingerTap,
  threeFingerTap,
  fourFingerTap,
  twoFingerLongPress,
  threeFingerLongPress;

  String get label => switch (this) {
    TouchGesture.twoFingerTap => '2-Finger Tap',
    TouchGesture.threeFingerTap => '3-Finger Tap',
    TouchGesture.fourFingerTap => '4-Finger Tap',
    TouchGesture.twoFingerLongPress => '2-Finger Hold',
    TouchGesture.threeFingerLongPress => '3-Finger Hold',
  };

  static TouchGesture? fromName(String? name) {
    for (final gesture in TouchGesture.values) {
      if (gesture.name == name) {
        return gesture;
      }
    }
    return null;
  }
}

/// Observes RAW touch pointers over its child and fires the bound
/// [TouchGesture] when a stationary multi-finger tap or hold releases.
///
/// Purely observational (a translucent [Listener]): drawing (one finger),
/// pinch navigation and every widget underneath keep working — a gesture
/// only fires when ALL fingers lift without ever moving past the touch
/// slop, which is exactly the contact pattern pinches and strokes never
/// produce. Mouse and stylus pointers are ignored.
class TouchShortcutLayer extends StatefulWidget {
  const TouchShortcutLayer({
    super.key,
    required this.onGesture,
    this.playing,
    required this.child,
  });

  final ValueChanged<TouchGesture> onGesture;

  /// Whether anything plays. A gesture whose FIRST finger lands while this
  /// reads true fires nothing when its fingers lift.
  ///
  /// 🚨T28-c (유저): 「재생 중 첫 작동은 정지이고, **정지일 뿐이다**」. On the
  /// playing canvas the fingers pass through to navigate (D13), and the
  /// panel's own tap-to-stop stops playback when the first of them lifts —
  /// so by the time the gesture fired, nothing played any more and the
  /// action funnel's playback check let it through. Measured 2026-09-24: a
  /// four-finger tap stopped playback and then started it again, and a
  /// two-finger tap stopped it AND undid. The question has to be asked when
  /// the gesture BEGINS, which only this layer sees.
  final ValueListenable<bool>? playing;

  final Widget child;

  /// Releases faster than this are taps; slower ones are holds.
  static const Duration holdThreshold = Duration(milliseconds: 450);

  /// Contacts held past this are abandoned (a rest, not a shortcut).
  static const Duration gestureDeadline = Duration(seconds: 2);

  @override
  State<TouchShortcutLayer> createState() => _TouchShortcutLayerState();
}

class _TouchShortcutLayerState extends State<TouchShortcutLayer> {
  final Map<int, Offset> _downPositions = <int, Offset>{};
  int _maxSimultaneous = 0;
  bool _moved = false;

  /// The gesture began while something played ([TouchShortcutLayer.playing]).
  bool _spentOnStop = false;

  /// Event timestamps (not wall clock): correct under the test binding's
  /// fake clock AND the engine's event times on device.
  Duration? _firstDown;

  void _reset() {
    _downPositions.clear();
    _maxSimultaneous = 0;
    _moved = false;
    _spentOnStop = false;
    _firstDown = null;
  }

  void _handleDown(PointerDownEvent event) {
    if (event.kind != PointerDeviceKind.touch) {
      return;
    }
    if (_downPositions.isEmpty) {
      _moved = false;
      _maxSimultaneous = 0;
      _spentOnStop = widget.playing?.value ?? false;
      _firstDown = event.timeStamp;
    }
    _downPositions[event.pointer] = event.position;
    if (_downPositions.length > _maxSimultaneous) {
      _maxSimultaneous = _downPositions.length;
    }
  }

  void _handleMove(PointerMoveEvent event) {
    final start = _downPositions[event.pointer];
    if (start == null || _moved) {
      return;
    }
    if ((event.position - start).distance > kTouchSlop) {
      _moved = true;
    }
  }

  void _handleUp(PointerUpEvent event) {
    if (_downPositions.remove(event.pointer) == null) {
      return;
    }
    if (_downPositions.isNotEmpty) {
      return;
    }
    final firstDown = _firstDown;
    final fingers = _maxSimultaneous;
    final moved = _moved;
    final spentOnStop = _spentOnStop;
    _reset();
    if (spentOnStop || moved || firstDown == null || fingers < 2) {
      return;
    }
    final held = event.timeStamp - firstDown;
    if (held >= TouchShortcutLayer.gestureDeadline) {
      return;
    }
    final isHold = held >= TouchShortcutLayer.holdThreshold;
    final gesture = switch ((fingers, isHold)) {
      (2, false) => TouchGesture.twoFingerTap,
      (3, false) => TouchGesture.threeFingerTap,
      (>= 4, false) => TouchGesture.fourFingerTap,
      (2, true) => TouchGesture.twoFingerLongPress,
      (3, true) => TouchGesture.threeFingerLongPress,
      _ => null,
    };
    if (gesture == null) {
      return;
    }
    // 🚨★★★THE GESTURE FIRES ONCE ITS LIFT HAS BEEN HEARD EVERYWHERE — after
    // this event's dispatch, not inside it.
    //
    // 유저 2026-09-24: 「두손가락 핑거로 언두랑 세손가락 리두가
    // 안먹히는거같으니」. This listener hears the last finger's up BEFORE the
    // pointer router does (hit-test targets first, the router last), and the
    // router is where the app counts the contacts that are down. Fired here,
    // undo and redo asked F-173's 「is a verb in flight」 while that count
    // still held the finger that was leaving — and refused, every time.
    //
    // A microtask runs the moment the pointer queue drains: the same frame,
    // no latency. A contact that is REALLY still down — a pen mid-stroke —
    // is still counted then, so F-173 holds.
    scheduleMicrotask(() {
      if (mounted) {
        widget.onGesture(gesture);
      }
    });
  }

  void _handleCancel(PointerCancelEvent event) {
    if (_downPositions.remove(event.pointer) == null) {
      return;
    }
    if (_downPositions.isEmpty) {
      _reset();
    } else {
      // A cancelled contact invalidates the whole gesture.
      _moved = true;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: _handleDown,
      onPointerMove: _handleMove,
      onPointerUp: _handleUp,
      onPointerCancel: _handleCancel,
      child: widget.child,
    );
  }
}
