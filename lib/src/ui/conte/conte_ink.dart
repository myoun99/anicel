import 'package:flutter/material.dart';

import '../../models/brush_edit_session_state.dart';
import '../../models/brush_frame_key.dart';
import '../../models/brush_history_policy.dart';
import '../../models/canvas_size.dart';
import '../../models/canvas_viewport.dart';
import '../../models/cut_id.dart';
import '../../models/frame_id.dart';
import '../../models/layer_id.dart';
import '../../models/project_id.dart';
import '../../models/track_id.dart';
import '../../services/brush_frame_edit_session_store.dart';
import '../../services/brush_frame_editing_coordinator.dart';
import '../../services/brush_frame_store.dart';
import '../../services/brush_stroke_commit_data.dart';
import '../../services/cache_invalidation_executor.dart';
import '../../services/commands/brush_stroke_history_command.dart';
import '../../services/history_manager.dart';
import '../brush/brush_tool_state.dart';
import '../canvas/interactive_brush_edit_canvas_view.dart';

/// Owns the conte's sheet ink (#16 — the conte panel is the timesheet's
/// canvas shell with conte content): brush strokes on the conte pages,
/// kept in a coordinator/store fully SEPARATE from the session's cel
/// [BrushFrameStore], committed through the app [HistoryManager] with the
/// same [BrushStrokeHistoryCommand] the drawing canvas uses.
///
/// ONE plane — the conte page is one sheet of paper, so ink is
/// paper-anchored per page (`conte-page-p<n>`). The timesheet's second,
/// frame-anchored strip plane has no conte counterpart: conte cells are
/// pictures, not frame rows.
class ConteInkController extends ChangeNotifier {
  /// Ink resolution multiplier over document space (the timesheet's 4×).
  static const int inkScale = 4;

  /// The ink store is namespaced by these synthetic ids; they only need
  /// to be unique inside the controller's own store. The conte spans the
  /// PROJECT, so unlike the timesheet the keys carry no real CutId.
  static const ProjectId inkProjectId = ProjectId('conte-ink');
  static const TrackId inkTrackId = TrackId('conte-ink');
  static const CutId inkCutId = CutId('conte-ink');
  static const LayerId pageLayerId = LayerId('conte-page');

  static BrushFrameKey pageKey(int page) {
    return BrushFrameKey(
      projectId: inkProjectId,
      trackId: inkTrackId,
      cutId: inkCutId,
      layerId: pageLayerId,
      frameId: FrameId('conte-page-p$page'),
    );
  }

  final BrushFrameStore _store = BrushFrameStore();
  BrushFrameEditingCoordinator? _coordinator;

  /// One conte page of paper, at [inkScale].
  CanvasSize? get pageSurfaceSize => _pageSize;
  CanvasSize? _pageSize;

  /// Adopts the page geometry (every conte page shares one size). Never
  /// notifies: callers run this during build.
  void syncGeometry({required double pageWidth, required double pageHeight}) {
    final pageSize = CanvasSize(
      width: (pageWidth * inkScale).ceil(),
      height: (pageHeight * inkScale).ceil(),
    );
    if (_coordinator != null && pageSize == _pageSize) {
      return;
    }
    _pageSize = pageSize;
    final coordinator = _coordinator;
    if (coordinator != null) {
      // Dedicated single-canvas ink store: the whole-store resize is the
      // right one here (the timesheet ink planes' rule).
      coordinator.resizeCanvasAllCuts(pageSize);
      return;
    }
    _coordinator = BrushFrameEditingCoordinator(
      // A sentinel key; every real access selects its own page key.
      initialFrameKey: BrushFrameKey(
        projectId: inkProjectId,
        trackId: inkTrackId,
        cutId: const CutId('conte-ink-init'),
        layerId: pageLayerId,
        frameId: const FrameId('conte-ink-init'),
      ),
      frameStore: _store,
      sessionStore: BrushFrameEditSessionStore(canvasSize: pageSize),
      historyPolicy: const BrushHistoryPolicy(
        userUndoLimit: 24,
        deferredBakeRatio: 0,
      ),
    );
  }

  BrushFrameEditingCoordinator get _requireCoordinator {
    final coordinator = _coordinator;
    if (coordinator == null) {
      throw StateError('syncGeometry must run before ink access.');
    }
    return coordinator;
  }

  /// The session surface for one page (created blank on first access).
  BrushEditSessionState sessionStateFor(BrushFrameKey key) {
    final coordinator = _requireCoordinator;
    coordinator.selectFrame(key);
    return coordinator.activeSessionState;
  }

  /// Commits a finished sheet stroke through the app history (one undo
  /// step, exactly like a canvas stroke).
  void commitStroke({
    required BrushFrameKey key,
    required BrushStrokeCommitData strokeData,
    required HistoryManager historyManager,
    CacheInvalidationSink? cacheInvalidationSink,
  }) {
    final coordinator = _requireCoordinator;
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

  /// Whether the page cel holds any ink (test/debug oracle).
  bool hasInkFor(BrushFrameKey key) => _store.celHasRenderableContent(key);
}

/// The conte's ink input/display layer: ONE window over the visible page,
/// hosting the same interactive brush view the drawing canvas uses. The
/// page sits at the document origin (document space IS page space in the
/// conte shell), so the ink viewport is the panel transform over the ink
/// scale.
class ConteInkLayer extends StatelessWidget {
  const ConteInkLayer({
    super.key,
    required this.controller,
    required this.page,
    required this.pageWidth,
    required this.pageHeight,
    required this.brushToolState,
    required this.historyManager,
    required this.viewport,
    required this.strokeActive,
    this.cacheInvalidationSink,
  });

  final ConteInkController controller;

  /// The page ON SCREEN — its surface is the window; the other pages'
  /// surfaces keep their ink, they just have no window.
  final int page;

  /// The page's document-space size (the display clip: strokes must not
  /// land on the pasteboard outside the paper).
  final double pageWidth;
  final double pageHeight;

  final BrushToolState brushToolState;
  final HistoryManager historyManager;

  /// The live panel viewport (the same transform the page painter applies).
  final CanvasViewport viewport;

  /// Raised while a stroke is in progress, so the panel's gesture layer
  /// holds navigation exactly as it does for canvas strokes.
  final ValueNotifier<bool> strokeActive;

  final CacheInvalidationSink? cacheInvalidationSink;

  @override
  Widget build(BuildContext context) {
    final key = ConteInkController.pageKey(page);
    final inkZoom = viewport.zoom / ConteInkController.inkScale;
    return ClipRect(
      // The page's on-screen rect (the paper sits at the document origin):
      // pointer-downs outside the paper fall through, the timesheet
      // window's clip rule.
      clipper: _PageRectClipper(
        Rect.fromLTWH(
          viewport.panX,
          viewport.panY,
          viewport.zoom * pageWidth,
          viewport.zoom * pageHeight,
        ),
      ),
      child: RepaintBoundary(
        child: InteractiveBrushEditCanvasView(
          // A STABLE key: a page turn changes [frameId] and flows through
          // the view's in-place reset (which also drops an in-flight
          // stroke's active flag) — a per-page key remounted the view and
          // a mid-stroke turn left the nav/warm hold pinned.
          key: const ValueKey<String>('conte-ink-view'),
          sessionState: controller.sessionStateFor(key),
          layerId: key.layerId,
          frameId: key.frameId,
          inputSettings: brushToolState.toInputSettings(),
          // Ink pixel (x, y) lands exactly where the page paints: the
          // panel transform over the ink scale (the timesheet window math
          // with the window at the document origin).
          viewport: CanvasViewport(
            zoom: inkZoom,
            panX: viewport.panX,
            panY: viewport.panY,
          ),
          // The conte paper is painted below this layer; an opaque
          // background here would cover it.
          showTransparentBackground: false,
          onActiveStrokeChanged: (active) {
            strokeActive.value = active;
          },
          onSourceStrokeCommitted: (strokeData) {
            controller.commitStroke(
              key: key,
              strokeData: strokeData,
              historyManager: historyManager,
              cacheInvalidationSink: cacheInvalidationSink,
            );
          },
        ),
      ),
    );
  }
}

class _PageRectClipper extends CustomClipper<Rect> {
  const _PageRectClipper(this.rect);

  final Rect rect;

  @override
  Rect getClip(Size size) => rect;

  @override
  bool shouldReclip(covariant _PageRectClipper oldClipper) =>
      oldClipper.rect != rect;
}
