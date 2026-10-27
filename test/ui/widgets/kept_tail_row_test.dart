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
                // The padding after the floor: the one before it is where the
                // floor stands in its group.
                headPadding: padding,
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

  // ↩️F-463-Q1's 「묶음 안에서 재생 · 줌이 따로」 (15:23) gave this row a
  // middle group, the tail and it giving way in turn, until the answer
  // became one right group (20:2x), kept by its start until F-491.
  group('🗣️F-491 (유저 10-27 23:15: 「오른쪽이 마지막에 남도록 … 왼쪽묶음은 '
      '… 제일 왼쪽것이 마지막으로 남는구조」): past the head\'s floor the TAIL '
      'gives way, down to its own floor — the head kept by its start, the '
      'tail by its end', () {
    const lead = ValueKey<String>('lead');
    const headFloor = ValueKey<String>('head-floor');
    const tailFloor = ValueKey<String>('tail-floor');
    const gap = 8.0;

    /// The head: 20 that stand before its floor, the floor's 30, and 70
    /// after — the last in a scroller of its own, as the bar's pills after
    /// its transport.
    Widget head() => const Row(
      children: [
        SizedBox(key: lead, width: 20, height: 10),
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                FoldFloor(
                  child: SizedBox(key: headFloor, width: 30, height: 10),
                ),
                SizedBox(width: 70, height: 10),
              ],
            ),
          ),
        ),
      ],
    );

    /// The tail: 70, then its floor's 30 — in a scroller that stands at
    /// its end.
    Widget tail() => const SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      reverse: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(width: 70, height: 10),
          FoldFloor(child: SizedBox(key: tailFloor, width: 30, height: 10)),
        ],
      ),
    );

    Future<void> pumpRow(WidgetTester tester, double width) =>
        tester.pumpWidget(
          Directionality(
            textDirection: TextDirection.ltr,
            child: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: width,
                height: rowHeight,
                child: FloorFoldRow(gap: gap, head: head(), tail: tail()),
              ),
            ),
          ),
        );

    /// Where [floor]'s group is shown — its scroller.
    Finder groupOf(Key floor) => find.ancestor(
      of: find.byKey(floor),
      matching: find.byType(SingleChildScrollView),
    );

    testWidgets('where the row holds it, the tail is whole', (tester) async {
      await pumpRow(tester, 250);

      expect(tester.takeException(), isNull);
      expect(tester.getRect(groupOf(headFloor)).width, 250 - gap - 100 - 20);
      expect(
        tester.getRect(groupOf(tailFloor)),
        const Rect.fromLTWH(150, 15, 100, 10),
      );
    });

    testWidgets('narrower, the head at its floor — what stands before it '
        'kept too — and the tail gives way from its START: its floor whole '
        'at its end, the rest its own to scroll', (tester) async {
      // The head at its 20 + 30; the tail is left 140 − 50 − 8.
      await pumpRow(tester, 140);

      expect(tester.takeException(), isNull);
      expect(tester.getRect(find.byKey(lead)).left, 0);
      expect(tester.getRect(groupOf(headFloor)).width, 30);
      expect(
        tester.getRect(groupOf(tailFloor)),
        const Rect.fromLTWH(58, 15, 82, 10),
      );
      expect(
        tester.getRect(find.byKey(tailFloor)),
        const Rect.fromLTWH(110, 15, 30, 10),
        reason: 'its floor whole, at its end',
      );
      final hidden = tester
          .state<ScrollableState>(
            find.descendant(
              of: groupOf(tailFloor),
              matching: find.byType(Scrollable),
            ),
          )
          .position;
      expect(hidden.pixels, 0, reason: 'shown from its end');
      expect(
        hidden.maxScrollExtent,
        100 - 82,
        reason: 'its start to scroll to',
      );
    });

    testWidgets('🚨below both floors, both of them at their floors, smaller '
        'by one factor — each floor whole, nothing run over', (tester) async {
      const width = 60.0;
      await pumpRow(tester, width);

      expect(tester.takeException(), isNull);
      const factor = width / (20 + 30 + gap + 30);
      for (final floor in [headFloor, tailFloor]) {
        final group = tester.getRect(groupOf(floor));
        expect(group.width, moreOrLessEquals(30 * factor), reason: '$floor');
        final shown = tester.getRect(find.byKey(floor));
        expect(shown.left, moreOrLessEquals(group.left), reason: '$floor');
        expect(
          shown.right,
          moreOrLessEquals(group.right),
          reason: '$floor shows its floor and no more',
        );
      }
      expect(tester.getRect(groupOf(tailFloor)).right, moreOrLessEquals(width));
      expect(tester.getRect(find.byKey(lead)).left, 0);
      expect(
        tester.getRect(find.byKey(lead)).width,
        moreOrLessEquals(20 * factor),
        reason: 'what stands before the head\'s floor, smaller with it',
      );
    });
  });

  // The bar's head holds two: the transport's own floor and the cut
  // pill's past it (F-491).
  group('a group with more than one floor is kept to the farthest', () {
    const near = ValueKey<String>('near');
    const far = ValueKey<String>('far');
    const gap = 8.0;

    /// A head of 10, 30 and 70 — the first two floors where [withNear] and
    /// [withFar] say so — and a tail of 100.
    Future<void> pumpRow(
      WidgetTester tester,
      double width, {
      bool withNear = true,
      bool withFar = true,
    }) => tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: width,
            height: rowHeight,
            child: FloorFoldRow(
              gap: gap,
              head: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (withNear)
                      const FoldFloor(
                        child: SizedBox(key: near, width: 10, height: 10),
                      )
                    else
                      const SizedBox(key: near, width: 10, height: 10),
                    if (withFar)
                      const FoldFloor(
                        child: SizedBox(key: far, width: 30, height: 10),
                      )
                    else
                      const SizedBox(key: far, width: 30, height: 10),
                    const SizedBox(width: 70, height: 10),
                  ],
                ),
              ),
              tail: const SizedBox(key: tail, width: 100, height: 10),
            ),
          ),
        ),
      ),
    );

    /// What the head shows of itself — its scroller's width.
    double headShown(WidgetTester tester) =>
        tester.getSize(find.byType(SingleChildScrollView)).width;

    testWidgets('🚨the farther one holds, whichever came first', (
      tester,
    ) async {
      await pumpRow(tester, 120, withNear: false);
      expect(headShown(tester), 40, reason: '⛔전제: the far one alone');

      // The near one comes after it, keeping less.
      await pumpRow(tester, 120);

      expect(tester.takeException(), isNull);
      expect(headShown(tester), 40, reason: 'still the far one\'s');
    });

    testWidgets('🚨one that moves to the other group is that group\'s alone', (
      tester,
    ) async {
      final moving = GlobalKey();
      Future<void> pumpMoved({required bool inTail}) => tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 120,
              height: rowHeight,
              child: FloorFoldRow(
                gap: gap,
                head: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (!inTail)
                        FoldFloor(
                          key: moving,
                          child: const SizedBox(width: 30, height: 10),
                        ),
                      const SizedBox(width: 70, height: 10),
                    ],
                  ),
                ),
                tail: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(width: 70, height: 10),
                    if (inTail)
                      FoldFloor(
                        key: moving,
                        child: const SizedBox(width: 30, height: 10),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );

      await pumpMoved(inTail: false);
      expect(headShown(tester), 120 - gap - 70, reason: '⛔전제: room for it');

      await pumpMoved(inTail: true);

      expect(tester.takeException(), isNull);
      expect(
        headShown(tester),
        120 - gap - 100,
        reason: 'the head holds no floor now — it gives way to nothing',
      );
    });

    testWidgets('🚨one taken away keeps nothing, in the frame it goes', (
      tester,
    ) async {
      await pumpRow(tester, 120);
      expect(
        headShown(tester),
        40,
        reason: 'the far one, laid out after the near one',
      );

      await pumpRow(tester, 120, withFar: false);

      expect(tester.takeException(), isNull);
      expect(headShown(tester), 120 - gap - 100);
      expect(tester.getSize(find.byKey(tail)).width, 100);
    });
  });
}
