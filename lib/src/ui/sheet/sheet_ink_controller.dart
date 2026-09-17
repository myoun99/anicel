import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

import '../../models/bitmap_surface.dart';
import '../../models/brush_edit_session_state.dart';
import '../../models/brush_frame_key.dart';
import '../../models/brush_history_policy.dart';
import '../../models/canvas_size.dart';
import '../../services/brush_frame_edit_session_store.dart';
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
/// a third copy of a guard. [displayImageFor] then composed tiles
/// asynchronously and notified when the image landed; the envelope checked
/// `_disposed` first, because "the panel can close while a compose is in
/// flight — a notify then would throw, and the image would leak". The
/// conte never got that check: the fix arrived with the envelope and did
/// not flow back. Closing the conte panel mid-compose threw and leaked.
/// (The asynchronous compose itself went on 2026-09-17 — see
/// [displayImageFor] — and the guard with it; the lesson is the merge.)
///
/// ⛔SO THE FIX IS THE MERGE, not a guard added in a second place — a
/// second place to remember is what produced the bug.
///
/// [P] is the panel's own plane type. A sheet with one plane passes a
/// type with one value (or `void`-like) and ignores the argument.
///
/// 🚨THE TIMESHEET WAS THE THIRD COPY (F-80 ②, 2026-09-15). Its controller
/// re-wrote the session lookup, the commit and the has-ink oracle beside
/// this class instead of extending it, so a law written here reached two
/// sheets of three. It extends this now, and every sheet hands over its
/// planes rather than answering the two lookups by hand.
abstract class SheetInkController<P> extends ChangeNotifier {
  /// [planes] is every plane the sheet draws on, keyed by the plane value
  /// its windows carry.
  ///
  /// 🚨★★★F-80 ② — THE PANEL FOLLOWS THE STORE, NOT THE CALLER.
  ///
  /// 유저 2026-09-11: 「드로잉on인상태에서 그릴때 undo로 기록이안되는거같음.
  /// 언두해도 언두안되고 다른곳 타임라인 조작이나 그 패널 바깥의 동작이
  /// 언두됨」. The stroke WAS in history, and undo did put the surface back.
  /// The panel was never told: its ink windows take their surface when the
  /// host rebuilds, the host rebuilds on this notifier, and this notified
  /// for a commit only — undo and redo reach the store through the history
  /// command, never through here. The session's notify after every undo had
  /// been covering for that until 44bdeb49 (2026-09-10) stopped an undo
  /// that moves no row from tidying the document up. The stroke stayed on
  /// the sheet, and the next press undid something outside the panel.
  ///
  /// The canvas met the same thing on 2026-08-27, and its answer is the one
  /// here: [BrushFrameStore.celPixelRevision] is the one signal every
  /// surface write bumps — a stroke, an undo, a redo, a file restore — so
  /// the controller follows that, whoever made the write.
  SheetInkController(Map<P, InkPlaneSlot> planes) : _planes = planes {
    for (final slot in planes.values) {
      slot.store.celPixelRevision.addListener(_onCelPixelsChanged);
    }
  }

  final Map<P, InkPlaneSlot> _planes;

  void _onCelPixelsChanged() => notifyListeners();

  /// WHICH coordinator owns [plane]'s surfaces. Throws if geometry has not
  /// been synced — the panels all build their coordinators lazily from
  /// their own `syncGeometry`, whose rules genuinely differ (the conte
  /// derives two sizes from sheet metrics, the envelope one from an aspect
  /// ratio), so that stays with each panel.
  @protected
  BrushFrameEditingCoordinator coordinatorFor(P plane) =>
      _planes[plane]!.coordinator;

  /// WHICH store holds [plane]'s baked surfaces.
  @protected
  BrushFrameStore storeFor(P plane) => _planes[plane]!.store;

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

  /// The painter-side display image for a window: the baked surface's
  /// tiles composed inside this call, and kept until that surface changes.
  ///
  /// 🚨★★★IT IS THE SURFACE'S PICTURE THE MOMENT IT IS THE SURFACE — a
  /// stroke's pen-up, an undo, a redo, ink mode switched off (유저 절대규칙
  /// 2026-09-17 「보이는 중이랑 결과랑 절대로 다르면 안 되」). A tile that has
  /// no picture gets one made here, through the one door
  /// ([composeTiledSurfaceImageNow]), so there is nothing to wait for.
  ///
  /// 🪦Until then a surface with an unpictured tile was composed
  /// ASYNCHRONOUSLY and 「the stale image holds meanwhile」: an undo made
  /// while ink mode was off left the undone stroke on the sheet for the
  /// frames the compose took. That road is also what needed a `_disposed`
  /// guard — the panel could close while a compose was in flight, a notify
  /// then threw and the image leaked — and the guard existed on ONE of the
  /// two copies this class replaced (the header's story). With nothing in
  /// flight there is nothing to guard.
  ui.Image? displayImageFor(P plane, BrushFrameKey key) {
    final surface = storeFor(plane).bakedSurfaceOrNull(key);
    if (surface == null) {
      return null;
    }
    final cached = _display[key];
    if (cached != null && identical(cached.$1, surface)) {
      return cached.$2;
    }
    final composed = composeTiledSurfaceImageNow(
      surface,
      reuse: BitmapTileImageCache.instance,
    );
    cached?.$2.dispose();
    _display[key] = (surface, composed);
    return composed;
  }

  @override
  void dispose() {
    // The stores can outlive the panel — the session keeps the envelope's
    // and the conte's for the life of the project.
    for (final slot in _planes.values) {
      slot.store.celPixelRevision.removeListener(_onCelPixelsChanged);
    }
    for (final entry in _display.values) {
      entry.$2.dispose();
    }
    _display.clear();
    super.dispose();
  }
}

/// [coordinator] resized to [canvasSize], or a fresh one over [store] when
/// the plane has none yet — the sync every ink plane runs once its own
/// geometry rule has picked the size.
///
/// 🚨ONE law for the conte, envelope and timesheet inks (the audit's clone
/// scan, 2026-09-03); each keeps only its initial frame key.
BrushFrameEditingCoordinator inkCoordinatorSynced(
  BrushFrameEditingCoordinator? coordinator, {
  required BrushFrameStore store,
  required CanvasSize canvasSize,
  required BrushFrameKey initialFrameKey,
}) {
  if (coordinator != null) {
    coordinator.resizeCanvasAllCuts(canvasSize);
    return coordinator;
  }
  return BrushFrameEditingCoordinator(
    initialFrameKey: initialFrameKey,
    frameStore: store,
    sessionStore: BrushFrameEditSessionStore(canvasSize: canvasSize),
    historyPolicy: const BrushHistoryPolicy(),
  );
}

/// One ink PLANE: its coordinator, the canvas size that coordinator was
/// built for, and the store behind it.
///
/// ⛔THREE CONTROLLERS KEPT THOSE THREE AS LOOSE FIELDS — the conte's page
/// and row, the timesheet's strip and page, the envelope's one — and each
/// re-wrote the same guard: rebuild when the coordinator is missing OR the
/// size moved, and remember the new size. Five copies of a three-field
/// invariant is five chances to update the size and not the coordinator.
///
/// [coordinator] throws rather than returning null: asking before the
/// geometry is known is a programming error, not a state to render around
/// — and that is the message all three already threw.
class InkPlaneSlot {
  InkPlaneSlot({required this.store, required this.initialFrameKey});

  final BrushFrameStore store;
  final BrushFrameKey initialFrameKey;

  BrushFrameEditingCoordinator? _coordinator;
  CanvasSize? _size;

  /// The size the coordinator was built for, or null before the first
  /// [syncTo] — the surface size the controllers expose.
  CanvasSize? get size => _size;

  /// Whether the plane has been given its geometry yet.
  bool get isReady => _coordinator != null;

  BrushFrameEditingCoordinator get coordinator {
    final coordinator = _coordinator;
    if (coordinator == null) {
      throw StateError('syncGeometry must run before ink access.');
    }
    return coordinator;
  }

  void syncTo(CanvasSize canvasSize) {
    if (_coordinator != null && canvasSize == _size) {
      return;
    }
    _size = canvasSize;
    _coordinator = inkCoordinatorSynced(
      _coordinator,
      store: store,
      canvasSize: canvasSize,
      initialFrameKey: initialFrameKey,
    );
  }
}
