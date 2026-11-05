import 'sheet_paper.dart' show SheetPaperFormat;

/// What a box of an XDTS sheet's info header holds, as its template names
/// it (`InfoFormats\i\infoType`): nothing the viewer writes, the cut, the
/// length, or the sheet count — total over current, or current over total.
enum XdtsInfoType { none, scene, time, sheet, sheetInverted }

/// A box of an XDTS sheet's info header: the label its template gives it
/// (`EPISODE`, `SEQ.` …), its width, and what it holds.
typedef XdtsInfoBox = ({String label, double widthMm, XdtsInfoType type});

/// A sheet form the XDTS Viewer prints an XDTS file on — one of the
/// `xsheettemplates/*.ini` its release carries, held as the numbers the
/// file gives (I-162: 「xdts의 서식같은거 다 타입으로 구현하자 … 서식
/// 바꾸면 xdts의 해당 서식에서 보는거랑 똑같은 화면」).
///
/// ⛔The viewer's code is not ours to copy (BSD-3, Shun Iwasawa — the
/// independent-reimplementation policy): what is kept here is the files'
/// numbers, and [XdtsSheetForm] lays them out by the measures the viewer
/// draws with. The four were read off the viewer's v1.3.0 release by the
/// save lane (I-162, 2026-11-05); the A3 and the B4 3-second sheets' info
/// boxes are OpenToonz's presets of the same files, which the release's
/// B4 6-second one matches line for line.
///
/// Only what the sheet draws is held: the places the viewer sets out for a
/// memo, its logo, the date and the overlap's length (`DataFields`) — none
/// of them printed here yet (I-162-Q2) — the memo's line count and the
/// extra cel columns of a sheet that does not widen are the viewer's own
/// business.
class XdtsSheetTemplate {
  const XdtsSheetTemplate({
    required this.label,
    required this.paper,
    required this.marginLeftMm,
    required this.marginTopMm,
    required this.bodyAmount,
    required this.keyColAmount,
    required this.cellsColAmount,
    required this.cameraColAmount,
    required this.frameLength,
    this.drawCameraGrid = true,
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
  });

  /// What the viewer lists it by — and what a `config.ini` names it by
  /// (`TemplateName`).
  final String label;

  /// Its paper (`PageSize`), standing upright.
  final SheetPaperFormat paper;

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

  /// Whether the camera block is ruled in rows.
  final bool drawCameraGrid;

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

  /// `a3_6sec.ini`.
  static const XdtsSheetTemplate a3SixSeconds = XdtsSheetTemplate(
    label: 'A3 size, 6 seconds sheet',
    paper: SheetPaperFormat.a3,
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
      (label: 'EPISODE', widthMm: 36, type: XdtsInfoType.none),
      (label: 'SEQ.', widthMm: 30, type: XdtsInfoType.none),
      (label: 'SCENE', widthMm: 38, type: XdtsInfoType.scene),
      (label: 'TIME', widthMm: 55, type: XdtsInfoType.time),
      (label: 'NAME', widthMm: 32, type: XdtsInfoType.none),
      (label: 'SHEET', widthMm: 35, type: XdtsInfoType.sheetInverted),
    ],
  );

  /// `b4_3sec.ini`.
  static const XdtsSheetTemplate b4ThreeSeconds = XdtsSheetTemplate(
    label: 'B4 size, 3 seconds sheet',
    paper: SheetPaperFormat.jisB4,
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
      (label: 'EPISODE', widthMm: 26.5, type: XdtsInfoType.none),
      (label: 'SEQ.', widthMm: 18, type: XdtsInfoType.none),
      (label: 'SCENE', widthMm: 18.5, type: XdtsInfoType.scene),
      (label: 'TIME', widthMm: 40, type: XdtsInfoType.time),
      (label: 'NAME', widthMm: 26, type: XdtsInfoType.none),
      (label: 'SHEET', widthMm: 26, type: XdtsInfoType.sheetInverted),
    ],
  );

  /// `b4_6sec.ini`.
  static const XdtsSheetTemplate b4SixSeconds = XdtsSheetTemplate(
    label: 'B4 size, 6 seconds sheet',
    paper: SheetPaperFormat.jisB4,
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
      (label: 'EPISODE', widthMm: 26, type: XdtsInfoType.none),
      (label: 'SEQ.', widthMm: 18.5, type: XdtsInfoType.none),
      (label: 'SCENE', widthMm: 18.5, type: XdtsInfoType.scene),
      (label: 'TIME', widthMm: 40, type: XdtsInfoType.time),
      (label: 'NAME', widthMm: 26, type: XdtsInfoType.none),
      (label: 'SHEET', widthMm: 26, type: XdtsInfoType.sheet),
    ],
  );

  /// `ponoc_6sec.ini` — the sheet the viewer opens an XDTS file on when
  /// nothing names another (its `defaultconfig.ini`).
  static const XdtsSheetTemplate ponocSixSeconds = XdtsSheetTemplate(
    label: 'Ponoc 6 seconds sheet',
    paper: SheetPaperFormat.jisB4,
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
      (label: 'SCENE', widthMm: 36.9, type: XdtsInfoType.scene),
      (label: 'TIME', widthMm: 40.3, type: XdtsInfoType.time),
      (label: 'NAME', widthMm: 25.6, type: XdtsInfoType.none),
      (label: 'SHEET', widthMm: 25.6, type: XdtsInfoType.sheetInverted),
    ],
  );
}
