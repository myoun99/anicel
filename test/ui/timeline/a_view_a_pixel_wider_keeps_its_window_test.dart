import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/ui/timeline/timeline_frame_window.dart';

/// A VIEW A PIXEL WIDER KEEPS ITS WINDOW (storyboard-strips-build-on-every-
/// view-pixel, 2026-10-30): a window reaches whole spans, so a breadth
/// moves it only where it crosses one — as an offset moves its bucket.
///
/// ↩️It reached the view's last cell and the overscan past it, so every
/// cell of a rail splitter's drag moved its end, and the storyboard's
/// strips, built for the window, were built again on every pixel (273
/// widgets a step on the default project; 162 after — the grid's frame
/// around the rows).
void main() {
  const cell = 6.0;
  const bucket = 3;
  final span = timelineFrameWindowSpanFor(cell);

  ({int startIndex, int endIndexExclusive}) windowAt(double view) =>
      timelineFrameWindowFor(
        bucket: bucket,
        cellExtent: cell,
        viewportExtent: view,
      );

  test('a window ends on the edge of the span its view and overscan end '
      'in', () {
    expect(span, 16, reason: '⛔전제: 96px of six-pixel cells');
    for (var view = 1.0; view <= 2000; view += 1) {
      // Every cell the view can reveal from anywhere in the bucket, and the
      // overscan past them.
      final reached =
          (bucket + 1) * span +
          (view / cell).ceil() +
          timelineFrameWindowOverscanCells;
      final end = windowAt(view).endIndexExclusive;
      expect(end % span, 0, reason: 'a ${view}px view ends on a span');
      expect(
        end,
        greaterThanOrEqualTo(reached),
        reason: 'a ${view}px view reaches every cell it can show',
      );
      expect(
        end,
        lessThan(reached + span),
        reason: 'a ${view}px view reaches no span past the one it ends in',
      );
    }
  });

  test('a breadth reaching the spans another does gives its window — what a '
      'piece built for the window keys on', () {
    final windowsByReach =
        <int, Set<({int startIndex, int endIndexExclusive})>>{};
    for (var view = 1.0; view <= 2000; view += 1) {
      final reach = timelineFrameWindowReachFor(
        viewportExtent: view,
        cellExtent: cell,
      );
      (windowsByReach[reach] ??= {}).add(windowAt(view));
    }
    for (final MapEntry(key: reach, value: windows)
        in windowsByReach.entries) {
      expect(windows, hasLength(1), reason: 'reach $reach: one window');
    }
    // Two thousand breadths, a window a span of them — ↩️334, one a cell.
    expect(
      windowsByReach.length,
      lessThanOrEqualTo(2000 ~/ (span * cell) + 2),
    );
  });

  test('a view of no breadth reaches nothing, and neither does a cell of '
      'none', () {
    for (final (view, cellExtent) in [
      (0.0, cell),
      (-4.0, cell),
      (600.0, 0.0),
    ]) {
      expect(
        timelineFrameWindowReachFor(
          viewportExtent: view,
          cellExtent: cellExtent,
        ),
        0,
        reason: 'a ${view}px view of ${cellExtent}px cells',
      );
    }
    expect(
      timelineFrameWindowReachFor(viewportExtent: 1, cellExtent: cell),
      greaterThan(0),
      reason: 'CONTROL: a pixel of view reaches',
    );
  });
}
