import 'package:flutter/material.dart';

import '../../models/canvas_viewport.dart';
import '../../models/cut_id.dart';
import '../../services/cache_invalidation_executor.dart';
import '../../services/history_manager.dart';
import '../brush/brush_tool_state.dart';
import '../sheet/sheet_ink_layer.dart';
import 'timesheet_document_painter.dart';
import 'timesheet_ink_controller.dart';

/// Computes the ink windows for the current view mode, bottom-of-stack
/// first: page ink lies under the strip windows, so a stroke STARTING on
/// the column grid goes to the frame-anchored strip plane and everything
/// else (header, memo band, margins, gaps) goes to the page plane. A
/// stroke keeps its start plane for its whole duration (pointer capture) —
/// simpler than per-segment routing and closer to how a pen behaves.
List<SheetInkWindow> timesheetInkWindows({
  required TimesheetDocumentLayout layout,
  required TimesheetDocumentLayout pagedLayout,
  required CutId cutId,
}) {
  final document = layout.document;
  final windows = <SheetInkWindow>[];
  const rowHeight = TimesheetDocumentLayout.rowHeight;

  if (layout.continuous) {
    // Page ink: page 1's surface over the identical header/memo geometry
    // (later pages' page ink is paged-view only).
    windows.add(
      SheetInkWindow(
        id: 'page-0-continuous',
        surfaceScale: TimesheetInkController.inkScale.toDouble(),
        plane: TimesheetInkPlane.page,
        key: TimesheetInkController.pageKey(cutId, 0),
        documentRect: Rect.fromLTWH(
          layout.paperLeft,
          layout.pageTop(0),
          pagedLayout.paperWidth,
          pagedLayout.paperHeight,
        ),
        inkOffset: Offset.zero,
      ),
    );
    // Strip ink: the page bands stacked seamlessly down the single strip.
    final bandHeight = document.pageFrameCount * rowHeight;
    for (var band = 0; band < document.pages.length; band += 1) {
      windows.add(
        SheetInkWindow(
          id: 'strip-$band-continuous',
          surfaceScale: TimesheetInkController.inkScale.toDouble(),
          plane: TimesheetInkPlane.strip,
          key: TimesheetInkController.stripBandKey(cutId, band),
          documentRect: Rect.fromLTWH(
            layout.halfLeft(0, 0),
            layout.halfRowsTop(0) + band * bandHeight,
            layout.halfWidth,
            bandHeight,
          ),
          inkOffset: Offset.zero,
        ),
      );
    }
    return windows;
  }

  // Page view mounts windows for the page ON SCREEN only (R26 #41) — the
  // off-screen pages' surfaces keep their ink, they just have no window.
  final visiblePages = layout.visiblePageIndexes;
  for (final pageIndex in visiblePages) {
    windows.add(
      SheetInkWindow(
        id: 'page-$pageIndex',
        surfaceScale: TimesheetInkController.inkScale.toDouble(),
        plane: TimesheetInkPlane.page,
        key: TimesheetInkController.pageKey(cutId, pageIndex),
        documentRect: layout.pageRect(pageIndex),
        inkOffset: Offset.zero,
      ),
    );
  }
  for (final pageIndex in visiblePages) {
    for (var half = 0; half < 2; half += 1) {
      final rowCount = layout.halfRowCount(half);
      if (rowCount <= 0) {
        continue;
      }
      windows.add(
        SheetInkWindow(
          id: 'strip-$pageIndex-h$half',
          surfaceScale: TimesheetInkController.inkScale.toDouble(),
          plane: TimesheetInkPlane.strip,
          key: TimesheetInkController.stripBandKey(cutId, pageIndex),
          documentRect: Rect.fromLTWH(
            layout.halfLeft(pageIndex, half),
            layout.halfRowsTop(pageIndex),
            layout.halfWidth,
            rowCount * rowHeight,
          ),
          inkOffset: Offset(
            0,
            half *
                document.halfFrameCount *
                rowHeight *
                TimesheetInkController.inkScale,
          ),
        ),
      );
    }
  }
  return windows;
}

/// The sheet's ink input/display stack: every window hosts the SAME
/// interactive brush view the drawing canvas uses (current brush/eraser,
/// live overlay, dab commit), windowed onto its ink surface by a derived
/// viewport and clipped to its on-screen rect so pointer-downs outside it
/// fall through to the window below.
class TimesheetInkLayer extends StatelessWidget {
  const TimesheetInkLayer({
    super.key,
    required this.controller,
    required this.layout,
    required this.pagedLayout,
    required this.cutId,
    required this.brushToolState,
    required this.historyManager,
    required this.viewport,
    required this.strokeActive,
    this.cacheInvalidationSink,
  });

  final TimesheetInkController controller;
  final TimesheetDocumentLayout layout;
  final TimesheetDocumentLayout pagedLayout;
  final CutId cutId;
  final BrushToolState brushToolState;
  final HistoryManager historyManager;

  /// The live panel viewport (the same transform the document painter
  /// applies).
  final CanvasViewport viewport;

  /// Raised while any window has a stroke in progress, so the panel's
  /// gesture layer holds navigation exactly as it does for canvas strokes.
  final ValueNotifier<bool> strokeActive;

  final CacheInvalidationSink? cacheInvalidationSink;

  @override
  Widget build(BuildContext context) {
    final windows = timesheetInkWindows(
      layout: layout,
      pagedLayout: pagedLayout,
      cutId: cutId,
    );
    return SheetInkLayer(
      windows: windows,
      keyPrefix: 'timesheet',
      viewport: viewport,
      brushToolState: brushToolState,
      strokeActive: strokeActive,
      // The plane axis stays HERE, with the controller that has one. The
      // shared layer hands the window back and asks nothing about it.
      sessionStateFor: (window) => controller.sessionStateFor(
        window.plane! as TimesheetInkPlane,
        window.key,
      ),
      onStrokeCommitted: (window, strokeData) => controller.commitStroke(
        plane: window.plane! as TimesheetInkPlane,
        key: window.key,
        strokeData: strokeData,
        historyManager: historyManager,
        cacheInvalidationSink: cacheInvalidationSink,
      ),
    );
  }
}
