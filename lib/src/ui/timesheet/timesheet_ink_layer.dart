import 'dart:math' as math;

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';

import '../../models/brush_frame_key.dart';
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
import 'timesheet_ink_bands.dart';
import 'timesheet_ink_controller.dart';

/// Computes the ink windows for the current view mode, bottom-of-stack
/// first: page ink lies under the strip windows, so a stroke started on
/// the column grid goes to the frame-anchored strip plane and one started
/// anywhere else (header, memo band, margins, gaps) to the page plane —
/// each kept to what its window shows ([sheetInkRegions]).
///
/// [pages] are the pages of the page view to lay windows for — every
/// page the layout prints when null.
List<SheetInkWindow> timesheetInkWindows({
  required TimesheetDocumentLayout layout,
  required TimesheetDocumentLayout pagedLayout,
  required CutId cutId,
  Iterable<int>? pages,
}) {
  final document = layout.document;
  final windows = <SheetInkWindow>[];
  const rowHeight = TimesheetDocumentLayout.rowHeight;
  // A pixel of the ink is a pixel of the paper (F-294).
  final scale = pagedLayout.paperScale;
  SheetInkWindow window(
    String id,
    BrushFrameKey key,
    Rect rect, {
    Offset origin = Offset.zero,
    double stretch = 1,
  }) => SheetInkWindow(
    id: id,
    key: key,
    plane: TimesheetInkPlane.of(key),
    placement: SheetInkPlacement(
      window: rect,
      scale: scale,
      origin: origin,
      stretch: stretch,
    ),
  );

  // Frame-anchored ink: [rows] rows from global frame [first], laid from
  // ([left], [top]) — each run of columns a window onto the band surface
  // the rows are kept on ([timesheetInkRuns]). One run keeps the strip's
  // own id.
  final runs = timesheetInkRuns(layout);
  final bandFrames = timesheetInkBandFrames(document);
  void strip(
    String id, {
    required int first,
    required int rows,
    required double left,
    required double top,
  }) {
    final band = first ~/ bandFrames;
    final row = first % bandFrames;
    for (final run in runs) {
      windows.add(
        window(
          runs.length == 1 ? id : '$id-c${run.first}',
          timesheetInkStripKey(cutId, band),
          Rect.fromLTWH(left + run.left, top, run.width, rows * rowHeight),
          origin: Offset(
            run.surfaceLeft * scale,
            row * rowHeight * scale,
          ),
          stretch: run.stretch,
        ),
      );
    }
  }

  if (layout.continuous) {
    // Page ink: page 1's surface over the identical header/memo geometry
    // (later pages' page ink is paged-view only).
    windows.add(
      window(
        'page-0-continuous',
        timesheetInkPageKey(cutId, 0),
        Rect.fromLTWH(
          layout.paperLeft,
          layout.pageTop(0),
          pagedLayout.paperWidth,
          pagedLayout.paperHeight,
        ),
      ),
    );
    // Strip ink: the bands stacked seamlessly down the single strip.
    final bands = (document.rowCount + bandFrames - 1) ~/ bandFrames;
    for (var band = 0; band < bands; band += 1) {
      final first = band * bandFrames;
      strip(
        'strip-$band-continuous',
        first: first,
        rows: math.min(bandFrames, document.rowCount - first),
        left: layout.halfLeft(0, 0),
        top: layout.halfRowsTop(0) + first * rowHeight,
      );
    }
    return windows;
  }

  final visiblePages = pages ?? layout.visiblePageIndexes;
  for (final pageIndex in visiblePages) {
    windows.add(
      window(
        'page-$pageIndex',
        timesheetInkPageKey(cutId, pageIndex),
        layout.pageRect(pageIndex),
      ),
    );
  }
  for (final pageIndex in visiblePages) {
    final page = document.pages[pageIndex];
    for (final half in layout.halfStrips) {
      // The right half shows the band's lower rows: one surface, two
      // windows onto it — and a 3-second page, half a band.
      strip(
        'strip-$pageIndex-h${half.half}',
        first: page.startFrame + half.half * document.halfFrameCount,
        rows: half.rowCount,
        left: layout.halfLeft(pageIndex, half.half),
        top: layout.halfRowsTop(pageIndex),
      );
    }
  }
  return windows;
}

/// The sheet's ink input/display stack: every window hosts the SAME
/// interactive brush view the drawing canvas uses (current brush/eraser,
/// live overlay, dab commit), windowed onto its ink surface by a derived
/// viewport ([SheetInkLayer]).
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

  /// The layer for a [box] of the panel: in the page view, windows for
  /// the pages on screen only — the pages off it keep their ink on their
  /// surfaces (the sheet's strata print it), they just have no window
  /// to draw through. Every page's three would be a brush view each.
  Widget _windowsOver(Size box) {
    final windows = timesheetInkWindows(
      layout: layout,
      pagedLayout: pagedLayout,
      cutId: cutId,
      pages: layout.continuous
          ? null
          : layout.pageStack.pagesMeeting(canvasRectShown(viewport, box)),
    );
    return SheetInkLayer(
      windows: windows,
      keyPrefix: 'timesheet',
      viewport: viewport,
      brushToolState: brushToolState,
      strokeActive: strokeActive,
      history: historyManager.gestures,
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
