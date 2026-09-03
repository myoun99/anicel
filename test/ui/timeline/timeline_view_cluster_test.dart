// THE VIEW CLUSTER: THE COUNTER READS ONE-BASED (GLOBAL ABOVE LOCAL WHEN A
// GLOBAL FRAME IS GIVEN, AN EMPTY TOP LINE OTHERWISE), AND THE ZOOM STEP
// BUTTONS STEP BY ×1.25 ON THE WHOLE-PIXEL GRID, DEAD AT THE BOUNDS.
//
// No test named this widget (audit 2026-09-03) although both the timeline
// and the storyboard tabs mount it. These pins drive it alone.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/project_frame_rate.dart';
import 'package:anicel/src/ui/timeline/timeline_view_cluster.dart';
import 'package:anicel/src/ui/timeline/timeline_zoom_limits.dart';

void main() {
  Future<List<double>> pump(
    WidgetTester tester, {
    required int frame,
    int? globalFrame,
    double pixelsPerFrame = 12,
    bool showSeconds = false,
  }) async {
    final zooms = <double>[];
    final cursor = ValueNotifier<int>(frame);
    addTearDown(cursor.dispose);
    final global = globalFrame == null
        ? null
        : ValueNotifier<int?>(globalFrame);
    if (global != null) {
      addTearDown(global.dispose);
    }
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Row(
            children: [
              TimelineViewCluster(
                frameCursor: cursor,
                globalFrame: global,
                projectFrameRate: ProjectFrameRate.fps24,
                showSeconds: showSeconds,
                pixelsPerFrame: pixelsPerFrame,
                onPixelsPerFrameChanged: zooms.add,
              ),
            ],
          ),
        ),
      ),
    );
    return zooms;
  }

  String textOf(WidgetTester tester, String key) =>
      tester.widget<Text>(find.byKey(ValueKey<String>(key))).data!;

  testWidgets(
    'the counter is one-based with an empty top line on the timeline',
    (tester) async {
      await pump(tester, frame: 4);
      expect(textOf(tester, 'timeline-local-frame-counter'), '5');
      expect(textOf(tester, 'timeline-global-frame-counter'), '');
    },
  );

  testWidgets('a global frame reads above the local one', (tester) async {
    await pump(tester, frame: 4, globalFrame: 23);
    expect(textOf(tester, 'timeline-global-frame-counter'), '24');
    expect(textOf(tester, 'timeline-local-frame-counter'), '5');
  });

  testWidgets('seconds notation changes the counter', (tester) async {
    await pump(tester, frame: 30, showSeconds: true);
    expect(textOf(tester, 'timeline-local-frame-counter'), isNot('31'));
  });

  testWidgets('zoom steps by ×1.25 on the whole-pixel grid', (tester) async {
    final zooms = await pump(tester, frame: 0, pixelsPerFrame: 12);
    await tester.tap(
      find.byKey(const ValueKey<String>('timeline-zoom-in-button')),
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('timeline-zoom-out-button')),
    );
    expect(zooms, [15, 10]);
  });

  testWidgets('at the top bound zoom-in is dead', (tester) async {
    final zooms = await pump(
      tester,
      frame: 0,
      pixelsPerFrame: TimelineZoomLimits.maxPixelsPerFrame,
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('timeline-zoom-in-button')),
      warnIfMissed: false,
    );
    expect(zooms, isEmpty);
  });
}
