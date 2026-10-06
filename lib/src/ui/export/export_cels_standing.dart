import '../../models/attached_layer_resolve.dart';
import '../../models/cut.dart';
import '../../models/export_spec.dart';
import '../../models/frame_id.dart';
import '../../models/layer.dart';
import '../../models/layer_folder.dart';
import '../../models/layer_id.dart';
import '../timeline/layer_timeline_display_adapter.dart';
import '../widgets/boolean_dot.dart';
import 'export_cel_group_plan.dart';
import 'export_cels_board.dart';
import 'export_cels_selection.dart';

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

  /// The list's rows, top to bottom as the TIMELINE draws the stack: the
  /// rows the list holds, less whatever a shut twirl folds away ([shut]).
  ///
  /// Each row's switch reads what [selection] says of it — a folder's, what
  /// the rows listed under it say together — and its drawings are [sheets],
  /// the plan's answers for the cut.
  List<ExportCelsBoardRow> rows({
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
            ExportCelsBoardRow(
              layer: layer,
              state: BooleanMix.of(leavesOf(layer).map(selection.includes)),
              sheets: const [],
              open: !shut.contains(layer.id),
            )
          else
            ExportCelsBoardRow(
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

// WHERE THE CELS LIST STANDS: a row, the drawing of it the preview shows,
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

  /// The row stood on; null stands on the first row that holds a drawing.
  final LayerId? row;

  /// The drawing of [row] the preview shows.
  final FrameId? shown;

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
      if (each.layer.id == row) {
        return each;
      }
      first ??= each;
    }
    return first;
  }

  /// The drawing of [rows] the preview shows, or null when the row stood on
  /// has none to show.
  ExportCelSheet? sheetIn(List<ExportCelsBoardRow> rows) {
    final stood = rowIn(rows);
    if (stood == null) {
      return null;
    }
    for (final sheet in exportCelsPages(stood)) {
      if (sheet.frame.id == shown) {
        return sheet;
      }
    }
    return null;
  }

  /// Standing on [rowId]: its drawing at the remembered [place] when that
  /// one is among what it shows, its first otherwise. A row the list does
  /// not show with a drawing on it is not stood on.
  ExportCelsStanding standingOn(LayerId rowId, List<ExportCelsBoardRow> rows) {
    final target = ExportCelsStanding(row: rowId, place: place).rowIn(rows);
    if (target == null || target.layer.id != rowId) {
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
    return ExportCelsStanding(row: rowId, shown: show?.frame.id, place: place);
  }

  /// [steps] drawings on from the one shown, held to what the row shows —
  /// and that place is the one remembered.
  ExportCelsStanding stepped(int steps, List<ExportCelsBoardRow> rows) {
    final stood = rowIn(rows);
    if (stood == null) {
      return this;
    }
    final pages = exportCelsPages(stood);
    final at = pages.indexWhere((sheet) => sheet.frame.id == shown);
    if (pages.isEmpty || at < 0) {
      return this;
    }
    final next = pages[(at + steps).clamp(0, pages.length - 1)];
    return ExportCelsStanding(
      row: stood.layer.id,
      shown: next.frame.id,
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
    if (stood.layer.id != row) {
      return ExportCelsStanding(place: place).standingOn(stood.layer.id, rows);
    }
    final pages = exportCelsPages(stood);
    if (pages.any((sheet) => sheet.frame.id == shown)) {
      return this;
    }
    if (pages.isEmpty) {
      return ExportCelsStanding(row: row, place: place);
    }
    final was = stood.sheets.indexWhere((sheet) => sheet.frame.id == shown);
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
      shown: nearest.frame.id,
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
List<ExportCelSheet> exportCelsPages(ExportCelsBoardRow row) {
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
