import 'dart:async' show unawaited;
import 'dart:ui' as ui show Image;
import 'dart:ui' show Rect, Size;

import 'package:flutter/foundation.dart';

import '../../models/bitmap_surface.dart';
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
import '../canvas/bitmap_tile_image_cache.dart';
import '../canvas/tiled_surface_compose.dart';

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

  final BrushFrameStore _store;
  BrushFrameEditingCoordinator? _coordinator;

  /// One box surface's size, in FORM space at [envelopeInkSurfaceWidth].
  /// Every box in the plane shares one geometry (the coordinator's rule)
  /// and each box's window exposes its own slice; the tile-sparse store
  /// makes the remainder free.
  CanvasSize? get surfaceSize => _surfaceSize;
  CanvasSize? _surfaceSize;

  /// Adopts the FORM's geometry — deliberately not the paper's.
  ///
  /// The panel prints on the cut's canvas, the export may print on a real
  /// 봉투, and the next cut's canvas is a different size again; keying the
  /// surface to any of those would shift yesterday's handwriting every time
  /// one changed. The form's aspect ratio is the one thing all of them
  /// share, so that is what the ink is measured in.
  ///
  /// A geometry change (the user picks another preset) rebuilds the ink
  /// session from its durable commands with stroke coordinates preserved
  /// — top-left anchored, like a canvas resize.
  ///
  /// Never notifies: callers run this during build.
  void syncGeometry({required double aspectRatio}) {
    final ratio = aspectRatio <= 0 ? 1.0 : aspectRatio;
    final size = CanvasSize(
      width: envelopeInkSurfaceWidth.ceil(),
      height: (envelopeInkSurfaceWidth / ratio).ceil().clamp(1, 1 << 16),
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

  /// The painter-side display image for a box, composed lazily from the
  /// baked surface and invalidated by SURFACE IDENTITY: strokes, undo and
  /// redo all replace the baked surface object, so staleness is structural
  /// and needs no invalidation wiring (the conte's rule).
  ///
  /// This is what makes saved ink visible at all: only a handful of boxes
  /// are ever MOUNTED as input windows ([mountedEnvelopeInkWindows]), so
  /// without the painter drawing the rest, everything written in a cell
  /// would vanish the moment that cell got small or scrolled away. A key
  /// whose window IS live is skipped by the caller instead — the
  /// interactive view already shows that surface.
  ui.Image? displayImageFor(BrushFrameKey key) {
    final surface = _store.bakedSurfaceOrNull(key);
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
    // Tile images not GPU-resident yet: compose async once and repaint via
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
          // The panel can close while a compose is in flight — a notify
          // then would throw, and the image would leak.
          if (_disposed ||
              !identical(_store.bakedSurfaceOrNull(key), surface)) {
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
  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    for (final entry in _display.values) {
      entry.$2.dispose();
    }
    _display.clear();
    super.dispose();
  }
}

/// One box's ink window: where its strokes live and where they land.
class EnvelopeInkWindow {
  const EnvelopeInkWindow({
    required this.boxId,
    required this.key,
    required this.documentRect,
    required this.surfaceScale,
  });

  final String boxId;
  final BrushFrameKey key;

  /// The box's rect in PAPER space.
  final Rect documentRect;

  /// Ink surface pixels per paper unit ([CutEnvelopeLayout.inkSurfaceScale])
  /// — the whole reason a stroke stays put when the paper changes size.
  final double surfaceScale;

  /// The box's slice of the shared surface, in surface pixels.
  Rect get surfaceRect => Rect.fromLTWH(
    0,
    0,
    documentRect.width * surfaceScale,
    documentRect.height * surfaceScale,
  );

  /// Surface pixel (0,0) maps to the box's TOP-LEFT, not the paper's.
  ///
  /// That is what makes ink survive a form change: a box that moves or
  /// grows carries its strokes with it, the way a conte cell keeps its
  /// annotation through repagination. Anchoring to the paper instead would
  /// leave the marks behind whenever a preset shifted a cell.
  CanvasViewport inkViewport(CanvasViewport panelViewport) {
    return CanvasViewport(
      zoom: panelViewport.zoom / surfaceScale,
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

/// The windows worth MOUNTING right now.
///
/// The analog preset has 86 inking boxes — eight times a conte page — and
/// every mounted window costs a brush session even though only one can
/// take a stroke at a time. So a window is mounted only when it is both on
/// screen and big enough to draw in, the same gate the timeline uses to
/// hide sparse elements below a zoom tier.
///
/// Zoomed out, that leaves nothing mounted, which is correct: a cell a few
/// pixels across is not one anybody is writing in. Zoomed in, it leaves
/// the handful actually in view.
List<EnvelopeInkWindow> mountedEnvelopeInkWindows(
  List<EnvelopeInkWindow> windows,
  CanvasViewport viewport,
  Size screenSize, {
  double minScreenExtent = 24,
}) {
  final screen = Rect.fromLTWH(0, 0, screenSize.width, screenSize.height);
  return [
    for (final window in windows)
      if (_mountable(window, viewport, screen, minScreenExtent)) window,
  ];
}

bool _mountable(
  EnvelopeInkWindow window,
  CanvasViewport viewport,
  Rect screen,
  double minScreenExtent,
) {
  final rect = window.screenRect(viewport);
  if (rect.width < minScreenExtent || rect.height < minScreenExtent) {
    return false;
  }
  return rect.overlaps(screen);
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
  final surfaceScale = layout.inkSurfaceScale;
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
          surfaceScale: surfaceScale,
        ),
  ];
}
