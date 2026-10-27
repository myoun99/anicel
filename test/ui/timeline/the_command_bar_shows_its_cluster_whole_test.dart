import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/ui/timeline/timeline_command_bar.dart';

/// timeline-row-overflows-at-360 (2026-10-14): in a 360px window the
/// timeline's bar had 248px for its 252 — the cluster pinned right was laid
/// out wider than the bar and ran off it. The bar keeps the page strip's
/// law now, as the canvas pill does (`canvas-bottom-bar-overflows-at-437`):
/// too narrow for its cluster, it shows all of the cluster, smaller.
void main() {
  const cluster = ValueKey<String>('cluster');
  const clusterWidth = 244.0;
  const clusterHeight = 20.0;

  /// The bar [width] wide, round a leading wider than any bar here — or none,
  /// as the timeline's bar is with its toolbar hidden — and a cluster
  /// [clusterWidth] wide: a ROW, as the view cluster is, which held
  /// narrower than its width runs over instead of growing smaller.
  Future<void> pumpBar(
    WidgetTester tester,
    double width, {
    bool withLeading = true,
  }) => tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: width,
            child: TimelineCommandBar(
              leading: withLeading
                  ? const Row(children: [SizedBox(width: 600, height: 20)])
                  : null,
              cluster: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    key: cluster,
                    width: clusterWidth,
                    height: clusterHeight,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );

  /// The bar's padding either side, and the gap before the cluster — kept
  /// only where there is a leading to keep it from.
  final sides = TimelineCommandBar.padding.horizontal;
  const gap = 8.0;

  /// The inset after the leading's scroller — the least a leading with no
  /// [FoldFloor] in it is shown at.
  const inset = TimelineCommandBar.leadingInset;

  /// The pills' overflow scroller — the bar's first: the cluster stands in
  /// one of its own after it (F-491).
  final pills = find.byType(SingleChildScrollView).first;

  for (final withLeading in [true, false]) {
    testWidgets('🚨too narrow for its cluster, the bar '
        '${withLeading ? 'with' : 'without'} a leading shows all of it, '
        'smaller — none of it runs off', (tester) async {
      const room = clusterWidth - 4;
      final width = sides + (withLeading ? gap : 0) + room;
      await pumpBar(tester, width, withLeading: withLeading);

      expect(tester.takeException(), isNull);
      // Below the leading's floor — its inset, and the gap — all of it is
      // smaller by one factor (F-463 ⑥).
      final kept = withLeading ? inset + gap : 0.0;
      final factor = (width - sides) / (kept + clusterWidth);
      final shown = tester.getRect(find.byKey(cluster));
      expect(shown.width, moreOrLessEquals(clusterWidth * factor));
      expect(shown.height, moreOrLessEquals(clusterHeight * factor));
      expect(
        shown.right,
        moreOrLessEquals(width - TimelineCommandBar.padding.right),
      );
    });
  }

  // 🗣️F-491 (유저 2026-10-27 23:15): 「재생쪽은 역시 왼쪽 묶음의 제일
  // 왼쪽으로 옮기도록」. ↩️F-463 ⑥ (10-25 17:15: 「재생버튼쪽은 오른쪽에 줌쪽
  // 버튼이랑 같은묶음」) stood it beside the cluster, and F-111-Q1 at the
  // bar's head before that, as now.
  group('with the transport at the bar\'s start (F-491)', () {
    const transport = ValueKey<String>('transport');
    const transportWidth = 236.0;
    const transportHeight = 28.0;

    Future<void> pumpBar(WidgetTester tester, double width) =>
        tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Align(
                alignment: Alignment.topLeft,
                child: SizedBox(
                  width: width,
                  child: const TimelineCommandBar(
                    transport: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          key: transport,
                          width: transportWidth,
                          height: transportHeight,
                        ),
                      ],
                    ),
                    leading: Row(
                      children: [SizedBox(width: 600, height: 20)],
                    ),
                    cluster: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          key: cluster,
                          width: clusterWidth,
                          height: clusterHeight,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );

    testWidgets('where the bar holds them, the transport stands at its own '
        'size at the bar\'s start, the pills\' scroller after it and the '
        'cluster at the bar\'s end', (tester) async {
      const width = 800.0;
      await pumpBar(tester, width);

      final shown = tester.getRect(find.byKey(transport));
      final shownCluster = tester.getRect(find.byKey(cluster));
      expect(shown.size, const Size(transportWidth, transportHeight));
      expect(shown.left, TimelineCommandBar.padding.left);
      expect(shownCluster.size, const Size(clusterWidth, clusterHeight));
      expect(
        shownCluster.right,
        width - TimelineCommandBar.padding.right,
      );
      final scroller = tester.getRect(pills);
      expect(
        scroller.left,
        moreOrLessEquals(
          shown.right + gap + TimelineCommandBar.leadingInset,
        ),
      );
      expect(
        scroller.right,
        moreOrLessEquals(
          shownCluster.left - gap - TimelineCommandBar.leadingInset,
        ),
      );
      expect(
        find.descendant(
          of: pills,
          matching: find.byKey(transport),
        ),
        findsNothing,
        reason: 'outside the scroller: a scrolled pill row leaves it be',
      );
    });

    testWidgets('🚨too narrow for both ends, the bar shows the transport and '
        'the cluster all of each, smaller by one factor — none of it runs '
        'off', (tester) async {
      const width = 360.0;
      await pumpBar(tester, width);

      expect(tester.takeException(), isNull);
      final factor =
          (width - sides) /
          (transportWidth + TimelineCommandBar.leadingInset + gap +
              clusterWidth);
      final shownTransport = tester.getRect(find.byKey(transport));
      final shownCluster = tester.getRect(find.byKey(cluster));
      expect(
        shownTransport.width,
        moreOrLessEquals(transportWidth * factor),
      );
      expect(shownCluster.width, moreOrLessEquals(clusterWidth * factor));
      expect(
        shownTransport.left,
        moreOrLessEquals(TimelineCommandBar.padding.left),
      );
      expect(
        shownCluster.right,
        moreOrLessEquals(width - TimelineCommandBar.padding.right),
      );
      expect(
        shownTransport.right,
        lessThanOrEqualTo(shownCluster.left),
        reason: 'nothing run over',
      );
    });
  });

  testWidgets('where the bar holds it, nothing is scaled — the leading '
      'takes what is left, and both stand in the middle of the bar', (
    tester,
  ) async {
    const width = 800.0;
    await pumpBar(tester, width);

    final shown = tester.getRect(find.byKey(cluster));
    expect(shown.size, const Size(clusterWidth, clusterHeight));
    final scroller = tester.getRect(pills);
    expect(
      scroller.width,
      moreOrLessEquals(width - sides - clusterWidth - gap - 2 * inset),
    );
    final middle = tester.getRect(find.byType(TimelineCommandBar)).center.dy;
    expect(shown.center.dy, moreOrLessEquals(middle));
    expect(scroller.center.dy, moreOrLessEquals(middle));
  });
}
