import 'package:anicel/src/ui/widgets/kept_tail_row.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
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

  group('a row that keeps its LEAD too (F-111-Q1: the frame panels\' bar '
      'pins the transport at its start)', () {
    const lead = ValueKey<String>('lead');
    const leadWidth = 60.0;
    const leadHeight = 30.0;

    /// A row [width] wide with a lead, a head and a tail — the lead a ROW
    /// of its natural width, as the tail is, and pressable.
    Future<void> pumpRow(
      WidgetTester tester,
      double width, {
      double gap = 0,
      double headKeeps = 0,
      VoidCallback? onLead,
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
              lead: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: onLead,
                    child: const SizedBox(
                      key: lead,
                      width: leadWidth,
                      height: leadHeight,
                    ),
                  ),
                ],
              ),
              head: const SizedBox(key: head, height: 10),
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

    testWidgets('where the row holds them, the lead stands at its own size '
        'at the row\'s start, the tail at its end, and the head between — '
        'a gap either side of it', (tester) async {
      await pumpRow(tester, 300, gap: 8);

      expect(
        tester.getRect(find.byKey(lead)),
        const Rect.fromLTWH(0, 5, leadWidth, leadHeight),
      );
      expect(
        tester.getRect(find.byKey(tail)),
        const Rect.fromLTWH(200, 10, tailWidth, tailHeight),
      );
      expect(
        tester.getRect(find.byKey(head)),
        const Rect.fromLTWH(leadWidth + 8, 15, 300 - 160 - 16, 10),
      );
    });

    testWidgets('🚨where it cannot hold both ends, BOTH are all of '
        'themselves, smaller by one factor — neither gives way for the '
        'other, none runs over — and the head keeps its place', (
      tester,
    ) async {
      const width = 120.0;
      await pumpRow(tester, width, gap: 8, headKeeps: 20);

      expect(tester.takeException(), isNull);
      const factor = (width - 2 * 8 - 20) / (leadWidth + tailWidth);
      final shownLead = tester.getRect(find.byKey(lead));
      final shownTail = tester.getRect(find.byKey(tail));
      expect(shownLead.width, moreOrLessEquals(leadWidth * factor));
      expect(shownLead.height, moreOrLessEquals(leadHeight * factor));
      expect(shownTail.width, moreOrLessEquals(tailWidth * factor));
      expect(shownTail.height, moreOrLessEquals(tailHeight * factor));
      expect(shownLead.left, moreOrLessEquals(0));
      expect(shownTail.right, moreOrLessEquals(width));
      expect(shownLead.center.dy, moreOrLessEquals(rowHeight / 2));
      expect(shownTail.center.dy, moreOrLessEquals(rowHeight / 2));
      final shownHead = tester.getRect(find.byKey(head));
      expect(shownHead.width, moreOrLessEquals(20));
      expect(shownHead.left, moreOrLessEquals(shownLead.right + 8));
    });

    testWidgets('a kept end taller than the row is shown to the row\'s '
        'height, as a scaling box shows it — the other end keeps its size', (
      tester,
    ) async {
      await tester.pumpWidget(
        const Directionality(
          textDirection: TextDirection.ltr,
          child: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 300,
              height: rowHeight,
              child: KeptTailRow(
                lead: SizedBox(key: lead, width: leadWidth, height: 80),
                tail: SizedBox(
                  key: tail,
                  width: tailWidth,
                  height: tailHeight,
                ),
              ),
            ),
          ),
        ),
      );

      expect(
        tester.getRect(find.byKey(lead)),
        const Rect.fromLTWH(0, 0, leadWidth * rowHeight / 80, rowHeight),
      );
      expect(
        tester.getRect(find.byKey(tail)).size,
        const Size(tailWidth, tailHeight),
      );
    });

    testWidgets('a lead shown smaller is PAINTED smaller — nothing of it '
        'past what is shown', (tester) async {
      const frame = ValueKey<String>('frame');
      await tester.pumpWidget(
        const Directionality(
          textDirection: TextDirection.ltr,
          child: Align(
            alignment: Alignment.topLeft,
            child: RepaintBoundary(
              key: frame,
              child: SizedBox(
                width: 120,
                height: rowHeight,
                child: KeptTailRow(
                  lead: ColoredBox(
                    color: Color(0xFFFF0000),
                    child: SizedBox(width: leadWidth, height: leadHeight),
                  ),
                  tail: SizedBox(width: tailWidth, height: tailHeight),
                ),
              ),
            ),
          ),
        ),
      );
      // One factor for both ends: 120 / (60 + 100) — the lead shown 45 wide.
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(frame),
      );
      final image = (await tester.runAsync(boundary.toImage))!;
      addTearDown(image.dispose);
      final bytes = (await tester.runAsync(image.toByteData))!;
      int redAt(int x, int y) => bytes.getUint8((y * image.width + x) * 4);

      expect(redAt(40, 20), 0xFF, reason: 'premise: what is shown is red');
      expect(redAt(55, 20), 0, reason: 'past 45, nothing of the lead');
    });

    testWidgets('a lead shown smaller is pressed where it is shown', (
      tester,
    ) async {
      var pressed = 0;
      await pumpRow(tester, 120, gap: 8, onLead: () => pressed += 1);
      final shown = tester.getRect(find.byKey(lead));
      expect(shown.width, lessThan(leadWidth), reason: 'premise: smaller');

      await tester.tapAt(shown.center);
      expect(pressed, 1);
      await tester.tapAt(Offset(shown.right + 2, shown.center.dy));
      expect(pressed, 1, reason: 'past what is shown is not the lead');
    });
  });
}
