import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/attached_mode.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/export_overrides.dart';
import 'package:anicel/src/models/export_spec.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_folder.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_mark.dart';
import 'package:anicel/src/models/layer_process.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/editing/default_cut_helpers.dart';
import 'package:anicel/src/ui/export/export_cel_group_plan.dart';
import 'package:anicel/src/ui/export/export_cels_board.dart';
import 'package:anicel/src/ui/export/export_cels_selection.dart';
import 'package:anicel/src/ui/export/export_cels_standing.dart';
import 'package:anicel/src/ui/widgets/boolean_dot.dart';

/// The Cels list (F-289): which rows it shows, and where it stands.
///
/// 🗣️유저 2026-10-06: 「서있는걸 일단 레이어별로 서있도록 하고싶어 …
/// 미리보기창엔 서있는 레이어를 보여주는거지 … 서있는 행의 그림들만
/// 보여주도록」 · 「미리보기 창의 프레임 인덱스 기억하기로하자」.
void main() {
  const cutId = CutId('cut');
  const key = LayerMark(process: LayerProcess.key);
  const layout = LayerMark(process: LayerProcess.layout);

  Frame frame(String id, String name) =>
      Frame(id: FrameId(id), duration: 1, strokes: const [], name: name);

  Layer row(
    String id,
    String name,
    List<String> cels, {
    LayerMark mark = key,
    String? folder,
    String? attachedTo,
    AttachedMode mode = AttachedMode.free,
  }) => Layer(
    id: LayerId(id),
    name: name,
    frames: [for (final cel in cels) frame('$id-$cel', cel)],
    mark: mark,
    folderId: folder == null ? null : LayerId(folder),
    attachedToLayerId: attachedTo == null ? null : LayerId(attachedTo),
    attachedMode: mode,
  );

  /// Top of the timeline first: folder F holding C (one cel) and B (three),
  /// then A (four) with a FREE attach row A_r of its own two — and a LO
  /// row L the 원화 label leaves off.
  Cut film() => Cut(
    id: cutId,
    name: '301',
    duration: 8,
    canvasSize: const CanvasSize(width: 8, height: 8),
    layers: [
      row('l', 'L', ['1', '2'], mark: layout),
      row('a', 'A', ['1', '2', '3', '4']),
      row('ar', 'A_r', ['1', '2'], attachedTo: 'a'),
      row('b', 'B', ['1', '2', '3'], folder: 'f'),
      row('c', 'C', ['1'], folder: 'f'),
      createFolderLayer(id: const LayerId('f'), name: 'F'),
      createCameraLayer(cutId: cutId),
    ],
  );

  ({List<ExportCelsBoardRow> rows, ExportCelGroupPlan plan}) board(
    Cut cut, {
    CelsExportSpec spec = const CelsExportSpec(),
    ExportCelsCutDelta? delta,
    Set<LayerId> shut = const {},
  }) {
    final overrides = delta == null
        ? ExportProjectOverrides()
        : ExportProjectOverrides().withCelsDelta(cutId, delta);
    final plan = buildExportCelGroupPlan(
      project: Project(
        id: const ProjectId('project'),
        name: 'Project',
        exportOverrides: overrides,
        tracks: [
          Track(id: const TrackId('track'), name: 'Track', cuts: [cut]),
        ],
        createdAt: DateTime.utc(2026),
      ),
      activeCutId: cutId,
      spec: spec,
      overrides: overrides,
    );
    return (
      plan: plan,
      rows: ExportCelsListing(cut, spec).rows(
        selection: resolveExportCelsSelection(
          cut: cut,
          spec: spec,
          delta: delta,
        ),
        sheets: plan.sheets,
        shut: shut,
      ),
    );
  }

  List<String> ids(List<ExportCelsBoardRow> rows) => [
    for (final row in rows) row.layer.id.value,
  ];

  ExportCelsBoardRow of(List<ExportCelsBoardRow> rows, String id) =>
      rows.singleWhere((row) => row.layer.id.value == id);

  List<String> names(Iterable<ExportCelSheet> sheets) => [
    for (final sheet in sheets) sheet.celName,
  ];

  ExportCelRef ref(String row, String cel) =>
      (row: LayerId(row), cel: FrameId('$row-$cel'));

  group('the rows', () {
    test('are the cut\'s listed rows as the timeline draws them, each with '
        'the drawings that stand on it', () {
      final rows = board(film()).rows;
      expect(ids(rows), ['f', 'c', 'b', 'ar', 'a', 'l']);
      expect(names(of(rows, 'a').sheets), ['1', '2', '3', '4']);
      expect(names(of(rows, 'ar').sheets), ['1', '2']);
      expect(of(rows, 'f').sheets, isEmpty);
    });

    test('a row\'s switch reads the selection; a folder\'s, what its rows '
        'say together', () {
      final rows = board(film()).rows;
      expect(of(rows, 'a').state, BooleanMix.on);
      expect(of(rows, 'l').state, BooleanMix.off, reason: 'LO, under 원화');
      expect(of(rows, 'f').state, BooleanMix.on);

      final one = board(
        film(),
        delta: ExportCelsCutDelta().withLayerOverride(
          const LayerId('c'),
          false,
        ),
      ).rows;
      expect(of(one, 'f').state, BooleanMix.mixed);
      expect(of(one, 'c').state, BooleanMix.off);
      expect(of(one, 'b').state, BooleanMix.on);

      final none = board(
        film(),
        delta: ExportCelsCutDelta()
            .withLayerOverride(const LayerId('c'), false)
            .withLayerOverride(const LayerId('b'), false),
      ).rows;
      expect(of(none, 'f').state, BooleanMix.off);
    });

    test('a twirl is worn by a folder and by a base with attach rows — and '
        'shut, it folds what is under it away', () {
      final rows = board(film()).rows;
      expect(of(rows, 'f').open, isTrue);
      expect(of(rows, 'a').open, isTrue);
      expect(of(rows, 'b').open, isNull, reason: 'nothing rides it');
      expect(of(rows, 'ar').open, isNull);

      final folded = board(
        film(),
        shut: {const LayerId('f'), const LayerId('a')},
      ).rows;
      expect(ids(folded), ['f', 'a', 'l']);
      expect(of(folded, 'f').open, isFalse);
      expect(of(folded, 'a').open, isFalse);
      expect(
        of(folded, 'f').state,
        BooleanMix.on,
        reason: 'a folder still says what the rows it folds say',
      );
    });

    test('a row of a kind that is off is not a row of the list', () {
      final rows = board(film(), spec: const CelsExportSpec(kinds: {})).rows;
      expect(rows, isEmpty);
    });
  });

  group('what the preview turns through on a row', () {
    test('the drawings that are written; one turned off is not among them', () {
      final rows = board(
        film(),
        delta: ExportCelsCutDelta().withCelSkipped(ref('a', '2'), true),
      ).rows;
      expect(names(exportCelsPages(of(rows, 'a'))), ['1', '3', '4']);
    });

    test('on a row that is OFF, the drawings that were left on (유저 '
        '2026-10-06: 「그 상태에서 콘티행 off해도 1,3 활성화되있으니까 서서 '
        '보여줄수있게」)', () {
      final rows = board(
        film(),
        delta: ExportCelsCutDelta().withCelSkipped(ref('l', '1'), true),
      ).rows;
      final off = of(rows, 'l');
      expect(off.sheets.every((sheet) => !sheet.planned), isTrue);
      expect(names(exportCelsPages(off)), ['2']);
    });
  });

  group('standing', () {
    test('with nothing chosen it is the first row that holds a drawing', () {
      final rows = board(film()).rows;
      const standing = ExportCelsStanding();
      expect(standing.rowIn(rows)?.layer.id.value, 'c');
      expect(standing.sheetIn(rows), isNull, reason: 'nothing is shown yet');
      final settled = standing.settledOn(rows);
      expect(
        (settled.row?.value, settled.shown?.value, settled.place),
        ('c', 'c-1', 0),
      );
    });

    test('standing on a row shows its drawing at the place remembered, and '
        'its first where it has none there', () {
      final rows = board(film()).rows;
      final onA = const ExportCelsStanding().standingOn(
        const LayerId('a'),
        rows,
      );
      expect((onA.row?.value, onA.shown?.value), ('a', 'a-1'));

      final third = onA.stepped(2, rows);
      expect((third.shown?.value, third.place), ('a-3', 2));

      // B has a third drawing: the same place.
      final onB = third.standingOn(const LayerId('b'), rows);
      expect((onB.row?.value, onB.shown?.value, onB.place), ('b', 'b-3', 2));
      // C has one: its first — and the place is kept for the next row.
      final onC = onB.standingOn(const LayerId('c'), rows);
      expect((onC.shown?.value, onC.place), ('c-1', 2));
      final backOnA = onC.standingOn(const LayerId('a'), rows);
      expect(backOnA.shown?.value, 'a-3');
    });

    test('a folder is not stood on — it holds no drawing', () {
      final rows = board(film()).rows;
      final onA = const ExportCelsStanding().standingOn(
        const LayerId('a'),
        rows,
      );
      expect(onA.standingOn(const LayerId('f'), rows), onA);
    });

    test('the steps stop at the row\'s ends', () {
      final rows = board(film()).rows;
      final onA = const ExportCelsStanding().standingOn(
        const LayerId('a'),
        rows,
      );
      expect(onA.stepped(-1, rows).shown?.value, 'a-1');
      expect(onA.stepped(9, rows).shown?.value, 'a-4');
      expect(onA.stepped(9, rows).place, 3);
    });

    test('the drawing shown is turned off: the nearest one left takes its '
        'place — the next before the previous — and that place is '
        'remembered', () {
      final before = board(film()).rows;
      final onSecond = const ExportCelsStanding()
          .standingOn(const LayerId('a'), before)
          .stepped(1, before);
      expect(onSecond.shown?.value, 'a-2');

      final after = board(
        film(),
        delta: ExportCelsCutDelta().withCelSkipped(ref('a', '2'), true),
      ).rows;
      final settled = onSecond.settledOn(after);
      expect((settled.shown?.value, settled.place), ('a-3', 2));

      // …and with the next one off too, the previous.
      final both = board(
        film(),
        delta: ExportCelsCutDelta()
            .withCelSkipped(ref('a', '2'), true)
            .withCelSkipped(ref('a', '3'), true)
            .withCelSkipped(ref('a', '4'), true),
      ).rows;
      expect(onSecond.settledOn(both).shown?.value, 'a-1');
    });

    test('the row stood on leaves the list: the first row left with a '
        'drawing is stood on', () {
      final rows = board(film()).rows;
      final onC = const ExportCelsStanding().standingOn(
        const LayerId('c'),
        rows,
      );
      final folded = board(film(), shut: {const LayerId('f')}).rows;
      final settled = onC.settledOn(folded);
      expect((settled.row?.value, settled.shown?.value), ('ar', 'ar-1'));
    });

    test('a standing that still holds is left as it is', () {
      final rows = board(film()).rows;
      final onA = const ExportCelsStanding()
          .standingOn(const LayerId('a'), rows)
          .stepped(1, rows);
      expect(identical(onA.settledOn(rows), onA), isTrue);
    });
  });
}
