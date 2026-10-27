import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/ui/timeline/timeline_zoom_limits.dart';
import 'package:anicel/src/ui/widgets/drag_value_label.dart';

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

/// Zooms the frame panel on screen to [pixelsPerFrame] — its nearest step —
/// as a number typed into its zoom readout lands. ↩️The tests that zoomed
/// to a number handed it to the zoom slider's `onChanged`.
Future<void> typeTimelineZoom(
  WidgetTester tester,
  double pixelsPerFrame,
) async {
  tester
      .widget<DragValueLabel>(
        find.ancestor(
          of: timelineZoomReadout,
          matching: find.byType(DragValueLabel),
        ),
      )
      .onEditSubmit(
        '${pixelsPerFrame * 100 / TimelineZoomLimits.referencePixelsPerFrame}',
      );
  await tester.pumpAndSettle();
}
