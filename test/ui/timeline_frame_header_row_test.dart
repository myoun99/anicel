import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/timeline/timeline_frame_header_row.dart';
import 'package:anicel/src/ui/timeline/timeline_grid_metrics.dart';

import 'timeline/timeline_ruler_probe.dart';

/// The ruler strip is PAINTERIZED (UI-R13 #1): headers are paint, not
/// widgets — the probe reads models/geometry off the strip's painter.
void main() {
  Future<void> pumpHeaderRow(
    WidgetTester tester, {
    required int frameStartIndex,
    required int frameEndIndexExclusive,
    required int currentFrameIndex,
    required int playbackFrameCount,
    required ValueChanged<int> onSelectFrame,
    double leadingFrameSpacerWidth = 96,
    double trailingFrameSpacerWidth = 144,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Material(
          child: TimelineFrameHeaderRow(
            frameStartIndex: frameStartIndex,
            frameEndIndexExclusive: frameEndIndexExclusive,
            currentFrameIndex: currentFrameIndex,
            playbackFrameCount: playbackFrameCount,
            leadingFrameSpacerWidth: leadingFrameSpacerWidth,
            trailingFrameSpacerWidth: trailingFrameSpacerWidth,
            metrics: TimelineGridMetrics.defaults,
            onSelectFrame: onSelectFrame,
          ),
        ),
      ),
    );
  }

  testWidgets('the strip is ONE CustomPaint sized spacers + window', (
    tester,
  ) async {
    await pumpHeaderRow(
      tester,
      frameStartIndex: 3,
      frameEndIndexExclusive: 6,
      currentFrameIndex: 4,
      playbackFrameCount: 6,
      onSelectFrame: (_) {},
    );

    expect(timelineRulerPaintFinder(), findsOneWidget);
    // Geometry flows through the painter (spacer offset + cell widths).
    final rect3 = timelineHeaderGlobalRect(tester, 3);
    expect(rect3.left, 96);
    expect(rect3.width, TimelineGridMetrics.defaults.frameCellWidth);
  });

  testWidgets('the painter window covers exactly the supplied range', (
    tester,
  ) async {
    await pumpHeaderRow(
      tester,
      frameStartIndex: 3,
      frameEndIndexExclusive: 6,
      currentFrameIndex: 4,
      playbackFrameCount: 6,
      onSelectFrame: (_) {},
    );

    expect(timelineHeaderInWindow(tester, 3), isTrue);
    expect(timelineHeaderInWindow(tester, 5), isTrue);
    expect(timelineHeaderInWindow(tester, 6), isFalse);
    expect(timelineHeaderInWindow(tester, 2), isFalse);
  });

  testWidgets('headers label with one-based frame numbers', (tester) async {
    await pumpHeaderRow(
      tester,
      frameStartIndex: 3,
      frameEndIndexExclusive: 6,
      currentFrameIndex: 4,
      playbackFrameCount: 6,
      onSelectFrame: (_) {},
    );

    expect(timelineHeaderModel(tester, 3).label, '4');
    expect(timelineHeaderModel(tester, 4).label, '5');
    expect(timelineHeaderModel(tester, 5).label, '6');
  });

  testWidgets('header cells are PASSIVE (UI-R10 #25): no per-cell tap '
      'handler — selection rides the grid ruler scrub listener', (
    tester,
  ) async {
    int? selectedFrameIndex;

    await pumpHeaderRow(
      tester,
      frameStartIndex: 3,
      frameEndIndexExclusive: 6,
      currentFrameIndex: 4,
      playbackFrameCount: 6,
      onSelectFrame: (frameIndex) => selectedFrameIndex = frameIndex,
    );

    await tester.tapAt(timelineHeaderGlobalRect(tester, 4).center);

    expect(selectedFrameIndex, isNull);
  });

  testWidgets('the current frame reads selected with its tinted background', (
    tester,
  ) async {
    await pumpHeaderRow(
      tester,
      frameStartIndex: 3,
      frameEndIndexExclusive: 6,
      currentFrameIndex: 4,
      playbackFrameCount: 6,
      onSelectFrame: (_) {},
    );

    expect(timelineHeaderModel(tester, 4).selected, isTrue);
    expect(timelineHeaderModel(tester, 3).selected, isFalse);
    expect(
      timelineHeaderModel(tester, 4).background,
      isNot(timelineHeaderModel(tester, 3).background),
    );
  });

  testWidgets('outside-playback frame headers still paint, marked outside', (
    tester,
  ) async {
    await pumpHeaderRow(
      tester,
      frameStartIndex: 3,
      frameEndIndexExclusive: 7,
      currentFrameIndex: 4,
      playbackFrameCount: 5,
      onSelectFrame: (_) {},
    );

    expect(timelineHeaderInWindow(tester, 5), isTrue);
    expect(timelineHeaderInWindow(tester, 6), isTrue);
    expect(timelineHeaderModel(tester, 5).outsidePlaybackRange, isTrue);
    expect(timelineHeaderModel(tester, 4).outsidePlaybackRange, isFalse);
  });
}
