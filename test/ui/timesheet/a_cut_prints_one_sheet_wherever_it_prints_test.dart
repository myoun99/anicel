import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/app_language.dart';
import 'package:anicel/src/models/camera_instruction.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/timesheet_document.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/export/xdts_builder.dart';
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
  Cut cut(String name, [List<Layer> layers = const []]) => Cut(
    id: CutId(name),
    name: name,
    duration: 24,
    canvasSize: const CanvasSize(width: 64, height: 36),
    layers: layers,
  );

  EditorSessionManager session({
    List<Layer> seLayers = const [],
    List<Layer> layersOf302 = const [],
  }) {
    final s = EditorSessionManager(
      initialProject: Project(
        id: const ProjectId('p'),
        name: 'P',
        createdAt: DateTime.utc(2026),
        tracks: [
          Track(
            id: const TrackId('t'),
            name: 'T',
            seLayers: seLayers,
            cuts: [cut('301'), cut('302', layersOf302)],
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
      'カット O.L',
    );
  });

  // 🗣️Board `I-73-ol-sheet-columns`: 302 is drawn from the O.L's start,
  // six frames before its place on the track, so its own frame 12 plays at
  // the track's 30. ↩️Its sounds and its marks were counted from its
  // place: the sound printed on row 6, the fade on row 18.
  test('🚨in the cut the O.L arrives into, a picture, the sound heard with '
      'it and a fade over it share a row — on the sheet and in the XDTS '
      'alike', () {
    Frame named(String id) =>
        Frame(id: FrameId(id), duration: 1, strokes: const [], name: id);
    final s = session(
      seLayers: [
        Layer(
          id: const LayerId('s1'),
          name: 'S1',
          kind: LayerKind.se,
          frames: [named('door')],
          timeline: const {
            30: TimelineExposure.drawing(FrameId('door'), length: 4),
          },
        ),
      ],
      layersOf302: [
        Layer(
          id: const LayerId('a'),
          name: 'A',
          frames: [named('1'), named('2')],
          timeline: const {
            12: TimelineExposure.drawing(FrameId('1'), length: 4),
            24: TimelineExposure.drawing(FrameId('2'), length: 6),
          },
        ),
      ],
    );
    addTearDown(s.dispose);
    s.transitions.updateTransitionInstructions({
      18: const InstructionEvent(instructionId: 'ol', length: 12),
      42: const InstructionEvent(instructionId: 'fo', length: 6),
    });
    final cut302 = s.activeTrack.cuts.last;

    final sheet = cutSheetDocument(s, cut: cut302, cutStartFrame: 24);
    List<int> rowsOf(LayerId id, TimesheetCellKind kind) {
      final cells = sheet.columns
          .firstWhere((column) => column.layerId == id)
          .cells;
      return [
        for (var row = 0; row < cells.length; row += 1)
          if (cells[row].kind == kind) row,
      ];
    }

    expect(rowsOf(const LayerId('a'), TimesheetCellKind.drawing), [12, 24]);
    expect(rowsOf(const LayerId('s1'), TimesheetCellKind.drawing), [12]);
    expect(
      rowsOf(
        s.activeTrack.transitionLayer.id,
        TimesheetCellKind.instructionStart,
      ),
      [0, 24],
    );

    final xdts = cutXdtsContent(s, cut: cut302, cutStartFrame: 24);
    final json =
        jsonDecode(xdts.substring(xdts.indexOf('\n') + 1))
            as Map<String, dynamic>;
    final table =
        (json['timeTables'] as List<dynamic>).single as Map<String, dynamic>;
    final fields = (table['fields'] as List<dynamic>)
        .cast<Map<String, dynamic>>();
    String valueOf(Map<String, dynamic> entry) =>
        (((entry['data'] as List<dynamic>).single
                        as Map<String, dynamic>)['values']
                    as List<dynamic>)
                .single
            as String;
    // The first frame the field's one track writes something on.
    int firstWritten(int fieldId) {
      final field = fields.firstWhere((field) => field['fieldId'] == fieldId);
      final track =
          (field['tracks'] as List<dynamic>).single as Map<String, dynamic>;
      return (track['frames'] as List<dynamic>)
              .cast<Map<String, dynamic>>()
              .firstWhere((entry) => valueOf(entry) != xdtsNullCell)['frame']
          as int;
    }

    expect(firstWritten(xdtsFieldCell), 12);
    expect(firstWritten(xdtsFieldDialog), 12);
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
