import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/project_background.dart';
import 'package:anicel/src/ui/brush/brush_canvas_panel.dart';
import 'package:anicel/src/ui/editor_workspace.dart';
import 'package:anicel/src/ui/home_page.dart';

/// The canvas panel's view bars — the scrollbars and the zoom/rotate/fit
/// buttons — must survive a flip. They show viewport geometry and nothing
/// else, so nothing about WHICH FRAME the playhead is on may throw their
/// memo away.
///
/// It did. The memo token carried the panel title, which reads
/// "Project: … · Cut: … · Layer: … · Frame: <label>", so a step that
/// changed the frame label rebuilt the whole bar — 13 icon buttons with
/// tooltips, overlay portals, ink and gesture detectors. Measured at 391
/// widget rebuilds in one step against 24 for the panel's own spine.
///
/// ⚠️ The fixture below crosses "no cel ↔ cel" because two freshly created
/// cels share an empty frame label, which is the only way a DEV project
/// changes the label at all. A real cut names every cel, so there the bar
/// was rebuilt on every single flip step. Do not read the fixture's
/// narrowness as the defect's.
void main() {
  testWidgets('…but a colour the pill SHOWS does rebuild it', (tester) async {
    // The other half of the same rule. The token was trimmed to what the
    // bars actually display — and the two surface swatches the pill carries
    // were never in it, so the pill went on painting yesterday's paper
    // colour until an unrelated pan or resize happened to invalidate the
    // memo. Tapping the stale swatch even reopened the picker seeded with
    // the old value.
    await tester.binding.setSurfaceSize(const Size(1600, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const MaterialApp(home: HomePage()));
    await tester.pumpAndSettle();

    final session = tester
        .widget<EditorWorkspace>(find.byType(EditorWorkspace))
        .session;
    final swatch = find.descendant(
      of: find.byKey(const ValueKey<String>('main-canvas-brush-host')),
      matching: find.byKey(const ValueKey<String>('canvas-paper-color-button')),
    );
    expect(swatch, findsOneWidget, reason: 'the pill is wide enough here');
    final before = tester.widget(swatch);

    session.setProjectBackground(const ProjectBackground.color(0xFF123456));
    await tester.pumpAndSettle();

    expect(
      identical(tester.widget(swatch), before),
      isFalse,
      reason: 'the pill shows this colour, so the memo may not serve it stale',
    );
    session.prerenderScheduler.cancel();
  });

  testWidgets('a flip that changes the frame label keeps the view bars', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1600, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const MaterialApp(home: HomePage()));
    await tester.pumpAndSettle();

    final session = tester
        .widget<EditorWorkspace>(find.byType(EditorWorkspace))
        .session;
    final mainPanel = find.byKey(
      const ValueKey<String>('main-canvas-brush-host'),
    );
    // Scoped to the MAIN canvas: the conte, timesheet and envelope sheets
    // mount panels — and scrollbars — of their own.
    Object viewBar() => tester.widget(
      find.descendant(
        of: mainPanel,
        matching: find.byType(CanvasViewportVerticalScrollbar),
      ),
    );

    session.selectFrameIndex(0);
    session.createDrawingAtCurrentFrame();
    await tester.pumpAndSettle();
    final titleOnCel = session.canvasSelectionLabels.title;
    final barOnCel = viewBar();

    session.selectFrameIndex(4);
    await tester.pumpAndSettle();

    // FIXTURE GUARD: without this the test passes on a fixture whose title
    // never moved, which is exactly the case the defect does not touch.
    expect(
      session.canvasSelectionLabels.title,
      isNot(titleOnCel),
      reason: 'the step really did change the panel title',
    );
    expect(
      identical(viewBar(), barOnCel),
      isTrue,
      reason: 'the view bars show viewport geometry, not the playhead — a '
          'frame step must not rebuild them',
    );

    session.prerenderScheduler.cancel();
  });
}
