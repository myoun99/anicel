import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/timeline/timeline_frame_header_row.dart';
import 'package:anicel/src/ui/timeline/timeline_grid_metrics.dart';

import 'timeline_ruler_probe.dart';

/// UI-R10 #27: the ruler reads TWO lines — seconds on top (plain second
/// index on its boundary), frame numbers below (absolute in frame mode,
/// the 1..fps cycle in seconds mode; no quote notation anywhere). The
/// strip is painterized (UI-R13 #1): the lines probe as painter models.
void main() {
  Widget harness({required bool showSeconds}) => MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: TimelineFrameHeaderRow(
          frameStartIndex: 22,
          frameEndIndexExclusive: 28,
          currentFrameIndex: 22,
          playbackFrameCount: 48,
          leadingFrameSpacerWidth: 0,
          trailingFrameSpacerWidth: 0,
          metrics: const TimelineGridMetrics(
            frameCellWidth: 48,
            layerRowHeight: 52,
          ),
          onSelectFrame: (_) {},
          framesPerSecond: 24,
          showSeconds: showSeconds,
        ),
      ),
    ),
  );

  testWidgets('frame mode: absolute numbers below, the second index on '
      'its boundary above', (tester) async {
    await tester.pumpWidget(harness(showSeconds: false));

    expect(timelineHeaderModel(tester, 22).label, '23');
    expect(timelineHeaderModel(tester, 24).label, '25');
    // The seconds line: frame 24 starts second 2, off-boundary rows stay
    // blank (plain numbers only, no quote notation).
    expect(timelineHeaderModel(tester, 24).secondsLabel, '2');
    expect(timelineHeaderModel(tester, 23).secondsLabel, '');
    expect(timelineHeaderModel(tester, 25).secondsLabel, '');
  });

  testWidgets('seconds mode: the bottom line cycles 1..fps', (tester) async {
    await tester.pumpWidget(harness(showSeconds: true));

    expect(
      timelineHeaderModel(tester, 22).label,
      '23',
      reason: 'frame 22 → cycle 23',
    );
    expect(
      timelineHeaderModel(tester, 23).label,
      '24',
      reason: 'frame 23 → cycle 24',
    );
    // Frame 24 restarts the cycle at 1 — and its seconds label 2 sits on
    // the same boundary.
    expect(timelineHeaderModel(tester, 24).label, '1');
    expect(timelineHeaderModel(tester, 24).secondsLabel, '2');
    expect(
      timelineHeaderModel(tester, 25).label,
      '2',
      reason: 'the cycle, never absolute 26',
    );
  });
}
