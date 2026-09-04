import 'dart:ui';

import '../brush_frame_key.dart';
import '../cut_id.dart';
import 'conte_ink_keys.dart';
import 'conte_sheet_layout.dart';

/// Every ink window a conte page shows, in PAINT ORDER: the page's own
/// margin ink first, then each cell's row band.
///
/// ⛔THE SCREEN PAINTER AND THE PDF WRITER BOTH WALKED IT, and both
/// skipped a cell with no frame. A page whose ink walk differs between
/// screen and print is a page that prints something the user never saw —
/// and the order matters too, because the page ink lies under the rows.
Iterable<({BrushFrameKey key, Rect rect})> conteInkWindows(
  ContePageLayout page,
  ConteSheetMetrics metrics,
) sync* {
  yield (
    key: conteInkPageKey(page.pageIndex),
    rect: Rect.fromLTWH(0, 0, metrics.pageWidth, metrics.pageHeight),
  );
  for (final cell in page.cells) {
    final frameId = cell.source.frameId;
    if (frameId == null) {
      continue;
    }
    yield (
      key: conteInkRowKey(CutId(cell.cutId), frameId),
      rect: cell.rowBandRect(metrics),
    );
  }
}
