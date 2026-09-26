import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import '../../models/cut.dart';
import '../../models/cut_warm_extent.dart';
import '../../services/playback/cut_composite_structure.dart';
import '../../services/playback/cut_frame_composite_signature.dart';
import '../playback/cut_frame_composite_cache.dart';
import '../playback/playback_cache_budget.dart';
import '../../models/playback_quality.dart';
import '../playback/canvas_playback_controller.dart';
import 'render_caches.dart';
import 'session_roles.dart';

/// The RUN this budget is trimming for — declared on the CONSUMER's
/// side (2026-09-06) so that [PlaybackRig], which both implements it and
/// builds this object, does not have to import a file that imports it
/// back. The pair is one cycle in the file graph and none at all in the
/// dependency direction: the budget knows about a run, not about a rig.
abstract interface class PlaybackRun {
  CanvasPlaybackController get playback;
  PlaybackQuality get playbackQuality;
}

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
class PlaybackCacheBudget {
  PlaybackCacheBudget({
    required ProjectAccess project,
    required RenderCaches renderCaches,
    required PlaybackRun run,
  }) : _project = project,
       _renderCaches = renderCaches,
       _run = run;

  final ProjectAccess _project;
  final RenderCaches _renderCaches;
  final PlaybackRun _run;

  PlaybackCacheBudgetEnforcer? _enforcer;

  /// [playbackReadyRunsForCut]'s memo: per cut instance, each structure's
  /// full signature at one quality and one pixel revision.
  final Expando<
    ({
      PlaybackQuality quality,
      int pixelRevision,
      Map<CutFrameCompositeSignature, CutFrameCompositeSignature> byStructure,
    })
  >
  _signedStructures = Expando('signedCompositeStructures');

  PlaybackCacheBudgetEnforcer get _playbackCacheBudgetEnforcer =>
      _enforcer ??= PlaybackCacheBudgetEnforcer(
        layerImages: _renderCaches.layerFrameImageCache,
        composites: _renderCaches.cutFrameCompositeCache,
        maxBytes:
            _debugMaxBytes ?? _allowedMaxBytes ?? playbackCacheBudgetBytes,
      );

  /// What the memory tab's allowance gives playback
  /// ([CacheBudgets.playback]), kept until the enforcer is built.
  int? _allowedMaxBytes;

  /// The budget a TEST hands the enforcer, in place of the 600 MB the
  /// product uses — nothing a unit test can fill. Set before the first
  /// cache use; the enforcer reads it once, when it is built. Added when
  /// the adversarial check on the 2026-09-02 cut made
  /// [enforcePlaybackCacheBudget] a no-op and every test stayed green: the
  /// enforcer was measured, the session's wiring to it was not.
  int? _debugMaxBytes;

  /// A test's budget for the playback caches — see [_debugMaxBytes].
  @visibleForTesting
  void debugSetPlaybackCacheBudgetBytes(int bytes) => _debugMaxBytes = bytes;

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

  /// ⚠️A test's [debugSetPlaybackCacheBudgetBytes] still wins.
  set playbackCacheByteBudget(int bytes) {
    _allowedMaxBytes = bytes;
    _enforcer?.maxBytes = _debugMaxBytes ?? bytes;
  }

  void enforcePlaybackCacheBudget() => _playbackCacheBudgetEnforcer.enforce(
    protect: _playbackProtectedRanges(),
    reservedForDisplayBytes: _renderCaches.layerFrameImageCache.pinnedBytes,
  );

  /// The OS memory warning, the playback caches' share: the enforcer
  /// lowers its cap, and the trim runs against the lowered cap at once.
  void respondToMemoryPressure() {
    _playbackCacheBudgetEnforcer.respondToMemoryPressure();
    enforcePlaybackCacheBudget();
  }

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
    if (_run.playback.isActive) {
      return [
        for (final entry in _run.playback.playlist)
          PlaybackProtectedRange(
            cutId: entry.cutId,
            startFrame: 0,
            endFrame: math.max(0, entry.duration - 1),
            quality: _run.playbackQuality,
          ),
      ];
    }

    final cut = _project.activeCutOrNull;
    if (cut == null) {
      return const [];
    }
    return [
      PlaybackProtectedRange(
        cutId: cut.id,
        startFrame: 0,
        endFrame: cutWarmFrameCount(cut) - 1,
        quality: _run.playbackQuality,
      ),
    ];
  }

  /// [_playbackProtectedRanges], for the tests that pin the one-law
  /// derivation (warm count == protected count) — the production reader
  /// stays [enforcePlaybackCacheBudget].
  @visibleForTesting
  List<PlaybackProtectedRange> debugPlaybackProtectedRanges() =>
      _playbackProtectedRanges();

  /// The stretches of the active cut's frames in `[start, end)` that are
  /// READY to play at the current quality — the timeline ruler's green
  /// bar. None without an active cut.
  List<({int startIndex, int endIndexExclusive})> playbackReadyRuns(
    int start,
    int end,
  ) {
    final cut = _project.activeCutOrNull;
    if (cut == null) {
      return const [];
    }
    return playbackReadyRunsForCut(cut, start, end);
  }

  /// [playbackReadyRuns] for an arbitrary cut — the storyboard's green
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
  ///
  /// ★Asked once per span of one picture, never per frame (I-22): zoomed
  /// out to ten minutes the per-frame read was 94% of a playback tick. The
  /// spans come from [compositeStructureSpansIn]; each structure's full
  /// signature is taken once per pixel revision, and the cache is asked
  /// with [CutFrameCompositeCache.holdsComposite] — a pure read, where the
  /// per-frame bar filed an index key and touched the entry as used for
  /// every frame on screen.
  List<({int startIndex, int endIndexExclusive})> playbackReadyRunsForCut(
    Cut cut,
    int start,
    int end,
  ) {
    final composites = _renderCaches.cutFrameCompositeCache;
    final quality = _run.playbackQuality;
    final signed = _signedStructuresOf(cut, quality);
    final runs = <({int startIndex, int endIndexExclusive})>[];
    for (final span in compositeStructureSpansIn(
      cut,
      start: start,
      end: end,
    )) {
      final structure = span.signature;
      final ready =
          structure.nodes.isEmpty ||
          composites.holdsComposite(
            signed[structure] ??= composites.signatureOf(
              cut: cut,
              frameIndex: span.start,
              quality: quality,
            ),
          );
      if (!ready) {
        continue;
      }
      final last = runs.isEmpty ? null : runs.last;
      if (last != null && last.endIndexExclusive == span.start) {
        runs.last = (
          startIndex: last.startIndex,
          endIndexExclusive: span.endExclusive,
        );
      } else {
        runs.add((
          startIndex: span.start,
          endIndexExclusive: span.endExclusive,
        ));
      }
    }
    return runs;
  }

  /// Each structure's full signature for [cut] at [quality], good until a
  /// pixel moves: [BrushFrameStore.celPixelRevision] is the store's one
  /// signal that a source revision may have changed (a whole-store swap
  /// opens a new project, so its cuts are new instances and miss here).
  Map<CutFrameCompositeSignature, CutFrameCompositeSignature>
  _signedStructuresOf(Cut cut, PlaybackQuality quality) {
    final revision =
        _renderCaches.cutFrameCompositeCache.frameStore.celPixelRevision.value;
    final held = _signedStructures[cut];
    if (held != null &&
        held.quality == quality &&
        held.pixelRevision == revision) {
      return held.byStructure;
    }
    final fresh = (
      quality: quality,
      pixelRevision: revision,
      byStructure: <CutFrameCompositeSignature, CutFrameCompositeSignature>{},
    );
    _signedStructures[cut] = fresh;
    return fresh.byStructure;
  }
}
