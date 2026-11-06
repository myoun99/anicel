/// The sheets the XDTS Viewer lays a timesheet's ink on and prints an XDTS
/// file on (opentoonz/xdts_viewer v1.3.0, BSD-3 — its
/// `xsheettemplates/*.ini`, read from its release), and the one rate it
/// counts them in.
library;

import 'sheet_paper.dart' show SheetPaperFormat;
import 'timesheet_info.dart' show TimesheetHeaderField;
import 'transition_geometry.dart' show CutTransitionHandles;

/// The frames a second the XDTS Viewer counts its sheet in: fixed — it
/// reads no rate from the file and makes its seconds of 24 frames.
const int xdtsViewerFps = 24;

/// Whether a project counting [fps] frames a second (`Project.fps`, where
/// 23.976 counts 24) is one the viewer's sheet reads true. 🗣️I-161-Q7 (유저
/// 2026-11-05): 「24fps 가 아니면 잉크 버튼을 회색으로」 — ink laid on a
/// sheet whose rows are not the cut's frames lands on the wrong ones. The
/// same answer greys the viewer's sheets in the timesheet's own picker
/// (I-162-Q3) — 「이런 기준 법 사본화되있으면 통일하면서」.
bool xdtsViewerReads(int fps) => fps == xdtsViewerFps;

/// The O.L the viewer is told a cut carries at each end, in frames: twice
/// the のりしろ its side draws ([CutTransitionHandles]).
///
/// The viewer takes half an O.L off each end of a sheet's frames for its
/// 尺, so twice the のりしろ gives back the conte 尺 the app prints — 저장's
/// call, not the user's (I-161); an O.L laid evenly across the cut is
/// exactly that. ONE answer for the ink folder's `config.ini` and the O.L
/// an XDTS sheet draws of itself (I-162-Q7, 유저 2026-11-05: 「뷰어의 OL
/// 표시를 우리 O.L 로 채운다」).
({int start, int end}) xdtsViewerOverlaps(CutTransitionHandles handles) =>
    (start: handles.head * 2, end: handles.tail * 2);

/// A box of an XDTS sheet's info header: the label the viewer prints over
/// it — its template's (`EPISODE`, `SEQ.` …) as the viewer's Japanese says
/// it (`第　　話`, `シーン` …) — its width, and which of our header's values
/// it holds (I-162-Q2: 「채운다」).
///
/// The viewer writes only the length and the sheet count in its boxes
/// (`InfoFormats\i\infoType`) and leaves the rest to the pen; its `SCENE`
/// box is the cut's, as a Japanese sheet's カット is.
typedef XdtsInfoBox = ({
  String label,
  double widthMm,
  TimesheetHeaderField field,
});

/// A place an XDTS sheet's template sets out from the margin's corner
/// (`DataFields\<name>`) — the viewer draws no edge round it.
typedef XdtsDataField = ({
  double leftMm,
  double topMm,
  double widthMm,
  double heightMm,
});

/// A sheet of the viewer's — one of the `xsheettemplates/*.ini` its release
/// carries: its template's label, the name its `config.ini` picks it by,
/// the paper it is printed on, and the numbers the file lays it out by.
///
/// The export lays a cut's ink on one (I-161), and a cut's timesheet prints
/// on one as the viewer prints it (I-162: 「xdts의 서식같은거 다 타입으로
/// 구현하자 … 서식 바꾸면 xdts의 해당 서식에서 보는거랑 똑같은 화면」) —
/// [XdtsSheetForm] lays the numbers out by the measures the viewer draws
/// with.
///
/// ⛔The viewer's code is not ours to copy (BSD-3, Shun Iwasawa — the
/// independent-reimplementation policy): what is kept here is the files'
/// numbers. The four were read off the viewer's v1.3.0 release by the
/// save lane (I-161 · I-162, 2026-11-05); the A3 and the B4 3-second
/// sheets' info boxes are OpenToonz's presets of the same files, which the
/// release's B4 6-second one matches line for line.
///
/// Only what the sheet draws is held: of the places the viewer sets out
/// (`DataFields`), the memo's and the logo's, which our values fill
/// (I-162-Q2) — not the date's or the overlap's length, which the viewer
/// writes only into its own export. The memo's line count and the extra
/// cel columns of a sheet that does not widen are the viewer's own
/// business.
enum XdtsViewerSheet {
  a3SixSeconds(
    'a3-6s',
    label: 'A3 size, 6 seconds sheet',
    paper: 'A3',
    paperFormat: SheetPaperFormat.a3,
    marginLeftMm: 9.0,
    marginTopMm: 5.0,
    bodyAmount: 2,
    keyColAmount: 7,
    cellsColAmount: 8,
    cameraColAmount: 3,
    frameLength: 144,
    bodyWidthMm: 137.5,
    bodyHeightMm: 315.5,
    bodyHMarginMm: 7.0,
    bodyTopMm: 91.0,
    headerHeightMm: 6.5,
    keyColWidthMm: 4.5,
    lastKeyColWidthMm: 7,
    dialogColWidthMm: 11,
    cellsColWidthMm: 8,
    cameraColWidthMm: 8,
    rowHeightMm: 4.25,
    secondHeightMm: 103,
    infoOriginLeftMm: 56,
    infoOriginTopMm: 0,
    infoTitleHeightMm: 4.5,
    infoBodyHeightMm: 12.5,
    info: [
      (label: _episode, widthMm: 36, field: TimesheetHeaderField.episode),
      (label: _seq, widthMm: 30, field: TimesheetHeaderField.scene),
      (label: _scene, widthMm: 38, field: TimesheetHeaderField.cut),
      (label: _time, widthMm: 55, field: TimesheetHeaderField.time),
      (label: _name, widthMm: 32, field: TimesheetHeaderField.name),
      (label: _sheet, widthMm: 35, field: TimesheetHeaderField.sheet),
    ],
    memo: (leftMm: 0, topMm: 23, widthMm: 282, heightMm: 65),
    logo: (leftMm: 0, topMm: 0, widthMm: 51, heightMm: 17),
  ),
  b4SixSeconds(
    'b4-6s',
    label: 'B4 size, 6 seconds sheet',
    paper: 'B4',
    paperFormat: SheetPaperFormat.jisB4,
    marginLeftMm: 9.5,
    marginTopMm: 6.0,
    bodyAmount: 2,
    keyColAmount: 4,
    cellsColAmount: 5,
    cameraColAmount: 3,
    frameLength: 144,
    bodyWidthMm: 117,
    bodyHeightMm: 315.5,
    bodyHMarginMm: 5,
    bodyTopMm: 36.5,
    headerHeightMm: 6.5,
    keyColWidthMm: 5,
    lastKeyColWidthMm: 7,
    dialogColWidthMm: 10,
    cellsColWidthMm: 10,
    cameraColWidthMm: 10,
    rowHeightMm: 4.25,
    secondHeightMm: 103,
    infoOriginLeftMm: 84,
    infoOriginTopMm: 0,
    infoTitleHeightMm: 4.5,
    infoBodyHeightMm: 8.5,
    info: [
      (label: _episode, widthMm: 26, field: TimesheetHeaderField.episode),
      (label: _seq, widthMm: 18.5, field: TimesheetHeaderField.scene),
      (label: _scene, widthMm: 18.5, field: TimesheetHeaderField.cut),
      (label: _time, widthMm: 40, field: TimesheetHeaderField.time),
      (label: _name, widthMm: 26, field: TimesheetHeaderField.name),
      (label: _sheet, widthMm: 26, field: TimesheetHeaderField.sheet),
    ],
    totalOverCurrent: false,
    memo: (leftMm: 0, topMm: 14, widthMm: 239, heightMm: 20.5),
    logo: (leftMm: 0, topMm: 0, widthMm: 84, heightMm: 13),
  ),
  b4ThreeSeconds(
    'b4-3s',
    label: 'B4 size, 3 seconds sheet',
    paper: 'B4',
    paperFormat: SheetPaperFormat.jisB4,
    marginLeftMm: 7.5,
    marginTopMm: 6.0,
    bodyAmount: 1,
    keyColAmount: 14,
    cellsColAmount: 14,
    cameraColAmount: 1,
    frameLength: 72,
    bodyWidthMm: 242,
    bodyHeightMm: 317.5,
    bodyHMarginMm: 0,
    bodyTopMm: 34.5,
    headerHeightMm: 8.5,
    keyColWidthMm: 5,
    lastKeyColWidthMm: 6.5,
    dialogColWidthMm: 11.5,
    cellsColWidthMm: 8.25,
    cameraColWidthMm: 38.5,
    rowHeightMm: 4.2625,
    secondHeightMm: 103,
    infoOriginLeftMm: 87,
    infoOriginTopMm: 0,
    infoTitleHeightMm: 4.5,
    infoBodyHeightMm: 8.5,
    info: [
      (label: _episode, widthMm: 26.5, field: TimesheetHeaderField.episode),
      (label: _seq, widthMm: 18, field: TimesheetHeaderField.scene),
      (label: _scene, widthMm: 18.5, field: TimesheetHeaderField.cut),
      (label: _time, widthMm: 40, field: TimesheetHeaderField.time),
      (label: _name, widthMm: 26, field: TimesheetHeaderField.name),
      (label: _sheet, widthMm: 26, field: TimesheetHeaderField.sheet),
    ],
    memo: (leftMm: 0, topMm: 14, widthMm: 242, heightMm: 18.5),
    logo: (leftMm: 0, topMm: 0, widthMm: 87, heightMm: 13),
  ),

  /// `ponoc_6sec.ini` — the sheet the viewer opens an XDTS file on when
  /// nothing names another (its `defaultconfig.ini`).
  ponocSixSeconds(
    'ponoc-6s',
    label: 'Ponoc 6 seconds sheet',
    paper: 'Ponoc',
    paperFormat: SheetPaperFormat.jisB4,
    marginLeftMm: 7.4,
    marginTopMm: 4.0,
    bodyAmount: 2,
    keyColAmount: 8,
    cellsColAmount: 7,
    cameraColAmount: 3,
    frameLength: 144,
    drawCameraHeaderGrid: true,
    drawCameraHeaderLabel: false,
    drawCellsHeaderLabel: false,
    drawKeysHeaderLabel: false,
    drawDialogHeaderLine: true,
    bodyWidthMm: 115.4,
    bodyHeightMm: 308.0,
    bodyHMarginMm: 12.6,
    bodyTopMm: 44.2,
    headerHeightMm: 8.6,
    keyColWidthMm: 4.0,
    lastKeyColWidthMm: 0.0,
    dialogColWidthMm: 8.9,
    cellsColWidthMm: 7.5,
    cameraColWidthMm: 7.5,
    rowHeightMm: 4.15,
    secondHeightMm: 99.8,
    infoOriginLeftMm: 112.9,
    infoOriginTopMm: 0,
    infoTitleHeightMm: 3.4,
    infoBodyHeightMm: 9.3,
    info: [
      (label: _scene, widthMm: 36.9, field: TimesheetHeaderField.cut),
      (label: _time, widthMm: 40.3, field: TimesheetHeaderField.time),
      (label: _name, widthMm: 25.6, field: TimesheetHeaderField.name),
      (label: _sheet, widthMm: 25.6, field: TimesheetHeaderField.sheet),
    ],
    memo: (leftMm: 0, topMm: 14.4, widthMm: 243.5, heightMm: 28.2),
    logo: (leftMm: 0, topMm: 0, widthMm: 46.7, heightMm: 5.5),
    overlapLength: (leftMm: 133.9, topMm: 13.4, widthMm: 72.2, heightMm: 3.5),
  );

  const XdtsViewerSheet(
    this.jsonValue, {
    required this.label,
    required this.paper,
    required this.paperFormat,
    required this.marginLeftMm,
    required this.marginTopMm,
    required this.bodyAmount,
    required this.keyColAmount,
    required this.cellsColAmount,
    required this.cameraColAmount,
    required this.frameLength,
    this.drawCameraHeaderGrid = false,
    this.drawCameraHeaderLabel = true,
    this.drawCellsHeaderLabel = true,
    this.drawKeysHeaderLabel = true,
    this.drawDialogHeaderLine = false,
    required this.bodyWidthMm,
    required this.bodyHeightMm,
    required this.bodyHMarginMm,
    required this.bodyTopMm,
    required this.headerHeightMm,
    required this.keyColWidthMm,
    required this.lastKeyColWidthMm,
    required this.dialogColWidthMm,
    required this.cellsColWidthMm,
    required this.cameraColWidthMm,
    required this.rowHeightMm,
    required this.secondHeightMm,
    required this.infoOriginLeftMm,
    required this.infoOriginTopMm,
    required this.infoTitleHeightMm,
    required this.infoBodyHeightMm,
    required this.info,
    this.totalOverCurrent = true,
    required this.memo,
    required this.logo,
    this.overlapLength,
  });

  /// The stored key.
  final String jsonValue;

  /// What the viewer lists it by — and what a `config.ini` names it by
  /// (`TemplateName`).
  final String label;

  /// The template's own name for its paper — the Ponoc sheet is printed on
  /// JIS B4 like the B4 ones.
  final String paper;

  /// Its paper (`PageSize`), standing upright.
  final SheetPaperFormat paperFormat;

  /// The corner the sheet is drawn from (`Margin`'s left and top — the
  /// right and the bottom move nothing).
  final double marginLeftMm;
  final double marginTopMm;

  /// The 3-second bodies a page lays side by side, 72 frames each.
  final int bodyAmount;

  /// The ACTION block's columns, the CELL block's and the camera block's.
  final int keyColAmount;
  final int cellsColAmount;
  final int cameraColAmount;

  /// The frames a page holds.
  final int frameLength;

  /// Whether the camera block's head is split as the ACTION and CELL
  /// blocks' are — a middle line and a wall between columns — rather than
  /// closed by its bottom line alone.
  final bool drawCameraHeaderGrid;

  /// Whether the camera, the CELL and the ACTION blocks print their names.
  final bool drawCameraHeaderLabel;
  final bool drawCellsHeaderLabel;
  final bool drawKeysHeaderLabel;

  /// Whether the dialogue column's head is closed by a line.
  final bool drawDialogHeaderLine;

  final double bodyWidthMm;
  final double bodyHeightMm;

  /// The gap between two bodies.
  final double bodyHMarginMm;

  /// How far below the margin's corner the bodies stand.
  final double bodyTopMm;

  /// The block heads' height, over the rows.
  final double headerHeightMm;

  /// An ACTION column's width, and the frame-number column's after them —
  /// none, and the numbers stand outside the body.
  final double keyColWidthMm;
  final double lastKeyColWidthMm;

  final double dialogColWidthMm;
  final double cellsColWidthMm;
  final double cameraColWidthMm;

  /// A frame row's height, and a second's — its 24 rows and the gap of
  /// its closing double rule.
  final double rowHeightMm;
  final double secondHeightMm;

  /// Where the info header stands from the margin's corner, and its two
  /// rows' heights: the labels' and the values'.
  final double infoOriginLeftMm;
  final double infoOriginTopMm;
  final double infoTitleHeightMm;
  final double infoBodyHeightMm;

  /// The info header's boxes, left to right.
  final List<XdtsInfoBox> info;

  /// Whether the sheet box writes the sheets the cut fills over the one
  /// it is on (`SheetInv`), or the one over them all (`Sheet`).
  final bool totalOverCurrent;

  /// The places for the memo and for the logo.
  final XdtsDataField memo;
  final XdtsDataField logo;

  /// The place the sheet writes a cut's O.L lengths in (`OverlapLength`) —
  /// the Ponoc sheet's alone.
  final XdtsDataField? overlapLength;

  /// The seconds a page holds, at the viewer's rate.
  int get pageSeconds => frameLength ~/ xdtsViewerFps;

  /// The viewer's Japanese for its boxes' labels (`TranslateInfoLabel`).
  static const String _episode = '第　　話';
  static const String _seq = 'シーン';
  static const String _scene = 'カット';
  static const String _time = 'タイム';
  static const String _name = '原画';
  static const String _sheet = 'シート';

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
