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
import '../effective_device_pixel_ratio.dart';
import '../sheet/sheet_ink_layer.dart';
import '../text/app_face.dart';
import '../widgets/static_raster.dart';
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
  SheetInkWindow window(
    String id,
    BrushFrameKey key,
    Rect rect, {
    Offset origin = Offset.zero,
  }) => SheetInkWindow(
    id: id,
    key: key,
    plane: TimesheetInkPlane.of(key),
    placement: SheetInkPlacement(
      window: rect,
      scale: timesheetInkScale.toDouble(),
      origin: origin,
    ),
  );

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
    // Strip ink: the page bands stacked seamlessly down the single strip.
    final bandHeight = document.pageFrameCount * rowHeight;
    for (var band = 0; band < document.pages.length; band += 1) {
      windows.add(
        window(
          'strip-$band-continuous',
          timesheetInkStripKey(cutId, band),
          Rect.fromLTWH(
            layout.halfLeft(0, 0),
            layout.halfRowsTop(0) + band * bandHeight,
            layout.halfWidth,
            bandHeight,
          ),
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
      window(
        'page-$pageIndex',
        timesheetInkPageKey(cutId, pageIndex),
        layout.pageRect(pageIndex),
      ),
    );
  }
  for (final pageIndex in visiblePages) {
    for (final strip in layout.halfStrips) {
      windows.add(
        window(
          'strip-$pageIndex-h${strip.half}',
          timesheetInkStripKey(cutId, pageIndex),
          Rect.fromLTWH(
            layout.halfLeft(pageIndex, strip.half),
            layout.halfRowsTop(pageIndex),
            layout.halfWidth,
            strip.rowCount * rowHeight,
          ),
          // The right half shows the band's lower rows: one surface, two
          // windows onto it.
          origin: Offset(
            0,
            strip.half *
                document.halfFrameCount *
                rowHeight *
                timesheetInkScale,
          ),
        ),
      );
    }
  }
  return windows;
}

/// The sheet's ink over its other strata: the saved ink, baked
/// ([TimesheetInkStratum]) — whatever the brush switch says — and, while
/// the brush is allowed ([brush]), the live windows it writes through
/// ([TimesheetInkLayer]) above it.
class TimesheetInk extends StatelessWidget {
  const TimesheetInk({
    super.key,
    required this.controller,
    required this.layout,
    required this.pagedLayout,
    required this.cutId,
    required this.viewport,
    this.brush,
  });

  final TimesheetInkController controller;
  final TimesheetDocumentLayout layout;
  final TimesheetDocumentLayout pagedLayout;
  final CutId cutId;
  final CanvasViewport viewport;

  /// What the live windows write with — null while the brush is off.
  final ({
    ValueListenable<BrushToolState> tool,
    HistoryManager history,
    ValueNotifier<bool> strokeActive,
    CacheInvalidationSink? sink,
  })?
  brush;

  @override
  Widget build(BuildContext context) {
    final brush = this.brush;
    return Stack(
      children: [
        Positioned.fill(
          child: TimesheetInkStratum(
            controller: controller,
            layout: layout,
            pagedLayout: pagedLayout,
            cutId: cutId,
            viewport: viewport,
            live: brush != null,
          ),
        ),
        if (brush != null)
          Positioned.fill(
            // The tool-state boundary (R18 UI-3): the brush reaches only
            // this small overlay — the sheet document below never rebuilds
            // for it — and since H40 ② (2026-09-24) not even the overlay
            // does: its windows read the brush when a stroke starts.
            child: TimesheetInkLayer(
              key: const ValueKey<String>('timesheet-ink-layer'),
              controller: controller,
              layout: layout,
              pagedLayout: pagedLayout,
              cutId: cutId,
              brushToolState: brush.tool,
              historyManager: brush.history,
              viewport: viewport,
              strokeActive: brush.strokeActive,
              cacheInvalidationSink: brush.sink,
            ),
          ),
      ],
    );
  }
}

/// The sheet's SAVED ink, a baked stratum of its own: the windows the
/// brush writes through ([timesheetInkWindows]), each window's surface
/// laid where it shows it — whatever the brush switch says — but for the
/// keys the live layer above is showing ([live]), which stand down so
/// translucent ink never composites twice. The controller repaints it when
/// a stroke lands or undoes.
///
/// ⛔The sheet printed no ink of its own: its writing showed only through
/// the brush's windows, which mount with the switch on — so with the switch
/// off (every sheet's default since 09-25) it vanished, while the conte's
/// and the envelope's stayed (유저 2026-09-26: 「다 통일해줘. 기능은 어차피
/// 생길수있어」).
class TimesheetInkStratum extends StatelessWidget {
  const TimesheetInkStratum({
    super.key,
    required this.controller,
    required this.layout,
    required this.pagedLayout,
    required this.cutId,
    required this.viewport,
    required this.live,
  });

  final TimesheetInkController controller;
  final TimesheetDocumentLayout layout;
  final TimesheetDocumentLayout pagedLayout;
  final CutId cutId;

  /// The panel's pan/zoom — the transform the sheet's other strata take.
  final CanvasViewport viewport;

  /// Whether the live brush layer is mounted over this stratum.
  final bool live;

  @override
  Widget build(BuildContext context) {
    final windows = timesheetInkWindows(
      layout: layout,
      pagedLayout: pagedLayout,
      cutId: cutId,
    );
    return IgnorePointer(
      child: StaticRaster(
        debugLabel: 'timesheet-ink',
        child: CustomPaint(
          key: const ValueKey<String>('timesheet-ink-paint'),
          painter: TimesheetDocumentPainter(
            document: layout.document,
            layout: layout,
            face: appFaceOf(DefaultTextStyle.of(context).style),
            viewport: viewport,
            effectiveRatio: EffectiveDevicePixelRatio.of(context),
            layers: const {SheetPaintLayer.ink},
            ink: [for (final window in windows) window.mark],
            inkImageFor: (key) =>
                controller.displayImageFor(TimesheetInkPlane.of(key), key),
            liveInkKeys: live
                ? {for (final window in windows) window.key}
                : const {},
            inkRepaint: controller,
          ),
          child: const SizedBox.expand(),
        ),
      ),
    );
  }
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
  /// Forwarded to [SheetInkLayer.brushToolState] — heard, not handed over.
  final ValueListenable<BrushToolState> brushToolState;
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
