import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/canvas/canvas_touch_contacts.dart';

/// 🚨★★★D34 최종 (유저 2026-08-23, 실기): 「**커서는 일단 커서ui랑 같은곳에
/// 있는게 최우선**이고, **터치는 커서 없애고 펜은 커서 보이는채로 유지**하는
/// 그런것만 가능할까싶은데」
///
/// Windows drags the real cursor to the touch the moment a finger lands, so
/// a ring left standing at the old spot is a lie about where the pointer is
/// — 「실제 커서는 물론 터치의 중앙에 있고」. The app cannot make it true (the
/// promoted mouse arrives after the contacts are gone, `touch=0/0`), so it
/// stops claiming: a finger anywhere drops the aim, and a pen or mouse
/// writes it back on its next sample.
void main() {
  tearDown(CanvasTouchContacts.reset);

  PointerDownEvent down(int pointer, PointerDeviceKind kind) =>
      PointerDownEvent(pointer: pointer, kind: kind);

  test('a finger landing ANYWHERE tells the tool cursors to drop the aim', () {
    var fired = 0;
    void listener() => fired += 1;
    CanvasTouchContacts.addAppWideTouchListener(listener);
    addTearDown(() => CanvasTouchContacts.removeAppWideTouchListener(listener));

    CanvasTouchContacts.noteAppWide(down(1, PointerDeviceKind.touch));
    expect(fired, 1);
    // MUTATION GUARD: removing the notify loop makes this 0.

    expect(CanvasTouchContacts.appWideCount, 1);
    expect(
      CanvasTouchContacts.count,
      0,
      reason:
          '⛔and NOT on the ink census — that one answers a different '
          'question (a second finger standing a running stroke down), and '
          'reading it here is exactly what left the gate blind on the '
          'timeline',
    );
  });

  test('a PEN does not — 「펜은 커서 보이는채로 유지」', () {
    var fired = 0;
    void listener() => fired += 1;
    CanvasTouchContacts.addAppWideTouchListener(listener);
    addTearDown(() => CanvasTouchContacts.removeAppWideTouchListener(listener));

    CanvasTouchContacts.noteAppWide(down(1, PointerDeviceKind.stylus));
    CanvasTouchContacts.noteAppWide(down(2, PointerDeviceKind.mouse));
    expect(fired, 0);
    expect(CanvasTouchContacts.appWideCount, 0);
  });

  test('the app-wide count follows up AND cancel — a leaked contact would '
      'hold the aim down for the life of the app', () {
    CanvasTouchContacts.noteAppWide(down(1, PointerDeviceKind.touch));
    CanvasTouchContacts.noteAppWide(down(2, PointerDeviceKind.touch));
    expect(CanvasTouchContacts.appWideCount, 2);

    CanvasTouchContacts.noteAppWide(
      const PointerUpEvent(pointer: 1, kind: PointerDeviceKind.touch),
    );
    CanvasTouchContacts.noteAppWide(
      const PointerCancelEvent(pointer: 2, kind: PointerDeviceKind.touch),
    );
    expect(CanvasTouchContacts.appWideCount, 0);
  });
}
