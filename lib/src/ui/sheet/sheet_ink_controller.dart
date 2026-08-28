import 'dart:async' show unawaited;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

import '../../models/bitmap_surface.dart';
import '../../models/brush_edit_session_state.dart';
import '../../models/brush_frame_key.dart';
import '../../services/brush_frame_editing_coordinator.dart';
import '../../services/brush_frame_store.dart';
import '../../services/brush_stroke_commit_data.dart';
import '../../services/cache_invalidation_executor.dart';
import '../../services/commands/brush_stroke_history_command.dart';
import '../../services/history_manager.dart';
import '../canvas/bitmap_tile_image_cache.dart';
import '../canvas/tiled_surface_compose.dart';

/// 🚨★★★WHAT EVERY SHEET'S INK CONTROLLER DOES, once.
///
/// The conte's and the envelope's controllers were the same object with
/// one difference: which coordinator a window's ink belongs to. The conte
/// picks by plane (paper vs cell), the envelope has a single one — and
/// every method below was written twice around that one lookup.
///
/// 🚨THE COPIES HAD ALREADY DIVERGED, which is why this exists rather than
/// a third copy of a guard. [displayImageFor] composes tiles
/// asynchronously and notifies when the image lands; the envelope checks
/// `_disposed` first, because "the panel can close while a compose is in
/// flight — a notify then would throw, and the image would leak". The
/// conte never got that check: the fix arrived with the envelope and did
/// not flow back. Closing the conte panel mid-compose threw and leaked.
///
/// ⛔SO THE FIX IS THE MERGE, not a guard added in a second place — a
/// second place to remember is what produced the bug.
///
/// [P] is the panel's own plane type. A sheet with one plane passes a
/// type with one value (or `void`-like) and ignores the argument.
abstract class SheetInkController<P> extends ChangeNotifier {
  /// WHICH coordinator owns [plane]'s surfaces. Throws if geometry has not
  /// been synced — the panels all build their coordinators lazily from
  /// their own `syncGeometry`, whose rules genuinely differ (the conte
  /// derives two sizes from sheet metrics, the envelope one from an aspect
  /// ratio), so that stays with each panel.
  @protected
  BrushFrameEditingCoordinator coordinatorFor(P plane);

  /// WHICH store holds [plane]'s baked surfaces.
  @protected
  BrushFrameStore storeFor(P plane);

  /// The session surface for one window (created blank on first access).
  BrushEditSessionState sessionStateFor(P plane, BrushFrameKey key) {
    final coordinator = coordinatorFor(plane);
    coordinator.selectFrame(key);
    return coordinator.activeSessionState;
  }

  /// Commits a finished sheet stroke through the app history (one undo
  /// step, exactly like a canvas stroke).
  void commitStroke({
    required P plane,
    required BrushFrameKey key,
    required BrushStrokeCommitData strokeData,
    required HistoryManager historyManager,
    CacheInvalidationSink? cacheInvalidationSink,
  }) {
    final coordinator = coordinatorFor(plane);
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
  ///
  /// The baked raster IS the content, so "count" collapses to
  /// has-content.
  bool hasInkFor(P plane, BrushFrameKey key) =>
      storeFor(plane).celHasRenderableContent(key);

  final Map<BrushFrameKey, (BitmapSurface, ui.Image)> _display = {};
  final Set<BrushFrameKey> _composing = {};
  bool _disposed = false;

  /// The painter-side display image for a window, composed lazily from the
  /// baked surface's tiles and cached until that surface changes.
  ui.Image? displayImageFor(P plane, BrushFrameKey key) {
    final surface = storeFor(plane).bakedSurfaceOrNull(key);
    if (surface == null) {
      return null;
    }
    final cached = _display[key];
    if (cached != null && identical(cached.$1, surface)) {
      return cached.$2;
    }
    final immediate = composeTiledSurfaceImageSyncOrNull(
      surface,
      reuse: BitmapTileImageCache.instance,
    );
    if (immediate != null) {
      cached?.$2.dispose();
      _display[key] = (surface, immediate);
      return immediate;
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
          // 🚨The panel can close while a compose is in flight — a notify
          // then would throw, and the image would leak. This guard existed
          // on ONE of the two copies this class replaced.
          if (_disposed ||
              !identical(storeFor(plane).bakedSurfaceOrNull(key), surface)) {
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
