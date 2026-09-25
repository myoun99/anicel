import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/layer_mark.dart';
import 'package:anicel/src/models/layer_process.dart';
import 'package:anicel/src/ui/timeline/timeline_grid_metrics.dart';
import 'package:anicel/src/ui/widgets/panel_flyout.dart';
import 'package:anicel/src/ui/timeline/timeline_layer_controls_header.dart';

/// **ONE LEGEND FLYOUT TEMPLATE.**
///
/// "Legend absent → no flyout; the bulk entries; then, ONLY when
/// [TimelineLayerControlsHeader.showRowSolos], a divider and the solo
/// entries" is one rule spelled at four cells (timesheet, mark, fill-ref,
/// fx). These pin the rule at all four so it cannot be shared into a
/// shape that answers differently at one of them.
void main() {
  LayerLegendCallbacks callbacks() => LayerLegendCallbacks(
    onShowAllLayers: () {},
    onHideAllLayers: () {},
    onToggleVisibilitySolo: () {},
    onSheetAllOn: () {},
    onSheetAllOff: () {},
    onClearMarkFilter: () {},
    onClearAllFillReferences: () {},
    onMuteAllSe: () {},
    onUnmuteAllSe: () {},
    onBypassAllFx: () {},
    onEnableAllFx: () {},
    onToggleMarkFilter: (_) {},
    onToggleKindFilter: (_) {},
    onToggleSheetOnlyFilter: () {},
    onToggleFxOnlyFilter: () {},
    onToggleFillReferenceOnlyFilter: () {},
    onPreviewLayersOpacity: (_, _) {},
    onCommitLayersOpacity: (_, _) {},
  );

  Future<void> pump(
    WidgetTester tester, {
    required bool withLegend,
    required bool showRowSolos,
    Set<LayerMark> marksInUse = const {},
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 900,
            child: TimelineLayerControlsHeader(
              metrics: TimelineGridMetrics.defaults,
              legend: withLegend ? callbacks() : null,
              showRowSolos: showRowSolos,
              marksInUse: marksInUse,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Opens one legend cell and reports what its flyout holds.
  Future<({List<String> items, int dividers})> openFlyout(
    WidgetTester tester,
    String cellKey,
  ) async {
    await tester.tap(find.byKey(ValueKey<String>(cellKey)));
    await tester.pumpAndSettle();
    final items = <String>[];
    for (final element in find.byType(PopupMenuItem<PanelFlyoutItem>).evaluate()) {
      final key = element.widget.key;
      if (key is ValueKey<String> && key.value.startsWith('legend-')) {
        items.add(key.value);
      }
    }
    final dividers = find.byType(PopupMenuDivider).evaluate().length;
    return (items: items, dividers: dividers);
  }

  /// The four cells the template covers, with the bulk item each must
  /// always offer and the solo item each offers only under showRowSolos.
  const cells = <(String cell, String bulk, String solo)>[
    ('legend-sheet', 'legend-sheet-all-on', 'legend-filter-sheet'),
    ('legend-fill-ref', 'legend-fill-ref-clear', 'legend-filter-fill-ref'),
    ('legend-fx', 'legend-fx-enable-all', 'legend-filter-fx'),
  ];

  testWidgets('no legend, no flyout — the cell still keeps its key', (
    tester,
  ) async {
    await pump(tester, withLegend: false, showRowSolos: true);
    for (final (cell, _, _) in [
      ...cells,
      ('legend-mark', 'legend-mark-filter-clear', 'legend-filter-mark-layout'),
    ]) {
      // ⛔The key stays on the cell whether or not it can open a flyout —
      // it is the column's stable address.
      expect(find.byKey(ValueKey<String>(cell)), findsOneWidget);
      await tester.tap(find.byKey(ValueKey<String>(cell)));
      await tester.pumpAndSettle();
      expect(
        find.byType(PopupMenuItem<PanelFlyoutItem>),
        findsNothing,
        reason: '$cell opened a flyout with no legend behind it',
      );
    }
  });

  testWidgets('with row solos: bulk entries, a divider, then the solos', (
    tester,
  ) async {
    await pump(tester, withLegend: true, showRowSolos: true);
    for (final (cell, bulk, solo) in cells) {
      final flyout = await openFlyout(tester, cell);
      expect(flyout.items, contains(bulk), reason: cell);
      expect(flyout.items, contains(solo), reason: cell);
      expect(flyout.dividers, 1, reason: '$cell: one divider, before the solos');
      expect(
        flyout.items.indexOf(bulk),
        lessThan(flyout.items.indexOf(solo)),
        reason: '$cell: the bulk half comes first',
      );
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();
    }
  });

  testWidgets('⛔without row solos: the bulk half alone, and NO divider', (
    tester,
  ) async {
    await pump(tester, withLegend: true, showRowSolos: false);
    for (final (cell, bulk, solo) in cells) {
      final flyout = await openFlyout(tester, cell);
      expect(flyout.items, contains(bulk), reason: cell);
      expect(flyout.items, isNot(contains(solo)), reason: cell);
      expect(
        flyout.dividers,
        0,
        reason: '$cell: a divider with nothing under it is a stray line',
      );
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();
    }
  });

  // 🚨THE MARKS IN USE: the mark cell's solo half is a product of what is
  // actually on the rows, so an empty set means no solos AND no divider,
  // even with row solos on.
  testWidgets('the MARK cell shows only the marks in use', (tester) async {
    await pump(tester, withLegend: true, showRowSolos: true);
    var flyout = await openFlyout(tester, 'legend-mark');
    expect(flyout.items, contains('legend-mark-filter-clear'));
    expect(
      flyout.dividers,
      0,
      reason: 'no mark is on any row, so there is no solo half to divide',
    );
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();

    await pump(
      tester,
      withLegend: true,
      showRowSolos: true,
      marksInUse: {
        const LayerMark(process: LayerProcess.layout),
        LayerMark.none,
      },
    );
    flyout = await openFlyout(tester, 'legend-mark');
    expect(flyout.items, contains('legend-mark-filter-clear'));
    expect(flyout.items, contains('legend-filter-mark-layout'));
    expect(flyout.dividers, 1);
  });

  testWidgets('and the mark solos stand down with row solos off', (
    tester,
  ) async {
    await pump(
      tester,
      withLegend: true,
      showRowSolos: false,
      marksInUse: {const LayerMark(process: LayerProcess.layout)},
    );
    final flyout = await openFlyout(tester, 'legend-mark');
    expect(flyout.items, contains('legend-mark-filter-clear'));
    expect(flyout.items, isNot(contains('legend-filter-mark-layout')));
    expect(flyout.dividers, 0);
  });
}
