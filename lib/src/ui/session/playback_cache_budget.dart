import 'package:flutter/foundation.dart';
import '../../models/cut.dart';
import '../../services/playback/cut_composite_structure.dart';
import '../../services/playback/frame_demand.dart';
import '../playback/playback_cache_budget.dart';
import '../playback/frame_pictures.dart';
import '../playback/playback_pictures.dart' show PictureState;
import '../playback/canvas_playback_controller.dart';
import '../playback/playback_prerender_scheduler.dart' show PictureRoom;
import '../timeline/timeline_ruler_cursor_overlay.dart' show ReadyRun;
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
  FramePictures get pictures;
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
class PlaybackCacheBudget implements PictureRoom, HeldNodesLine {
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
        pictures: _renderCaches.framePictureStore,
        maxBytes:
            _debugMaxBytes ?? _allowedMaxBytes ?? playbackCacheBudgetBytes,
      );

  /// What the memory tab's allowance gives playback
  /// ([CacheBudgets.playback]), kept until the enforcer is built.
  int? _allowedMaxBytes;

  /// The budget a TEST hands the enforcer, in place of the line the
  /// product uses (hundreds of MB) — nothing a unit test can fill. Set
  /// before the first cache use; the enforcer reads it once, when it is
  /// built. Added when
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
  /// the allowance, a run that borrows it, a memory warning, the nodes over
  /// a pen held ([giveWayToNodes]). ⛔Not after a picture lands: the warmer
  /// asks the room again then ([makeRoomFor]), which never lets go of what
  /// it just made (F-365).
  ///
  /// 🚨WHAT IS LET GO IS WHAT IS WANTED LATEST ([FrameDemand] — the one
  /// order the warmer makes pictures in). ↩️B1 had to DERIVE a kept range
  /// from the warm's own frame count, because the two disagreeing was not
  /// hypothetical: warming baked the runway past the end line while the
  /// range stopped AT the line, so every runway composite was evictable the
  /// moment it landed. They are one object now, and nothing is kept whole.
  ///
  /// The nodes held go first only past their own room ([bytesForNodes]):
  /// the line moved under them.
  void enforcePlaybackCacheBudget() {
    _run.pictures.heldNodes.fit();
    _playbackCacheBudgetEnforcer.enforce(
      wantedAt: _run.pictures.wantedAt(_run.demand),
      lentBytes: _besideThePictures,
    );
  }

  @override
  int get bytes =>
      _playbackCacheBudgetEnforcer.room(lentBytes: _besideThePictures);

  /// What the line holds beside the frames' pictures, which give way to it:
  /// what is [lent], and the pictures the nodes of the frame a screen
  /// stands on are held in (`FramePictures.heldNodes`) — taken off the
  /// pictures made ahead ([bytesForNodes]), never laid past the line.
  int get _besideThePictures => _lentBytes + _run.pictures.heldNodes.heldBytes;

  /// How much of the line the nodes over a pen may hold, one by one
  /// (`FramePictures.heldNodes`): all of it but what a screen shows, what
  /// is [lent] and what lies below the pen held — the frames' pictures made
  /// ahead give way to them ([giveWayToNodes]). 🗣️유저 2026-10-27 (Q3 = c):
  /// 「위 폴더는 하나씩, 재생 메모리 몫 안에서 전부」.
  @override
  int get bytesForNodes {
    final room =
        _playbackCacheBudgetEnforcer.lendableBytes() -
        _lentBytes -
        _run.pictures.heldNodes.heldBelowBytes;
    return room < 0 ? 0 : room;
  }

  @override
  void giveWayToNodes() => enforcePlaybackCacheBudget();

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
  /// playback caches will not give back, and the frame's nodes held
  /// ([_besideThePictures]).
  int get lendableBytes {
    final lendable =
        _playbackCacheBudgetEnforcer.lendableBytes() -
        _run.pictures.heldNodes.heldBytes;
    return lendable < 0 ? 0 : lendable;
  }

  /// A run holds [bytes] on this line from now on, and the playback caches
  /// give way to it at once — 0 when its last row is let go.
  void lend(int bytes) {
    _lentBytes = bytes;
    enforcePlaybackCacheBudget();
  }

  /// The OS memory warning, the playback caches' share: the enforcer
  /// lowers its cap, and the trim runs against the lowered cap at once —
  /// the frame's nodes held let go of first, as they only make a stroke's
  /// steps cheaper.
  void respondToMemoryPressure() {
    _run.pictures.heldNodes.clear();
    _playbackCacheBudgetEnforcer.respondToMemoryPressure();
    enforcePlaybackCacheBudget();
  }

  /// The stretches of the active cut's frames in `[start, end)` that are
  /// READY to play — the timeline ruler's bar. None without an active cut.
  List<ReadyRun> playbackReadyRuns(int start, int end) {
    final cut = _project.activeCutOrNull;
    if (cut == null) {
      return const [];
    }
    // The cut's own run, on the canvas: on its paper.
    return playbackReadyRunsForCut(cut, start, end, paintPaper: true);
  }

  /// [playbackReadyRuns] for an arbitrary cut — the storyboard's green
  /// bar spans every cut of the track.
  ///
  /// TWO kinds of frame, one bar (유저 2026-08-16, 「왜 콘텐츠끝너머가
  /// 초록이되면 안되는거지? 재생가능한거잖아」):
  ///  * a frame with something to compose is green when its picture is
  ///    made — the making IS its readiness;
  ///  * a frame that composes to NOTHING (a hole between blocks, the
  ///    runway past the drawings, hidden or faded-out layers) is not an
  ///    exception the bar skips — it is ready BY DEFINITION. Playback at
  ///    that frame draws its page alone, the paper or nothing
  ///    (`FramePictures.drawsOnlyItsPage`), and nothing of it is made.
  ///
  /// The two are ONE question, the run's own ([FramePictures.has]).
  /// ↩️The bar answered a frame of nothing by the plan's empty signature,
  /// beside the run's question — the same answer asked twice, until a
  /// frame became one picture and the run's answered it too.
  ///
  /// ★Asked once per span of one picture, never per frame (I-22): zoomed
  /// out to ten minutes the per-frame read was 94% of a playback tick. The
  /// spans come from [compositeStructureSpansIn].
  ///
  /// 🚨A BAR COUNTS WHAT ITS RUN SHOWS (playback-plays-the-screen-material):
  /// a span is ready when the pictures every screen shows a frame from are —
  /// the question a run asks before it goes on ([FramePictures.standingOf])
  /// asked of the span's first frame. ↩️The film's bar — the storyboard's —
  /// counted composites while the film played on them.
  ///
  /// 🗣️AND A SPAN WITH A CEL THAT COULD NOT BE READ IS READY RED
  /// (frame-picture-indicator-Q1 b) once the run waits for no more of it:
  /// its picture is made without that cel ([PictureState.there]), or
  /// nothing more of it is to come ([PictureState.gaveUp]) — it plays
  /// without that cel. ↩️The bar asked only whether the span's pictures
  /// were there, and such a span was never painted at all — the run going
  /// on past it said nothing anywhere.
  ///
  /// [paintPaper]: whether the screen its run plays on paints the cut's
  /// paper ([DemandedPicture.paintPaper]) — which of its pictures it shows.
  List<ReadyRun> playbackReadyRunsForCut(
    Cut cut,
    int start,
    int end, {
    required bool paintPaper,
  }) {
    final pictures = _run.pictures;
    final runs = <ReadyRun>[];
    for (final span in compositeStructureSpansIn(
      cut,
      start: start,
      end: end,
    )) {
      final picture = (
        cut: cut,
        frameIndex: span.start,
        paintPaper: paintPaper,
        // A run shows no ghosts.
        ghosts: FrameGhosts.none,
      );
      final (:state, cannotRead: unreadable) = pictures.standingOf(picture);
      if (state == PictureState.toCome ||
          (state == PictureState.gaveUp && !unreadable)) {
        continue;
      }
      final last = runs.isEmpty ? null : runs.last;
      if (last != null &&
          last.endIndexExclusive == span.start &&
          last.unreadable == unreadable) {
        runs.last = (
          startIndex: last.startIndex,
          endIndexExclusive: span.endExclusive,
          unreadable: unreadable,
        );
      } else {
        runs.add((
          startIndex: span.start,
          endIndexExclusive: span.endExclusive,
          unreadable: unreadable,
        ));
      }
    }
    return runs;
  }

}
