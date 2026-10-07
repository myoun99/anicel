import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';

import '../../models/canvas_viewport.dart';
import '../../models/cut_id.dart';
import '../../models/sheet_marks.dart';
import '../../models/timesheet_ink_keys.dart';
import '../../services/cache_invalidation_executor.dart';
import '../../services/history_manager.dart';
import '../brush/brush_tool_state.dart';
import '../canvas/viewport_canvas_transform.dart' show canvasRectShown;
import '../sheet/sheet_ink_layer.dart';
import 'timesheet_document_painter.dart';
import 'timesheet_ink_controller.dart';

/// The ink windows: one per page, the whole paper — a stroke is the page's
/// it starts on, kept to that page ([sheetInkRegions]).
///
/// A pixel of the ink is a pixel of the paper (F-294), and it stays where
/// it was written whatever the sheet prints under it (F-252, 유저
/// 2026-10-01: 「내용물이 뭐가 바뀌던 독립적」).
///
/// [pages] are the pages to lay windows for — every page the layout
/// prints when null.
List<SheetInkWindow> timesheetInkWindows({
  required TimesheetDocumentLayout layout,
  required CutId cutId,
  Iterable<int>? pages,
}) => [
  for (final pageIndex in pages ?? layout.pageIndexes)
    SheetInkWindow(
      id: 'page-$pageIndex',
      key: timesheetInkPageKey(cutId, pageIndex),
      placement: SheetInkPlacement(
        window: layout.pageRect(pageIndex),
        scale: layout.paperScale,
      ),
    ),
];

/// The sheet's ink input/display stack: every window hosts the SAME
/// interactive brush view the drawing canvas uses (current brush/eraser,
/// live overlay, dab commit), windowed onto its ink surface by a derived
/// viewport ([SheetInkLayer]).
class TimesheetInkLayer extends StatelessWidget {
  const TimesheetInkLayer({
    super.key,
    required this.controller,
    required this.layout,
    required this.cutId,
    required this.brushToolState,
    required this.historyManager,
    required this.viewport,
    required this.strokeActive,
    this.cacheInvalidationSink,
  });

  final TimesheetInkController controller;
  final TimesheetDocumentLayout layout;
  final CutId cutId;
  /// Forwarded to [SheetInkLayer.brushToolState] — heard, not handed over.
  final ValueListenable<BrushToolState> brushToolState;
  final HistoryManager historyManager;

  /// The live panel viewport (the same transform the document painter
  /// applies).
  final CanvasViewport viewport;

  /// Forwarded to [SheetInkLayer.strokeActive].
  final ValueNotifier<bool> strokeActive;

  final CacheInvalidationSink? cacheInvalidationSink;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) => _windowsOver(box.biggest),
  );

  /// The layer for a [box] of the panel: windows for the pages on screen
  /// only — the pages off it keep their ink on their surfaces (the sheet's
  /// strata print it), they just have no window to draw through. Every
  /// page's would be a brush view each.
  Widget _windowsOver(Size box) {
    final windows = timesheetInkWindows(
      layout: layout,
      cutId: cutId,
      pages: layout.pageStack.pagesMeeting(canvasRectShown(viewport, box)),
    );
    return SheetInkLayer(
      windows: windows,
      keyPrefix: 'timesheet',
      viewport: viewport,
      brushToolState: brushToolState,
      strokeActive: strokeActive,
      history: historyManager.gestures,
      sessionStateFor: (window) => controller.sessionStateFor(null, window.key),
      onStrokeCommitted: (window, strokeData) => controller.commitStroke(
        plane: null,
        key: window.key,
        strokeData: strokeData,
        historyManager: historyManager,
        cacheInvalidationSink: cacheInvalidationSink,
      ),
    );
  }
}
