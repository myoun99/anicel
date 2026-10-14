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

  /// The bar's padding either side, and the gap before the cluster.
  final sides = TimelineCommandBar.padding.horizontal;
  const gap = 8.0;

  for (final withLeading in [true, false]) {
    testWidgets('🚨too narrow for its cluster, the bar '
        '${withLeading ? 'with' : 'without'} a leading shows all of it, '
        'smaller — none of it runs off', (tester) async {
      const room = clusterWidth - 4;
      final width = sides + gap + room;
      await pumpBar(tester, width, withLeading: withLeading);

      expect(tester.takeException(), isNull);
      final shown = tester.getRect(find.byKey(cluster));
      expect(shown.width, moreOrLessEquals(room));
      expect(
        shown.height,
        moreOrLessEquals(clusterHeight * room / clusterWidth),
      );
      expect(
        shown.right,
        moreOrLessEquals(width - TimelineCommandBar.padding.right),
      );
    });
  }

  testWidgets('where the bar holds it, nothing is scaled — the leading '
      'takes what is left, and both stand in the middle of the bar', (
    tester,
  ) async {
    const width = 800.0;
    await pumpBar(tester, width);

    final shown = tester.getRect(find.byKey(cluster));
    expect(shown.size, const Size(clusterWidth, clusterHeight));
    final scroller = tester.getRect(find.byType(SingleChildScrollView));
    const insets = 2 * TimelineCommandBar.leadingInset;
    expect(
      scroller.width,
      moreOrLessEquals(width - sides - clusterWidth - gap - insets),
    );
    final middle = tester.getRect(find.byType(TimelineCommandBar)).center.dy;
    expect(shown.center.dy, moreOrLessEquals(middle));
    expect(scroller.center.dy, moreOrLessEquals(middle));
  });
}
