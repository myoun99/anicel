import 'package:anicel/src/ui/widgets/kept_tail_row.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter_test/flutter_test.dart';

/// A ROW THAT KEEPS ITS TAIL (the page turner's law): the tail whole at its
/// own width, pinned to the end — where the row is narrower, all of it,
/// smaller — and the head in what is left, never less than its own place.
/// And the row whose head gives way only down to a floor, below which both
/// are smaller ([FloorFoldRow]).
///
/// ↩️The lead — a kept end at the row's start, F-111-Q1 — went with the
/// transport's move to the bar's end (F-463).
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


  group('a row of two groups that each give way down to a floor (F-463 ⑥: '
      'the frame panels\' bar)', () {
    const floor = ValueKey<String>('floor');
    const rest = ValueKey<String>('rest');
    const restWidth = 150.0;
    const padding = 4.0;
    const gap = 8.0;

    /// A row [width] wide: the head a scroller in [padding], its first
    /// piece the [FoldFloor] — red, and pressable — the tail a ROW of its
    /// natural width.
    Future<void> pumpRow(
      WidgetTester tester,
      double width, {
      double floorWidth = 50,
      double tailHeight = tailHeight,
      VoidCallback? onFloor,
      Key? frame,
    }) => tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Align(
          alignment: Alignment.topLeft,
          child: RepaintBoundary(
            key: frame,
            child: SizedBox(
              width: width,
              height: rowHeight,
              child: FloorFoldRow(
                gap: gap,
                headPadding: 2 * padding,
                head: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: padding),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        FoldFloor(
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: onFloor,
                            child: ColoredBox(
                              color: const Color(0xFFFF0000),
                              child: SizedBox(
                                key: floor,
                                width: floorWidth,
                                height: 10,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(key: rest, width: restWidth, height: 10),
                      ],
                    ),
                  ),
                ),
                tail: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(key: tail, width: tailWidth, height: tailHeight),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );

    /// What the head shows of itself — its scroller's width.
    double headShown(WidgetTester tester) =>
        tester.getSize(find.byType(SingleChildScrollView)).width;

    testWidgets('where the row holds both whole, each stands at its own '
        'size — the head from the row\'s start, the tail at its end', (
      tester,
    ) async {
      await pumpRow(tester, 400);

      expect(
        tester.getRect(find.byKey(tail)),
        const Rect.fromLTWH(300, 10, tailWidth, tailHeight),
      );
      expect(
        tester.getRect(find.byKey(floor)),
        const Rect.fromLTWH(padding, 15, 50, 10),
      );
      expect(
        tester.getRect(find.byKey(rest)),
        const Rect.fromLTWH(padding + 50, 15, restWidth, 10),
      );
    });

    testWidgets('narrower, the HEAD gives way first — down to its floor, '
        'scrolling what it no longer shows — and the tail keeps its size', (
      tester,
    ) async {
      // The head's floor is 50 + 2 × 4; here it is left 92.
      await pumpRow(tester, 200);

      expect(tester.takeException(), isNull);
      expect(
        tester.getRect(find.byKey(tail)),
        const Rect.fromLTWH(100, 10, tailWidth, tailHeight),
      );
      expect(headShown(tester), 200 - tailWidth - gap - 2 * padding);
      expect(tester.getSize(find.byKey(floor)), const Size(50, 10));
    });

    testWidgets('🚨below the floor, BOTH groups are all of themselves, '
        'smaller by one factor — the floor whole, nothing run over', (
      tester,
    ) async {
      const width = 120.0;
      await pumpRow(tester, width);

      expect(tester.takeException(), isNull);
      const factor = width / (50 + 2 * padding + gap + tailWidth);
      final shownTail = tester.getRect(find.byKey(tail));
      expect(shownTail.width, moreOrLessEquals(tailWidth * factor));
      expect(shownTail.height, moreOrLessEquals(tailHeight * factor));
      expect(shownTail.right, moreOrLessEquals(width));
      expect(shownTail.center.dy, moreOrLessEquals(rowHeight / 2));
      final shownFloor = tester.getRect(find.byKey(floor));
      expect(shownFloor.width, moreOrLessEquals(50 * factor));
      expect(shownFloor.left, moreOrLessEquals(padding * factor));
      expect(shownFloor.center.dy, moreOrLessEquals(rowHeight / 2));
      expect(
        headShown(tester),
        moreOrLessEquals(50),
        reason: 'the head shows its floor and no more',
      );
    });

    testWidgets('the floor is what the FoldFloor is laid out at: a wider '
        'one gives way sooner', (tester) async {
      await pumpRow(tester, 200, floorWidth: 100);

      // 100 + 2 × 4 does not stand in the 92 the tail leaves.
      final shownTail = tester.getRect(find.byKey(tail));
      expect(shownTail.width, lessThan(tailWidth));
      expect(
        tester.getRect(find.byKey(floor)).right,
        lessThanOrEqualTo(shownTail.left),
        reason: 'the floor whole before the tail',
      );
    });

    testWidgets('a tail taller than the row is shown to the row\'s height, '
        'as a scaling box shows it — the head keeps its size', (
      tester,
    ) async {
      await pumpRow(tester, 400, tailHeight: 80);

      expect(
        tester.getRect(find.byKey(tail)),
        const Rect.fromLTWH(
          400 - tailWidth * rowHeight / 80,
          0,
          tailWidth * rowHeight / 80,
          rowHeight,
        ),
      );
      expect(tester.getSize(find.byKey(floor)), const Size(50, 10));
    });

    testWidgets('a group shown smaller is PAINTED smaller — nothing of it '
        'past what is shown', (tester) async {
      const frame = ValueKey<String>('frame');
      await pumpRow(tester, 120, frame: frame);
      final shown = tester.getRect(find.byKey(floor));
      expect(shown.right, lessThan(45), reason: '⛔전제: smaller');

      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(frame),
      );
      final image = (await tester.runAsync(boundary.toImage))!;
      addTearDown(image.dispose);
      final bytes = (await tester.runAsync(image.toByteData))!;
      int redAt(int x, int y) => bytes.getUint8((y * image.width + x) * 4);

      expect(redAt(20, 20), 0xFF, reason: '⛔전제: what is shown is red');
      expect(redAt(48, 20), 0, reason: 'past what is shown, nothing of it');
    });

    testWidgets('a group shown smaller is pressed where it is shown', (
      tester,
    ) async {
      var pressed = 0;
      await pumpRow(tester, 120, onFloor: () => pressed += 1);
      final shown = tester.getRect(find.byKey(floor));
      expect(shown.width, lessThan(50), reason: '⛔전제: smaller');

      await tester.tapAt(shown.center);
      expect(pressed, 1);
      await tester.tapAt(Offset(shown.right + 2, shown.center.dy));
      expect(pressed, 1, reason: 'past what is shown is not the floor');
    });
  });
}
