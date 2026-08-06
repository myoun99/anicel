import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/brush/brush_canvas_panel.dart';
import 'package:anicel/src/ui/brush/brush_preset_panel.dart';
import 'package:anicel/src/ui/brush/brush_settings_panel.dart';
import 'package:anicel/src/ui/editor_canvas_area.dart';
import 'package:anicel/src/ui/envelope/cut_envelope_tab_host.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/storyboard_panel.dart';
import 'package:anicel/src/ui/timeline/timeline_panel.dart';
import 'package:anicel/src/ui/timesheet_tab_host.dart';

import '../helpers/panel_finders.dart';

/// R26 #31 — the FACTORY dock arrangement.
///
/// This layout was attempted once and reverted: docking the timesheet open
/// by default made 201 tests fail, because the sheet mounts a second
/// [BrushCanvasPanel] (and real interactive canvas views inside it) and
/// every app-wide finder suddenly matched twice. The answer was to scope
/// the finders ([panel_finders.dart]), not to hide the sheet — so this
/// file pins BOTH halves: the arrangement itself, and the fact that two
/// canvas panels coexisting is the expected state, not a bug.
void main() {
  Future<void> pumpWorkspace(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1600, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const MaterialApp(home: HomePage()));
    await tester.pumpAndSettle();
  }

  testWidgets('the timesheet ships OPEN in the right vertical dock', (
    tester,
  ) async {
    await pumpWorkspace(tester);

    expect(
      find.byKey(const ValueKey<String>('editor-panel-dock-right')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey<String>('editor-panel-dock-right')),
        matching: find.byType(TimesheetTabHost),
      ),
      findsOneWidget,
    );
    // Really rendering, not just mounted behind a tab.
    expect(
      find.byKey(const ValueKey<String>('timesheet-document-paint')),
      findsOneWidget,
    );
  });

  testWidgets('the left dock stacks Tool Library OVER Tool Settings — both '
      'open at once', (tester) async {
    await pumpWorkspace(tester);

    expect(find.byType(BrushPresetPanel), findsOneWidget);
    expect(find.byType(BrushSettingsPanel), findsOneWidget);
    expect(
      tester.getCenter(find.byType(BrushPresetPanel)).dy,
      lessThan(tester.getCenter(find.byType(BrushSettingsPanel)).dy),
      reason: 'the library is the TOP section',
    );
    // Both live in the wide left dock, left of the canvas.
    expect(
      tester.getCenter(find.byType(BrushSettingsPanel)).dx,
      lessThan(tester.getCenter(find.byType(EditorCanvasArea)).dx),
    );
  });

  testWidgets('the bottom strip keeps the frame-axis panels, timeline '
      'active', (tester) async {
    await pumpWorkspace(tester);

    expect(find.byType(TimelinePanel), findsOneWidget);
    expect(find.byType(StoryboardPanel), findsNothing);
    expect(
      tester.getCenter(find.byType(TimelinePanel)).dy,
      greaterThan(tester.getCenter(find.byType(EditorCanvasArea)).dy),
    );
  });

  testWidgets('the 컷봉투 ships as a bottom-strip tab beside the conte — '
      'closed, like every other paper tab there', (tester) async {
    await pumpWorkspace(tester);

    expect(
      find.byKey(const ValueKey<String>('timeline-mode-envelope-button')),
      findsOneWidget,
    );
    expect(find.byType(CutEnvelopeTabHost), findsNothing);

    await tester.tap(
      find.byKey(const ValueKey<String>('timeline-mode-envelope-button')),
    );
    await tester.pumpAndSettle();

    expect(find.byType(CutEnvelopeTabHost), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('cut-envelope-page')),
      findsOneWidget,
      reason: 'really drawing the sheet, not just mounted',
    );
  });

  testWidgets('TWO canvas panels are the expected default — the drawing '
      'canvas and the sheet — so finders must name their panel', (
    tester,
  ) async {
    await pumpWorkspace(tester);

    // The fact that reverted this change the first time, stated as a
    // contract: an app-wide finder is now ambiguous ON PURPOSE.
    expect(find.byType(BrushCanvasPanel), findsNWidgets(2));
    // And the scoped ones stay unambiguous.
    expect(inMainCanvas(find.byType(BrushCanvasPanel)), findsOneWidget);
    expect(inTimesheet(find.byType(BrushCanvasPanel)), findsOneWidget);
  });
}
