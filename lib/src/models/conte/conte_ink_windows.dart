import '../cut_id.dart';
import '../sheet_marks.dart';
import '../sheet_paint_layer.dart';
import 'conte_ink_keys.dart';
import 'conte_sheet_layout.dart';

/// Every ink window a conte page shows, in PAINT ORDER — each cell's row
/// band, as the marks that print them, each with where its window shows
/// its surface.
///
/// ⛔THE SCREEN PAINTER AND THE PDF WRITER BOTH WALKED IT, and both
/// skipped a cell with no frame. A page whose ink walk differs between
/// screen and print is a page that prints something the user never saw.
/// The brush's input windows are made from this walk as well.
///
/// ⛔No paper: ink is the cells' alone (유저 09-26, H44 「칸에만 넣고싶거든 …
/// 컷 이동하면 따라오도록 구조적으로 강제」) — a stroke outside every cell has
/// nothing to land in.
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
  for (final cell in page.cells) {
    final inkId = cell.source.inkId ?? unwrittenInkIdOf?.call(cell);
    if (inkId == null) {
      continue;
    }
    yield SheetInk(
      SheetPaintLayer.ink,
      key: conteInkRowKey(CutId(cell.cutId), inkId),
      placement: SheetInkPlacement(
        window: cell.rowBandRect(metrics),
        scale: conteInkScale.toDouble(),
      ),
    );
  }
}
