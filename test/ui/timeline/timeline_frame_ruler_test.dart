import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/timeline/timeline_frame_ruler.dart';
import 'package:anicel/src/ui/timeline/timeline_grid_metrics.dart';

import 'timeline_ruler_probe.dart';

void main() {
  testWidgets('renders the supplied range through the PAINTERIZED strip '
      '(UI-R13 #1) with the cut-end boundary aligned', (tester) async {
    int? selectedFrameIndex;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TimelineFrameRuler(
            frameStartIndex: 2,
            frameEndIndexExclusive: 5,
            currentFrameIndex: 3,
            playbackFrameCount: 5,
            leadingFrameSpacerWidth: 96,
            trailingFrameSpacerWidth: 144,
            metrics: TimelineGridMetrics.defaults,
            onSelectFrame: (frameIndex) => selectedFrameIndex = frameIndex,
          ),
        ),
      ),
    );

    expect(
      find.byKey(const ValueKey<String>('timeline-frame-ruler')),
      findsOneWidget,
    );
    expect(timelineRulerPaintFinder(), findsOneWidget);
    final rulerBoundary = find.byKey(
      const ValueKey<String>('timeline-cut-end-boundary-ruler'),
    );
    expect(rulerBoundary, findsOneWidget);
    expect(
      tester.getTopLeft(rulerBoundary).dx -
          tester
              .getTopLeft(
                find.byKey(const ValueKey<String>('timeline-frame-ruler')),
              )
              .dx,
      5 * TimelineGridMetrics.defaults.frameCellWidth,
    );

    // The painter window covers exactly the supplied range.
    expect(timelineHeaderInWindow(tester, 1), isFalse);
    expect(timelineHeaderInWindow(tester, 2), isTrue);
    expect(timelineHeaderInWindow(tester, 4), isTrue);
    expect(timelineHeaderInWindow(tester, 5), isFalse);

    // The header cells are PASSIVE (UI-R10 #25): selection rides the
    // grid's ruler scrub listener, not per-cell taps — the standalone
    // ruler forwards nothing.
    await tester.tapAt(timelineHeaderGlobalRect(tester, 4).center);
    expect(selectedFrameIndex, isNull);
  });
}
