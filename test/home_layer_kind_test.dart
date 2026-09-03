// HomePage widget tests — layer kinds and the layer order.
// Split from widget_test.dart (2026-09-04) so the suite runs across
// isolates; the shared probes live in helpers/home_page_probes.dart.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/main.dart';

import 'helpers/vertical_text_finder.dart';
import 'ui/timeline/timeline_cell_probe.dart';

import 'helpers/home_page_probes.dart';

void main() {
  testWidgets('uses the sample cut resolved from the project by default', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const AnicelApp());

    await expectCutName(tester, 'default-cut-1', '1');
    await expectCutsNamed(tester, 'Cut 2', 0);
    expectActiveLayerName('A');
    expect(find.text('B'), findsNothing);
    await expectCutsNamed(tester, 'New Cut', 0);
    expect(find.text('A'), findsWidgets);
    expectCellText('default-layer-1', 0, 'X');
    expect(
      find.byKey(const ValueKey<String>('timeline-row-cells-default-layer-1')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('timeline-row-cells-default-layer-2')),
      findsNothing,
    );
    await expectActiveCutName(tester, '1');
  });

  testWidgets('initial timeline layer shows animation kind icon', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const AnicelApp());

    expect(
      find.byKey(
        const ValueKey<String>('timeline-layer-kind-icon-default-layer-1'),
      ),
      findsOneWidget,
    );
    expect(layerKindIcon(tester, 'default-layer-1'), Icons.filter_outlined);
    expect(find.bySemanticsLabel('Animation layer'), findsOneWidget);
    expect(find.text('A'), findsWidgets);
  });

  testWidgets('Add Layer creates an animation kind icon for active B', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const AnicelApp());

    await addLayer(tester);

    expect(
      find.byKey(
        const ValueKey<String>('timeline-layer-kind-icon-default-layer-2'),
      ),
      findsOneWidget,
    );
    expect(layerKindIcon(tester, 'default-layer-2'), Icons.filter_outlined);
    expectActiveLayerName('B');
    expect(find.bySemanticsLabel('Animation layer'), findsNWidgets(2));
  });

  testWidgets('storyboard toggle updates the active layer kind icon', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const AnicelApp());

    expect(layerKindIcon(tester, 'default-layer-1'), Icons.filter_outlined);

    await tapToolbarButton(
      tester,
      const ValueKey<String>('toggle-storyboard-layer-button'),
    );

    expect(
      layerKindIcon(tester, 'default-layer-1'),
      Icons.auto_stories_outlined,
    );
    expect(find.bySemanticsLabel('Storyboard layer'), findsOneWidget);

    await tapToolbarButton(
      tester,
      const ValueKey<String>('toggle-storyboard-layer-button'),
    );

    expect(layerKindIcon(tester, 'default-layer-1'), Icons.filter_outlined);
    expect(find.bySemanticsLabel('Animation layer'), findsOneWidget);
  });

  testWidgets('multiple layers can show different layer kind icons', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const AnicelApp());
    await addLayer(tester);

    await tapToolbarButton(
      tester,
      const ValueKey<String>('toggle-storyboard-layer-button'),
    );

    expect(layerKindIcon(tester, 'default-layer-1'), Icons.filter_outlined);
    expect(
      layerKindIcon(tester, 'default-layer-2'),
      Icons.auto_stories_outlined,
    );
    expect(find.bySemanticsLabel('Animation layer'), findsOneWidget);
    expect(find.bySemanticsLabel('Storyboard layer'), findsOneWidget);
    expect(find.text('A'), findsWidgets);
    expect(find.text('B'), findsWidgets);

    final layerAName = find.byKey(
      const ValueKey<String>('timeline-layer-name-default-layer-1'),
    );
    await tester.ensureVisible(layerAName);
    await tester.pumpAndSettle();
    await tester.tap(layerAName);
    await tester.pumpAndSettle();

    expectActiveLayerName('A');
  });

  testWidgets('pressing Add Layer creates B then C above active layers', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const AnicelApp());

    expectActiveLayerName('A');
    expect(
      find.byKey(const ValueKey<String>('timeline-layer-row-default-layer-2')),
      findsNothing,
    );

    await addLayer(tester);

    expectActiveLayerName('B');
    expect(
      find.byKey(const ValueKey<String>('timeline-row-cells-default-layer-2')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('timeline-selected-layer')),
      findsOneWidget,
    );
    expectCellText('default-layer-2', 0, 'X');

    var layerBTop = tester
        .getTopLeft(
          find.byKey(
            const ValueKey<String>('timeline-layer-row-default-layer-2'),
          ),
        )
        .dy;
    var layerATop = tester
        .getTopLeft(
          find.byKey(
            const ValueKey<String>('timeline-layer-row-default-layer-1'),
          ),
        )
        .dy;
    expect(layerBTop, lessThan(layerATop));

    await addLayer(tester);

    expectActiveLayerName('C');
    expect(
      find.byKey(const ValueKey<String>('timeline-row-cells-default-layer-3')),
      findsOneWidget,
    );
    expectCellText('default-layer-3', 0, 'X');

    // The layer axis is virtualized and the drawing rows sit at the BOTTOM
    // of the display order — scroll them into the window before measuring.
    final verticalScrollable = find
        .descendant(
          of: find.byKey(
            const ValueKey<String>('timeline-vertical-scroll-viewport'),
          ),
          matching: find.byType(Scrollable),
        )
        .first;
    final verticalPosition = tester
        .state<ScrollableState>(verticalScrollable)
        .position;
    verticalPosition.jumpTo(verticalPosition.maxScrollExtent);
    await tester.pumpAndSettle();

    final layerCTop = tester
        .getTopLeft(
          find.byKey(
            const ValueKey<String>('timeline-layer-row-default-layer-3'),
          ),
        )
        .dy;
    layerBTop = tester
        .getTopLeft(
          find.byKey(
            const ValueKey<String>('timeline-layer-row-default-layer-2'),
          ),
        )
        .dy;
    layerATop = tester
        .getTopLeft(
          find.byKey(
            const ValueKey<String>('timeline-layer-row-default-layer-1'),
          ),
        )
        .dy;

    expect(layerCTop, lessThan(layerBTop));
    expect(layerBTop, lessThan(layerATop));
    expect(
      find.byKey(
        const ValueKey<String>('timeline-layer-kind-icon-default-layer-3'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('XSheet keeps raw layer order after adding B and C', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const AnicelApp());

    await addLayer(tester);
    await addLayer(tester);
    await tapToolbarButton(
      tester,
      const ValueKey<String>('timeline-orientation-toggle-button'),
    );

    final layerALeft = tester
        .getTopLeft(
          find.byKey(
            const ValueKey<String>('xsheet-layer-row-default-layer-1'),
          ),
        )
        .dx;
    final layerBLeft = tester
        .getTopLeft(
          find.byKey(
            const ValueKey<String>('xsheet-layer-row-default-layer-2'),
          ),
        )
        .dx;
    final layerCLeft = tester
        .getTopLeft(
          find.byKey(
            const ValueKey<String>('xsheet-layer-row-default-layer-3'),
          ),
        )
        .dx;

    expect(layerALeft, lessThan(layerBLeft));
    expect(layerBLeft, lessThan(layerCLeft));
    expect(
      find.byKey(const ValueKey<String>('xsheet-row-cells-default-layer-1')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('xsheet-row-cells-default-layer-2')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('xsheet-row-cells-default-layer-3')),
      findsOneWidget,
    );

    await tapTimelineCell(tester, 'default-layer-1', 0, prefix: 'xsheet');
    await tester.pumpAndSettle();
    // R10 R6: the selected column's name is vertical writing now.
    expect(
      find.descendant(
        of: find.byKey(const ValueKey<String>('xsheet-selected-layer')),
        matching: findVerticalText('A'),
      ),
      findsOneWidget,
    );
  });
}
