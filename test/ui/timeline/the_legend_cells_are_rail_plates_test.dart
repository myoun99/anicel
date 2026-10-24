// The legend's cells are the rail's plate buttons (I-57 ①): the claim and
// ONE face around the heading, as the rows' mark and take are — not a
// tooltip, a builder and an InkWell of their own (~35 elements a cell, ten
// of them a legend, mounted anew whenever a frame panel is shown again —
// frame-panels-build-in-one-frame, 10-24).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/ui/theme/app_theme.dart';
import 'package:anicel/src/ui/timeline/layer_rail_columns.dart'
    show noOptionalRailColumns;
import 'package:anicel/src/ui/timeline/timeline_grid_metrics.dart';
import 'package:anicel/src/ui/timeline/timeline_layer_controls_header.dart';
import 'package:anicel/src/ui/timeline/timeline_legend_menus.dart';
import 'package:anicel/src/ui/widgets/rail_glyph_button.dart';

import '../../helpers/app_icon_button_probe.dart';

/// Every verb a legend can be handed, none doing anything.
LayerLegendCallbacks _everyVerb() => LayerLegendCallbacks(
  onShowAllLayers: () {},
  onHideAllLayers: () {},
  onToggleVisibilitySolo: () {},
  onSheetAllOn: () {},
  onSheetAllOff: () {},
  onClearMarkFilter: () {},
  onClearAllClips: () {},
  onBypassAllFx: () {},
  onEnableAllFx: () {},
  onToggleMarkFilter: (_) {},
  onToggleKindFilter: (_) {},
  onToggleSheetOnlyFilter: () {},
  onToggleFxOnlyFilter: () {},
  onToggleClippedOnlyFilter: () {},
  onPreviewLayersOpacity: (_, _) {},
  onCommitLayersOpacity: (_, _) {},
  onToggleOnionSkinForDisplayed: () {},
  onRevealOnionSkinPanel: () {},
  onSetBlendModeForDisplayed: (_, _) {},
);

Widget _legend({
  LayerLegendCallbacks? legend,
  VoidCallback? onExpandAllLanes,
}) => MaterialApp(
  home: Material(
    child: SizedBox(
      width: 900,
      child: TimelineLayerControlsHeader(
        metrics: TimelineGridMetrics.defaults,
        optionalColumns: legend == null
            ? noOptionalRailColumns
            : (onion: true, blend: true),
        legend: legend,
        kinds: legend == null ? const {} : const {LayerKind.animation},
        displayedLayerIds: legend == null ? null : () => <LayerId>{},
        onExpandAllLanes: onExpandAllLanes,
        onCollapseAllLanes: onExpandAllLanes == null ? null : () {},
      ),
    ),
  ),
);

/// The plate face a legend cell keyed [key] is.
Finder _faceOf(String key) => find.descendant(
  of: find.byKey(ValueKey<String>(key)),
  matching: find.byType(RailPlateFace),
);

void main() {
  testWidgets('every pressed legend cell is a rail plate — no InkWell, and '
      'no Tooltip but the master opacity bar\'s', (tester) async {
    var expanded = 0;
    await tester.pumpWidget(
      _legend(legend: _everyVerb(), onExpandAllLanes: () => expanded += 1),
    );

    for (final cell in const [
      'legend-sections',
      'legend-lanes-toggle',
      'legend-sheet',
      'legend-mark',
      'legend-kind',
      'legend-clip',
      'legend-fx',
      'legend-onion',
      'legend-eye',
      'legend-blend',
    ]) {
      expect(_faceOf(cell), findsOneWidget, reason: '$cell is a plate');
      expect(
        tester.widget<RailPlateFace>(_faceOf(cell)).onSemanticTap,
        isNotNull,
        reason: '$cell presses',
      );
    }
    final legend = find.byType(TimelineLayerControlsHeader);
    expect(
      find.descendant(of: legend, matching: find.byType(InkWell)),
      findsNothing,
    );
    // AppTooltip IS a Tooltip — a subclass, which `byType` would not match.
    expect(
      find.descendant(
        of: legend,
        matching: find.byWidgetPredicate((widget) => widget is Tooltip),
      ),
      findsOneWidget,
      reason: 'the master opacity bar keeps its own',
    );

    // The lanes cell's press is its own, not a list's.
    await tester.tap(find.byKey(const ValueKey<String>('legend-lanes-toggle')));
    await tester.pump();
    expect(expanded, 1);
  });

  testWidgets('a passive host\'s cells are dead plates that still name their '
      'column', (tester) async {
    await tester.pumpWidget(_legend());

    final eye = tester.widget<RailPlateFace>(_faceOf('legend-eye'));
    expect(eye.onSemanticTap, isNull);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey<String>('legend-eye')),
        matching: find.railTooltip(eye.tooltip),
      ),
      findsOneWidget,
    );
    expect(eye.tooltip, isNotEmpty);
  });

  test('the legend\'s plate is opaque — so a cell wears no ink of its own: '
      'an ink under it is never seen, as under the rows\' mark and take', () {
    expect(AppColors.washUp.a, 1.0);
  });
}
