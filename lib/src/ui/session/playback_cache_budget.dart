part of '../editor_session_manager.dart';

/// The PLAYBACK CACHE BUDGET — how many bytes the playback cache may hold,
/// the ranges it must not evict (what is playing, what is about to), the
/// enforcer that trims it, and whether a frame is ready to show — as its
/// own object.
///
/// 🚨A collaborator carved out of `EditorSessionManager` (the audit's SRP cut,
/// 2026-09-02). The wider 「follow playback」 family was measured first and
/// refused: the session read it from twenty-two places (its lifecycle —
/// selectCut, dispose, the frame-rate setters — IS the following). This
/// is the part that stands on its own.
class _PlaybackCacheBudget {
  _PlaybackCacheBudget(this._session);

  final EditorSessionManager _session;

  late final PlaybackCacheBudgetEnforcer _playbackCacheBudgetEnforcer =
      PlaybackCacheBudgetEnforcer(
        layerImages: _session.layerFrameImageCache,
        composites: _session.cutFrameCompositeCache,
      );

  /// The composite-cache budget trim, runnable by every producer: the
  /// warmer after each cached frame, and the parked track stack after each
  /// on-demand build (its composites would otherwise grow the cache with
  /// nothing trimming until the next warm run). LRU: what is on screen was
  /// just touched, so it survives its own trim; held clones cover the rest.
  /// A6: the reserve is MEASURED now — the bytes the editing canvas has
  /// actually pinned — replacing an estimate that saturated at its clamp
  /// around twenty layers and then reported the same number for a
  /// hundred. The holders declare their clones to the cache (pins), so
  /// "what the screen needs" stopped being a guess about a widget tree
  /// and became a number the cache itself carries. While playing the
  /// editing stack holds no pins, so the old "zero while playing" rule
  /// falls out for free instead of being an `if`.
  /// The playback caches' combined cap in force (diagnostics/tests) — it
  /// is [playbackCacheBudgetBytes] until the OS warns.
  int get playbackCacheByteBudget => _playbackCacheBudgetEnforcer.maxBytes;

  void enforcePlaybackCacheBudget() => _playbackCacheBudgetEnforcer.enforce(
    protect: _playbackProtectedRanges(),
    reservedForDisplayBytes: _session.layerFrameImageCache.pinnedBytes,
  );

  /// What budget eviction must never touch: the full PLAYING playlist while
  /// playback is active (a looping pass must keep every cut warm so the
  /// second pass plays fully cached), otherwise the active cut's range.
  ///
  /// B1: the non-playing range DERIVES from [cutWarmFrameCount] — the same
  /// law the warm bakes over — because the two disagreeing was not
  /// hypothetical: warming baked the runway past the end line while this
  /// stopped AT the line, so every runway composite was evictable the
  /// moment it landed, by the enforcer that runs after every baked frame.
  /// The PLAYING branch stays on `entry.duration` on purpose: a playlist
  /// plays exactly its duration, and protecting more than plays would
  /// starve the budget during the one activity that needs it most.
  List<PlaybackProtectedRange> _playbackProtectedRanges() {
    if (_session.playback.isActive) {
      return [
        for (final entry in _session.playback.playlist)
          PlaybackProtectedRange(
            cutId: entry.cutId,
            startFrame: 0,
            endFrame: math.max(0, entry.duration - 1),
            quality: _session.playbackQuality,
          ),
      ];
    }

    final cut = _session.activeCutOrNull;
    if (cut == null) {
      return const [];
    }
    return [
      PlaybackProtectedRange(
        cutId: cut.id,
        startFrame: 0,
        endFrame: cutWarmFrameCount(cut) - 1,
        quality: _session.playbackQuality,
      ),
    ];
  }

  /// [_playbackProtectedRanges], for the tests that pin the one-law
  /// derivation (warm count == protected count) — the production reader
  /// stays [enforcePlaybackCacheBudget].
  @visibleForTesting
  List<PlaybackProtectedRange> debugPlaybackProtectedRanges() =>
      _playbackProtectedRanges();

  /// Whether [frameIndex] is READY to play at the current quality — the
  /// timeline ruler's green bar.
  bool isPlaybackFrameReady(int frameIndex) {
    final cut = _session.activeCutOrNull;
    if (cut == null) {
      return false;
    }
    return isPlaybackFrameReadyForCut(cut, frameIndex);
  }

  /// [isPlaybackFrameReady] for an arbitrary cut — the storyboard's green
  /// bar spans every cut of the track.
  ///
  /// TWO kinds of frame, one bar (유저 2026-08-16, 「왜 콘텐츠끝너머가
  /// 초록이되면 안되는거지? 재생가능한거잖아」):
  ///  * a frame with something to compose is green when its composite is
  ///    warmed — the bake IS its readiness;
  ///  * a frame that composes to NOTHING (a hole between blocks, the
  ///    runway past the drawings, hidden or faded-out layers) is not an
  ///    exception the bar skips — it is ready BY DEFINITION. Playback at
  ///    that frame draws exactly what its composite would hold: nothing.
  ///
  /// The empty answer reads the same shared visit the signature rides, so
  /// it cannot disagree with what the compose loop would actually paint.
  bool isPlaybackFrameReadyForCut(Cut cut, int frameIndex) {
    if (_session.cutFrameCompositeCache.validCompositeOrNull(
          cut: cut,
          frameIndex: frameIndex,
          quality: _session.playbackQuality,
        ) !=
        null) {
      return true;
    }
    return resolveCutFrameCompositeTree(
      cut: cut,
      frameIndex: frameIndex,
    ).isEmpty;
  }
}
