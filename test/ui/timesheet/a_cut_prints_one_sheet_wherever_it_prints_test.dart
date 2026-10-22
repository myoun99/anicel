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
import 'package:anicel/src/models/timeline_row_address.dart';
import 'package:anicel/src/models/timesheet_document.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/export/xdts_builder.dart';
import 'package:anicel/src/ui/editor_command_actions.dart';
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
    List<Layer> layersOf301 = const [],
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
            cuts: [cut('301', layersOf301), cut('302', layersOf302)],
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

  Frame named(String id) =>
      Frame(id: FrameId(id), duration: 1, strokes: const [], name: id);

  /// The rows [sheet]'s column for [id] marks [kind] on.
  List<int> rowsOf(
    TimesheetDocument sheet,
    LayerId id,
    TimesheetCellKind kind,
  ) {
    final cells = sheet.columns
        .firstWhere((column) => column.layerId == id)
        .cells;
    return [
      for (var row = 0; row < cells.length; row += 1)
        if (cells[row].kind == kind) row,
    ];
  }

  /// The one time table of the XDTS [cut] exports.
  Map<String, dynamic> xdtsTableOf(
    EditorSessionManager s,
    Cut cut, {
    required int cutStartFrame,
  }) {
    final xdts = cutXdtsContent(s, cut: cut, cutStartFrame: cutStartFrame);
    final json =
        jsonDecode(xdts.substring(xdts.indexOf('\n') + 1))
            as Map<String, dynamic>;
    return (json['timeTables'] as List<dynamic>).single
        as Map<String, dynamic>;
  }

  /// What the one track of [table]'s field [fieldId] writes, by frame — a
  /// track writes only the frames its value changes on.
  Map<int, String> writtenOn(Map<String, dynamic> table, int fieldId) {
    final field = (table['fields'] as List<dynamic>)
        .cast<Map<String, dynamic>>()
        .firstWhere((field) => field['fieldId'] == fieldId);
    final track =
        (field['tracks'] as List<dynamic>).single as Map<String, dynamic>;
    return {
      for (final entry
          in (track['frames'] as List<dynamic>).cast<Map<String, dynamic>>())
        entry['frame'] as int:
            (((entry['data'] as List<dynamic>).single
                            as Map<String, dynamic>)['values']
                        as List<dynamic>)
                    .single
                as String,
    };
  }

  /// The frames [table]'s field [fieldId] writes a picture or a sound on.
  List<int> framesWritten(Map<String, dynamic> table, int fieldId) => [
    for (final MapEntry(:key, :value) in writtenOn(table, fieldId).entries)
      if (value != xdtsNullCell) key,
  ];

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
    expect(
      rowsOf(sheet, const LayerId('a'), TimesheetCellKind.drawing),
      [12, 24],
    );
    expect(
      rowsOf(sheet, const LayerId('s1'), TimesheetCellKind.drawing),
      [12],
    );
    expect(
      rowsOf(
        sheet,
        s.activeTrack.transitionLayer.id,
        TimesheetCellKind.instructionStart,
      ),
      [0, 24],
    );

    final table = xdtsTableOf(s, cut302, cutStartFrame: 24);
    expect(framesWritten(table, xdtsFieldCell).first, 12);
    expect(framesWritten(table, xdtsFieldDialog).first, 12);
  });

  // 🗣️Board `I-73-ol-xdts-duration` (저장 2026-10-20): the XDTS runs the
  // rows the sheet draws. ↩️It ran the conte 尺: 302 — its own frame 0 six
  // before its conte — lost its last six rows, and 301 the six past its
  // conte, with the picture and the sound on each.
  test('🚨the XDTS runs as long as its sheet is drawn — the のりしろ an O.L '
      'asks of the cut it leaves and of the cut it arrives into, and the '
      'pictures and sounds on it, are written where the sheet prints '
      'them', () {
    final s = session(
      seLayers: [
        Layer(
          id: const LayerId('s1'),
          name: 'S1',
          kind: LayerKind.se,
          frames: [named('ring'), named('bell')],
          timeline: const {
            // 301's own 27, past its conte; 302's own 9.
            27: TimelineExposure.drawing(FrameId('ring'), length: 2),
            // 302's own 26, in its last six.
            44: TimelineExposure.drawing(FrameId('bell'), length: 2),
          },
        ),
      ],
      layersOf301: [
        Layer(
          id: const LayerId('c'),
          name: 'C',
          frames: [named('3')],
          timeline: const {
            26: TimelineExposure.drawing(FrameId('3'), length: 2),
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
    final [cut301, cut302] = s.activeTrack.cuts;

    for (final (cut, cutStartFrame, picture, pictures, sounds) in [
      (cut301, 0, const LayerId('c'), [26], [27]),
      (cut302, 24, const LayerId('a'), [12, 24], [9, 26]),
    ]) {
      final sheet = cutSheetDocument(
        s,
        cut: cut,
        cutStartFrame: cutStartFrame,
      );
      final table = xdtsTableOf(s, cut, cutStartFrame: cutStartFrame);
      expect(sheet.drawnFrameCount, 24 + 6, reason: cut.name);
      expect(table['duration'], sheet.drawnFrameCount, reason: cut.name);
      expect(
        framesWritten(table, xdtsFieldCell),
        pictures,
        reason: '${cut.name}: its pictures, the のりしろ\'s included',
      );
      expect(
        rowsOf(sheet, picture, TimesheetCellKind.drawing),
        pictures,
        reason: '${cut.name}: on the rows the sheet prints them on',
      );
      expect(
        framesWritten(table, xdtsFieldDialog),
        sounds,
        reason: '${cut.name}: its sounds, the のりしろ\'s included',
      );
      expect(
        rowsOf(sheet, const LayerId('s1'), TimesheetCellKind.drawing),
        sounds,
        reason: '${cut.name}: on the rows the sheet prints them on',
      );
    }
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

  // 🗣️F-338 ② (유저 2026-10-11): a block made on the transition row right
  // after an O.L turned the sheet red. The cut view's ＋ makes a one-frame
  // span there (F-180), and the sheet's transition column counted from the
  // cut's place while its rows count from its own frame 0, so the block
  // printed over the O.L's rows (I-73-ol-sheet-columns).
  test('a block the cut view makes right after the O.L prints on its own '
      'row of the cut the O.L arrives into, and past the cut it leaves', () {
    final s = session();
    addTearDown(s.dispose);
    s.selectCut(const CutId('302'));
    s.standOnRow(LayerRowAddress(s.activeTrack.transitionLayer.id));
    s.selectFrameIndex(12);
    expect(s.editingGlobalFrame, 30, reason: '⛔전제: the frame after the O.L');
    expect(s.cellInstances.canCreateInstance, isTrue, reason: '⛔전제');

    createActiveInstance(s);

    expect(
      s.activeTrack.transitionLayer.instructions.keys,
      [18, 30],
      reason: '⛔전제: the ＋ made its span',
    );
    List<int> startsOn(TimesheetDocument sheet) => [
      for (final (row, cell) in transitionColumnOf(sheet, s)!.cells.indexed)
        if (cell.kind == TimesheetCellKind.instructionStart) row,
    ];
    final cuts = s.activeTrack.cuts;
    expect(
      startsOn(cutSheetDocument(s, cut: cuts.last, cutStartFrame: 24)),
      contains(12),
    );
    expect(startsOn(sheetOf301(s)), [18]);
  });
}
