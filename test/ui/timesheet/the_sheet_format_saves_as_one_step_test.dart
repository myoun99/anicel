// The 「타임시트 서식」 window's save: the work's sheet format and the paper
// of the cut the sheet shows (timesheet-sheet-kind-scope-Q1 「컷마다 따로」)
// go in as ONE undo step — only what changed, and nothing when nothing did.
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/timesheet_sheet_kind.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';

void main() {
  late EditorSessionManager session;

  setUp(() {
    session = EditorSessionManager(initialProject: createDefaultProject());
  });

  tearDown(() => session.dispose());

  TimesheetSheetKind paperOf(EditorSessionManager session) =>
      session.activeCutOrNull!.metadata.sheetKind;

  test('the format and the cut\'s paper are one step: one undo puts both '
      'back', () {
    final cut = session.activeCutOrNull!;
    final before = session.timesheetInfo;
    final after = before.copyWith(seEmptyFill: !before.seEmptyFill);
    expect(paperOf(session), TimesheetSheetKind.sixSeconds, reason: '⛔전제');

    session.updateTimesheetFormat(
      info: after,
      cutId: cut.id,
      kind: TimesheetSheetKind.threeSeconds,
    );
    expect(session.timesheetInfo, after);
    expect(paperOf(session), TimesheetSheetKind.threeSeconds);

    session.undo();
    expect(session.timesheetInfo, before);
    expect(paperOf(session), TimesheetSheetKind.sixSeconds);
  });

  test('only what changed is written, and nothing banks an empty step', () {
    final cut = session.activeCutOrNull!;
    final info = session.timesheetInfo;

    session.updateTimesheetFormat(
      info: info,
      cutId: cut.id,
      kind: TimesheetSheetKind.sixSeconds,
    );
    expect(session.historyManager.canUndo, isFalse);

    session.updateTimesheetFormat(
      info: info,
      cutId: cut.id,
      kind: TimesheetSheetKind.threeSeconds,
    );
    expect(paperOf(session), TimesheetSheetKind.threeSeconds);
    session.undo();
    expect(paperOf(session), TimesheetSheetKind.sixSeconds);
    expect(session.timesheetInfo, info);
  });

  test('in the gap the save writes the format alone', () {
    final before = session.timesheetInfo;
    final after = before.copyWith(seEmptyFill: !before.seEmptyFill);

    session.updateTimesheetFormat(info: after);
    expect(session.timesheetInfo, after);
    expect(paperOf(session), TimesheetSheetKind.sixSeconds);
  });
}
