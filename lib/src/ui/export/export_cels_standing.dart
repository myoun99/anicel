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

/// THE CUT THE CELS LIST SHOWS, read under the tab's rules: its FILE rows
/// — a row a series of files ([rows]) — and, for the row stood on, the
/// STACK its files hold ([stackOf]).
///
/// 🗣️export-four-tabs (유저 2026-10-09, the consult): the list says 「무슨
/// 파일이 나가나」 and the attach column 「그 파일에 무엇이 담기나」 — 「결국
/// 나가는건 파일 하나니까 파일기준 행이니까 접기 펼치기 없이 한 행만
/// 보이면되」. ↩️It listed the cut's layers: folders with a switch over
/// their rows, attach rows under their base behind a twirl.
class ExportCelsListing {
  const ExportCelsListing(this.cut, this.spec);

  final Cut cut;
  final CelsExportSpec spec;

  /// The list's rows: the cut's file rows ([layerRows]), and under them the
  /// documents the plan lists for it ([documentRows]).
  List<ExportCelsBoardRow> rows(ExportCelGroupPlan plan) => [
    ...layerRows(plan.sheets.where((sheet) => sheet.cut.id == cut.id)),
    ...documentRows(
      plan.documents.where((sheet) => sheet.listedIn.id == cut.id),
    ),
  ];

  /// One row a kind of document in [sheets], in the order the kinds are
  /// declared — the timesheet, then the cut envelope ([exportRowState]: a
  /// 겸용 group's cuts each keep a timesheet, and may disagree).
  List<ExportCelsDocumentRow> documentRows(
    Iterable<ExportDocumentSheet> sheets,
  ) => [
    for (final kind in ExportCelKind.values)
      if (sheets.where((sheet) => sheet.kind == kind).toList()
          case final files when files.isNotEmpty)
        ExportCelsDocumentRow(
          kind: kind,
          name: exportCelKindLabel(kind),
          state: exportRowState(files),
          sheets: files,
        ),
  ];

  /// The cut's FILE rows, top to bottom as the timeline draws the stack: a
  /// row a stack ([exportCelsHeadsAStack]), its files the drawings the plan
  /// files on its bundle's axis ([sheets]) — none while the stack holds no
  /// picture, and the row is there all the same, switched off.
  ///
  /// 🗣️(유저 2026-10-09): 「블록 없어도 그냥 행 보이게하는게 좋을거같단
  /// 생각들었어 … 그냥 말없이 출력행에서 안보이면 별로라. 보이더라도
  /// 다른거처럼 이름 흐리게 이런거 동일하게」. ↩️The consult first left a row
  /// with no file to write out of the list (「안보이게 해도 된다고생각」), and
  /// took it back within the hour.
  List<ExportCelsLayerRow> layerRows(Iterable<ExportCelSheet> sheets) {
    final layers = cut.layers;
    // A stack's files stand on its bundle's axis: its base, or the free
    // attach row that is its only picture.
    final byBase = <LayerId, ({Layer axis, List<ExportCelSheet> files})>{};
    for (final sheet in sheets) {
      final base = attachGroupBaseOf(sheet.row, layers) ?? sheet.row.id;
      (byBase[base] ??= (axis: sheet.row, files: [])).files.add(sheet);
    }
    return [
      for (final layer in horizontalLayerDisplayOrder(layers))
        if (exportCelsHeadsAStack(layer, layers, spec))
          if (byBase[layer.id] case final stack?)
            ExportCelsLayerRow(
              layer: stack.axis,
              base: layer.id,
              state: exportRowState(stack.files),
              sheets: stack.files,
            )
          else
            ExportCelsLayerRow(
              layer: layer,
              base: layer.id,
              state: BooleanMix.off,
              sheets: const [],
            ),
    ];
  }

  /// What [row]'s files can hold, top to bottom as the timeline draws the
  /// stack: its base — always, as what the stack is — and the attach rows
  /// riding it that the tab's filters admit ([rules]: the rules without
  /// the hand). A document holds no rows.
  ///
  /// 🗣️(유저 2026-10-09): 「색라벨이나 테이크, 어태치행에도 그거만
  /// 보이게하도록 하는게 맞을거같은데」 — 「너말대로 필터전부」: an attach
  /// row a filter leaves out is not offered, and comes back with the filter.
  List<Layer> stackOf(ExportCelsBoardRow row, ExportCelsSelection rules) =>
      switch (row) {
        ExportCelsLayerRow(:final base) => [
          for (final layer in horizontalLayerDisplayOrder(cut.layers))
            if (layer.id == base ||
                (layer.attachedToLayerId == base && rules.includes(layer)))
              layer,
        ],
        ExportCelsDocumentRow() => const [],
      };
}

/// A row's switch over [files]: on while every one of them that can be a
/// file is written, off while none is, mixed between.
///
/// 🗣️export-four-tabs ③ (유저 2026-10-09): a row whose files are all off
/// IS a row switched off — 「한 장만 있을때 그 블록 빈블록만들면 해당 행
/// 체크해제랑 동일한 로직으로 … 법 통일」.
BooleanMix exportRowState(Iterable<ExportListSheet> files) => BooleanMix.of([
  for (final file in files)
    if (file.planned) file.written,
]);

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
  /// first row that holds a drawing.
  final String? row;

  /// The file of [row] the preview shows ([ExportListSheet.idValue]).
  final String? shown;

  /// Where in its row the drawing last CHOSEN stands. Standing on another
  /// row shows that row's drawing at the same place when it has one to
  /// show, so A's 2 goes to its retake's 2.
  final int place;

  /// The row of [rows] stood on: [row] while the list shows it, the first
  /// row that holds a drawing otherwise — the first row in a list with no
  /// drawing at all, and null in an empty one.
  ///
  /// 🗣️유저 2026-10-08: 「그림 자체가 존재안하는 레이어는 서있는것도
  /// 불가능한데, 서있을수는 있게하고」 — a row with no file is stood on like
  /// any: its attach column is where its pictures are put back
  /// (export-four-tabs). ↩️Only a row that held a drawing could be.
  ExportCelsBoardRow? rowIn(List<ExportCelsBoardRow> rows) {
    ExportCelsBoardRow? drawn;
    for (final each in rows) {
      if (each.idValue == row) {
        return each;
      }
      if (drawn == null && each.sheets.isNotEmpty) {
        drawn = each;
      }
    }
    return drawn ?? (rows.isEmpty ? null : rows.first);
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
  /// one is among what it shows, its first otherwise — none, on a row with
  /// no file. A row the list does not show is not stood on.
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
  /// The row went (its kind was turned off) → the first row that holds a
  /// drawing. The drawing went (it was turned off) →
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

/// What the preview turns through on [row]: its files that are written —
/// or, while none of them is (the row is off), every one that can be a
/// file. A drawing that can be none is in neither.
///
/// 🗣️유저 2026-10-06: 「미리보기는 활성화된 것만 보여줌 … 1,3비활성화하면
/// 미리보기창에서 1,3만 리스트에 보이는거지. 그 상태에서 콘티행 off해도 1,3
/// 활성화되있으니까 서서 보여줄수있게」. ↩️The row's switch was an answer of
/// its own then, so a row switched off still had the drawings left on to
/// show; it turns every file of the row now (export-four-tabs ③), and a
/// row switched off shows them all — it is still stood on to be looked at.
List<ExportListSheet> exportCelsPages(ExportCelsBoardRow row) {
  final files = [
    for (final sheet in row.sheets)
      if (sheet.planned) sheet,
  ];
  final written = [
    for (final sheet in files)
      if (!sheet.skipped) sheet,
  ];
  return written.isEmpty ? files : written;
}
