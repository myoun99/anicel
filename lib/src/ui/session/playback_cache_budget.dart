import 'package:flutter/foundation.dart';
import '../../models/cut.dart';
import '../../services/playback/cut_composite_structure.dart';
import '../../services/playback/cut_frame_composite_signature.dart';
import '../../services/playback/frame_demand.dart';
import '../playback/playback_cache_budget.dart';
import '../playback/canvas_pictures.dart';
import '../playback/canvas_playback_controller.dart';
import '../playback/playback_prerender_scheduler.dart' show PictureRoom;
import 'render_caches.dart';
import 'session_roles.dart';

/// The RUN this budget is trimming for — declared on the CONSUMER's
/// side (2026-09-06) so that [PlaybackRig], which both implements it and
/// builds this object, does not have to import a file that imports it
/// back. The pair is one cycle in the file graph and none at all in the
/// dependency direction: the budget knows about a run, not about a rig.
abstract interface class PlaybackRun {
  CanvasPlaybackController get playback;

  /// The order pictures are wanted in now — what the warmer follows — or
  /// null while it follows nothing.
  FrameDemand? get demand;

  /// The pictures every screen shows a frame from — the budget keeps them by
  /// [demand].
  CanvasPictures get pictures;
}

/// The PLAYBACK CACHE BUDGET — how many bytes the playback cache may hold,
/// the enforcer that trims it by what is wanted soonest, the room the
/// warmer asks before it makes a picture, and whether a frame is ready to
/// show — as its own object.
///
/// 🚨A collaborator carved out of `EditorSessionManager` (the audit's SRP cut,
/// 2026-09-02). The wider 「follow playback」 family was measured first and
/// refused: the session read it from twenty-two places (its lifecycle —
/// selectCut, dispose, the frame-rate setters — IS the following). This
/// is the part that stands on its own.
class PlaybackCacheBudget implements PictureRoom {
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

  PlaybackCacheBudgetEnforcer get _playbackCacheBudgetEnforcer =>
      _enforcer ??= PlaybackCacheBudgetEnforcer(
        layerImages: _renderCaches.layerFrameImageCache,
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

  /// The playback cache's cap in force (diagnostics/tests) — it is
  /// [playbackCacheBudgetBytes] until the OS warns.
  int get playbackCacheByteBudget => _playbackCacheBudgetEnforcer.maxBytes;

  /// ⚠️A test's [debugSetPlaybackCacheBudgetBytes] still wins.
  set playbackCacheByteBudget(int bytes) {
    _allowedMaxBytes = bytes;
    _enforcer?.maxBytes = _debugMaxBytes ?? bytes;
  }

  /// The playback cache's trim, run when the line moves under what is held —
  /// the allowance, a run that borrows it, a memory warning. ⛔Not after a
  /// picture lands: the warmer asks the room again then ([makeRoomFor]),
  /// which never lets go of what it just made (F-365).
  ///
  /// 🚨WHAT IS LET GO IS WHAT IS WANTED LATEST ([FrameDemand] — the one
  /// order the warmer makes pictures in). ↩️B1 had to DERIVE a kept range
  /// from the warm's own frame count, because the two disagreeing was not
  /// hypothetical: warming baked the runway past the end line while the
  /// range stopped AT the line, so every runway composite was evictable the
  /// moment it landed. They are one object now, and nothing is kept whole.
  void enforcePlaybackCacheBudget() => _playbackCacheBudgetEnforcer.enforce(
    wantedAt: _run.pictures.wantedAt(_run.demand),
    lentBytes: _lentBytes,
  );

  @override
  int get bytes => _playbackCacheBudgetEnforcer.room(lentBytes: _lentBytes);

  @override
  bool makeRoomFor({required int bytes, required int step}) =>
      _playbackCacheBudgetEnforcer.makeRoomFor(
        bytes: bytes,
        step: step,
        within: this.bytes,
        wantedAt: _run.pictures.wantedAt(_run.demand),
      );

  /// What an export run holds on this line while it goes — the row
  /// pictures its held cut pictures are made of (F-289-Q21, 유저 2026-10-07:
  /// 「붙든다 — 재생 줄의 허용치 안에서」). Playback rests while a run goes,
  /// so the run borrows the line and the playback caches give way to it;
  /// they fill again, as they are asked, once it is lent no more.
  int get lentBytes => _lentBytes;
  int _lentBytes = 0;

  /// How much of the line a run may hold now — all of it but what the
  /// playback caches will not give back.
  int get lendableBytes => _playbackCacheBudgetEnforcer.lendableBytes();

  /// A run holds [bytes] on this line from now on, and the playback caches
  /// give way to it at once — 0 when its last row is let go.
  void lend(int bytes) {
    _lentBytes = bytes;
    enforcePlaybackCacheBudget();
  }

  /// The OS memory warning, the playback caches' share: the enforcer
  /// lowers its cap, and the trim runs against the lowered cap at once.
  void respondToMemoryPressure() {
    _playbackCacheBudgetEnforcer.respondToMemoryPressure();
    enforcePlaybackCacheBudget();
  }

  /// The stretches of the active cut's frames in `[start, end)` that are
  /// READY to play — the timeline ruler's green bar. None without an active
  /// cut.
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
  /// spans come from [compositeStructureSpansIn].
  ///
  /// 🚨A BAR COUNTS WHAT ITS RUN SHOWS (playback-plays-the-screen-material):
  /// a span is ready when the pictures every screen shows a frame from are —
  /// the question a run asks before it goes on ([CanvasPictures.has]) asked
  /// of the span's first frame. ↩️The film's bar — the storyboard's — counted
  /// composites while the film played on them.
  List<({int startIndex, int endIndexExclusive})> playbackReadyRunsForCut(
    Cut cut,
    int start,
    int end,
  ) {
    bool isReady(CutFrameCompositeSignature structure, int frameIndex) =>
        structure.nodes.isEmpty ||
        _run.pictures.has((cut: cut, frameIndex: frameIndex));

    final runs = <({int startIndex, int endIndexExclusive})>[];
    for (final span in compositeStructureSpansIn(
      cut,
      start: start,
      end: end,
    )) {
      if (!isReady(span.signature, span.start)) {
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

}
