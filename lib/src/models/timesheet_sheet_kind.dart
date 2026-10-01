/// Which paper a cut's timesheet prints on (유저 2026-09-25, 사진 TOEI_3sec ·
/// TOEI_book): the 6-second sheet lays two 3-second strips side by side, 8
/// cel columns a strip; the 3-second sheet is one strip across the same
/// paper, 12 cel columns (timesheet-3s-columns-Q1: 「사진대로 ACTION 12 ·
/// CELL 12」 — SE and CAM by our own rule), its columns wider.
///
/// Each CUT keeps its own (timesheet-sheet-kind-scope-Q1: 「컷마다 따로」);
/// the 6-second sheet unless the cut says otherwise.
enum TimesheetSheetKind {
  sixSeconds('6s', strips: 2, celColumns: 8),
  threeSeconds('3s', strips: 1, celColumns: 12);

  const TimesheetSheetKind(
    this.jsonValue, {
    required this.strips,
    required this.celColumns,
  });

  /// The stored key.
  final String jsonValue;

  /// The 3-second strips a page lays side by side.
  final int strips;

  /// The ACTION and the CELL blocks' columns a strip carries. A cut with
  /// more cel layers grows its ACTION block past them; the CELL block
  /// stays.
  final int celColumns;

  /// Seconds of rows a strip holds, on either sheet.
  static const int stripSeconds = 3;

  /// Seconds of rows a page holds.
  int get pageSeconds => strips * stripSeconds;

  static TimesheetSheetKind fromJson(Object? json) {
    for (final kind in values) {
      if (json == kind.jsonValue) {
        return kind;
      }
    }
    return sixSeconds;
  }
}

/// The sheet a cut that chose [chosen] prints on, carrying [celColumns] cel
/// columns: [chosen] while a 6-second strip holds them, the 3-second sheet
/// once it cannot (유저 2026-09-25, timesheet-sheet-capacity-Q1 「3초
/// 시트로 고정(6초 끔)」) — the one question the sheet, its export and the
/// format window's switch all ask.
TimesheetSheetKind sheetKindFor(
  TimesheetSheetKind chosen, {
  required int celColumns,
}) => celColumns > TimesheetSheetKind.sixSeconds.celColumns
    ? TimesheetSheetKind.threeSeconds
    : chosen;

/// Whether a cut carrying [celColumns] cel columns can print on [kind]
/// ([sheetKindFor]) — the format window offers only these.
bool sheetKindFits(TimesheetSheetKind kind, {required int celColumns}) =>
    sheetKindFor(kind, celColumns: celColumns) == kind;
