import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/canvas/canvas_touch_contacts.dart';

/// 🚨D34 재개 (유저 2026-08-21) — **터치가 만든 마우스는 손이 아니다.**
///
/// > 「**커서가 있는 툴**을 사용하는 경우(브러시/스포이드). 터치조작시 **해당
/// > 커서가 보임.** 위치는 **터치의 중앙부분** … 어떤 툴을 쓰든 터치조작
/// > 하고나면 **마우스 커서가 해당 위치로 이동**해 있음. 다만 **바탕화면에서
/// > 터치하면 커서가 안 움직이는 걸 보면 디바이스 문제는 아닌 것 같다**」
///
/// 🧪The cause was traced to Flutter's Windows embedder, not to this app:
/// `flutter_window.cc` handles `WM_POINTERDOWN` and then falls through to
/// `DefWindowProc` without calling `SkipPointerFrameMessages` (zero hits in
/// the whole engine at 3.44.2), so Windows also synthesizes the legacy mouse
/// messages — and that synthesis physically moves the system cursor to the
/// touch point. The desktop escapes because the shell suppresses promotion,
/// which is exactly the difference the user reported.
///
/// ⇒ We cannot stop the cursor moving. What we can stop is the tool aim
/// believing a mouse sample that only exists because a finger was there.
void main() {
  var now = DateTime(2026, 8, 23, 12);

  setUp(() {
    CanvasTouchContacts.reset();
    CanvasTouchContacts.debugClock = () => now;
  });

  tearDown(() {
    CanvasTouchContacts.debugClock = DateTime.now;
    CanvasTouchContacts.reset();
  });

  test('with no touch anywhere near, a mouse sample is a mouse', () {
    expect(CanvasTouchContacts.mouseIsProbablyPromotedTouch, isFalse);
  });

  test('while a finger is down, a mouse sample is the promotion', () {
    CanvasTouchContacts.add(1);
    expect(CanvasTouchContacts.mouseIsProbablyPromotedTouch, isTrue);
  });

  test('and for a moment after it lifts — the promoted move arrives AFTER '
      'the pointer frame, which is when the cursor actually jumps', () {
    CanvasTouchContacts.add(1);
    CanvasTouchContacts.remove(1);
    expect(CanvasTouchContacts.count, 0);
    expect(
      CanvasTouchContacts.mouseIsProbablyPromotedTouch,
      isTrue,
      reason:
          '⛔this is the case that matters: 「터치조작 하고나면」 — the '
          'ring jumped after the finger was already gone',
    );
  });

  test('the window closes, so a real mouse is never locked out', () {
    CanvasTouchContacts.add(1);
    CanvasTouchContacts.remove(1);
    now = now.add(CanvasTouchContacts.promotionWindow * 2);
    expect(
      CanvasTouchContacts.mouseIsProbablyPromotedTouch,
      isFalse,
      reason:
          'a hand that then picks up the mouse must move the aim on its '
          'very next sample — the worst case is ONE skipped update',
    );
  });

  test('a view disposed mid-touch stamps too — its contacts never get an '
      'up, and a leaked stamp would be worse than a leaked contact', () {
    CanvasTouchContacts.add(1);
    CanvasTouchContacts.add(2);
    CanvasTouchContacts.removeAll([1, 2]);
    expect(CanvasTouchContacts.count, 0);
    expect(CanvasTouchContacts.mouseIsProbablyPromotedTouch, isTrue);
  });

  test('removing a pointer that was never down does not restamp', () {
    CanvasTouchContacts.add(1);
    CanvasTouchContacts.remove(1);
    now = now.add(CanvasTouchContacts.promotionWindow * 2);
    CanvasTouchContacts.remove(99);
    expect(
      CanvasTouchContacts.mouseIsProbablyPromotedTouch,
      isFalse,
      reason:
          'a spurious up must not re-open the window — that is how a '
          'coarse guard turns into a mouse that stops working',
    );
  });
}
