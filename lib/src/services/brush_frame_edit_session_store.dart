import '../models/bitmap_surface.dart';
import '../models/brush_bitmap_materialization_history_state.dart';
import '../models/brush_edit_session_state.dart';
import '../models/brush_frame_key.dart';
import '../models/canvas_size.dart';
import '../models/canvas_surface_state.dart';

class BrushFrameEditSessionStore {
  BrushFrameEditSessionStore({
    required CanvasSize canvasSize,
    this.tileSize = defaultCelTileSize,
  }) : _canvasSize = canvasSize;

  CanvasSize _canvasSize;
  final int tileSize;

  /// Insertion order doubles as recency (accesses re-insert): the LAST
  /// entries are the most recently used — what [evictBeyondRetainLimit]
  /// keeps.
  final Map<BrushFrameKey, BrushEditSessionState> _sessions = {};

  CanvasSize get canvasSize => _canvasSize;

  /// Live session count (eviction-guard oracle).
  int get sessionCount => _sessions.length;

  /// Adopts a new canvas size and drops every session state: session surfaces
  /// are derived caches at the old size, so the caller must rebuild them from
  /// the durable paint commands.
  void resizeCanvas(CanvasSize canvasSize) {
    if (canvasSize == _canvasSize) {
      return;
    }
    _canvasSize = canvasSize;
    _sessions.clear();
  }

  BrushEditSessionState getOrCreate(BrushFrameKey key) {
    final existing = sessionOrNull(key);
    if (existing != null) {
      return existing;
    }
    final created = _createBlankSessionState();
    _sessions[key] = created;
    return created;
  }

  BrushEditSessionState? sessionOrNull(BrushFrameKey key) {
    final session = _sessions.remove(key);
    if (session == null) {
      return null;
    }
    // Re-insert: reads count as uses for the LRU order.
    _sessions[key] = session;
    return session;
  }

  BrushEditSessionState update(
    BrushFrameKey key,
    BrushEditSessionState sessionState,
  ) {
    _sessions.remove(key);
    _sessions[key] = sessionState;
    return sessionState;
  }

  BrushEditSessionState reset(BrushFrameKey key) {
    final next = _createBlankSessionState();
    _sessions.remove(key);
    _sessions[key] = next;
    return next;
  }

  /// Drops the least-recently-used sessions beyond [retainLimit] (R13).
  ///
  /// Sessions are DERIVED state: the durable dabs live in the frame store,
  /// the current pixels live on as the donated display cache (an immutable
  /// tile map — dropping the session frees only what nothing else shares:
  /// chiefly the materialization undo snapshots, megabytes per cel). A
  /// revisit reseeds from the display cache in O(1); undoing an evicted
  /// cel's strokes takes the command-replay fallback — correct, just
  /// slower, and only for cels older than the whole retained set.
  /// [protect] (the active frame) is never evicted.
  void evictBeyondRetainLimit({
    required int retainLimit,
    required BrushFrameKey protect,
  }) {
    if (_sessions.length <= retainLimit) {
      return;
    }
    final evictable = [
      for (final key in _sessions.keys)
        if (key != protect) key,
    ];
    final keepCount = retainLimit - (_sessions.containsKey(protect) ? 1 : 0);
    final dropCount = evictable.length - keepCount;
    for (var index = 0; index < dropCount; index += 1) {
      _sessions.remove(evictable[index]);
    }
  }

  BrushEditSessionState _createBlankSessionState() {
    return BrushEditSessionState(
      canvasState: CanvasSurfaceState(
        currentSurface: BitmapSurface(
          canvasSize: _canvasSize,
          tileSize: tileSize,
        ),
      ),
      materializationHistoryState: BrushBitmapMaterializationHistoryState(),
    );
  }
}
