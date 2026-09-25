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
Iterable<SheetInk> conteInkMarks(
  ContePageLayout page,
  ConteSheetMetrics metrics,
) sync* {
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
    final frameId = cell.source.frameId;
    if (frameId == null) {
      continue;
    }
    yield ink(
      conteInkRowKey(CutId(cell.cutId), frameId),
      cell.rowBandRect(metrics),
    );
  }
}
