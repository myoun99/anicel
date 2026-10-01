import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/app_language.dart';
import 'package:anicel/src/models/camera_instruction.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/timesheet_document.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/timesheet/cut_sheet_document.dart';

/// A cut's sheet is [cutSheetDocument]'s — the timesheet panel's and the
/// export's alike (export-sheet-lacks-transitions, 2026-09-30): the のりしろ
/// an O.L asks of the cut, and the O.L itself in the notation language's
/// word, whenever the transition row is kept on the sheet.
///
/// Two 24-frame cuts, 301 and 302, and an O.L over frames 18..29: 301 owes
/// six frames of のりしろ past its end.
void main() {
  Cut cut(String name) => Cut(
    id: CutId(name),
    name: name,
    duration: 24,
    canvasSize: const CanvasSize(width: 64, height: 36),
    layers: const [],
  );

  EditorSessionManager session() {
    final s = EditorSessionManager(
      initialProject: Project(
        id: const ProjectId('p'),
        name: 'P',
        createdAt: DateTime.utc(2026),
        tracks: [
          Track(
            id: const TrackId('t'),
            name: 'T',
            cuts: [cut('301'), cut('302')],
          ),
        ],
      ),
    );
    s.transitions.updateTransitionInstructions({
      18: const InstructionEvent(instructionId: 'ol', length: 12),
    });
    s.selectCut(const CutId('301'));
    return s;
  }

  TimesheetDocument sheetOf301(EditorSessionManager s) => cutSheetDocument(
    s,
    cut: s.activeTrack.cuts.first,
    cutStartFrame: 0,
  );

  TimesheetColumn? transitionColumnOf(
    TimesheetDocument document,
    EditorSessionManager s,
  ) => document.columns
      .where((column) => column.layerId == s.activeTrack.transitionLayer.id)
      .firstOrNull;

  test('the sheet runs on through the のりしろ the O.L asks of the cut', () {
    final s = session();
    addTearDown(s.dispose);
    final sheet = sheetOf301(s);
    expect(sheet.transitionHandles.tail, 6);
    expect(sheet.drawnFrameCount, 24 + 6);
  });

  test('the O.L prints in the notation language\'s word', () {
    final s = session();
    addTearDown(s.dispose);
    s.setLanguageSettings(
      s.languageSettings.value.copyWith(
        programLanguage: AppLanguage.en,
        notationLanguage: AppLanguage.ja,
      ),
    );
    final column = transitionColumnOf(sheetOf301(s), s);
    expect(column, isNotNull);
    expect(
      column!.cells
          .firstWhere((cell) => cell.kind == TimesheetCellKind.instructionStart)
          .label,
      'カットO.L',
    );
  });

  test('a transition row kept off the sheet leaves its slot blank — the '
      'のりしろ still counts', () {
    final s = session();
    addTearDown(s.dispose);
    s.layerSwitches.toggleLayerTimesheet(s.activeTrack.transitionLayer.id);
    final sheet = sheetOf301(s);
    expect(transitionColumnOf(sheet, s), isNull);
    expect(sheet.drawnFrameCount, 24 + 6);
  });
}
