import 'dart:math' as math;

import 'xdts_sheet_form.dart';
import 'xdts_viewer_sheet.dart';

/// Which paper a cut's timesheet prints on (유저 2026-09-25, 사진 TOEI_3sec ·
/// TOEI_book): the 6-second sheet lays two 3-second strips side by side, 8
/// cel columns a strip; the 3-second sheet is one strip across the same
/// paper, its cells as wide as the 6-second sheet's and as many as the two
/// halves span — 19 (유저 2026-10-08, F-252: 「셀 칸 하나 가로길이
/// 유지한채로 그만큼 칸 더 많이 만들도록」; SE and CAM by our own rule).
/// ↩️It printed 12 cel columns half again as wide
/// (timesheet-3s-columns-Q1: 「사진대로 ACTION 12 · CELL 12」).
///
/// And the XDTS Viewer's four sheets (I-162, 유저 2026-11-05: 「타임시트
/// 서식에 우리식 3초/6초에 추가로 xdts의 서식같은거 다 타입으로 구현하자 …
/// 서식 바꾸면 xdts의 해당 서식에서 보는거랑 똑같은 화면」): each prints as
/// the viewer prints its [xdts] template.
///
/// Each CUT keeps its own (timesheet-sheet-kind-scope-Q1: 「컷마다 따로」);
/// the 6-second sheet unless the cut says otherwise.
enum TimesheetSheetKind {
  sixSeconds('6s', strips: 2, celColumns: 8),
  threeSeconds('3s', strips: 1, celColumns: 19),
  xdtsA3SixSeconds('xdts-a3-6s', xdts: XdtsViewerSheet.a3SixSeconds),
  xdtsB4ThreeSeconds('xdts-b4-3s', xdts: XdtsViewerSheet.b4ThreeSeconds),
  xdtsB4SixSeconds('xdts-b4-6s', xdts: XdtsViewerSheet.b4SixSeconds),
  xdtsPonocSixSeconds(
    'xdts-ponoc-6s',
    xdts: XdtsViewerSheet.ponocSixSeconds,
  );

  const TimesheetSheetKind(
    this.jsonValue, {
    int strips = 0,
    int celColumns = 0,
    this.xdts,
  }) : _strips = strips,
       blockColumns = celColumns;

  /// The stored key.
  final String jsonValue;

  /// The viewer's sheet this one prints as, or null for one of our own.
  final XdtsViewerSheet? xdts;

  /// The viewer's sheet a cut printed on this one lays its ink on unless
  /// the export picks another: its own, on one of the viewer's — the A3
  /// 6-second sheet on ours. 🗣️I-161-Q8 (유저 2026-11-05): 「기본값은 현재
  /// 타임시트용지패널에서 선택된 서식을 기본으로하고 그게 애니셀서식이면 A3
  /// 6초를 기본값으로」.
  XdtsViewerSheet get viewerSheet => xdts ?? XdtsViewerSheet.a3SixSeconds;

  final int _strips;

  /// The ACTION and the CELL blocks' columns a strip of one of our own
  /// sheets carries. A block with more cel rows grows past them (F-406: the
  /// CELL block by the ACTION block's law).
  final int blockColumns;

  /// The 3-second strips a page lays side by side — an XDTS sheet's
  /// bodies.
  int get strips => xdts?.bodyAmount ?? _strips;

  /// Seconds of rows a strip holds, on our own sheets.
  static const int stripSeconds = 3;

  /// The frames a page holds at [fps]: seconds of rows on our own sheets,
  /// and an XDTS sheet's own count — the viewer counts 24 a second.
  int pageFramesAt(int fps) =>
      xdts?.frameLength ?? strips * stripSeconds * fps;

  /// The SE columns a strip prints with no SE row behind them — an XDTS
  /// sheet's one dialogue column — and the camera block's.
  int get seColumns => xdts == null ? 2 : 1;
  int get cameraColumns => xdts?.cameraColAmount ?? 2;

  /// The viewer's sheet laid out for [columns] rows in the wider of its
  /// blocks, or null on one of our own.
  XdtsSheetForm? xdtsFormFor({required int columns}) => switch (xdts) {
    null => null,
    final template => XdtsSheetForm(template, columns: columns),
  };

  /// The ACTION block's columns and the CELL block's, for [actions] and
  /// [cells] rows on them: each block its own rows past [blockColumns] on
  /// our own sheets, and both the wider's on an XDTS sheet, as the viewer
  /// widens them ([xdtsFormFor]).
  ({int action, int cel}) celBlockColumns({
    required int actions,
    required int cells,
  }) => switch (xdtsFormFor(columns: math.max(actions, cells))) {
    final form? => (action: form.keyColumns, cel: form.cellsColumns),
    null => (
      action: math.max(blockColumns, actions),
      cel: math.max(blockColumns, cells),
    ),
  };

  static TimesheetSheetKind fromJson(Object? json) {
    for (final kind in values) {
      if (json == kind.jsonValue) {
        return kind;
      }
    }
    return sixSeconds;
  }
}

/// Why a cut cannot print on a sheet — and the sheet it prints on instead.
enum TimesheetSheetRefusal {
  /// An XDTS sheet off the viewer's 24 a second ([xdtsViewerReads]): the
  /// 6-second sheet. 🗣️I-162-Q3 (유저 2026-11-05): 「24 계열에서만
  /// 고른다(아니면 회색)」.
  viewerRate(TimesheetSheetKind.sixSeconds),

  /// More cel columns in a block than the 6-second strip holds: the
  /// 3-second sheet (유저 2026-09-25, timesheet-sheet-capacity-Q1 「3초
  /// 시트로 고정(6초 끔)」). An XDTS sheet widens for them as the viewer
  /// does, and the 3-second sheet as F-406 does.
  celColumns(TimesheetSheetKind.threeSeconds);

  const TimesheetSheetRefusal(this.instead);

  final TimesheetSheetKind instead;
}

/// Why a cut carrying [celColumns] cel columns at [fps] frames a second
/// cannot print on [kind], or null where it can — the one question the
/// sheet, its export and the format window's paper all ask: the format
/// window greys a refused paper and says this of it (I-162-Q3, 유저
/// 2026-11-05: 「회색일때 툴팁으로 이유 표시」).
TimesheetSheetRefusal? sheetKindRefusal(
  TimesheetSheetKind kind, {
  required int celColumns,
  required int fps,
}) {
  if (kind.xdts != null && !xdtsViewerReads(fps)) {
    return TimesheetSheetRefusal.viewerRate;
  }
  if (kind == TimesheetSheetKind.sixSeconds && celColumns > kind.blockColumns) {
    return TimesheetSheetRefusal.celColumns;
  }
  return null;
}

/// The sheet a cut that chose [chosen] prints on: [chosen] while it can,
/// and the sheet each refusal names instead until one can
/// ([sheetKindRefusal]).
TimesheetSheetKind sheetKindFor(
  TimesheetSheetKind chosen, {
  required int celColumns,
  required int fps,
}) => switch (sheetKindRefusal(chosen, celColumns: celColumns, fps: fps)) {
  null => chosen,
  final refusal => sheetKindFor(
    refusal.instead,
    celColumns: celColumns,
    fps: fps,
  ),
};
