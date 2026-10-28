import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/ui/timeline/timeline_view_cluster.dart';
import 'package:anicel/src/ui/timeline/timeline_zoom_limits.dart';

/// The frame panels' zoom — a number to drag, the canvas zoom's readout
/// (F-463).
final Finder timelineZoomReadout = find.byKey(
  const ValueKey<String>('timeline-zoom-readout'),
);

/// Zooms the frame panel on screen by [percent] points: a mouse dragged
/// along its zoom readout, a percent a pixel. ↩️The tests that zoomed
/// pressed the − or the + beside a slider (F-463 took them off).
Future<void> dragTimelineZoom(WidgetTester tester, double percent) async {
  await tester.drag(
    timelineZoomReadout,
    Offset(percent, 0),
    kind: PointerDeviceKind.mouse,
  );
  await tester.pumpAndSettle();
}

/// Zooms the frame panel on screen to [pixelsPerFrame] — its nearest step
/// inside the zoom's range, as its readout lands a zoom — handed to the
/// host the readout hands it to. ↩️The tests that zoomed to a number typed
/// it into the readout's pencil until F-463 took the pencil off (유저
/// 2026-10-27), and before that handed it to the zoom slider's `onChanged`.
Future<void> zoomTimelineTo(WidgetTester tester, double pixelsPerFrame) async {
  final cluster = tester.widget<TimelineViewCluster>(
    find.ancestor(
      of: timelineZoomReadout,
      matching: find.byType(TimelineViewCluster),
    ),
  );
  cluster.onPixelsPerFrameChanged!(
    TimelineZoomLimits.clamped(
      pixelsPerFrame,
      framesPerSecond: cluster.projectFrameRate.countingBase,
    ),
  );
  await tester.pumpAndSettle();
}
