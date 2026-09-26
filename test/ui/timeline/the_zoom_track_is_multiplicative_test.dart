import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/project_frame_rate.dart';
import 'package:anicel/src/ui/input/control_press_claim.dart';
import 'package:anicel/src/ui/timeline/timeline_view_cluster.dart';
import 'package:anicel/src/ui/timeline/timeline_zoom_limits.dart';

/// I-22 ②-1 (유저 2026-09-12: 「지금 줌 배율? 을 좀 더 축소 가능하게하고싶음」).
///
/// The zoom bar is where the narrow end is reached from, so the track has to
/// SPEND ITS LENGTH there: a linear track gave 2.4→24px — the whole working
/// half — less than a quarter of its travel, and the drag wrote whatever
/// whole pixel it landed on without bringing it back into the range.
///
/// Measured through the bar itself: where the middle of the track lands, and
/// what the very bottom of it writes.
void main() {
  Finder trackOf() => find.descendant(
    of: find.byKey(const ValueKey<String>('timeline-zoom-slider')),
    matching: find.byType(DragVerbClaim),
  );

  Future<List<double>> pump(
    WidgetTester tester, {
    double pixelsPerFrame = 24,
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

  /// The floor at 24fps: a second at no fewer than three pixels.
  final floor = TimelineZoomLimits.minPixelsPerFrameAt(24);

  testWidgets('the middle of the zoom track is the range\'s GEOMETRIC middle '
      '— equal travel is equal ratio', (tester) async {
    final zooms = await pump(tester);
    await tester.tapAt(tester.getCenter(trackOf()));
    await tester.pump();

    final geometric = math.sqrt(floor * TimelineZoomLimits.maxPixelsPerFrame);
    final arithmetic = (floor + TimelineZoomLimits.maxPixelsPerFrame) / 2;
    expect(zooms, isNotEmpty);
    expect(
      zooms.last,
      closeTo(geometric, 1),
      reason: 'halfway along the bar is halfway in RATIO (about 3.5px)',
    );
    expect(
      zooms.last,
      isNot(closeTo(arithmetic, 1)),
      reason: 'a linear track put the middle at about 48px, which leaves the '
          'whole narrow half in the first few pixels of travel',
    );
  });

  testWidgets('the bottom of the track writes the floor itself, never a value '
      'under it', (tester) async {
    final zooms = await pump(tester);
    final track = tester.getRect(trackOf());
    await tester.tapAt(Offset(track.left + 1, track.center.dy));
    await tester.pump();

    expect(zooms, isNotEmpty);
    expect(
      zooms.last,
      floor,
      reason: 'rounding once wrote 2px under a 2.4px floor, and nothing '
          'brought it back',
    );
  });
}
