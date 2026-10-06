import '../../models/attached_layer_resolve.dart';
import '../../models/cut.dart';
import '../../models/export_spec.dart';
import '../../models/layer.dart';
import '../../models/layer_folder.dart';
import '../../models/layer_id.dart';
import '../timeline/layer_timeline_display_adapter.dart';
import '../widgets/boolean_dot.dart';
import 'export_cel_group_plan.dart';
import 'export_cels_board.dart';
import 'export_cels_selection.dart';
import 'export_settings_modules.dart' show exportCelKindLabel;

/// THE CUT THE CELS LIST SHOWS, read under the tab's rules: which of its
/// rows the list holds, what a folder row stands for, and the rows
/// themselves.
class ExportCelsListing {
  const ExportCelsListing(this.cut, this.spec);

  final Cut cut;
  final CelsExportSpec spec;

  /// Whether the list holds [layer]: a row of a kind the export writes, or
  /// a folder holding one ([exportCelsListsRow]).
  bool lists(Layer layer) => exportCelsListsRow(layer, cut.layers, spec);

  /// The rows a folder row stands for: the rows listed under it, at any
  /// depth.
  List<Layer> leavesOf(Layer folder) => [
    for (final layer in cut.layers.subtreeMembersOf(folder.id))
      if (!layer.kind.groupsLayers && lists(layer)) layer,
  ];

  /// The list's rows: the cut's ([layerRows]), and under them the
  /// documents the plan lists for it ([documentRows]).
  List<ExportCelsBoardRow> rows({
    required ExportCelsSelection selection,
    required ExportCelGroupPlan plan,
    Set<LayerId> shut = const {},
  }) => [
    ...layerRows(
      selection: selection,
      sheets: plan.sheets.where((sheet) => sheet.cut.id == cut.id),
      shut: shut,
    ),
    ...documentRows(
      plan.documents.where((sheet) => sheet.listedIn.id == cut.id),
    ),
  ];

  /// One row a kind of document in [sheets], in the order the kinds are
  /// declared — the timesheet, then the cut envelope: on while its files
  /// are answered for, off while its switch refuses them, and mixed where a
  /// 겸용 group's cuts disagree.
  List<ExportCelsDocumentRow> documentRows(
    Iterable<ExportDocumentSheet> sheets,
  ) => [
    for (final kind in ExportCelKind.values)
      if (sheets.where((sheet) => sheet.kind == kind).toList()
          case final files when files.isNotEmpty)
        ExportCelsDocumentRow(
          kind: kind,
          name: exportCelKindLabel(kind),
          state: BooleanMix.of(files.map((sheet) => sheet.planned)),
          sheets: files,
        ),
  ];

  /// The cut's rows, top to bottom as the TIMELINE draws the stack: the
  /// rows the list holds, less whatever a shut twirl folds away ([shut]).
  ///
  /// Each row's switch reads what [selection] says of it — a folder's, what
  /// the rows listed under it say together — and its drawings are [sheets],
  /// the plan's answers for the cut.
  List<ExportCelsLayerRow> layerRows({
    required ExportCelsSelection selection,
    required Iterable<ExportCelSheet> sheets,
    Set<LayerId> shut = const {},
  }) {
    final layers = cut.layers;
    final byRow = <LayerId, List<ExportCelSheet>>{};
    for (final sheet in sheets) {
      byRow.putIfAbsent(sheet.row.id, () => []).add(sheet);
    }
    bool folded(Layer layer) =>
        shut.contains(attachGroupBaseOf(layer, layers)) ||
        layers
            .ancestryOf(layer.folderId)
            .any((folder) => shut.contains(folder.id));
    return [
      for (final layer in horizontalLayerDisplayOrder(layers))
        if (lists(layer) && !folded(layer))
          if (layer.kind.groupsLayers)
            ExportCelsLayerRow(
              layer: layer,
              state: BooleanMix.of(leavesOf(layer).map(selection.includes)),
              sheets: const [],
              open: !shut.contains(layer.id),
            )
          else
            ExportCelsLayerRow(
              layer: layer,
              state: selection.includes(layer)
                  ? BooleanMix.on
                  : BooleanMix.off,
              sheets: byRow[layer.id] ?? const [],
              open: attachedLayersOf(layer.id, layers).any(lists)
                  ? !shut.contains(layer.id)
                  : null,
            ),
    ];
  }
}

/// WHERE THE CELS LIST STANDS: a row, the drawing of it the preview shows,
/// and the place in its row that was last chosen.
///
/// 🗣️유저 2026-10-06: 「서있는걸 일단 레이어별로 서있도록 하고싶어.
/// BG레이어에 서있으면 타임라인처럼 해당 행 강조색으로 좀 칠해지고,
/// 미리보기창엔 서있는 레이어를 보여주는거지 … 서있는 행의 그림들만
/// 보여주도록」 — and of the place: 「미리보기 창의 프레임 인덱스
/// 기억하기로하자」.
///
/// Window state, never saved: it says what is LOOKED at, not what is
/// written.
class ExportCelsStanding {
  const ExportCelsStanding({this.row, this.shown, this.place = 0});

  /// The row stood on ([ExportCelsBoardRow.idValue]); null stands on the
  /// first row that holds a file.
  final String? row;

  /// The file of [row] the preview shows ([ExportListSheet.idValue]).
  final String? shown;

  /// Where in its row the drawing last CHOSEN stands. Standing on another
  /// row shows that row's drawing at the same place when it has one to
  /// show, so A's 2 goes to its retake's 2.
  final int place;

  /// The row of [rows] stood on: [row] while the list shows it with a
  /// drawing on it, the first row that holds one otherwise — and null in a
  /// list with no drawing at all.
  ExportCelsBoardRow? rowIn(List<ExportCelsBoardRow> rows) {
    ExportCelsBoardRow? first;
    for (final each in rows) {
      if (each.sheets.isEmpty) {
        continue;
      }
      if (each.idValue == row) {
        return each;
      }
      first ??= each;
    }
    return first;
  }

  /// The drawing of [rows] the preview shows, or null when the row stood on
  /// has none to show.
  ExportListSheet? sheetIn(List<ExportCelsBoardRow> rows) {
    final stood = rowIn(rows);
    if (stood == null) {
      return null;
    }
    for (final sheet in exportCelsPages(stood)) {
      if (sheet.idValue == shown) {
        return sheet;
      }
    }
    return null;
  }

  /// Standing on [rowId]: its drawing at the remembered [place] when that
  /// one is among what it shows, its first otherwise. A row the list does
  /// not show with a drawing on it is not stood on.
  ExportCelsStanding standingOn(String rowId, List<ExportCelsBoardRow> rows) {
    final target = ExportCelsStanding(row: rowId, place: place).rowIn(rows);
    if (target == null || target.idValue != rowId) {
      return this;
    }
    final pages = exportCelsPages(target);
    final remembered = place < target.sheets.length
        ? target.sheets[place]
        : null;
    final show = pages.contains(remembered)
        ? remembered
        : pages.isEmpty
        ? null
        : pages.first;
    return ExportCelsStanding(row: rowId, shown: show?.idValue, place: place);
  }

  /// [steps] drawings on from the one shown, held to what the row shows —
  /// and that place is the one remembered.
  ExportCelsStanding stepped(int steps, List<ExportCelsBoardRow> rows) {
    final stood = rowIn(rows);
    if (stood == null) {
      return this;
    }
    final pages = exportCelsPages(stood);
    final at = pages.indexWhere((sheet) => sheet.idValue == shown);
    if (pages.isEmpty || at < 0) {
      return this;
    }
    final next = pages[(at + steps).clamp(0, pages.length - 1)];
    return ExportCelsStanding(
      row: stood.idValue,
      shown: next.idValue,
      place: stood.sheets.indexOf(next),
    );
  }

  /// This standing over [rows] as they are NOW: on a row the list shows,
  /// and showing a drawing that row still shows.
  ///
  /// The row went (its kind was turned off, a twirl shut over it) → the
  /// first row that holds a drawing. The drawing went (it was turned off) →
  /// the nearest one left in its row, the next before the previous — and
  /// that is the place remembered from then on.
  ExportCelsStanding settledOn(List<ExportCelsBoardRow> rows) {
    final stood = rowIn(rows);
    if (stood == null) {
      return ExportCelsStanding(place: place);
    }
    if (stood.idValue != row) {
      return ExportCelsStanding(place: place).standingOn(stood.idValue, rows);
    }
    final pages = exportCelsPages(stood);
    if (pages.any((sheet) => sheet.idValue == shown)) {
      return this;
    }
    if (pages.isEmpty) {
      return ExportCelsStanding(row: row, place: place);
    }
    final was = stood.sheets.indexWhere((sheet) => sheet.idValue == shown);
    final from = was < 0 ? place : was;
    var nearest = pages.first;
    var gap = (stood.sheets.indexOf(nearest) - from).abs();
    for (final sheet in pages.skip(1)) {
      final at = stood.sheets.indexOf(sheet);
      final away = (at - from).abs();
      if (away < gap || (away == gap && at > from)) {
        nearest = sheet;
        gap = away;
      }
    }
    return ExportCelsStanding(
      row: row,
      shown: nearest.idValue,
      place: stood.sheets.indexOf(nearest),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ExportCelsStanding &&
      other.row == row &&
      other.shown == shown &&
      other.place == place;

  @override
  int get hashCode => Object.hash(row, shown, place);
}

/// What the preview turns through on [row]: its drawings that are written —
/// or, while none of them is (the row is off), the ones that were left on.
/// A drawing turned off is in neither.
///
/// 🗣️유저 2026-10-06: 「미리보기는 활성화된 것만 보여줌 … 1,3비활성화하면
/// 미리보기창에서 1,3만 리스트에 보이는거지. 그 상태에서 콘티행 off해도 1,3
/// 활성화되있으니까 서서 보여줄수있게」.
List<ExportListSheet> exportCelsPages(ExportCelsBoardRow row) {
  final kept = [
    for (final sheet in row.sheets)
      if (!sheet.skipped) sheet,
  ];
  final written = [
    for (final sheet in kept)
      if (sheet.planned) sheet,
  ];
  return written.isEmpty ? kept : written;
}
