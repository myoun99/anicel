import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show SemanticsNode;
import 'package:flutter_test/flutter_test.dart';
import 'package:quick_animaker_v2/src/ui/timeline/timeline_row_cells_painter.dart';

/// Test probes for the PAINTED drawing-row cells (UI-R9 #12b): cells are
/// canvas work now, so `find.byKey('timeline-cell-…')` only exists for the
/// sparse widget rows (SE / instruction / camera). Drawing-row assertions
/// read the painter's cell model; taps go through painter geometry.
///
/// The geometry has ONE source of truth: [TimelineRowCellsPainter.cellRectFor]
/// — the same math the row's own hit-testing uses.
TimelineRowCellsPainter timelineRowCellsPainterFor(
  WidgetTester tester,
  String layerId, {
  String prefix = 'timeline',
}) {
  final paint = tester.widget<CustomPaint>(
    find.byKey(ValueKey<String>('$prefix-row-cells-$layerId')),
  );
  return paint.painter! as TimelineRowCellsPainter;
}

/// The painter-resolved model of one cell (glyph, exposure state, ghost /
/// dim flags) — the successor of reading TimelineFrameCell's fields.
TimelineRowCellModel timelineCellModel(
  WidgetTester tester,
  String layerId,
  int frameIndex, {
  String prefix = 'timeline',
}) => timelineRowCellsPainterFor(
  tester,
  layerId,
  prefix: prefix,
).cellModelAt(frameIndex);

/// The cell's center in GLOBAL coordinates (tap targets, drag anchors).
Offset timelineCellCenter(
  WidgetTester tester,
  String layerId,
  int frameIndex, {
  String prefix = 'timeline',
}) {
  final finder = find.byKey(ValueKey<String>('$prefix-row-cells-$layerId'));
  final painter = timelineRowCellsPainterFor(tester, layerId, prefix: prefix);
  final box = tester.renderObject(finder) as RenderBox;
  return box.localToGlobal(painter.cellRectFor(frameIndex).center);
}

/// The cell's rect in GLOBAL coordinates.
Rect timelineCellGlobalRect(
  WidgetTester tester,
  String layerId,
  int frameIndex, {
  String prefix = 'timeline',
}) {
  final finder = find.byKey(ValueKey<String>('$prefix-row-cells-$layerId'));
  final painter = timelineRowCellsPainterFor(tester, layerId, prefix: prefix);
  final box = tester.renderObject(finder) as RenderBox;
  final local = painter.cellRectFor(frameIndex);
  return box.localToGlobal(local.topLeft) & local.size;
}

/// Whether [frameIndex] lies inside the row's PAINT window (the painted
/// successor of `find.byKey(cell key) → findsOneWidget`). Under the
/// UI-R15 self-windowing contract this is the offset-derived slice the
/// painter actually records, not the widget's (now full) bounds.
bool timelineCellInWindow(
  WidgetTester tester,
  String layerId,
  int frameIndex, {
  String prefix = 'timeline',
}) {
  final window = timelineRowCellsPainterFor(
    tester,
    layerId,
    prefix: prefix,
  ).visibleFrameWindow();
  return frameIndex >= window.startIndex &&
      frameIndex < window.endIndexExclusive;
}

/// The cell's resolved BoxDecoration equivalent — a drop-in for the old
/// widget-cell decoration reads (background / 1px border / block radius).
BoxDecoration timelineCellDecoration(
  WidgetTester tester,
  String layerId,
  int frameIndex, {
  String prefix = 'timeline',
}) {
  final style = timelineRowCellsPainterFor(
    tester,
    layerId,
    prefix: prefix,
  ).resolvedCellStyleFor(frameIndex);
  return BoxDecoration(
    color: style.background,
    border: Border.all(color: style.border, width: 1),
    borderRadius: style.radius,
  );
}

/// Every semantics label the row's cell painter actually publishes.
///
/// `find.bySemanticsLabel` cannot see these: a painter's `semanticsBuilder`
/// produces SemanticsNodes owned by the RenderCustomPaint, not widgets with
/// their own semantics config. Requires `tester.ensureSemantics()` — without
/// it the tree is not built at all, which is exactly why this reads the tree
/// instead of the painter's model (the model would pass even if the nodes
/// were never emitted).
List<String> timelineCellSemanticsLabels(
  WidgetTester tester,
  String layerId, {
  String prefix = 'timeline',
}) {
  final node = tester.getSemantics(
    find.byKey(ValueKey<String>('$prefix-row-cells-$layerId')),
  );
  final labels = <String>[];
  void visit(SemanticsNode current) {
    if (current.label.isNotEmpty) {
      labels.add(current.label);
    }
    current.visitChildren((child) {
      visit(child);
      return true;
    });
  }

  visit(node);
  return labels;
}

/// Parses a legacy cell key (`timeline-cell-<layerId>-<index>` /
/// `xsheet-cell-<layerId>-<index>`) — the migration shim for helpers that
/// still receive key strings.
({String layerId, int frameIndex}) parseTimelineCellKey(String key) {
  final prefixEnd = key.indexOf('-cell-') + '-cell-'.length;
  final rest = key.substring(prefixEnd);
  final split = rest.lastIndexOf('-');
  return (
    layerId: rest.substring(0, split),
    frameIndex: int.parse(rest.substring(split + 1)),
  );
}

/// Taps the cell (pointer-down select fires immediately, like the widget
/// cells' raw-pointer contract).
Future<void> tapTimelineCell(
  WidgetTester tester,
  String layerId,
  int frameIndex, {
  String prefix = 'timeline',
}) async {
  await tester.tapAt(
    timelineCellCenter(tester, layerId, frameIndex, prefix: prefix),
  );
  await tester.pump();
}
