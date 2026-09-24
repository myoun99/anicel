import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';

import '../../models/brush_frame_key.dart';
import '../../models/canvas_size.dart';
import '../../models/canvas_viewport.dart';
import '../../models/conte/conte_ink_keys.dart';
import '../../models/conte/conte_sheet_layout.dart';
import '../../models/cut_id.dart';
import '../../models/frame_id.dart';
import '../../services/brush_frame_store.dart';
import '../../services/cache_invalidation_executor.dart';
import '../../services/commands/brush_stroke_history_command.dart';
import '../../services/history_manager.dart';
import '../brush/brush_tool_state.dart';
import '../sheet/sheet_ink_layer.dart';
import '../sheet/sheet_ink_controller.dart';

/// Which conte ink plane a stroke lands on.
enum ConteInkPlane {
  /// CELL-anchored ink over a cell's whole ROW BAND (cut column through
  /// the TIME column) — one surface per storyboard drawing block, keyed by
  /// the block's [FrameId] exactly like the cell memo (R5): the ink rides
  /// its cell through splits, moves and repagination, saves with the
  /// project, and dies with the drawing.
  row,

  /// Paper-anchored ink over the whole page (header, margins, the hole's
  /// X) — one surface per page (`conte-page-p<n>`), the original plane.
  page,
}

/// Owns the conte's sheet ink (#16 — the conte panel is the timesheet's
/// canvas shell with conte content): brush strokes on the conte pages,
/// kept in coordinators/stores SEPARATE from the session's cel
/// [BrushFrameStore] so sheet ink can never leak into cel rendering or
/// export, committed through the app [HistoryManager] with the same
/// [BrushStrokeHistoryCommand] the drawing canvas uses.
///
/// TWO planes (R5 — the timesheet's page/strip pair, said in conte): the
/// row plane binds ink to its CELL (the user's contract: strokes belong to
/// the cell they start on, clipped to its band), the page plane keeps the
/// margins. The row/page stores may be handed in by the session so the
/// project archive can persist them ([BrushFrameStore] cels, the second
/// namespace).
class ConteInkController extends SheetInkController<ConteInkPlane> {
  ConteInkController({BrushFrameStore? rowStore, BrushFrameStore? pageStore})
    : this._(
        InkPlaneSlot(
          store: rowStore ?? BrushFrameStore(),
          initialFrameKey: _initKey,
        ),
        InkPlaneSlot(
          store: pageStore ?? BrushFrameStore(),
          initialFrameKey: _initKey,
        ),
      );

  ConteInkController._(this._row, this._page)
    : super({ConteInkPlane.row: _row, ConteInkPlane.page: _page});

  static const BrushFrameKey _initKey = BrushFrameKey(
    projectId: conteInkProjectId,
    trackId: conteInkTrackId,
    cutId: CutId('conte-ink-init'),
    layerId: conteInkPageLayerId,
    frameId: FrameId('conte-ink-init'),
  );

  /// Ink resolution multiplier over document space (the timesheet's 4×).
  static const int inkScale = 4;

  /// The key contract lives in models/conte/conte_ink_keys.dart (R5): the
  /// session's archive routing and the exporters read the same namespace.
  static BrushFrameKey pageKey(int page) => conteInkPageKey(page);

  static BrushFrameKey rowKey(CutId cutId, FrameId frameId) =>
      conteInkRowKey(cutId, frameId);

  final InkPlaneSlot _row;
  final InkPlaneSlot _page;

  /// One conte page of paper, at [inkScale].
  CanvasSize? get pageSurfaceSize => _page.size;

  /// One row-plane surface, at [inkScale]: the page BODY's size for every
  /// cell (the coordinator shares one geometry per plane). A cell's window
  /// exposes only its own band's slice — the tile-sparse store makes the
  /// unused remainder free, and a cell that GROWS (rowSpan) simply reveals
  /// more of the same surface with its ink intact.
  CanvasSize? get rowSurfaceSize => _row.size;

  /// Adopts the sheet geometry (every page shares one metrics). Never
  /// notifies: callers run this during build.
  void syncGeometry(ConteSheetMetrics metrics) {
    _page.syncTo(
      CanvasSize(
        width: (metrics.pageWidth * inkScale).ceil(),
        height: (metrics.pageHeight * inkScale).ceil(),
      ),
    );
    _row.syncTo(
      CanvasSize(
        width: (metrics.bodyWidth * inkScale).ceil(),
        height: (metrics.bodyHeight * inkScale).ceil(),
      ),
    );
  }
}

/// The ink windows for one page, bottom-of-stack first: page ink lies
/// under the row bands, so a stroke STARTING on a cell's band goes to that
/// cell and everything else (header, margins, the hole) goes to the paper.
/// A stroke keeps its start plane for its whole duration (pointer capture).
/// A cell with no drawing block carries no band window — ink belongs to
/// drawings ("그림 삭제 시 잉크 동반 삭제"), so a block-less cell offers
/// only the paper behind it.
List<SheetInkWindow> conteInkWindows(ContePageLayout page) {
  final metrics = page.metrics;
  return [
    SheetInkWindow(
      id: 'page-${page.pageIndex}',
      surfaceScale: ConteInkController.inkScale.toDouble(),
      plane: ConteInkPlane.page,
      key: ConteInkController.pageKey(page.pageIndex),
      documentRect: Rect.fromLTWH(0, 0, metrics.pageWidth, metrics.pageHeight),
    ),
    for (final cell in page.cells)
      if (cell.source.frameId != null)
        SheetInkWindow(
          id: 'row-${cell.cutId}-${cell.source.frameId!.value}',
          surfaceScale: ConteInkController.inkScale.toDouble(),
          plane: ConteInkPlane.row,
          key: ConteInkController.rowKey(
            CutId(cell.cutId),
            cell.source.frameId!,
          ),
          documentRect: cell.rowBandRect(metrics),
        ),
  ];
}

/// The conte's ink input/display stack: every window hosts the SAME
/// interactive brush view the drawing canvas uses, windowed onto its ink
/// surface by a derived viewport and clipped to its on-screen rect so
/// pointer-downs outside it fall through to the window below.
class ConteInkLayer extends StatelessWidget {
  const ConteInkLayer({
    super.key,
    required this.controller,
    required this.page,
    required this.brushToolState,
    required this.historyManager,
    required this.viewport,
    required this.strokeActive,
    this.cacheInvalidationSink,
  });

  final ConteInkController controller;

  /// The page ON SCREEN — its windows are mounted; the other pages'
  /// surfaces keep their ink, they just have no window.
  final ContePageLayout page;

  /// Forwarded to [SheetInkLayer.brushToolState] — heard, not handed over.
  final ValueListenable<BrushToolState> brushToolState;
  final HistoryManager historyManager;

  /// The live panel viewport (the same transform the page painter applies).
  final CanvasViewport viewport;

  /// Raised while any window has a stroke in progress, so the panel's
  /// gesture layer holds navigation exactly as it does for canvas strokes.
  final ValueNotifier<bool> strokeActive;

  final CacheInvalidationSink? cacheInvalidationSink;

  @override
  Widget build(BuildContext context) {
    return SheetInkLayer(
      windows: conteInkWindows(page),
      keyPrefix: 'conte',
      viewport: viewport,
      brushToolState: brushToolState,
      strokeActive: strokeActive,
      // The plane axis stays HERE, with the controller that has one.
      sessionStateFor: (window) => controller.sessionStateFor(
        window.plane! as ConteInkPlane,
        window.key,
      ),
      onStrokeCommitted: (window, strokeData) => controller.commitStroke(
        plane: window.plane! as ConteInkPlane,
        key: window.key,
        strokeData: strokeData,
        historyManager: historyManager,
        cacheInvalidationSink: cacheInvalidationSink,
      ),
    );
  }
}
