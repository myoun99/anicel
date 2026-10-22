import 'package:anicel/src/ui/widgets/kept_tail_row.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// A ROW THAT KEEPS ITS TAIL (the page turner's law): the tail whole at its
/// own width, pinned to the end — where the row is narrower, all of it,
/// smaller — and the head in what is left, never less than its own place.
void main() {
  const head = ValueKey<String>('head');
  const tail = ValueKey<String>('tail');
  const tailWidth = 100.0;
  const tailHeight = 20.0;
  const rowHeight = 40.0;

  /// A row [width] wide. The tail is a ROW of its natural width — a row
  /// laid out wider than it is let be runs over, as the strips did, where
  /// a plain box would only be clamped.
  Future<void> pumpRow(
    WidgetTester tester,
    double width, {
    bool withHead = true,
    double gap = 0,
    double headKeeps = 0,
  }) => tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: width,
          height: rowHeight,
          child: KeptTailRow(
            gap: gap,
            headKeeps: headKeeps,
            head: withHead ? const SizedBox(key: head, height: 10) : null,
            tail: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(key: tail, width: tailWidth, height: tailHeight),
              ],
            ),
          ),
        ),
      ),
    ),
  );

  testWidgets('where the row holds it, the tail stands at its own size at '
      'the row\'s end, and the head takes the rest — each in the middle of '
      'the row\'s height', (tester) async {
    await pumpRow(tester, 300, gap: 8);

    expect(
      tester.getRect(find.byKey(tail)),
      const Rect.fromLTWH(200, 10, tailWidth, tailHeight),
    );
    expect(
      tester.getRect(find.byKey(head)),
      const Rect.fromLTWH(0, 15, 192, 10),
    );
  });

  testWidgets('🚨where it does not, the tail is ALL of it, smaller — never '
      'run over the row\'s end — and the head keeps its place', (
    tester,
  ) async {
    await pumpRow(tester, 90, gap: 8, headKeeps: 32);

    expect(tester.takeException(), isNull);
    const room = 90.0 - 8 - 32;
    final shown = tester.getRect(find.byKey(tail));
    expect(shown.width, moreOrLessEquals(room));
    expect(shown.height, moreOrLessEquals(tailHeight * room / tailWidth));
    expect(shown.right, moreOrLessEquals(90));
    expect(shown.center.dy, moreOrLessEquals(rowHeight / 2));
    expect(tester.getRect(find.byKey(head)).width, 32);
  });

  testWidgets('with no head the whole row is the tail\'s: no gap is kept '
      'before it, and no place for a head', (tester) async {
    await pumpRow(tester, 90, withHead: false, gap: 8, headKeeps: 32);

    expect(tester.takeException(), isNull);
    final shown = tester.getRect(find.byKey(tail));
    expect(shown.width, moreOrLessEquals(90));
    expect(shown.right, moreOrLessEquals(90));
  });
}
