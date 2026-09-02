import 'dart:math' as math;

class BrushHistoryPolicy {
  const BrushHistoryPolicy({
    required this.userUndoLimit,
    required this.deferredBakeRatio,
    this.minimumDeferredBakeBuffer = 16,
    this.retainedSessionLimit = defaultRetainedSessionLimit,
  }) : assert(userUndoLimit > 0),
       assert(deferredBakeRatio >= 0),
       assert(minimumDeferredBakeBuffer >= 0),
       assert(retainedSessionLimit > 0);

  /// Default cap for the per-frame bitmap undo snapshots (≈ 6 full-canvas
  /// strokes at the 2340×1654 default canvas; huge-canvas strokes trim to
  /// fewer fast entries, older undos fall back to the command replay).
  static const int defaultMaterializationByteBudget = 256 * 1024 * 1024;

  /// Default cap for LIVE edit sessions (R13): every cel ever drawn on used
  /// to keep its session — surface plus up to a full materialization byte
  /// budget of undo snapshots — alive for the rest of the app run. Across
  /// an animation working session that grew the heap by megabytes PER CEL,
  /// and the swelling GC pauses read as "the whole app gets slower the more
  /// I draw". Four sessions keep cross-cel undo fast where it actually
  /// happens (the cels just worked on) while everything older falls back to
  /// the O(1) display-cache reseed + command-replay undo.
  static const int defaultRetainedSessionLimit = 4;

  final int userUndoLimit;
  final double deferredBakeRatio;
  final int minimumDeferredBakeBuffer;

  /// Maximum LIVE sessions the edit-session store retains (LRU beyond it
  /// evicts; the active session is always kept).
  final int retainedSessionLimit;

  /// Byte cap for a frame's bitmap materialization history (the changed
  /// tiles each undo/redo snapshot retains). The undo COUNT limit alone is
  /// unbounded in bytes — one full-canvas stroke at 5000×5000 pins ~100MB,
  /// so 24 of them could pin gigabytes. Entries beyond the budget drop from
  /// the deep end; undoing past them still works through the command
  /// replay fallback (the resize path's mechanism), just slower.
  int get materializationByteBudget => defaultMaterializationByteBudget;

  int get deferredBakeLimit => math.max(
    minimumDeferredBakeBuffer,
    (userUndoLimit * deferredBakeRatio).round(),
  );
}
