import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/ui/input/eager_pan_gesture_recognizer.dart';
import 'package:anicel/src/ui/input/value_control_pointers.dart';

/// 🚨★★★A PRESS THAT LANDS ON A CONTROL BELONGS TO THAT CONTROL.
///
/// The law is in CLAUDE.md and its rationale in `axis_bar_gesture.dart`.
/// 유저 has stated it three times — 2026-08-14 for sliders (「슬라이더위에서
/// 조작하기 시작하면 슬라이더조작하는거고 **그 외가 스크롤인거야**」),
/// 08-28 for buttons, and 08-29:
///
/// > 「**터치 좌표가 버튼인데 거기서 움직였다고 스크롤이 발생하는게 심각한
/// > 버그야**」
///
/// ⛔THERE ARE TWO CLAIMS AND THAT IS NOT A COPY. A slider takes the strong
/// one because dragging IS its verb; a button takes the weak one because a
/// button must not own drags outright — the rail's eye-column swipe starts
/// on a button and is a real gesture. Collapsing them would break that
/// swipe, which is exactly why commit 0ccc1163 split them.
///
/// What was wrong was the QUESTION the pan asked: only the strong claim.
/// So a drag beginning on a button was allowed through and the row list
/// scrolled under the finger that pressed the eye.
void main() {
  setUp(debugClearValueControlPointers);
  tearDown(debugClearValueControlPointers);

  /// ⛔A HANDLER IS PART OF THE FIXTURE. `DragGestureRecognizer`
  /// answers `isPointerAllowed` false whenever no callback is attached —
  /// so a bare recogniser declines everything, and a test built on one
  /// would "pass" the two decline cases while measuring nothing.
  EagerPanGestureRecognizer newPan() =>
      EagerPanGestureRecognizer()..onStart = (_) {};

  PointerDownEvent down(int pointer) => PointerDownEvent(
    pointer: pointer,
    // ⛔A MOUSE, deliberately. `computeHitSlop` is 18px for a stylus and
    // 1px for a mouse, and three earlier attempts at this bug came back
    // green because they were measured with a stylus — the file that owns
    // these sets says so in as many words.
    kind: PointerDeviceKind.mouse,
    position: const Offset(10, 10),
  );

  test('a pan declines a pointer a BUTTON is holding', () {
    final pan = newPan();
    addTearDown(pan.dispose);
    claimTapForControl(7);
    expect(
      pan.isPointerAllowed(down(7)),
      isFalse,
      reason:
          'the press landed on a button, so the movement after it is '
          'not a scroll',
    );
  });

  test('a pan declines a pointer a SLIDER is holding', () {
    // The case that already worked — pinned so a change to the predicate
    // cannot fix buttons by dropping sliders.
    final pan = newPan();
    addTearDown(pan.dispose);
    claimPointerForValueControl(9);
    expect(pan.isPointerAllowed(down(9)), isFalse);
  });

  test('a pan takes a pointer NOBODY claimed', () {
    // ⛔THE CONTROL. A predicate that always declined would pass both tests
    // above and leave the panel unable to scroll at all.
    final pan = newPan();
    addTearDown(pan.dispose);
    expect(
      pan.isPointerAllowed(down(11)),
      isTrue,
      reason: 'scrolling still happens — everywhere that is not a control',
    );
  });

  test('releasing gives the pointer back', () {
    // 🚨A claim that outlives its gesture would deafen every later press
    // handed the same id — the id is recycled, so this is not theoretical.
    final pan = newPan();
    addTearDown(pan.dispose);
    claimTapForControl(3);
    expect(pan.isPointerAllowed(down(3)), isFalse);
    releaseTapForControl(3);
    expect(pan.isPointerAllowed(down(3)), isTrue);
  });

  test('a swipe column keeps BOTH claims, so it is unaffected', () {
    // The rail's swipe columns take the strong claim as well as the weak
    // one. Releasing only the weak claim must leave them held — otherwise
    // widening the question would have silently changed which gesture wins
    // on the eye column.
    final pan = newPan();
    addTearDown(pan.dispose);
    claimTapForControl(5);
    claimPointerForValueControl(5);
    releaseTapForControl(5);
    expect(pan.isPointerAllowed(down(5)), isFalse);
  });
}
