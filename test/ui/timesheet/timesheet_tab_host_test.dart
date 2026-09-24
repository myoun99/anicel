import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/canvas_viewport.dart';
import 'package:anicel/src/ui/brush/brush_tool_state.dart';
import 'package:anicel/src/ui/canvas/interactive_brush_edit_canvas_view.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/sheet/sheet_ink_layer.dart';
import 'package:anicel/src/ui/timesheet/timesheet_ink_controller.dart';
import 'package:anicel/src/ui/timesheet_tab_host.dart';

import '../../helpers/frame_census.dart';

const _inkLayerKey = ValueKey<String>('timesheet-ink-layer');
const _inkToggleKey = ValueKey<String>('timesheet-ink-toggle-button');
const _editorKey = ValueKey<String>('timesheet-header-edit-field');
const _titleZoneKey = ValueKey<String>('timesheet-header-edit-title-p0');
const _memoZoneKey = ValueKey<String>('timesheet-memo-edit-p0');

void main() {
  late EditorSessionManager session;
  late TimesheetInkController inkController;
  late ValueNotifier<BrushToolState> brushTool;

  Future<void> pumpHost(WidgetTester tester, {bool inkEnabled = true}) async {
    session = EditorSessionManager(initialProject: createDefaultProject());
    addTearDown(session.dispose);
    inkController = TimesheetInkController();
    addTearDown(inkController.dispose);
    brushTool = ValueNotifier<BrushToolState>(BrushToolState.defaults);
    addTearDown(brushTool.dispose);

    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    var enabled = inkEnabled;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => TimesheetTabHost(
              session: session,
              continuous: false,
              onContinuousChanged: (_) {},
              viewport: CanvasViewport(),
              onViewportChanged: (_) {},
              inkController: inkController,
              brushToolState: brushTool,
              inkEnabled: enabled,
              onInkEnabledChanged: (next) => setState(() => enabled = next),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('TimesheetTabHost sheet-ink toggle', () {
    testWidgets('blocking ink unmounts the ink windows; allowing restores '
        'them', (tester) async {
      await pumpHost(tester);

      expect(find.byKey(_inkLayerKey), findsOneWidget);

      await tester.tap(find.byKey(_inkToggleKey));
      await tester.pumpAndSettle();
      expect(find.byKey(_inkLayerKey), findsNothing);

      await tester.tap(find.byKey(_inkToggleKey));
      await tester.pumpAndSettle();
      expect(find.byKey(_inkLayerKey), findsOneWidget);
    });

    // H40 ② (2026-09-24): the ink layer was rebuilt on every brush change —
    // each frame of a settings slider drag. Its windows read the brush when
    // a stroke starts now, so a change reaches none of them.
    testWidgets('a brush change rebuilds no ink window, and the windows read '
        'the brush in hand', (tester) async {
      await pumpHost(tester);
      expect(find.byKey(_inkLayerKey), findsOneWidget);

      final next = brushTool.value.copyWith(size: 40, color: 0xFF336699);
      final census = await frameCensus(tester, () => brushTool.value = next);

      expect(census.rebuilt, isNot(contains(SheetInkLayer)));
      expect(census.rebuilt, isNot(contains(InteractiveBrushEditCanvasView)));
      final windows = tester.widgetList<InteractiveBrushEditCanvasView>(
        find.byType(InteractiveBrushEditCanvasView),
      );
      expect(windows, isNotEmpty);
      for (final window in windows) {
        expect(window.inputSettings(), next.toInputSettings());
      }
    });

    testWidgets('with ink allowed, a tap on a header box draws instead of '
        'opening the editor (pen-on-paper rule)', (tester) async {
      await pumpHost(tester);

      await tester.tap(find.byKey(_titleZoneKey), warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(find.byKey(_editorKey), findsNothing);
    });
  });

  group('TimesheetTabHost header editing (ink blocked)', () {
    testWidgets('editing the TITLE box commits to the project timesheet '
        'info', (tester) async {
      await pumpHost(tester, inkEnabled: false);

      await tester.tap(find.byKey(_titleZoneKey));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(_editorKey), 'YOASOBI');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(session.timesheetInfo.title, 'YOASOBI');
    });

    testWidgets('editing the memo band commits the cut note', (tester) async {
      await pumpHost(tester, inkEnabled: false);

      await tester.tap(find.byKey(_memoZoneKey));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(_editorKey), 'カットO.L');

      // Tap the document margin — covered only by the tap-away barrier.
      final paperOrigin = tester.getTopLeft(
        find.byKey(const ValueKey<String>('timesheet-document-paint')),
      );
      await tester.tapAt(paperOrigin + const Offset(5, 5));
      await tester.pumpAndSettle();

      expect(session.cutVerbs.activeCutNote, 'カットO.L');
    });
  });
}
