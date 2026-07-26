import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quick_animaker_v2/src/ui/timeline/timeline_row_edit_chrome.dart';

/// Test probes for a dense row's PAINTED edit chrome (R28 #4 tier 2): the
/// comma grips and the run-edge [+]/property clusters are canvas work now,
/// so `find.byKey('timeline-block-edge-grip-…')` no longer exists on the
/// drawing rows. Assertions read the painter's target model; gestures go
/// through the same rects the painter draws and the row hit-tests, so a
/// probe can never address a target the user could not.
///
/// The storyboard's CUT row mounts the same layer (`prefix: 'storyboard'`,
/// its track id in place of a layer id). The sparse surfaces (instruction
/// rows, storyboard SE strips) still mount `BlockEdgeGrip` widgets and keep
/// their key finders.
Finder timelineRowChromeFinder(String layerId, {String prefix = 'timeline'}) =>
    find.byKey(ValueKey<String>('$prefix-edit-chrome-$layerId'));

/// The row's chrome painter, or null when the row has no affordances at all
/// (the layer is not mounted then — the successor of `findsNothing`).
TimelineRowEditChromePainter? timelineRowChromePainter(
  WidgetTester tester,
  String layerId, {
  String prefix = 'timeline',
}) {
  final finder = timelineRowChromeFinder(layerId, prefix: prefix);
  if (finder.evaluate().isEmpty) {
    return null;
  }
  return tester.widget<CustomPaint>(finder).painter
      as TimelineRowEditChromePainter;
}

/// Every target the row would hit-test, in priority order.
List<TimelineRowChromeTarget> timelineRowChromeTargets(
  WidgetTester tester,
  String layerId, {
  String prefix = 'timeline',
}) => timelineRowChromePainter(tester, layerId, prefix: prefix)?.targets ?? [];

/// The ids of every target — the readable stand-in for a list of keys.
List<String> timelineRowChromeIds(
  WidgetTester tester,
  String layerId, {
  String prefix = 'timeline',
}) => timelineRowChromeTargets(
  tester,
  layerId,
  prefix: prefix,
).map((target) => target.id).toList();

/// One target by id; fails the test when the row does not draw it.
TimelineRowChromeTarget timelineRowChromeTarget(
  WidgetTester tester,
  String layerId,
  String id, {
  String prefix = 'timeline',
}) {
  final targets = timelineRowChromeTargets(tester, layerId, prefix: prefix);
  return targets.firstWhere(
    (target) => target.id == id,
    orElse: () => fail(
      'no chrome target "$id" on row $layerId; '
      'row draws ${targets.map((target) => target.id).toList()}',
    ),
  );
}

/// The target's rect in GLOBAL coordinates (drag anchors, tap targets).
Rect timelineRowChromeGlobalRect(
  WidgetTester tester,
  String layerId,
  String id, {
  String prefix = 'timeline',
}) {
  final target = timelineRowChromeTarget(tester, layerId, id, prefix: prefix);
  final box =
      tester.renderObject(timelineRowChromeFinder(layerId, prefix: prefix))
          as RenderBox;
  return box.localToGlobal(target.rect.topLeft) & target.rect.size;
}

/// The target's centre in GLOBAL coordinates.
Offset timelineRowChromeCenter(
  WidgetTester tester,
  String layerId,
  String id, {
  String prefix = 'timeline',
}) => timelineRowChromeGlobalRect(tester, layerId, id, prefix: prefix).center;

/// The row's selection-scoped repeat outlines, row-local.
List<Rect> timelineRowChromePatternSpans(
  WidgetTester tester,
  String layerId, {
  String prefix = 'timeline',
}) =>
    timelineRowChromePainter(
      tester,
      layerId,
      prefix: prefix,
    )?.model.patternSpans ??
    const [];
