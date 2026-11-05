import 'dart:math' as math;

import 'xdts_viewer_sheet.dart';

/// A box of an XDTS sheet's info header as the viewer lays it, from the
/// paper's corner: its template box, its left and its width.
typedef XdtsInfoPlace = ({XdtsInfoBox box, int left, int width});

/// A place on an XDTS sheet in the viewer's pixels, from the paper's
/// corner.
typedef XdtsPixelRect = ({int left, int top, int width, int height});

/// A sheet of the XDTS Viewer's ([XdtsViewerSheet]) laid out as the XDTS
/// Viewer lays it for our XDTS file, in the viewer's own pixels — so a
/// sheet drawn on it lands on the viewer's page line for line, and the
/// handwriting written on one lands on the other's cells (I-161-Q2).
///
/// 🚨THE VIEWER'S ARITHMETIC, NOT THE TEMPLATE'S MILLIMETRES. The viewer
/// turns every length of a template into whole pixels at 250dpi on its own
/// ([px]), then adds and multiplies those pixels and halves them in whole
/// pixels. A sheet drawn from the millimetres lands as much as half a
/// millimetre off its lines — so every measure here is a whole pixel, got
/// the viewer's way.
///
/// Every measure is from the paper's top-left corner unless it says
/// otherwise; a body's are from the body's corner.
class XdtsSheetForm {
  /// [template] for a cut whose wider block carries [columns] cel columns:
  /// the viewer's ExpandColumns widens the ACTION block and the CELL block
  /// both to as many, and the paper with them, where the template has
  /// fewer.
  ///
  /// 🗣️I-162-Q6 (유저 2026-11-05): 「나누고, 내보내기도 원화 · 동화 두
  /// 파일로」 — our XDTS is a `_genga_ts` file and a `_douga_ts` one, and
  /// the viewer opened on such a pair widens both blocks to the larger
  /// file's tracks, 「原画動画ペアの場合は、一方しかデータが無くても両方
  /// 拡張する」 (its `XSheetPDFTemplate::param`). ↩️It was one file of
  /// every cel track, the CELL block alone widened (저장 2026-11-05).
  XdtsSheetForm(this.template, {required int columns})
    : keyColumns = math.max(columns, template.keyColAmount),
      cellsColumns = math.max(columns, template.cellsColAmount);

  /// The viewer's sheet — the template its numbers are read from.
  final XdtsViewerSheet template;

  /// The ACTION block's columns and the CELL block's, widened.
  final int keyColumns;
  final int cellsColumns;

  /// The viewer's resolution.
  static const int dpi = 250;

  /// [mm] in the viewer's pixels: rounded to the nearest whole one, a half
  /// away from zero.
  static int px(double mm) => (mm * dpi / 25.4).round();

  /// Seconds a body holds, and the rows a second holds: the viewer counts
  /// 24 frames a second whatever the file was made at ([xdtsViewerFps]).
  static const int bodySeconds = 3;
  static const int rowsPerSecond = xdtsViewerFps;

  /// Frames a body holds.
  static const int bodyRows = bodySeconds * rowsPerSecond;

  late final int rowHeight = px(template.rowHeightMm);
  late final int secondHeight = px(template.secondHeightMm);
  late final int headerHeight = px(template.headerHeightMm);
  late final int keyColWidth = px(template.keyColWidthMm);
  late final int lastKeyColWidth = px(template.lastKeyColWidthMm);
  late final int dialogColWidth = px(template.dialogColWidthMm);
  late final int cellsColWidth = px(template.cellsColWidthMm);
  late final int cameraColWidth = px(template.cameraColWidthMm);
  late final int bodyHeight = px(template.bodyHeightMm);
  late final int bodyHMargin = px(template.bodyHMarginMm);

  /// The body's width — the template's, and the columns each block
  /// widened by.
  late final int bodyWidth =
      px(template.bodyWidthMm) +
      (keyColumns - template.keyColAmount) * keyColWidth +
      (cellsColumns - template.cellsColAmount) * cellsColWidth;

  /// The paper: the template's, and the bodies' widening beside it.
  late final int pageWidth =
      px(template.paperFormat.widthMm) +
      (bodyWidth - px(template.bodyWidthMm)) * template.bodyAmount;
  late final int pageHeight = px(template.paperFormat.heightMm);

  /// The corner the sheet is drawn from: the margin's.
  late final int originLeft = px(template.marginLeftMm);
  late final int originTop = px(template.marginTopMm);

  /// The left of body [body].
  int bodyLeft(int body) => originLeft + body * (bodyWidth + bodyHMargin);

  /// The top of the bodies — their heads' top.
  late final int bodyTop = originTop + px(template.bodyTopMm);

  /// The top of the bodies' first rows.
  late final int rowsTop = bodyTop + headerHeight;

  /// The ACTION block's width: its columns and the frame numbers' after.
  late final int keyBlockWidth = keyColWidth * keyColumns + lastKeyColWidth;

  /// Where the dialogue column, the CELL block and the camera block stand
  /// in a body.
  late final int dialogLeft = keyBlockWidth;
  late final int cellsLeft = dialogLeft + dialogColWidth;
  late final int cellsBlockWidth = cellsColWidth * cellsColumns;
  late final int cameraLeft = cellsLeft + cellsBlockWidth;
  late final int cameraBlockWidth =
      cameraColWidth * template.cameraColAmount;

  /// How far the rows by a second's double rule reach into its gap — the
  /// gap halved, in whole pixels (none past it: on the Ponoc sheet a
  /// second is shorter than its 24 rows, and the rows give a pixel each).
  late final int heightAdjust = (secondHeight - rowsPerSecond * rowHeight) ~/ 2;

  /// The top of row [row] of a body, below its first row's top — of any
  /// row, before the first or past the last as well.
  int rowTop(int row) {
    final (:second, :inSecond) = _secondOf(row);
    final top = second * secondHeight + inSecond * rowHeight;
    return inSecond == 0 && second != 0 ? top - heightAdjust : top;
  }

  /// The bottom of row [row] of a body, below its first row's top.
  int rowBottom(int row) {
    final (:second, :inSecond) = _secondOf(row);
    final bottom = second * secondHeight + (inSecond + 1) * rowHeight;
    return inSecond == rowsPerSecond - 1 && second != bodySeconds - 1
        ? bottom + heightAdjust
        : bottom;
  }

  /// The second of a body [row] lies in, and its row in that second.
  static ({int second, int inSecond}) _secondOf(int row) {
    final second = (row / rowsPerSecond).floor();
    return (second: second, inSecond: row - second * rowsPerSecond);
  }

  /// The info header's top, the rule between its labels and its values,
  /// and its bottom.
  late final int infoTop = originTop + px(template.infoOriginTopMm);
  late final int infoTitleBottom = infoTop + px(template.infoTitleHeightMm);
  late final int infoBottom = infoTitleBottom + px(template.infoBodyHeightMm);

  /// The memo's place and the logo's — the template's, which the CELL
  /// block's widening does not move.
  late final XdtsPixelRect memo = _placeOf(template.memo);
  late final XdtsPixelRect logo = _placeOf(template.logo);

  /// [field] in pixels, each of its lengths rounded on its own.
  XdtsPixelRect _placeOf(XdtsDataField field) => (
    left: originLeft + px(field.leftMm),
    top: originTop + px(field.topMm),
    width: px(field.widthMm),
    height: px(field.heightMm),
  );

  /// The info header's boxes, left to right.
  late final List<XdtsInfoPlace> info = () {
    var left = originLeft + px(template.infoOriginLeftMm);
    return [
      for (final box in template.info)
        () {
          final width = px(box.widthMm);
          final place = (box: box, left: left, width: width);
          left += width;
          return place;
        }(),
    ];
  }();
}
