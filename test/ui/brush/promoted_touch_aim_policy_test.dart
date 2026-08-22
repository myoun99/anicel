import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/brush/promoted_touch_aim_policy.dart';

/// 🚨★★D34 — the aim policy, pinned as a PURE FUNCTION.
///
/// ⚠️Deliberately not a widget test. The event this rule exists for is
/// produced by WINDOWS, not by the framework: the embedder never calls
/// `SkipPointerFrameMessages`, so the OS drags the system cursor to the
/// contact and a later genuine mouse sample honestly reports that position.
/// A widget test cannot manufacture that, and an earlier attempt to pin it
/// through the panel passed with the gate REMOVED — 13/13 green either way.
/// A test that cannot fail is not evidence, so the rule is stated where it
/// can actually be checked.
void main() {
  bool promoted({
    PointerDeviceKind kind = PointerDeviceKind.mouse,
    int contacts = 1,
    bool touchDraws = false,
  }) => aimIsPromotedTouch(
    kind: kind,
    touchContacts: contacts,
    touchDraws: touchDraws,
  );

  test('a mouse sample while a navigating finger is down is the promotion', () {
    expect(promoted(), isTrue);
    expect(promoted(contacts: 2), isTrue, reason: 'the pinch case reported');
  });

  test('with no finger on the glass a mouse is a mouse', () {
    expect(promoted(contacts: 0), isFalse);
  });

  test('a STYLUS is never refused — a hand steadying the tablet must not '
      'freeze a hovering pen\'s ring', () {
    expect(promoted(kind: PointerDeviceKind.stylus), isFalse);
    expect(promoted(kind: PointerDeviceKind.invertedStylus), isFalse);
    expect(
      promoted(kind: PointerDeviceKind.touch),
      isFalse,
      reason:
          'the finger itself is refused one gate up, not here — this '
          'must not double-answer a question that already has an owner',
    );
  });

  test('DRAWING mode is untouched — 「1핑거 드로잉일때 커서생기는건 ok」', () {
    expect(promoted(touchDraws: true), isFalse);
    expect(promoted(contacts: 2, touchDraws: true), isFalse);
  });

  /// 🚨★★★유저 캡처 (2026-08-23) — **the counter this rule reads was the
  /// wrong one.**
  ///
  /// ```
  /// touch move   #15 (1172,807)
  /// mouse hover  #0  (1070,751)     ← during a pure touch operation
  /// mouse scroll #0  (1070,751)     ← the pinch, promoted to a WHEEL
  /// aim census:mouse -> (1009,693) held=true touch=0 draws=false
  /// ```
  ///
  /// ⛔`touch=0` **while fingers were on the glass.** The gate was reading
  /// `CanvasTouchContacts.count`, which counts contacts on INK surfaces
  /// only — so a pinch on the timeline or the timesheet registered nowhere
  /// and the gate was blind exactly where the user was working. It reads
  /// `appWideCount` now, fed by the app's one always-mounted observer.
  test('a pinch OUTSIDE an ink surface still counts — the ink census was '
      'the wrong counter to ask', () {
    // What the app-wide census reports during a two-finger pinch on the
    // timeline: two fingers down, zero of them on ink.
    expect(promoted(contacts: 2), isTrue);
    expect(
      promoted(contacts: 0),
      isFalse,
      reason:
          'and the ink census reading 0 is exactly what it used to be '
          'handed, which is why the ring got through',
    );
  });

  test('the rule reads the CONTACTS, never a clock — 「400ms」 was invented '
      'and it swallowed real mouse hovers', () {
    // There is no time input to pass. Stated as a test so the next attempt
    // to add one has to delete this line and say why.
    expect(promoted(contacts: 0), isFalse);
    expect(promoted(contacts: 1), isTrue);
  });
}
