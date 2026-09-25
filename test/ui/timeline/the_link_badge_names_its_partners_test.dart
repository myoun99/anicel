// THE LINK BADGE NAMES WHERE THE PICTURES ARE SHARED (유저 2026-09-25:
// 「링크버튼통해서 어디랑 링크되고있는지만 제대로 표시하게」). A link is made
// by duplicating, never by a name, so the name cannot say it — the badge
// has to. It said only THAT the pictures are shared.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/ui/editor_workspace.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/text/app_strings.dart';
import 'package:anicel/src/ui/timeline/collapsed_row_overlay.dart';
import 'package:anicel/src/ui/timeline/layer_timeline_grid.dart';
import 'package:anicel/src/ui/timeline/timeline_grid_metrics.dart';
import 'package:anicel/src/ui/timeline/timeline_layer_controls_row.dart';
import 'package:anicel/src/ui/timeline/xsheet_timeline_grid.dart';

import '../../helpers/home_page_probes.dart';

void main() {
  Widget row(List<String> partners) => MaterialApp(
    home: Material(
      child: TimelineLayerControlsRow(
        layer: Layer(
          id: const LayerId('bg'),
          name: 'BG',
          frames: const [],
          timeline: const {},
        ),
        active: false,
        metrics: TimelineGridMetrics.defaults,
        onSelectLayer: (_) {},
        onToggleLayerVisibility: (_) {},
        onLayerOpacityChanged: (_, _) {},
        onToggleLayerTimesheet: (_) {},
        onLayerMarkSelected: (_, _) {},
        linkPartners: partners,
      ),
    ),
  );

  testWidgets('the badge\'s tooltip names every row it shares with, one a '
      'line', (tester) async {
    await tester.pumpWidget(row(const ['C2 · BG', 'C3 · BOOK']));
    expect(find.byIcon(Icons.link), findsOneWidget);
    expect(
      find.byTooltip(
        [AppText.strings.tlLinkedWith, 'C2 · BG', 'C3 · BOOK'].join('\n'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('no partners: not linked, no badge', (tester) async {
    await tester.pumpWidget(row(const []));
    expect(find.byIcon(Icons.link), findsNothing);
  });

  // THE WIRING, host by host: three surfaces stand the same row up, and
  // each hands it the partners itself — the sheet once lacked the badge
  // for exactly that reason (F-26).

  /// The app with its active row link-duplicated, and the tooltip the row
  /// and its copy each wear — the other one, in this cut, of this name.
  Future<String> linkedApp(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1500, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(home: HomePage(initialProject: createDefaultProject())),
    );
    await tester.pumpAndSettle();
    final s = tester
        .widget<EditorWorkspace>(find.byType(EditorWorkspace))
        .session;
    final name = s.activeLayer!.name;
    s.layerVerbs.linkDuplicateActiveLayer();
    await tester.pumpAndSettle();
    return [
      AppText.strings.tlLinkedWith,
      '${s.requireActiveCut.name} · $name',
    ].join('\n');
  }

  Finder tipIn(Type host, String tip) =>
      find.descendant(of: find.byType(host), matching: find.byTooltip(tip));

  testWidgets('the timeline\'s rail', (tester) async {
    final tip = await linkedApp(tester);
    expect(tipIn(LayerTimelineGrid, tip), findsNWidgets(2));
  });

  testWidgets('the sheet\'s header', (tester) async {
    final tip = await linkedApp(tester);
    await tapToolbarButton(
      tester,
      const ValueKey<String>('timeline-orientation-toggle-button'),
    );
    await tester.pumpAndSettle();
    expect(tipIn(XSheetTimelineGrid, tip), findsNWidgets(2));
  });

  testWidgets('the folded row', (tester) async {
    final tip = await linkedApp(tester);
    await tester.drag(
      find.byKey(const ValueKey<String>('dock-resize-bottom')),
      const Offset(0, -420),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('floating-bottom-collapse')),
    );
    await tester.pumpAndSettle();
    expect(tipIn(CollapsedRowOverlay, tip), findsOneWidget);
  });
}
