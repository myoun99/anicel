import 'package:flutter/gestures.dart'
    show
        PointerCancelEvent,
        PointerDeviceKind,
        PointerDownEvent,
        PointerEvent,
        PointerUpEvent;
import 'package:flutter/foundation.dart' show VoidCallback;

/// The ink views' SHARED finger census (R26 #5).
///
/// A single canvas view can count its own contacts, but the TIMESHEET
/// mounts one [InteractiveBrushEditCanvasView] per sheet window — two
/// fingers landing on two different windows each looked like a lone
/// contact, so both drew a line while the user was only trying to pinch
/// the panel. Every touch contact registers here, app-wide, so any view
/// can ask "how many fingers are down on ink surfaces right now?".
///
/// Process-wide static state on purpose: there is one pair of hands.
class CanvasTouchContacts {
  CanvasTouchContacts._();

  static final Set<int> _pointers = <int>{};
  static final Set<VoidCallback> _multiTouchListeners = <VoidCallback>{};

  /// Fingers currently down on ANY ink surface.
  static int get count => _pointers.length;

  /// 🚨★★★D34 — **FINGERS ANYWHERE IN THE APP**, not just on ink.
  ///
  /// 🧪유저 캡처 (2026-08-23) — a pure touch operation, and the aim probe
  /// printed the answer outright:
  ///
  /// ```
  /// touch move   #15 (1172,807)
  /// mouse hover  #0  (1070,751)      ← during the touch
  /// mouse scroll #0  (1070,751)      ← the pinch, promoted to a WHEEL
  /// touch move   #14 (970,698)
  /// aim census:mouse -> (1009,693) held=true touch=0 draws=false
  /// ```
  ///
  /// ⛔TWO of my conclusions were wrong, and this counter is the second one.
  ///
  /// 1. 「승격된 마우스는 앱 이벤트로 안 온다」 — I said that from ONE frozen
  ///    screenshot that happened not to contain any. It does: Windows
  ///    promotes the pinch to `mouse hover` + `mouse scroll` at the
  ///    centroid, and Flutter delivers them.
  /// 2. The gate I built on [count] reads **`touch=0` while fingers are on
  ///    the glass** — because [count] only knows contacts on INK surfaces.
  ///    A pinch on the timeline or the timesheet registers nowhere, so the
  ///    gate was blind exactly where the user was working.
  ///
  /// ⚠️[count] must NOT be widened to fix this. It has a job of its own —
  /// a second finger on an ink surface stands a running stroke down — and
  /// counting a finger on the timeline there would abort strokes for a
  /// gesture that never touched the canvas. Two questions, two counters.
  ///
  /// Fed by the app's ONE always-mounted pointer observer
  /// (`InputInspectorHost`), which already sees every event regardless of
  /// which panel it lands on.
  static final Set<int> _appWide = <int>{};

  /// Fingers currently down ANYWHERE — any panel, any surface.
  static int get appWideCount => _appWide.length;

  static void noteAppWide(PointerEvent event) {
    if (event.kind != PointerDeviceKind.touch) {
      return;
    }
    if (event is PointerDownEvent) {
      _appWide.add(event.pointer);
    } else if (event is PointerUpEvent || event is PointerCancelEvent) {
      _appWide.remove(event.pointer);
    }
  }

  /// Views listen so a stroke already running on ANOTHER view can stand
  /// down the moment a second finger lands — the sibling never sees that
  /// pointer's own down event.
  static void addMultiTouchListener(VoidCallback listener) =>
      _multiTouchListeners.add(listener);

  static void removeMultiTouchListener(VoidCallback listener) =>
      _multiTouchListeners.remove(listener);

  static void add(int pointer) {
    _pointers.add(pointer);
    if (_pointers.length < 2) {
      return;
    }
    for (final listener in _multiTouchListeners.toList(growable: false)) {
      listener();
    }
  }

  static void remove(int pointer) => _pointers.remove(pointer);

  /// Drops a view's contacts wholesale — a view disposed mid-touch never
  /// gets its pointer-up, and a leaked contact would block drawing until
  /// the app restarts.
  static void removeAll(Iterable<int> pointers) =>
      _pointers.removeAll(pointers);

  /// Test seam.
  static void reset() {
    _pointers.clear();
    _appWide.clear();
  }
}
