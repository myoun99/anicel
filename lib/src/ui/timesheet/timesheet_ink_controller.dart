import 'package:flutter/foundation.dart';

import '../../models/brush_edit_session_state.dart';
import '../../models/brush_frame_key.dart';
import '../../models/canvas_size.dart';
import '../../models/cut_id.dart';
import '../../models/frame_id.dart';
import '../../models/layer_id.dart';
import '../../models/project_id.dart';
import '../../models/track_id.dart';
import '../../services/brush_frame_editing_coordinator.dart';
import '../../services/brush_frame_store.dart';
import '../../services/brush_stroke_commit_data.dart';
import '../../services/cache_invalidation_executor.dart';
import '../../services/commands/brush_stroke_history_command.dart';
import '../../services/history_manager.dart';
import '../sheet/sheet_ink_controller.dart';
import 'timesheet_document_painter.dart';

/// Which sheet ink plane a stroke lands on.
enum TimesheetInkPlane {
  /// Frame-anchored ink over the half's column area: X = within-half
  /// offset, Y = frame row axis. One surface per PAGE BAND of frames
  /// (`sheet-strip-<cut>-b<n>`), so annotations follow their frames and
  /// switch losslessly between the paged and continuous views.
  strip,

  /// Paper-anchored ink over the whole page (header fields, Direction
  /// memo band, margins) — one surface per page
  /// (`sheet-page-<cut>-p<n>`); the continuous view shows page 1's in its
  /// identical header geometry.
  page,
}

/// Owns the sheet ink stores: brush strokes on the timesheet, kept in
/// coordinators/stores fully SEPARATE from the session's cel
/// [BrushFrameStore] so sheet ink can never leak into cel rendering or
/// export. Strokes commit through the app [HistoryManager] with the same
/// [BrushStrokeHistoryCommand] the drawing canvas uses (undo parity), and
/// erase reuses the same blend routes untouched.
class TimesheetInkController extends ChangeNotifier {
  /// Ink resolution multiplier over document space (72px per frame row —
  /// the plan's 4×). Affordable because the live-stroke rasterizer is
  /// tile-sparse: stroke cost scales with the ink actually drawn, never
  /// with the logical surface size.
  static const int inkScale = 4;

  /// The ink store is namespaced by these synthetic ids; they only need to
  /// be unique inside the controller's own stores.
  static const ProjectId inkProjectId = ProjectId('timesheet-ink');
  static const TrackId inkTrackId = TrackId('timesheet-ink');
  static const LayerId stripLayerId = LayerId('sheet-strip');
  static const LayerId pageLayerId = LayerId('sheet-page');

  static BrushFrameKey stripBandKey(CutId cutId, int band) {
    return BrushFrameKey(
      projectId: inkProjectId,
      trackId: inkTrackId,
      cutId: cutId,
      layerId: stripLayerId,
      frameId: FrameId('sheet-strip-${cutId.value}-b$band'),
    );
  }

  static BrushFrameKey pageKey(CutId cutId, int page) {
    return BrushFrameKey(
      projectId: inkProjectId,
      trackId: inkTrackId,
      cutId: cutId,
      layerId: pageLayerId,
      frameId: FrameId('sheet-page-${cutId.value}-p$page'),
    );
  }

  final BrushFrameStore _stripStore = BrushFrameStore();
  final BrushFrameStore _pageStore = BrushFrameStore();
  BrushFrameEditingCoordinator? _strip;
  BrushFrameEditingCoordinator? _page;

  /// One page band of frame rows × the half column width, at [inkScale].
  CanvasSize? get stripBandSurfaceSize => _stripBandSize;
  CanvasSize? _stripBandSize;

  /// The whole PAGED paper, at [inkScale].
  CanvasSize? get pageSurfaceSize => _pageSize;
  CanvasSize? _pageSize;

  /// Adopts the sheet geometry from the PAGED layout (both view modes
  /// share it — the paper never resizes with the view toggle). Geometry
  /// changes rebuild the ink sessions from their durable commands with
  /// stroke coordinates preserved (top-left anchored, like canvas resize).
  ///
  /// Never notifies: callers run this during build.
  void syncGeometry(TimesheetDocumentLayout pagedLayout) {
    final document = pagedLayout.document;
    final stripBandSize = CanvasSize(
      width: (pagedLayout.halfWidth * inkScale).ceil(),
      height:
          (document.pageFrameCount * TimesheetDocumentLayout.rowHeight).ceil() *
          inkScale,
    );
    final pageSize = CanvasSize(
      width: (pagedLayout.paperWidth * inkScale).ceil(),
      height: (pagedLayout.paperHeight * inkScale).ceil(),
    );

    if (_strip == null || stripBandSize != _stripBandSize) {
      _stripBandSize = stripBandSize;
      _strip = _syncCoordinator(_strip, _stripStore, stripBandSize);
    }
    if (_page == null || pageSize != _pageSize) {
      _pageSize = pageSize;
      _page = _syncCoordinator(_page, _pageStore, pageSize);
    }
  }

  BrushFrameEditingCoordinator _syncCoordinator(
    BrushFrameEditingCoordinator? coordinator,
    BrushFrameStore store,
    CanvasSize canvasSize,
  ) => inkCoordinatorSynced(
    coordinator,
    store: store,
    canvasSize: canvasSize,
    initialFrameKey: const BrushFrameKey(
      projectId: inkProjectId,
      trackId: inkTrackId,
      cutId: CutId('timesheet-ink-init'),
      layerId: stripLayerId,
      frameId: FrameId('timesheet-ink-init'),
    ),
  );

  BrushFrameEditingCoordinator _coordinatorFor(TimesheetInkPlane plane) {
    final coordinator = plane == TimesheetInkPlane.strip ? _strip : _page;
    if (coordinator == null) {
      throw StateError('syncGeometry must run before ink access.');
    }
    return coordinator;
  }

  /// The session surface for one band/page window (created blank on first
  /// access).
  BrushEditSessionState sessionStateFor(
    TimesheetInkPlane plane,
    BrushFrameKey key,
  ) {
    final coordinator = _coordinatorFor(plane);
    coordinator.selectFrame(key);
    return coordinator.activeSessionState;
  }

  /// Commits a finished sheet stroke through the app history (one undo
  /// step, exactly like a canvas stroke).
  void commitStroke({
    required TimesheetInkPlane plane,
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

  /// Whether the band/page cel holds any ink (test/debug oracle — R19
  /// P3b: the baked raster is the content; undo restores surfaces, so
  /// "count" collapses to has-content).
  bool hasInkFor(TimesheetInkPlane plane, BrushFrameKey key) {
    final store = plane == TimesheetInkPlane.strip ? _stripStore : _pageStore;
    return store.celHasRenderableContent(key);
  }
}
