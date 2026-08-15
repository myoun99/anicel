import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/timeline/timeline_frame_ruler_painter.dart';
import 'package:anicel/src/ui/timeline/timeline_ruler_cursor_overlay.dart';
import 'package:anicel/src/ui/timeline/xsheet_timeline_grid.dart'
    show XSheetFrameRailPainter;

/// Probe surface for the PAINTERIZED frame ruler (UI-R13 #1): headers are
/// paint, not widgets — labels, states and geometry live on
/// [TimelineFrameRulerPainter], reached through the strip's
/// 'timeline-frame-ruler-paint' CustomPaint. The widget-key era
/// ('timeline-frame-header-N') is over.

Finder timelineRulerPaintFinder() =>
    find.byKey(const ValueKey<String>('timeline-frame-ruler-paint'));

TimelineFrameRulerPainter timelineRulerPainter(
  WidgetTester tester, {
  int index = 0,
}) {
  final paint = tester
      .widgetList<CustomPaint>(timelineRulerPaintFinder())
      .elementAt(index);
  return paint.painter! as TimelineFrameRulerPainter;
}

/// Whether the ruler's PAINT window contains [frameIndex] — the
/// offset-derived slice under the UI-R15 self-windowing contract, the
/// full bounds otherwise.
bool timelineHeaderInWindow(
  WidgetTester tester,
  int frameIndex, {
  int index = 0,
}) {
  final window = timelineRulerPainter(
    tester,
    index: index,
  ).visibleHeaderWindow();
  return frameIndex >= window.startIndex &&
      frameIndex < window.endIndexExclusive;
}

/// The resolved header model at [frameIndex] (label, seconds line,
/// selected/outside/cached states, background).
TimelineRulerHeaderModel timelineHeaderModel(
  WidgetTester tester,
  int frameIndex, {
  int index = 0,
}) => timelineRulerPainter(tester, index: index).headerModelAt(frameIndex);

/// The header cell's GLOBAL rect (tap targets, alignment assertions).
Rect timelineHeaderGlobalRect(
  WidgetTester tester,
  int frameIndex, {
  int index = 0,
}) {
  final box = tester
      .renderObjectList<RenderBox>(timelineRulerPaintFinder())
      .elementAt(index);
  return timelineRulerPainter(
    tester,
    index: index,
  ).headerRectFor(frameIndex).shift(box.localToGlobal(Offset.zero));
}

// --- The X-sheet frame rail's painter probe (UI-R14 #1) ------------------

Finder xsheetRailPaintFinder() =>
    find.byKey(const ValueKey<String>('xsheet-frame-rail-paint'));

XSheetFrameRailPainter xsheetRailPainter(WidgetTester tester) =>
    tester.widget<CustomPaint>(xsheetRailPaintFinder()).painter!
        as XSheetFrameRailPainter;

/// Whether the rail's PAINT window contains [frameIndex] (the
/// offset-derived slice under UI-R15).
bool xsheetFrameRowInWindow(WidgetTester tester, int frameIndex) {
  final window = xsheetRailPainter(tester).visibleRowWindow();
  return frameIndex >= window.startIndex &&
      frameIndex < window.endIndexExclusive;
}

/// The resolved rail-row model at [frameIndex].
TimelineRulerHeaderModel xsheetFrameRowModel(
  WidgetTester tester,
  int frameIndex,
) => xsheetRailPainter(tester).modelAt(frameIndex);

/// The rail row's GLOBAL rect.
Rect xsheetFrameRowGlobalRect(WidgetTester tester, int frameIndex) {
  final box = tester.renderObject<RenderBox>(xsheetRailPaintFinder());
  return xsheetRailPainter(
    tester,
  ).rowRectFor(frameIndex).shift(box.localToGlobal(Offset.zero));
}

// --- The rulers' CURSOR OVERLAY (the split, scoped-notify audit) ----------
//
// The current-frame tint and the green cached bar left the gated strip
// painters: cached-ness is derived state (composites self-validate, nothing
// raises an invalidation event), so it repaints freely on its own thin
// layer. These read that layer.

TimelineRulerCursorOverlayPainter _overlayPainter(
  WidgetTester tester,
  String keyValue,
) =>
    tester
            .widget<CustomPaint>(find.byKey(ValueKey<String>(keyValue)))
            .painter!
        as TimelineRulerCursorOverlayPainter;

/// The frame the TIMELINE ruler marks as current (null when off-window) —
/// the successor of reading `.selected` off the header model.
int? timelineRulerTintedFrame(WidgetTester tester) =>
    _overlayPainter(tester, 'timeline-ruler-cursor-overlay').tintedFrame();

/// The frame the X-SHEET rail marks as current.
int? xsheetRailTintedFrame(WidgetTester tester) =>
    _overlayPainter(tester, 'xsheet-rail-cursor-overlay').tintedFrame();

/// The cached RUNS the timeline ruler's overlay would draw.
List<({int startIndex, int endIndexExclusive})> timelineRulerCachedRuns(
  WidgetTester tester,
) => _overlayPainter(tester, 'timeline-ruler-cursor-overlay').readyRuns();

/// The cached RUNS the X-sheet rail's overlay would draw.
List<({int startIndex, int endIndexExclusive})> xsheetRailCachedRuns(
  WidgetTester tester,
) => _overlayPainter(tester, 'xsheet-rail-cursor-overlay').readyRuns();
