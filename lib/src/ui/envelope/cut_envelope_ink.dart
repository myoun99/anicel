import 'dart:ui' show Rect;

import 'package:flutter/foundation.dart';

import '../../models/brush_edit_session_state.dart';
import '../../models/brush_frame_key.dart';
import '../../models/brush_history_policy.dart';
import '../../models/canvas_size.dart';
import '../../models/canvas_viewport.dart';
import '../../models/cut_id.dart';
import '../../models/envelope/cut_envelope_ink_keys.dart';
import '../../models/envelope/cut_envelope_layout.dart';
import '../../models/frame_id.dart';
import '../../services/brush_frame_edit_session_store.dart';
import '../../services/brush_frame_editing_coordinator.dart';
import '../../services/brush_frame_store.dart';
import '../../services/brush_stroke_commit_data.dart';
import '../../services/cache_invalidation_executor.dart';
import '../../services/commands/brush_stroke_history_command.dart';
import '../../services/history_manager.dart';

/// Owns the envelope's ink: brush strokes on a cut envelope, kept in a
/// store fully SEPARATE from the session's cel [BrushFrameStore] so sheet
/// ink can never leak into cel rendering or export. Strokes commit through
/// the app [HistoryManager] with the same command the drawing canvas uses,
/// so undo behaves identically.
///
/// ONE plane, unlike the timesheet's and conte's pair: an envelope has no
/// page plane because it has no margin — its boxes meet, and every stroke
/// belongs to the box it started in. A box that stops existing takes its
/// ink with it, which is exactly the contract that removes stray
/// annotations from a form the user re-shapes.
class CutEnvelopeInkController extends ChangeNotifier {
  CutEnvelopeInkController({BrushFrameStore? store})
    : _store = store ?? BrushFrameStore();

  /// Ink resolution multiplier over form space — the timesheet's 4×.
  /// Affordable because the live-stroke rasterizer is tile-sparse: cost
  /// scales with the ink drawn, never with the surface size.
  static const int inkScale = 4;

  final BrushFrameStore _store;
  BrushFrameEditingCoordinator? _coordinator;

  /// One box surface's size, at [inkScale]. Every box in the plane shares
  /// one geometry (the coordinator's rule) and each box's window exposes
  /// its own slice; the tile-sparse store makes the remainder free.
  CanvasSize? get surfaceSize => _surfaceSize;
  CanvasSize? _surfaceSize;

  /// Adopts the paper geometry. Geometry changes rebuild the ink session
  /// from its durable commands with stroke coordinates preserved
  /// (top-left anchored, like a canvas resize).
  ///
  /// Never notifies: callers run this during build.
  void syncGeometry({required double paperWidth, required double paperHeight}) {
    final size = CanvasSize(
      width: (paperWidth * inkScale).ceil().clamp(1, 1 << 16),
      height: (paperHeight * inkScale).ceil().clamp(1, 1 << 16),
    );
    if (_coordinator == null || size != _surfaceSize) {
      _surfaceSize = size;
      _coordinator = _syncCoordinator(_coordinator, size);
    }
  }

  BrushFrameEditingCoordinator _syncCoordinator(
    BrushFrameEditingCoordinator? coordinator,
    CanvasSize canvasSize,
  ) {
    if (coordinator != null) {
      // Dedicated single-canvas ink store: every box surface shares one
      // geometry, so the whole-store resize is the right one here.
      coordinator.resizeCanvasAllCuts(canvasSize);
      return coordinator;
    }
    return BrushFrameEditingCoordinator(
      // A sentinel key; every real access selects its own box key.
      initialFrameKey: const BrushFrameKey(
        projectId: envelopeInkProjectId,
        trackId: envelopeInkTrackId,
        cutId: CutId('envelope-ink-init'),
        layerId: envelopeInkLayerId,
        frameId: FrameId('envelope-ink-init'),
      ),
      frameStore: _store,
      sessionStore: BrushFrameEditSessionStore(canvasSize: canvasSize),
      historyPolicy: const BrushHistoryPolicy(
        userUndoLimit: 24,
        deferredBakeRatio: 0,
      ),
    );
  }

  BrushFrameEditingCoordinator get _required {
    final coordinator = _coordinator;
    if (coordinator == null) {
      throw StateError('syncGeometry must run before ink access.');
    }
    return coordinator;
  }

  /// The session surface for one box (created blank on first access).
  BrushEditSessionState sessionStateFor(BrushFrameKey key) {
    final coordinator = _required;
    coordinator.selectFrame(key);
    return coordinator.activeSessionState;
  }

  /// Commits a finished stroke through the app history — one undo step,
  /// exactly like a canvas stroke.
  void commitStroke({
    required BrushFrameKey key,
    required BrushStrokeCommitData strokeData,
    required HistoryManager historyManager,
    CacheInvalidationSink? cacheInvalidationSink,
  }) {
    final coordinator = _required;
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

  /// Whether a box holds any ink (test/debug oracle — the baked raster is
  /// the content, so "count" collapses to has-content).
  bool hasInkFor(BrushFrameKey key) => _store.celHasRenderableContent(key);
}

/// One box's ink window: where its strokes live and where they land.
class EnvelopeInkWindow {
  const EnvelopeInkWindow({
    required this.boxId,
    required this.key,
    required this.documentRect,
  });

  final String boxId;
  final BrushFrameKey key;

  /// The box's rect in PAPER space.
  final Rect documentRect;

  /// Surface pixel (0,0) maps to the box's TOP-LEFT, not the paper's.
  ///
  /// That is what makes ink survive a form change: a box that moves or
  /// grows carries its strokes with it, the way a conte cell keeps its
  /// annotation through repagination. Anchoring to the paper instead would
  /// leave the marks behind whenever a preset shifted a cell.
  CanvasViewport inkViewport(CanvasViewport panelViewport) {
    return CanvasViewport(
      zoom: panelViewport.zoom / CutEnvelopeInkController.inkScale,
      panX: panelViewport.panX + panelViewport.zoom * documentRect.left,
      panY: panelViewport.panY + panelViewport.zoom * documentRect.top,
    );
  }

  /// The window's on-screen rect under the panel transform — the input hit
  /// region and the display clip.
  Rect screenRect(CanvasViewport panelViewport) {
    return Rect.fromLTWH(
      panelViewport.panX + panelViewport.zoom * documentRect.left,
      panelViewport.panY + panelViewport.zoom * documentRect.top,
      panelViewport.zoom * documentRect.width,
      panelViewport.zoom * documentRect.height,
    );
  }
}

/// The envelope's ink windows, bottom-of-stack first.
///
/// One per box that takes ink, in FORM order — so a box drawn later (an
/// inner cell over the one it sits on) is hit first, matching
/// [CutEnvelopeLayout.inkBoxAt]. There is no page window: the form has no
/// margin, its cells meet, and a stroke that starts outside every inking
/// box simply has nowhere to go.
List<EnvelopeInkWindow> envelopeInkWindows(
  CutEnvelopeLayout layout,
  CutId ownerCutId,
) {
  return [
    for (final placed in layout.placedBoxes)
      if (placed.box.takesInk)
        EnvelopeInkWindow(
          boxId: placed.box.id,
          key: envelopeInkBoxKey(ownerCutId, placed.box.id),
          documentRect: Rect.fromLTWH(
            placed.x,
            placed.y,
            placed.width,
            placed.height,
          ),
        ),
  ];
}
