/// The sheets the XDTS Viewer lays a timesheet's ink on (opentoonz/xdts_viewer
/// v1.3.0, BSD-3 — its `xsheettemplates/*.ini`, read from its release), and
/// the one rate it counts them in.
library;

import 'timesheet_sheet_kind.dart';

/// The frames a second the XDTS Viewer counts its sheet in: fixed — it
/// reads no rate from the file and makes its seconds of 24 frames.
const int xdtsViewerFps = 24;

/// Whether a project counting [fps] frames a second (`Project.fps`, where
/// 23.976 counts 24) is one the viewer's sheet reads true. 🗣️I-161-Q7 (유저
/// 2026-11-05): 「24fps 가 아니면 잉크 버튼을 회색으로」 — ink laid on a
/// sheet whose rows are not the cut's frames lands on the wrong ones.
bool xdtsViewerReads(int fps) => fps == xdtsViewerFps;

/// A sheet of the viewer's: its template's label — the name its
/// `config.ini` picks it by — the paper it is printed on, and the seconds a
/// page holds.
enum XdtsViewerSheet {
  a3SixSeconds(
    'a3-6s',
    label: 'A3 size, 6 seconds sheet',
    paper: 'A3',
    widthMm: 297,
    heightMm: 420,
    pageSeconds: 6,
  ),
  b4SixSeconds(
    'b4-6s',
    label: 'B4 size, 6 seconds sheet',
    paper: 'B4',
    widthMm: 257,
    heightMm: 364,
    pageSeconds: 6,
  ),
  b4ThreeSeconds(
    'b4-3s',
    label: 'B4 size, 3 seconds sheet',
    paper: 'B4',
    widthMm: 257,
    heightMm: 364,
    pageSeconds: 3,
  ),
  ponocSixSeconds(
    'ponoc-6s',
    label: 'Ponoc 6 seconds sheet',
    paper: 'Ponoc',
    widthMm: 257,
    heightMm: 364,
    pageSeconds: 6,
  );

  const XdtsViewerSheet(
    this.jsonValue, {
    required this.label,
    required this.paper,
    required this.widthMm,
    required this.heightMm,
    required this.pageSeconds,
  });

  /// The stored key.
  final String jsonValue;
  final String label;

  /// The template's own name for its paper — the Ponoc sheet is printed on
  /// JIS B4 like the B4 ones.
  final String paper;
  final double widthMm;
  final double heightMm;
  final int pageSeconds;

  /// The pixels a page's ink picture is: the paper at the viewer's 250 dpi
  /// (`MyParams::PDF_Resolution`).
  ({int width, int height}) get pixelSize => (
    width: (widthMm / 25.4 * 250).round(),
    height: (heightMm / 25.4 * 250).round(),
  );

  /// The viewer sheet a cut printed on the app's [kind] lays its ink on
  /// unless the export picks another. 🗣️I-161-Q8 (유저 2026-11-05): 「기본값은
  /// 현재 타임시트용지패널에서 선택된 서식을 기본으로하고 그게 애니셀서식이면
  /// A3 6초를 기본값으로」 — both the app's own sheets.
  static XdtsViewerSheet of(TimesheetSheetKind kind) => switch (kind) {
    TimesheetSheetKind.sixSeconds || TimesheetSheetKind.threeSeconds =>
      a3SixSeconds,
  };

  /// The sheet [json] names — null for none, or one this build has not.
  static XdtsViewerSheet? fromJson(Object? json) {
    for (final sheet in values) {
      if (json == sheet.jsonValue) {
        return sheet;
      }
    }
    return null;
  }
}
