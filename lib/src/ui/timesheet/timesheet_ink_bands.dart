import 'dart:math' as math;

import '../../models/timesheet_document.dart';
import '../../models/timesheet_sheet_kind.dart';
import 'timesheet_document_painter.dart';

// WHERE A TIMESHEET'S WRITING LIVES — one band surface per 6-second page
// of rows, on either sheet, so a switch between the 3-second and the
// 6-second sheet moves no stroke off its frame or its cell (유저
// 2026-09-27, timesheet-sheet-kind-ink-Q1: 「프레임을 따라 옮겨 붙인다」 ·
// 「g셀만큼 그린게 3초시트로 늘리면 g셀까지만 보이게 똑같이 하면 늘리던
// 다시 줄이던 동일하잖아」). The stored pixels never change; the sheet
// changes the windows it shows them through.
//
// The surface keeps the 6-second strip's own layout — its ACTION and CELL
// blocks' eight columns and the SE and CAM allotments — so what was
// written there never moves; to its right lie the columns only the
// 3-second sheet prints: the CELL block's last four, then the ACTION
// block's columns past eight, as many as the cut has.

/// The rows a band surface holds: a 6-second page's — the page's own on
/// the 6-second sheet, two of the 3-second sheet's.
int timesheetInkBandFrames(TimesheetDocument document) =>
    document.pageFrameCount *
    TimesheetSheetKind.sixSeconds.strips ~/
    document.sheetKind.strips;

const double _action = TimesheetDocumentLayout.actionColumnWidth;
const double _cel = TimesheetDocumentLayout.celColumnWidth;
final int _sixColumns = TimesheetSheetKind.sixSeconds.celColumns;

/// Where the 6-second strip's blocks start on the surface.
final double _seLeft = _sixColumns * _action;
final double _celLeft = _seLeft + TimesheetDocumentLayout.seGroupWidth;
final double _cameraLeft = _celLeft + _sixColumns * _cel;

/// Where the columns only the 3-second sheet prints start: past the
/// 6-second strip.
final double _extraCelLeft =
    _cameraLeft + TimesheetDocumentLayout.cameraGroupWidth;
final double _extraActionLeft =
    _extraCelLeft +
    (TimesheetSheetKind.threeSeconds.celColumns - _sixColumns) * _cel;

/// How wide a band surface is, in sheet units: the 6-second strip, the
/// 3-second sheet's four more CELL columns, and every ACTION column past
/// eight the cut prints on the 3-second sheet — however [document] is
/// printed now, so nothing written on the other sheet falls off it.
double timesheetInkStripWidth(TimesheetDocument document) {
  final printed = document.columns
      .where((column) => column.kind == TimesheetColumnKind.action)
      .length;
  final action = math.max(
    printed,
    TimesheetSheetKind.threeSeconds.celColumns,
  );
  return _extraActionLeft + (action - _sixColumns) * _action;
}

/// A run of a strip's columns whose writing lies side by side on the band
/// surface: the columns [first] up to [end], where the run lies across the
/// strip ([left] and [width], sheet units), where its writing starts on the
/// surface ([surfaceLeft], sheet units at the 6-second sheet's scale), and
/// how much wider than that the strip prints it ([stretch]).
typedef TimesheetInkRun = ({
  int first,
  int end,
  double left,
  double width,
  double surfaceLeft,
  double stretch,
});

/// [layout]'s strip, cut into the runs its columns' writing lies in on the
/// band surface: one on the 6-second sheet, whose strip IS the surface's
/// layout; on the 3-second sheet a run wherever the columns leave the
/// 6-second strip's order (past its eight ACTION or CELL columns).
List<TimesheetInkRun> timesheetInkRuns(TimesheetDocumentLayout layout) {
  final document = layout.document;
  final stretch = TimesheetDocumentLayout.columnScaleOf(document.sheetKind);
  final runs = <TimesheetInkRun>[];
  final seen = <TimesheetColumnKind, int>{};
  for (final (index, column) in document.columns.indexed) {
    final kind = column.kind;
    final slot = seen[kind] ?? 0;
    seen[kind] = slot + 1;
    final width = layout.columnWidthFor(kind) / stretch;
    final surfaceLeft = switch (kind) {
      TimesheetColumnKind.action =>
        slot < _sixColumns
            ? slot * _action
            : _extraActionLeft + (slot - _sixColumns) * _action,
      TimesheetColumnKind.se => _seLeft + slot * width,
      TimesheetColumnKind.cel =>
        slot < _sixColumns
            ? _celLeft + slot * _cel
            : _extraCelLeft + (slot - _sixColumns) * _cel,
      TimesheetColumnKind.camera => _cameraLeft + slot * width,
    };
    final last = runs.isEmpty ? null : runs.last;
    if (last != null &&
        (last.surfaceLeft + last.width / stretch - surfaceLeft).abs() <
            1e-9) {
      runs[runs.length - 1] = (
        first: last.first,
        end: index + 1,
        left: last.left,
        width: last.width + width * stretch,
        surfaceLeft: last.surfaceLeft,
        stretch: stretch,
      );
    } else {
      runs.add((
        first: index,
        end: index + 1,
        left: layout.columnLeftInHalf(index),
        width: width * stretch,
        surfaceLeft: surfaceLeft,
        stretch: stretch,
      ));
    }
  }
  return runs;
}
