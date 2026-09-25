import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/brush_dab.dart';
import 'package:anicel/src/models/brush_edit_session_state.dart';
import 'package:anicel/src/models/brush_tip_shape.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_viewport.dart';
import 'package:anicel/src/models/timesheet_ink_keys.dart';
import 'package:anicel/src/services/brush_stroke_commit_data.dart';
import 'package:anicel/src/ui/brush/brush_tool_state.dart';
import 'package:anicel/src/ui/canvas/interactive_brush_edit_canvas_view.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/timesheet/timesheet_ink_controller.dart';
import 'package:anicel/src/ui/timesheet_tab_host.dart';

/// 🚨F-80 ② — THE TIMESHEET SHOWS WHAT THE UNDO PUT BACK.
///
/// 유저 2026-09-11: 「드로잉on인상태에서 그릴때 undo로 기록이안되는거같음.
/// 언두해도 언두안되고 다른곳 타임라인 조작이나 그 패널 바깥의 동작이 언두됨」.
///
/// Measured through the real host and the session's own undo: the ink
/// window takes its surface when the host rebuilds, so the question is
/// whether the window on screen holds the surface the store holds after
/// the step — not whether the store was put back, which it always was.
void main() {
  testWidgets('a stroke undone through the session leaves the sheet on '
      'screen as well as in the store', (tester) async {
    final session = EditorSessionManager(
      initialProject: createDefaultProject(),
    );
    addTearDown(session.dispose);
    final ink = TimesheetInkController();
    addTearDown(ink.dispose);
    final brushTool = ValueNotifier<BrushToolState>(BrushToolState.defaults);
    addTearDown(brushTool.dispose);
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TimesheetTabHost(
            session: session,
            continuous: false,
            onContinuousChanged: (_) {},
            viewport: CanvasViewport(),
            onViewportChanged: (_) {},
            inkController: ink,
            brushToolState: brushTool,
            // F-80 ② is a drawing-ON report: 「드로잉on인상태에서 그릴때」.
            brushAllowed: true,
            onBrushAllowedChanged: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final band = timesheetInkStripKey(
      session.requireActiveCut.id,
      0,
    );
    // Page 0's first half: the paged view's window over band 0.
    BrushEditSessionState onScreen() => tester
        .widget<InteractiveBrushEditCanvasView>(
          find.byKey(const ValueKey<String>('timesheet-ink-strip-0-h0')),
        )
        .sessionState;

    ink.commitStroke(
      plane: TimesheetInkPlane.strip,
      key: band,
      strokeData: BrushStrokeCommitData(
        sourceDabs: [
          BrushDab(
            center: CanvasPoint(x: 20, y: 20),
            color: 0xFF000000,
            size: 4,
            opacity: 1,
            flow: 1,
            hardness: 1,
            tipShape: BrushTipShape.round,
            pressure: 1,
            sequence: 0,
          ),
        ],
      ),
      historyManager: session.historyManager,
    );
    await tester.pump();
    expect(
      onScreen(),
      same(ink.sessionStateFor(TimesheetInkPlane.strip, band)),
      reason: 'the CONTROL — the stroke is on screen',
    );

    session.undo();
    await tester.pump();

    expect(
      ink.hasInkFor(TimesheetInkPlane.strip, band),
      isFalse,
      reason: 'the CONTROL — the undo put the band back',
    );
    expect(
      onScreen(),
      same(ink.sessionStateFor(TimesheetInkPlane.strip, band)),
      reason:
          'the window kept the surface from before the undo: nothing it '
          'rebuilds on was told, so the stroke stayed on the sheet and the '
          'next press went on to undo something outside the panel',
    );
  });
}
