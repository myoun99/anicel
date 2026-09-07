import '../../models/brush_frame_key.dart';
import '../brush_frame_editing_coordinator.dart';
import '../brush_stroke_commit_data.dart';
import '../cache_invalidation_executor.dart';
import '../command.dart';
import '../undo_surface_snapshot.dart';

/// Bridges a brush source stroke into the app-level [HistoryManager]
/// (R19 P3b surface-snapshot undo).
///
/// The first execute commits the stroke and captures its pre/post
/// SURFACE REFERENCES — immutable tile maps, so together they retain
/// only the stroke's changed tiles, and a chain of strokes shares each
/// link. Undo restores the pre-surface, redo the post-surface, both
/// byte-exactly and independent of any session/replay state (the entry
/// is self-contained: it survives session eviction and outlives every
/// cache).
class BrushStrokeHistoryCommand
    implements Command, RetainedBytesCommand, ParkableCommand {
  BrushStrokeHistoryCommand({
    required this.coordinator,
    required BrushStrokeCommitData strokeData,
    this.cacheInvalidationSink,
  }) : _strokeData = strokeData;

  final BrushFrameEditingCoordinator coordinator;
  final CacheInvalidationSink? cacheInvalidationSink;

  /// The one-shot commit payload; nulled after the first execute. The
  /// stroke's pre-rasterized pixel buffer can be megabytes, and this
  /// command sits on the app undo stack for the rest of the session —
  /// retaining the payload made drawing sessions gradually accumulate
  /// hundreds of MB (GC pressure = the progressive brush lag).
  BrushStrokeCommitData? _strokeData;
  bool _hasCommitted = false;
  bool _committedChanges = false;

  late BrushFrameKey _frameKey;
  UndoSurfaceSnapshot? _pre;
  UndoSurfaceSnapshot? _post;

  /// Diagnostic for the accumulation regression guard.
  bool get retainsCommitPayload => _strokeData != null;

  /// ONE image of the changed tiles is ours; the other end of every link
  /// is somebody else's. post(n) IS pre(n+1) — the same object, by
  /// structural sharing — and the newest post IS the live surface, so
  /// charging both counted a neighbour's bytes as ours. There is no
  /// "worst case" where both ends are unshared: an entry with nothing
  /// after it is the newest one, and its post is what the canvas is
  /// showing.
  ///
  /// ⚠️THE BILL NAMES THE PRE; [parkPayload] MOVES BOTH. Not an
  /// inconsistency — the very sharing that makes the post free to hold is
  /// what makes it impossible to free alone.
  @override
  int get estimatedRetainedBytes => _pre?.residentBytes ?? 0;

  @override
  Future<bool> parkPayload() {
    final pre = _pre;
    final post = _post;
    if (pre == null || post == null) {
      return Future.value(true); // A stroke that changed nothing.
    }
    return UndoSurfaceSnapshot.parkAll([pre, post]);
  }

  @override
  void dropPayload() {
    final pre = _pre;
    final post = _post;
    if (pre != null && post != null) {
      UndoSurfaceSnapshot.dropAll([pre, post]);
    }
  }

  @override
  String get description => 'Brush stroke';

  @override
  void execute() {
    if (_hasCommitted) {
      if (_committedChanges) {
        _restore(_post);
      }
      return;
    }
    // A stroke that changes no pixels retains nothing and stays inert so
    // undo/redo never disturb an unrelated state.
    final strokeData = _strokeData!;
    final frameKey = coordinator.activeFrameKey;
    final outcome = coordinator.commitSourceStroke(
      sourceDabs: strokeData.sourceDabs,
      cacheInvalidationSink: cacheInvalidationSink,
      prerasterizedStrokePixels: strokeData.strokePixels,
      prerasterizedStrokeBounds: strokeData.strokeBounds,
      blendMode: strokeData.blendMode,
      strokeOpacity: strokeData.strokeOpacity,
      promotedBase: strokeData.promotedBase,
      promotedTiles: strokeData.promotedTiles,
    );
    _hasCommitted = true;
    _strokeData = null;
    _committedChanges = outcome != null;
    if (outcome != null) {
      _frameKey = frameKey;
      _pre = UndoSurfaceSnapshot(
        key: frameKey,
        snapshot: outcome.preSurface,
        sharedWith: outcome.postSurface,
      );
      _post = UndoSurfaceSnapshot(
        key: frameKey,
        snapshot: outcome.postSurface,
        sharedWith: outcome.preSurface,
      );
    }
  }

  @override
  void undo() {
    if (!_committedChanges) {
      return;
    }
    _restore(_pre);
  }

  /// ⛔A payload that will not come back leaves the picture ALONE. The
  /// snapshot holds only the tiles the stroke did not touch when its own
  /// are unreadable, so painting that over the cel would erase the very
  /// drawing this step exists to protect.
  void _restore(UndoSurfaceSnapshot? snapshot) {
    final surface = snapshot?.surface;
    if (surface == null) {
      return;
    }
    coordinator.restoreSurfaceSnapshot(
      _frameKey,
      surface,
      cacheInvalidationSink: cacheInvalidationSink,
    );
  }
}
