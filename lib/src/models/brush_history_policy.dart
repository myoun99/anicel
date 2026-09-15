class BrushHistoryPolicy {
  const BrushHistoryPolicy({
    this.retainedSessionLimit = defaultRetainedSessionLimit,
  }) : assert(retainedSessionLimit > 0);

  /// Default cap for LIVE edit sessions (R13): every cel ever drawn on used
  /// to keep its session — surface plus up to a full materialization byte
  /// budget of undo snapshots — alive for the rest of the app run. Across
  /// an animation working session that grew the heap by megabytes PER CEL,
  /// and the swelling GC pauses read as "the whole app gets slower the more
  /// I draw". Four sessions keep cross-cel undo fast where it actually
  /// happens (the cels just worked on) while everything older falls back to
  /// the O(1) display-cache reseed + command-replay undo.
  static const int defaultRetainedSessionLimit = 4;

  /// Maximum LIVE sessions the edit-session store retains (LRU beyond it
  /// evicts; the active session is always kept).
  final int retainedSessionLimit;
}
