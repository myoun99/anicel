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

  /// Views listen so a stroke already running on ANOTHER view can stand
  /// down the moment a second finger lands — the sibling never sees that
  /// pointer's own down event.
  static void addMultiTouchListener(VoidCallback listener) =>
      _multiTouchListeners.add(listener);

  static void removeMultiTouchListener(VoidCallback listener) =>
      _multiTouchListeners.remove(listener);

  /// 🚨D34 (유저 2026-08-21, 재개): 「**커서가 있는 툴**을 사용하는 경우
  /// (브러시/스포이드). 터치조작시 **해당 커서가 보임.** 위치는 **터치의
  /// 중앙부분** … 어떤 툴을 쓰든 터치조작 하고나면 **마우스 커서가 해당
  /// 위치로 이동**해 있음. 다만 **바탕화면에서 터치하면 커서가 안 움직이는 걸
  /// 보면 디바이스 문제는 아닌 것 같다**」
  ///
  /// 🧪THE CAUSE IS NOT OURS AND CANNOT BE FIXED HERE. Flutter's Windows
  /// embedder handles `WM_POINTERDOWN` and then falls through to
  /// `DefWindowProc` without ever calling `SkipPointerFrameMessages` (zero
  /// hits in the entire engine, 3.44.2), so Windows also synthesizes the
  /// LEGACY mouse messages for that touch — and synthesizing a
  /// `WM_MOUSEMOVE` physically moves the system cursor to the touch point.
  /// The desktop is unaffected because the shell suppresses that promotion,
  /// which is exactly the difference the user spotted.
  ///
  /// ⇒ THE CURSOR REALLY IS THERE, so a mouse sample that arrives just
  /// afterwards is telling the truth about a position the user never
  /// pointed at. This stamp is what lets the tool aim ignore it: a mouse
  /// that "moves" while a finger is on the glass — or in the moment right
  /// after one lifts — is Windows' promotion talking, not a hand.
  ///
  /// ⚠️A COARSE window on purpose. It answers 「was a finger just here」,
  /// not 「how long ago exactly」. A real mouse the user then moves writes
  /// the aim on its very next sample, so the worst case is one skipped ring
  /// update — against a ring that otherwise jumps to wherever the last
  /// touch landed.
  static DateTime? _lastContactAt;

  /// Test seam: the clock the window below reads.
  static DateTime Function() debugClock = DateTime.now;

  /// How long after the last finger lifts a mouse sample is still assumed
  /// to be the touch promotion rather than a hand.
  static const Duration promotionWindow = Duration(milliseconds: 400);

  /// Whether a mouse sample right now is more likely Windows' promoted
  /// touch than a real mouse — fingers down, or one lifted a moment ago.
  static bool get mouseIsProbablyPromotedTouch {
    if (_pointers.isNotEmpty) {
      return true;
    }
    final last = _lastContactAt;
    return last != null && debugClock().difference(last) < promotionWindow;
  }

  static void add(int pointer) {
    _pointers.add(pointer);
    _lastContactAt = debugClock();
    if (_pointers.length < 2) {
      return;
    }
    for (final listener in _multiTouchListeners.toList(growable: false)) {
      listener();
    }
  }

  static void remove(int pointer) {
    if (_pointers.remove(pointer)) {
      _lastContactAt = debugClock();
    }
  }

  /// Drops a view's contacts wholesale — a view disposed mid-touch never
  /// gets its pointer-up, and a leaked contact would block drawing until
  /// the app restarts.
  static void removeAll(Iterable<int> pointers) {
    final before = _pointers.length;
    _pointers.removeAll(pointers);
    if (_pointers.length != before) {
      _lastContactAt = debugClock();
    }
  }

  /// Test seam.
  static void reset() {
    _pointers.clear();
    _lastContactAt = null;
  }
}
