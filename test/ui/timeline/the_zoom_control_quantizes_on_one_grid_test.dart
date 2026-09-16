import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/project_frame_rate.dart';
import 'package:anicel/src/ui/timeline/timeline_view_cluster.dart';
import 'package:anicel/src/ui/timeline/timeline_zoom_limits.dart';

/// I-22 ②-1: the slider and the −/+ buttons ask ONE quantizer, and it
/// rounds before it clamps — so no control can write a zoom outside the
/// range it was given.
void main() {
  group('TimelineZoomLimits.quantize', () {
    test('rounds to whole pixels per frame', () {
      expect(TimelineZoomLimits.quantize(9.6), 10);
      expect(TimelineZoomLimits.quantize(19.2), 19);
      expect(TimelineZoomLimits.quantize(30), 30);
    });

    test('🚨rounds BEFORE it clamps, so the bounds hold', () {
      expect(
        TimelineZoomLimits.quantize(TimelineZoomLimits.minPixelsPerFrame),
        TimelineZoomLimits.minPixelsPerFrame,
        reason: 'the floor rounds DOWN to 2 and must come back to 2.4',
      );
      expect(
        TimelineZoomLimits.quantize(0.4),
        TimelineZoomLimits.minPixelsPerFrame,
        reason: 'a zero cell trips the grid assert and the anchor division',
      );
      expect(
        TimelineZoomLimits.quantize(400),
        TimelineZoomLimits.maxPixelsPerFrame,
      );
    });
  });

  group('the −/+ buttons ask the same grid', () {
    Future<List<double>> pump(
      WidgetTester tester, {
      required double pixelsPerFrame,
    }) async {
      final zooms = <double>[];
      final cursor = ValueNotifier<int>(0);
      addTearDown(cursor.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Row(
              children: [
                TimelineViewCluster(
                  frameCursor: cursor,
                  projectFrameRate: ProjectFrameRate.fps24,
                  showSeconds: false,
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

    // ↩️These two used to be ONE case called 「a step that ×1.25 cannot move
    // takes one whole pixel」, and its comment promised a ROUND TRIP — but
    // the fixture hands the cluster a fixed zoom and only collects what it
    // asks for, so nothing round-tripped and only the + button was pressed.
    // The ±1 fallback it named turned out to be unreachable (measured
    // 2026-09-16, see `_steppedZoom`) and went; what is left is one case per
    // button, each starting where that button has somewhere to go.
    testWidgets('the + button lands on the ×1.25 neighbour on the grid', (
      tester,
    ) async {
      // 3 × 1.25 = 3.75 → 4.
      final zooms = await pump(tester, pixelsPerFrame: 3);
      await tester.tap(
        find.byKey(const ValueKey<String>('timeline-zoom-in-button')),
      );
      expect(zooms.last, 4);
      expect(zooms.last, isNot(3), reason: 'a step is never a no-op');
    });

    testWidgets('the − button lands on the ÷1.25 neighbour on the grid', (
      tester,
    ) async {
      // 4 ÷ 1.25 = 3.2 → 3. ⛔It must not multiply: 4 × 1.25 would read 5.
      final zooms = await pump(tester, pixelsPerFrame: 4);
      await tester.tap(
        find.byKey(const ValueKey<String>('timeline-zoom-out-button')),
      );
      expect(zooms.last, 3);
      expect(zooms.last, isNot(4), reason: 'a step is never a no-op');
    });

    testWidgets('a step never leaves the range', (tester) async {
      final zooms = await pump(
        tester,
        pixelsPerFrame: TimelineZoomLimits.minPixelsPerFrame + 0.1,
      );
      await tester.tap(
        find.byKey(const ValueKey<String>('timeline-zoom-out-button')),
      );
      expect(zooms.last, TimelineZoomLimits.minPixelsPerFrame);
    });
  });
}
