// The 「타임시트 서식」 button opens the window on the cut the sheet shows
// (timesheet-sheet-kind-scope-Q1 「컷마다 따로」): the paper picked there
// goes onto the cut in the same undo step as the format, and the sheet
// re-lays on it; a cut whose cel layers outgrow the 6-second strip is
// offered the 3-second sheet only (timesheet-sheet-capacity-Q1 「3초 시트로
// 고정(6초 끔)」).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/canvas_viewport.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/timesheet_document.dart';
import 'package:anicel/src/models/timesheet_sheet_kind.dart';
import 'package:anicel/src/ui/brush/brush_tool_state.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/timesheet/timesheet_document_painter.dart';
import 'package:anicel/src/ui/timesheet/timesheet_ink_controller.dart';
import 'package:anicel/src/ui/timesheet_tab_host.dart';
import 'package:anicel/src/ui/widgets/pill_strip.dart';

/// The default project, its cut given [cels] more cel layers.
Project _project({required int cels}) {
  final project = createDefaultProject();
  final track = project.tracks.first;
  final cut = track.cuts.first;
  return project.copyWith(
    tracks: [
      track.copyWith(
        cuts: [
          cut.copyWith(
            layers: [
              ...cut.layers,
              for (var index = 0; index < cels; index += 1)
                Layer(
                  id: LayerId('added-$index'),
                  name: 'Z$index',
                  frames: const [],
                ),
            ],
          ),
        ],
      ),
    ],
  );
}

ValueKey<String> _paper(TimesheetSheetKind kind) =>
    ValueKey<String>('timesheet-format-paper-${kind.jsonValue}');

void main() {
  late EditorSessionManager session;

  Future<void> pumpHost(WidgetTester tester, {required int cels}) async {
    session = EditorSessionManager(initialProject: _project(cels: cels));
    addTearDown(session.dispose);
    final ink = TimesheetInkController();
    addTearDown(ink.dispose);
    final brush = ValueNotifier<BrushToolState>(BrushToolState.defaults);
    addTearDown(brush.dispose);
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
            brushToolState: brush,
            brushAllowed: false,
            onBrushAllowedChanged: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// The sheet the panel prints now.
  TimesheetDocument sheet(WidgetTester tester) => tester
      .widgetList<CustomPaint>(find.byType(CustomPaint))
      .map((paint) => paint.painter)
      .whereType<TimesheetDocumentPainter>()
      .first
      .document;

  Future<void> tap(WidgetTester tester, ValueKey<String> key) async {
    await tester.ensureVisible(find.byKey(key));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(key));
    await tester.pumpAndSettle();
  }

  testWidgets('the paper picked goes onto the cut and the sheet re-lays on '
      'it; one undo puts it back', (tester) async {
    await pumpHost(tester, cels: 0);
    expect(sheet(tester).sheetKind, TimesheetSheetKind.sixSeconds);

    await tap(tester, const ValueKey<String>('timesheet-format-button'));
    await tap(tester, _paper(TimesheetSheetKind.threeSeconds));
    await tap(tester, const ValueKey<String>('timesheet-format-save-button'));

    expect(
      session.activeCutOrNull!.metadata.sheetKind,
      TimesheetSheetKind.threeSeconds,
    );
    expect(sheet(tester).sheetKind, TimesheetSheetKind.threeSeconds);

    session.undo();
    await tester.pumpAndSettle();
    expect(
      session.activeCutOrNull!.metadata.sheetKind,
      TimesheetSheetKind.sixSeconds,
    );
    expect(sheet(tester).sheetKind, TimesheetSheetKind.sixSeconds);
  });

  testWidgets('a cut whose cel layers outgrow the 6-second strip prints on '
      'the 3-second sheet, and its window refuses 6초', (tester) async {
    await pumpHost(tester, cels: 9);
    expect(sheet(tester).sheetKind, TimesheetSheetKind.threeSeconds);

    await tap(tester, const ValueKey<String>('timesheet-format-button'));
    final six = tester.widget<Pill>(
      find.byKey(_paper(TimesheetSheetKind.sixSeconds)),
    );
    final three = tester.widget<Pill>(
      find.byKey(_paper(TimesheetSheetKind.threeSeconds)),
    );
    expect(six.onTap, isNull);
    expect(three.selected, isTrue);
  });
}
