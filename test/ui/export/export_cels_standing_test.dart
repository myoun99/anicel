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

import '../../helpers/every_frame_drawn.dart';
import '../../helpers/export_cels_alone.dart';
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
    CelsExportSpec spec = celsAlone,
    ExportCelsCutDelta? delta,
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
      drawn: everyFrameDrawn,
      spec: spec,
      overrides: overrides,
    );
    return (plan: plan, rows: ExportCelsListing(cut, spec).rows(plan));
  }

  /// The attach column of [row]: what the filters of [spec] admit.
  List<String> stack(
    Cut cut,
    ExportCelsBoardRow row, {
    CelsExportSpec spec = celsAlone,
  }) => [
    for (final layer in ExportCelsListing(
      cut,
      spec,
    ).stackOf(row, resolveExportCelsSelection(cut: cut, spec: spec)))
      layer.id.value,
  ];

  List<String> ids(List<ExportCelsBoardRow> rows) => [
    for (final row in rows) row.idValue,
  ];

  ExportCelsBoardRow of(List<ExportCelsBoardRow> rows, String id) =>
      rows.singleWhere((row) => row.idValue == id);

  List<String> names(Iterable<ExportListSheet> sheets) => [
    for (final sheet in sheets) sheet.word,
  ];

  ExportCelRef ref(String row, String cel) =>
      (row: LayerId(row), cel: FrameId('$row-$cel'));

  // export-four-tabs (유저 2026-10-09): 「결국 나가는건 파일 하나니까
  // 파일기준 행이니까 접기 펼치기 없이 한 행만 보이면되」 · 「블록 없어도 그냥
  // 행 보이게」 · 「필터전부」.
  group('the rows', () {
    test('are the cut\'s STACKS as the timeline draws them, each with the '
        'files its bundle writes — no folder row, no attach row', () {
      final rows = board(film()).rows;
      expect(ids(rows), ['c', 'b', 'a', 'l']);
      expect(names(of(rows, 'a').sheets), ['1', '2', '3', '4']);
    });

    test('🚨a stack that holds no picture is a row all the same — off, with '
        'no file, and stood on like any', () {
      final rows = board(film()).rows;
      final lo = of(rows, 'l');
      expect(lo.sheets, isEmpty, reason: 'LO, under the 원화 label');
      expect(lo.state, BooleanMix.off);
    });

    test('a free attach row that is its stack\'s only picture lends the row '
        'its name and its drawings — the row stays its base\'s', () {
      final rows = board(
        film(),
        delta: ExportCelsCutDelta().withLayerOverride(
          const LayerId('a'),
          false,
        ),
      ).rows;
      final a = of(rows, 'a');
      expect(a.name, 'A_r');
      expect(names(a.sheets), ['1', '2']);
      expect(ids(rows), ['c', 'b', 'a', 'l'], reason: 'one row a stack');
    });

    test('🚨a row\'s switch says its files: on, mixed while some are off — '
        'and a row whose one file is off IS a row switched off', () {
      final some = board(
        film(),
        delta: ExportCelsCutDelta().withCelSkipped(ref('a', '2'), true),
      ).rows;
      expect(of(some, 'a').state, BooleanMix.mixed);
      expect(of(some, 'b').state, BooleanMix.on);

      final one = board(
        film(),
        delta: ExportCelsCutDelta().withCelSkipped(ref('c', '1'), true),
      ).rows;
      expect(of(one, 'c').state, BooleanMix.off);
    });

    test('a row of a kind that is off is not a row of the list', () {
      final rows = board(film(), spec: const CelsExportSpec(kinds: {})).rows;
      expect(rows, isEmpty);
    });
  });

  group('the attach column of a row', () {
    test('🚨is its base and the attach rows riding it, as the timeline '
        'stacks them — a document holds none', () {
      final cut = film();
      final rows = board(cut).rows;
      expect(stack(cut, of(rows, 'a')), ['ar', 'a']);
      expect(stack(cut, of(rows, 'b')), ['b']);
    });

    test('🚨an attach row a filter leaves out is not offered; the base always '
        'is', () {
      final cut = film();
      final rows = board(cut).rows;
      const noAttach = CelsExportSpec(
        kinds: {ExportCelKind.cel},
        label: key,
        attach: false,
      );
      expect(stack(cut, of(rows, 'a'), spec: noAttach), ['a']);

      // The base answers no filter here: 「LO」 leaves A out, and it is
      // still the stack's line.
      const lo = CelsExportSpec(kinds: {ExportCelKind.cel}, label: layout);
      expect(stack(cut, of(board(cut, spec: lo).rows, 'a'), spec: lo), ['a']);
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

    test('on a row that is OFF — every file of it off — all its files: it is '
        'still stood on to be looked at', () {
      final rows = board(
        film(),
        delta: ExportCelsCutDelta()
            .withCelSkipped(ref('b', '1'), true)
            .withCelSkipped(ref('b', '2'), true)
            .withCelSkipped(ref('b', '3'), true),
      ).rows;
      final off = of(rows, 'b');
      expect(off.state, BooleanMix.off);
      expect(names(exportCelsPages(off)), ['1', '2', '3']);
    });
  });

  group('standing', () {
    test('with nothing chosen it is the first row that holds a drawing', () {
      final rows = board(film()).rows;
      const standing = ExportCelsStanding();
      expect(standing.rowIn(rows)?.idValue, 'c');
      expect(standing.sheetIn(rows), isNull, reason: 'nothing is shown yet');
      final settled = standing.settledOn(rows);
      expect(
        (settled.row, settled.shown, settled.place),
        ('c', 'c-1', 0),
      );
    });

    test('standing on a row shows its drawing at the place remembered, and '
        'its first where it has none there', () {
      final rows = board(film()).rows;
      final onA = const ExportCelsStanding().standingOn('a',
        rows,
      );
      expect((onA.row, onA.shown), ('a', 'a-1'));

      final third = onA.stepped(2, rows);
      expect((third.shown, third.place), ('a-3', 2));

      // B has a third drawing: the same place.
      final onB = third.standingOn('b', rows);
      expect((onB.row, onB.shown, onB.place), ('b', 'b-3', 2));
      // C has one: its first — and the place is kept for the next row.
      final onC = onB.standingOn('c', rows);
      expect((onC.shown, onC.place), ('c-1', 2));
      final backOnA = onC.standingOn('a', rows);
      expect(backOnA.shown, 'a-3');
    });

    test('with nothing chosen it is the first row that HOLDS a drawing — not '
        'a row above it with none — and the first row where none does', () {
      const lo = CelsExportSpec(kinds: {ExportCelKind.cel}, label: layout);
      final rows = board(film(), spec: lo).rows;
      expect(ids(rows).first, 'c', reason: '⛔전제: C is first');
      expect(of(rows, 'c').sheets, isEmpty, reason: '⛔전제: none under LO');
      expect(const ExportCelsStanding().rowIn(rows)?.idValue, 'l');

      const nothing = CelsExportSpec(
        kinds: {ExportCelKind.cel},
        base: false,
        attach: false,
      );
      final bare = board(film(), spec: nothing).rows;
      expect(bare.every((row) => row.sheets.isEmpty), isTrue, reason: '⛔전제');
      expect(const ExportCelsStanding().rowIn(bare)?.idValue, 'c');
    });

    // 유저 2026-10-08: 「그림 자체가 존재안하는 레이어는 서있는것도
    // 불가능한데, 서있을수는 있게하고」.
    test('a row with no file is stood on — nothing is shown, and the place '
        'is kept for the next row', () {
      final rows = board(film()).rows;
      final third = const ExportCelsStanding()
          .standingOn('a', rows)
          .stepped(2, rows);
      final onLo = third.standingOn('l', rows);
      expect((onLo.row, onLo.shown, onLo.place), ('l', null, 2));
      expect(onLo.rowIn(rows)?.idValue, 'l');
      expect(onLo.standingOn('a', rows).shown, 'a-3');
    });

    test('a row the list does not show is not stood on', () {
      final rows = board(film()).rows;
      final onA = const ExportCelsStanding().standingOn('a', rows);
      expect(onA.standingOn('f', rows), onA, reason: 'a folder is no row');
    });

    test('the steps stop at the row\'s ends', () {
      final rows = board(film()).rows;
      final onA = const ExportCelsStanding().standingOn('a',
        rows,
      );
      expect(onA.stepped(-1, rows).shown, 'a-1');
      expect(onA.stepped(9, rows).shown, 'a-4');
      expect(onA.stepped(9, rows).place, 3);
    });

    test('the drawing shown is turned off: the nearest one left takes its '
        'place — the next before the previous — and that place is '
        'remembered', () {
      final before = board(film()).rows;
      final onSecond = const ExportCelsStanding()
          .standingOn('a', before)
          .stepped(1, before);
      expect(onSecond.shown, 'a-2');

      final after = board(
        film(),
        delta: ExportCelsCutDelta().withCelSkipped(ref('a', '2'), true),
      ).rows;
      final settled = onSecond.settledOn(after);
      expect((settled.shown, settled.place), ('a-3', 2));

      // …and with the next one off too, the previous.
      final both = board(
        film(),
        delta: ExportCelsCutDelta()
            .withCelSkipped(ref('a', '2'), true)
            .withCelSkipped(ref('a', '3'), true)
            .withCelSkipped(ref('a', '4'), true),
      ).rows;
      expect(onSecond.settledOn(both).shown, 'a-1');
    });

    test('the row stood on leaves the list: the first row left with a '
        'drawing is stood on', () {
      final rows = board(film()).rows;
      final onC = const ExportCelsStanding().standingOn('c', rows);
      final withoutC = film();
      final gone = board(
        Cut(
          id: cutId,
          name: withoutC.name,
          duration: withoutC.duration,
          canvasSize: withoutC.canvasSize,
          layers: [
            for (final layer in withoutC.layers)
              if (layer.id != const LayerId('c')) layer,
          ],
        ),
      ).rows;
      final settled = onC.settledOn(gone);
      expect((settled.row, settled.shown), ('b', 'b-1'));
    });

    test('a standing that still holds is left as it is', () {
      final rows = board(film()).rows;
      final onA = const ExportCelsStanding()
          .standingOn('a', rows)
          .stepped(1, rows);
      expect(identical(onA.settledOn(rows), onA), isTrue);
    });
  });
}
