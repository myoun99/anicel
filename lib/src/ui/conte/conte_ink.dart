import 'dart:async' show unawaited;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../models/bitmap_surface.dart';
import '../../models/brush_edit_session_state.dart';
import '../../models/brush_frame_key.dart';
import '../../models/brush_history_policy.dart';
import '../../models/canvas_size.dart';
import '../../models/canvas_viewport.dart';
import '../../models/conte/conte_ink_keys.dart';
import '../../models/conte/conte_sheet_layout.dart';
import '../../models/cut_id.dart';
import '../../models/frame_id.dart';
import '../../services/brush_frame_edit_session_store.dart';
import '../../services/brush_frame_editing_coordinator.dart';
import '../../services/brush_frame_store.dart';
import '../../services/brush_stroke_commit_data.dart';
import '../../services/cache_invalidation_executor.dart';
import '../../services/commands/brush_stroke_history_command.dart';
import '../../services/history_manager.dart';
import '../brush/brush_tool_state.dart';
import '../canvas/bitmap_tile_image_cache.dart';
import '../canvas/interactive_brush_edit_canvas_view.dart';
import '../canvas/tiled_surface_compose.dart';

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
class ConteInkController extends ChangeNotifier {
  ConteInkController({BrushFrameStore? rowStore, BrushFrameStore? pageStore})
    : _rowStore = rowStore ?? BrushFrameStore(),
      _pageStore = pageStore ?? BrushFrameStore();

  /// Ink resolution multiplier over document space (the timesheet's 4×).
  static const int inkScale = 4;

  /// The key contract lives in models/conte/conte_ink_keys.dart (R5): the
  /// session's archive routing and the exporters read the same namespace.
  static BrushFrameKey pageKey(int page) => conteInkPageKey(page);

  static BrushFrameKey rowKey(CutId cutId, FrameId frameId) =>
      conteInkRowKey(cutId, frameId);

  final BrushFrameStore _rowStore;
  final BrushFrameStore _pageStore;
  BrushFrameEditingCoordinator? _row;
  BrushFrameEditingCoordinator? _page;

  /// One conte page of paper, at [inkScale].
  CanvasSize? get pageSurfaceSize => _pageSize;
  CanvasSize? _pageSize;

  /// One row-plane surface, at [inkScale]: the page BODY's size for every
  /// cell (the coordinator shares one geometry per plane). A cell's window
  /// exposes only its own band's slice — the tile-sparse store makes the
  /// unused remainder free, and a cell that GROWS (rowSpan) simply reveals
  /// more of the same surface with its ink intact.
  CanvasSize? get rowSurfaceSize => _rowSize;
  CanvasSize? _rowSize;

  /// Adopts the sheet geometry (every page shares one metrics). Never
  /// notifies: callers run this during build.
  void syncGeometry(ConteSheetMetrics metrics) {
    final pageSize = CanvasSize(
      width: (metrics.pageWidth * inkScale).ceil(),
      height: (metrics.pageHeight * inkScale).ceil(),
    );
    final rowSize = CanvasSize(
      width: (metrics.bodyWidth * inkScale).ceil(),
      height: (metrics.bodyHeight * inkScale).ceil(),
    );
    if (_page == null || pageSize != _pageSize) {
      _pageSize = pageSize;
      _page = _syncCoordinator(_page, _pageStore, pageSize);
    }
    if (_row == null || rowSize != _rowSize) {
      _rowSize = rowSize;
      _row = _syncCoordinator(_row, _rowStore, rowSize);
    }
  }

  BrushFrameEditingCoordinator _syncCoordinator(
    BrushFrameEditingCoordinator? coordinator,
    BrushFrameStore store,
    CanvasSize canvasSize,
  ) {
    if (coordinator != null) {
      // Dedicated single-canvas ink store: every surface in the plane
      // shares one geometry, so the whole-store resize is the right one.
      coordinator.resizeCanvasAllCuts(canvasSize);
      return coordinator;
    }
    return BrushFrameEditingCoordinator(
      // A sentinel key; every real access selects its own window key.
      initialFrameKey: BrushFrameKey(
        projectId: conteInkProjectId,
        trackId: conteInkTrackId,
        cutId: const CutId('conte-ink-init'),
        layerId: conteInkPageLayerId,
        frameId: const FrameId('conte-ink-init'),
      ),
      frameStore: store,
      sessionStore: BrushFrameEditSessionStore(canvasSize: canvasSize),
      historyPolicy: const BrushHistoryPolicy(
        userUndoLimit: 24,
        deferredBakeRatio: 0,
      ),
    );
  }

  BrushFrameEditingCoordinator _coordinatorFor(ConteInkPlane plane) {
    final coordinator = plane == ConteInkPlane.row ? _row : _page;
    if (coordinator == null) {
      throw StateError('syncGeometry must run before ink access.');
    }
    return coordinator;
  }

  BrushFrameStore _storeFor(ConteInkPlane plane) =>
      plane == ConteInkPlane.row ? _rowStore : _pageStore;

  /// The session surface for one window (created blank on first access).
  BrushEditSessionState sessionStateFor(ConteInkPlane plane, BrushFrameKey key) {
    final coordinator = _coordinatorFor(plane);
    coordinator.selectFrame(key);
    return coordinator.activeSessionState;
  }

  /// Commits a finished sheet stroke through the app history (one undo
  /// step, exactly like a canvas stroke).
  void commitStroke({
    required ConteInkPlane plane,
    required BrushFrameKey key,
    required BrushStrokeCommitData strokeData,
    required HistoryManager historyManager,
    CacheInvalidationSink? cacheInvalidationSink,
  }) {
    final coordinator = _coordinatorFor(plane);
    coordinator.selectFrame(key);
    historyManager.execute(
      BrushStrokeHistoryCommand(
        coordinator: coordinator,
        strokeData: strokeData,
        cacheInvalidationSink: cacheInvalidationSink,
      ),
    );
    notifyListeners();
  }

  /// Whether the window's cel holds any ink (display gate + test oracle).
  bool hasInkFor(ConteInkPlane plane, BrushFrameKey key) =>
      _storeFor(plane).celHasRenderableContent(key);

  /// Painter-side display images, composed lazily from the baked
  /// surfaces and invalidated by SURFACE IDENTITY: strokes, undo and redo
  /// all replace the baked surface object, so staleness is structural —
  /// no invalidation wiring. The page painter draws these so saved ink
  /// shows with the ink mode OFF (and the PNG export inherits it free);
  /// a key with a LIVE input window is skipped by the caller instead
  /// (the interactive view already shows that surface).
  ui.Image? displayImageFor(ConteInkPlane plane, BrushFrameKey key) {
    final surface = _storeFor(plane).bakedSurfaceOrNull(key);
    if (surface == null) {
      return null;
    }
    final cached = _display[key];
    if (cached != null && identical(cached.$1, surface)) {
      return cached.$2;
    }
    final image = composeTiledSurfaceImageSyncOrNull(
      surface,
      reuse: BitmapTileImageCache.instance,
    );
    if (image != null) {
      cached?.$2.dispose();
      _display[key] = (surface, image);
      return image;
    }
    // Tile images not GPU-resident yet: compose async once, repaint via
    // notify; the stale image holds meanwhile (the playback policy).
    if (_composing.add(key)) {
      unawaited(
        composeTiledSurfaceImage(
          surface,
          reuse: BitmapTileImageCache.instance,
        ).then((composed) {
          _composing.remove(key);
          if (composed == null) {
            return;
          }
          if (!identical(_storeFor(plane).bakedSurfaceOrNull(key), surface)) {
            composed.dispose();
            return;
          }
          _display[key]?.$2.dispose();
          _display[key] = (surface, composed);
          notifyListeners();
        }),
      );
    }
    return cached?.$2;
  }

  final Map<BrushFrameKey, (BitmapSurface, ui.Image)> _display = {};
  final Set<BrushFrameKey> _composing = {};

  @override
  void dispose() {
    for (final entry in _display.values) {
      entry.$2.dispose();
    }
    _display.clear();
    super.dispose();
  }
}

/// One conte ink window: a page-local rect that shows (and draws into) a
/// region of an ink surface — the timesheet window model verbatim.
class ConteInkWindow {
  const ConteInkWindow({
    required this.id,
    required this.plane,
    required this.key,
    required this.documentRect,
  });

  final String id;
  final ConteInkPlane plane;
  final BrushFrameKey key;

  /// The window's rect in PAGE document space (the conte shell shows one
  /// page at the document origin).
  final Rect documentRect;

  /// Surface pixel (0,0) maps to [documentRect]'s top-left for every conte
  /// window (fresh surface per cell/page), so the ink viewport is the
  /// panel transform composed with the window placement over the scale.
  CanvasViewport inkViewport(CanvasViewport panelViewport) {
    final inkZoom = panelViewport.zoom / ConteInkController.inkScale;
    return CanvasViewport(
      zoom: inkZoom,
      panX: panelViewport.panX + panelViewport.zoom * documentRect.left,
      panY: panelViewport.panY + panelViewport.zoom * documentRect.top,
    );
  }

  /// The window's on-screen rect under the panel transform (the input hit
  /// region and display clip).
  Rect screenRect(CanvasViewport panelViewport) {
    return Rect.fromLTWH(
      panelViewport.panX + panelViewport.zoom * documentRect.left,
      panelViewport.panY + panelViewport.zoom * documentRect.top,
      panelViewport.zoom * documentRect.width,
      panelViewport.zoom * documentRect.height,
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
List<ConteInkWindow> conteInkWindows(ContePageLayout page) {
  final metrics = page.metrics;
  return [
    ConteInkWindow(
      id: 'page-${page.pageIndex}',
      plane: ConteInkPlane.page,
      key: ConteInkController.pageKey(page.pageIndex),
      documentRect: Rect.fromLTWH(0, 0, metrics.pageWidth, metrics.pageHeight),
    ),
    for (final cell in page.cells)
      if (cell.source.frameId != null)
        ConteInkWindow(
          id: 'row-${cell.cutId}-${cell.source.frameId!.value}',
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

  final BrushToolState brushToolState;
  final HistoryManager historyManager;

  /// The live panel viewport (the same transform the page painter applies).
  final CanvasViewport viewport;

  /// Raised while any window has a stroke in progress, so the panel's
  /// gesture layer holds navigation exactly as it does for canvas strokes.
  final ValueNotifier<bool> strokeActive;

  final CacheInvalidationSink? cacheInvalidationSink;

  @override
  Widget build(BuildContext context) {
    final windows = conteInkWindows(page);
    final inputSettings = brushToolState.toInputSettings();
    return Stack(
      children: [
        for (final window in windows)
          Positioned.fill(
            child: ClipRect(
              clipper: _WindowRectClipper(window.screenRect(viewport)),
              child: RepaintBoundary(
                child: InteractiveBrushEditCanvasView(
                  key: ValueKey<String>('conte-ink-${window.id}'),
                  sessionState: controller.sessionStateFor(
                    window.plane,
                    window.key,
                  ),
                  layerId: window.key.layerId,
                  frameId: window.key.frameId,
                  inputSettings: inputSettings,
                  viewport: window.inkViewport(viewport),
                  // The conte paper is painted below this stack; an opaque
                  // background here would cover it.
                  showTransparentBackground: false,
                  onActiveStrokeChanged: (active) {
                    strokeActive.value = active;
                  },
                  onSourceStrokeCommitted: (strokeData) {
                    controller.commitStroke(
                      plane: window.plane,
                      key: window.key,
                      strokeData: strokeData,
                      historyManager: historyManager,
                      cacheInvalidationSink: cacheInvalidationSink,
                    );
                  },
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _WindowRectClipper extends CustomClipper<Rect> {
  const _WindowRectClipper(this.rect);

  final Rect rect;

  @override
  Rect getClip(Size size) => rect;

  @override
  bool shouldReclip(covariant _WindowRectClipper oldClipper) =>
      oldClipper.rect != rect;
}
