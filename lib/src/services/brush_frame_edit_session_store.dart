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

  /// Link resolution — the SAME law `BrushFrameStore` keeps, because a
  /// session is state ABOUT a physical cel: every public operation folds
  /// its key through this first, so linked rows share ONE session.
  ///
  /// ⛔WITHOUT IT THE PICTURE SPLITS IN TWO. The store's pixels are one
  /// per cel, but a session held per ROW ADDRESS keeps its own surface —
  /// so a stroke committed through one 겸용 member left the other member's
  /// session on the pre-stroke pixels, and the row you STAND on is painted
  /// from the session. 🗣️유저 2026-09-12: 「컷1에서 그린 그림이 재생시에만
  /// 표시되고 아닐땐 안보여」 — playback reads the store (right), the canvas
  /// read the stale session (wrong).
  ///
  /// Identity by default, so an unlinked project — and every caller that
  /// never wires one — behaves exactly as before. The resolver must be
  /// idempotent; [BrushFrameEditingCoordinator] wires the frame store's,
  /// which reads the current project's registry on every resolve.
  BrushFrameKey Function(BrushFrameKey key) _canonicalize = _identityKey;

  static BrushFrameKey _identityKey(BrushFrameKey key) => key;

  /// Installs (or clears, with null) the canonical-key resolver.
  void setLinkResolver(BrushFrameKey Function(BrushFrameKey key)? resolver) {
    _canonicalize = resolver ?? _identityKey;
  }

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
    key = _canonicalize(key);
    final existing = sessionOrNull(key);
    if (existing != null) {
      return existing;
    }
    final created = _createBlankSessionState();
    _sessions[key] = created;
    return created;
  }

  BrushEditSessionState? sessionOrNull(BrushFrameKey key) {
    key = _canonicalize(key);
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
    key = _canonicalize(key);
    _sessions.remove(key);
    _sessions[key] = sessionState;
    return sessionState;
  }

  BrushEditSessionState reset(BrushFrameKey key) {
    key = _canonicalize(key);
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
    // The protected key is an ADDRESS like any other: fold it, or a linked
    // member would protect a session nobody is holding and evict the live
    // one.
    final protected = _canonicalize(protect);
    final evictable = [
      for (final key in _sessions.keys)
        if (key != protected) key,
    ];
    final keepCount =
        retainLimit - (_sessions.containsKey(protected) ? 1 : 0);
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
