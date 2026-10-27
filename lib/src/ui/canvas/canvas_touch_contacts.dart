import 'package:flutter/gestures.dart'
    show
        PointerCancelEvent,
        PointerDeviceKind,
        PointerDownEvent,
        PointerEvent,
        PointerUpEvent;
import 'package:flutter/foundation.dart' show VoidCallback;

import '../../models/app_input_settings.dart';

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

  /// Whether a finger other than [pointer] is down anywhere: one resting
  /// on the glass beside a press — on a tablet, the modifier key held
  /// (I-69-Q5 메모, 유저 2026-10-08: 「기본적으로 데스크톱의 쉬프트나
  /// 컨트롤등 수정자키는 태블릿에선 터치임」).
  ///
  /// ⚠️[pointer] is the press's own, and this census may not have heard it
  /// yet: its observer is an ancestor, and a down is dispatched deepest
  /// first. Null asks for any finger at all.
  ///
  /// 🚨THE ONE COUNT of a modifier finger. The brush view kept a set of its
  /// own and the selection layer the first finger landing mid-drag, and the
  /// two answered the same question differently: the layer never saw a
  /// finger laid down before its press, and let go when the first of two
  /// lifted with the second still resting (I-121-Q1, 유저 2026-10-22:
  /// 「손가락도 — 세는 곳을 하나로 묶고 나서」).
  static bool aFingerDownBesides(int? pointer) =>
      _appWide.any((finger) => finger != pointer);

  /// Whether a finger beside [pointer] holds a STROKE'S Shift: one resting
  /// on the glass ([aFingerDownBesides]), behind the switch that gives a
  /// stroke one ([AppInputSettings.strokeFingerModifier] — off, it is
  /// nothing at all).
  static bool aFingerHoldsAStrokesShift(int? pointer) =>
      AppInput.settings.value.strokeFingerModifier &&
      aFingerDownBesides(pointer);

  /// Whether a finger holds a MOVE drag's Shift — one resting on the glass
  /// ([aFingerDownBesides]) beside a pen's or a mouse's drag. A drag
  /// [byTouch] takes none: its second finger stays what it was.
  ///
  /// 🗣️유저 2026-09-22: 「수정자는 항상 그렇지만 터치 입구도 존재하게」 —
  /// and how far, as the stamp's drag settled it (I-121-Q1, 유저
  /// 2026-10-22: 「펜으로 끄는 스탬프에 한해 … 손가락으로 끄는 스탬프는
  /// 지금처럼 두 번째 손가락 = 핀치」).
  static bool aFingerHoldsAMovesShift({required bool byTouch}) =>
      !byTouch && aFingerDownBesides(null);

  /// 🚨★★★D34 최종 (유저 2026-08-23, 실기): 「**커서는 일단 커서ui랑 같은곳에
  /// 있는게 최우선**이고, **터치는 커서 없애고 펜은 커서 보이는채로 유지**하는
  /// 그런것만 가능할까싶은데」
  ///
  /// 🧪The measurement that settles it. After the seed guard the ring
  /// stopped teleporting — 「100번중에 한번꼴」 — but when a mouse had already
  /// put a ring on screen it now STAYS while Windows drags the real cursor
  /// to the touch centroid: 「실제 커서는 물론 터치의 중앙에 있고」. The two
  /// disagree, and the user names the priority that resolves it.
  ///
  /// ⇒ ★THE APP CANNOT KEEP THE RING HONEST DURING A TOUCH. The promoted
  /// mouse arrives after the contacts are already gone (`touch=0/0` in the
  /// capture), so no contact-based gate can catch it, and nothing in the
  /// event distinguishes it from a hand on a mouse. What the app CAN do is
  /// stop claiming: a finger on the glass means the pointing device is not
  /// the one this ring was drawn for. A pen or mouse writes it back on its
  /// next sample, at a position that is true again.
  static final Set<VoidCallback> _appWideTouchListeners = <VoidCallback>{};

  /// Fires when a finger lands ANYWHERE — the tool cursors drop their aim
  /// on it. Separate from [addMultiTouchListener], which asks a different
  /// question (a SECOND finger on ink, to stand a running stroke down).
  static void addAppWideTouchListener(VoidCallback listener) =>
      _appWideTouchListeners.add(listener);

  static void removeAppWideTouchListener(VoidCallback listener) =>
      _appWideTouchListeners.remove(listener);

  /// Fires when a finger leaves the glass ANYWHERE — lifted or cancelled —
  /// once the census no longer counts it: a modifier finger let go of
  /// ([aFingerDownBesides]), heard after every view under it has heard the
  /// same event.
  static final Set<VoidCallback> _appWideLiftListeners = <VoidCallback>{};

  static void addAppWideLiftListener(VoidCallback listener) =>
      _appWideLiftListeners.add(listener);

  static void removeAppWideLiftListener(VoidCallback listener) =>
      _appWideLiftListeners.remove(listener);

  static void noteAppWide(PointerEvent event) {
    if (event.kind != PointerDeviceKind.touch) {
      return;
    }
    if (event is PointerDownEvent) {
      _appWide.add(event.pointer);
      for (final listener in _appWideTouchListeners.toList(growable: false)) {
        listener();
      }
    } else if ((event is PointerUpEvent || event is PointerCancelEvent) &&
        _appWide.remove(event.pointer)) {
      for (final listener in _appWideLiftListeners.toList(growable: false)) {
        listener();
      }
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
