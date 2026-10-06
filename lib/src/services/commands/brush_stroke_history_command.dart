import '../brush_frame_editing_coordinator.dart';
import '../brush_stroke_commit_data.dart';
import '../cache_invalidation_executor.dart';
import '../command.dart';
import '../undo_surface_snapshot.dart';
import 'cel_snapshot_step.dart';

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
class BrushStrokeHistoryCommand with CelSnapshotStep implements Command {
  BrushStrokeHistoryCommand({
    required this.coordinator,
    required BrushStrokeCommitData strokeData,
    this.cacheInvalidationSink,
  }) : _strokeData = strokeData;

  @override
  final BrushFrameEditingCoordinator coordinator;
  @override
  final CacheInvalidationSink? cacheInvalidationSink;

  /// The one-shot commit payload; nulled after the first execute. The
  /// stroke's pre-rasterized pixel buffer can be megabytes, and this
  /// command sits on the app undo stack for the rest of the session —
  /// retaining the payload made drawing sessions gradually accumulate
  /// hundreds of MB (GC pressure = the progressive brush lag).
  BrushStrokeCommitData? _strokeData;
  bool _hasCommitted = false;

  UndoSurfacePair? _surfaces;

  /// Diagnostic for the accumulation regression guard.
  bool get retainsCommitPayload => _strokeData != null;

  /// Null for a stroke that changed nothing: it has nothing to move, reads
  /// nothing ahead and puts nothing back ([CelSnapshotStep]).
  ///
  /// ONE image of the changed tiles is ours; the other end of every link
  /// is somebody else's. There is no "worst case" where both ends are
  /// unshared: an entry with nothing after it is the newest one, and its
  /// post is what the canvas is showing. See [UndoSurfacePair] for why
  /// the bill and the park name different things.
  @override
  UndoSurfacePair? get surfaces => _surfaces;

  /// What history calls a stroke — this command, and the one step a
  /// stroke's landings on several surfaces fold into (a sheet's windows).
  static const String label = 'Brush stroke';

  @override
  String get description => label;

  @override
  void execute() {
    if (_hasCommitted) {
      restoreAfter();
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
    if (outcome != null) {
      _surfaces = UndoSurfacePair(
        key: frameKey,
        before: outcome.preSurface,
        after: outcome.postSurface,
      );
    }
  }

  @override
  void undo() => restoreBefore();
}
