/// The XDTS Viewer's ink folder (opentoonz/xdts_viewer, BSD-3 — its FORMAT
/// only, read from its sources and its v1.3.0 release): what a timesheet's
/// handwriting is written as beside its `.xdts` so the viewer shows it.
///
/// 🗣️I-161 (유저 2026-11-05): 「형식 xdts로하면 잉크 출력 on off버튼 둠 …
/// 같은이름 폴더안에 잉크층을 png로 저장하면 볼수있었던거같은데」. The viewer
/// keeps a page's scribble as `<folder>/<page>.png` — transparent, its
/// sheet's paper at 250 dpi, laid from the top left — and the sheet it lays
/// them on in that folder's `config.ini`.
library;

import '../../models/timesheet_sheet_kind.dart';
import '../../models/transition_geometry.dart';

/// The folder the viewer reads [xdtsFileName]'s ink from: the name less
/// its `.xdts`, and less the `_genga_ts` / `_douga_ts` a genga or douga
/// sheet's name carries (in any case), with `_xdts` after it — the
/// viewer's `MyParams::getImageFolderPath`.
String xdtsInkFolderName(String xdtsFileName) {
  final pairSuffix = RegExp('_(genga|douga)_ts', caseSensitive: false);
  final name = xdtsFileName.replaceAll(pairSuffix, '');
  return '${name.substring(0, name.length - '.xdts'.length)}_xdts';
}

/// The file the viewer reads page [pageIndex]'s ink from — its pages count
/// from 1 (0 is a sheet's back, which the app has none of), one picture a
/// page while every column fits it.
String xdtsInkPageFileName(int pageIndex) => '${pageIndex + 1}.png';

/// A sheet the viewer lays ink on: its template's label — the name its
/// `config.ini` picks it by — and its paper in millimetres.
enum XdtsViewerSheet {
  b4ThreeSeconds(
    label: 'B4 size, 3 seconds sheet',
    widthMm: 257,
    heightMm: 364,
  ),
  a3SixSeconds(label: 'A3 size, 6 seconds sheet', widthMm: 297, heightMm: 420);

  const XdtsViewerSheet({
    required this.label,
    required this.widthMm,
    required this.heightMm,
  });

  final String label;
  final double widthMm;
  final double heightMm;

  /// The pixels a page's ink picture is: the paper at the viewer's 250 dpi
  /// (`MyParams::PDF_Resolution`).
  ({int width, int height}) get pixelSize => (
    width: (widthMm / 25.4 * 250).round(),
    height: (heightMm / 25.4 * 250).round(),
  );

  /// The viewer sheet a page of the app's [kind] is laid on: the one sheet
  /// of its seconds the viewer has — of the three 6-second ones, the A3 the
  /// app's paper is (I-161-Q8).
  static XdtsViewerSheet of(TimesheetSheetKind kind) => switch (kind) {
    TimesheetSheetKind.threeSeconds => b4ThreeSeconds,
    TimesheetSheetKind.sixSeconds => a3SixSeconds,
  };
}

/// The viewer's `config.ini` for a sheet laid on [sheet] that draws
/// [handles] of のりしろ: the template, the cells area and the O.L each
/// end — every other setting the viewer's own default. `Version` says
/// which page names it reads (1A, 1B from 1.2.0).
///
/// An O.L is written as twice the のりしろ its side draws: the viewer takes
/// half an O.L off each end of a sheet's frames for its 尺, so twice the
/// のりしろ gives back the conte 尺 the app prints — my call, not the
/// user's (I-161); an O.L laid evenly across the cut is exactly that.
String xdtsViewerConfig({
  required XdtsViewerSheet sheet,
  required CutTransitionHandles handles,
}) =>
    '[General]\n'
    'Version=1.3.0\n'
    '\n'
    '[FormatSettings]\n'
    'TemplateName="${sheet.label}"\n'
    'ExportArea=Cells\n'
    'StartOverlapFrameLength=${handles.head * 2}\n'
    'EndOverlapFrameLength=${handles.tail * 2}\n';
