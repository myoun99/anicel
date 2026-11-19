import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/ui/layout/scroll_window_part.dart';

/// Where a box in a scrolled column lays what it holds ([shownPartOf]) —
/// a slot 320 tall with a 30 strip at its head, down a window 400 tall.
void main() {
  ShownPart shown({
    required double slotTop,
    required double windowTop,
    double floor = 30,
  }) => shownPartOf(
    slot: (top: slotTop, extent: 320),
    window: (offset: windowTop, viewport: 400),
    head: 30,
    floor: floor,
  );

  test('a box the window shows all of is laid whole', () {
    expect(shown(slotTop: 40, windowTop: 0), (top: 0.0, extent: 320.0));
    expect(shown(slotTop: 80, windowTop: 0), (top: 0.0, extent: 320.0));
  });

  test('a box running past the window\'s end is laid to it', () {
    // Slot 300..620 against 0..400: its body shows 330..400.
    expect(shown(slotTop: 300, windowTop: 0), (top: 0.0, extent: 100.0));
  });

  test('a box whose top the window has passed keeps its body\'s bottom '
      'and lays its strip just above the window', () {
    // Slot 0..320 against 200..600: its body shows 200..320, its strip
    // stands at 170..200 — out of the window, where it would be anyway.
    expect(shown(slotTop: 0, windowTop: 200), (top: 170.0, extent: 150.0));
  });

  test('a strip the window shows part of is the box\'s own: laid whole', () {
    // Slot 0..320 against 10..410: the window cuts the strip, not the body.
    expect(shown(slotTop: 0, windowTop: 10), (top: 0.0, extent: 320.0));
  });

  test('a box whose body the window shows none of is laid whole', () {
    // Only its strip shows (370..400), or nothing of it at all.
    expect(shown(slotTop: 370, windowTop: 0), (top: 0.0, extent: 320.0));
    expect(shown(slotTop: 400, windowTop: 0), (top: 0.0, extent: 320.0));
    expect(shown(slotTop: 0, windowTop: 320), (top: 0.0, extent: 320.0));
  });

  test('a box is never laid shorter than its floor', () {
    // Slot 300..620 shows 70 of its body; its floor is 200.
    expect(
      shown(slotTop: 300, windowTop: 0, floor: 200),
      (top: 0.0, extent: 200.0),
      reason: 'cut from below, it keeps its top',
    );
    // Slot 0..320 against 260..660 shows 60 of its body.
    expect(
      shown(slotTop: 0, windowTop: 260, floor: 200),
      (top: 120.0, extent: 200.0),
      reason: 'cut from above, it keeps its bottom',
    );
    expect(
      shown(slotTop: 300, windowTop: 0, floor: 320),
      (top: 0.0, extent: 320.0),
      reason: 'a floor of the whole box lays it whole',
    );
  });
}
