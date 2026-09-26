import 'dart:ui';

import '../brush_frame_key.dart';
import '../cut_id.dart';
import '../sheet_marks.dart';
import '../sheet_paint_layer.dart';
import 'conte_ink_keys.dart';
import 'conte_sheet_layout.dart';

/// Every ink window a conte page shows, in PAINT ORDER: the page's own
/// margin ink first, then each cell's row band — as the marks that print
/// them, each with where its window shows its surface.
///
/// ⛔THE SCREEN PAINTER AND THE PDF WRITER BOTH WALKED IT, and both
/// skipped a cell with no frame. A page whose ink walk differs between
/// screen and print is a page that prints something the user never saw —
/// and the order matters too, because the page ink lies under the rows.
/// The brush's input windows are made from this walk as well.
///
/// A cell's row is its BLOCK's handwriting ([ConteCellSource.inkId]). A
/// block not yet written on has none to print; the pen still writes there,
/// under the id [unwrittenInkIdOf] names before it exists — the printers
/// pass nothing and print no row for it. So does a cell with no block at
/// all: its band is the handwriting of the block its first stroke makes
/// (유저 답 conte-drawing-target-Q3 「그림 칸과 같이 (토글을 따른다)」).
Iterable<SheetInk> conteInkMarks(
  ContePageLayout page,
  ConteSheetMetrics metrics, {
  String Function(ContePlacedCell cell)? unwrittenInkIdOf,
}) sync* {
  SheetInk ink(BrushFrameKey key, Rect window) => SheetInk(
    SheetPaintLayer.ink,
    key: key,
    placement: SheetInkPlacement(
      window: window,
      scale: conteInkScale.toDouble(),
    ),
  );

  yield ink(
    conteInkPageKey(page.pageIndex),
    Rect.fromLTWH(0, 0, metrics.pageWidth, metrics.pageHeight),
  );
  for (final cell in page.cells) {
    final inkId = cell.source.inkId ?? unwrittenInkIdOf?.call(cell);
    if (inkId == null) {
      continue;
    }
    yield ink(
      conteInkRowKey(CutId(cell.cutId), inkId),
      cell.rowBandRect(metrics),
    );
  }
}
