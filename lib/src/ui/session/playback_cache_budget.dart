import 'package:flutter/foundation.dart';
import '../../models/composite_tree.dart';
import '../../models/cut.dart';
import '../../models/cut_id.dart';
import '../../services/playback/cut_composite_structure.dart';
import '../../services/playback/frame_demand.dart';
import '../canvas/canvas_layer_stack_view.dart' show CanvasStackRow;
import '../playback/playback_cache_budget.dart';
import '../playback/frame_pictures.dart';
import '../playback/playback_pictures.dart' show PictureState;
import '../playback/canvas_playback_controller.dart';
import '../playback/playback_prerender_scheduler.dart' show PictureRoom;
import '../playback/stacked_frame_picture.dart' show FramePictureKey;
import '../timeline/timeline_ruler_cursor_overlay.dart'
    show ReadyRun, appendReadyRun;
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

  /// Whether a hand is on ([PlaybackPrerenderScheduler.handOn]) — what the
  /// bars that count the frames ready wait behind (F-620-Q3).
  ValueListenable<bool> get handOn;

  /// The open cut's frame at the playhead as the canvas shows it — every
  /// drag in flight in it, written or not: what a hand moves.
  List<CompositeNode<CanvasStackRow>> stackShown();

  /// Whether what a hand shows in flight, not written, moves what frames
  /// are made of — anywhere in the cut, the frame stood on or not.
  bool framesInFlight();
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
    _run.pictures.fitNodes();
    _playbackCacheBudgetEnforcer.enforce(
      wantedAt: _run.pictures.wantedAt(_run.demand),
      lentBytes: _besideThePictures,
    );
  }

  @override
  int get bytes =>
      _playbackCacheBudgetEnforcer.room(lentBytes: _besideThePictures);

  /// What the line holds beside the frames' pictures, which give way to it:
  /// the pictures the nodes of the frame a screen stands on are held in
  /// (`FramePictures.heldNodes`) — taken off the pictures made ahead
  /// ([bytesForNodes]), never laid past the line.
  int get _besideThePictures => _run.pictures.heldNodes.heldBytes;

  /// How much of the line the nodes over a pen may hold, one by one
  /// (`FramePictures.heldNodes`): all of it but what a screen shows and
  /// what lies below the pen held — the frames' pictures made ahead give
  /// way to them ([giveWayToNodes]). 🗣️유저 2026-10-27 (Q3 = c):
  /// 「위 폴더는 하나씩, 재생 메모리 몫 안에서 전부」.
  @override
  int get bytesForNodes {
    final room = _playbackCacheBudgetEnforcer.lendableBytes();
    return room < 0 ? 0 : room;
  }

  @override
  int get bytesLeftFree {
    final free = bytes - _renderCaches.framePictureStore.estimatedBytes;
    return free < 0 ? 0 : free;
  }

  @override
  void giveWayToNodes() => enforcePlaybackCacheBudget();

  /// Lets go of [key]'s picture where no step of the run wants it and no
  /// screen holds it — what the line holds is what the warmer follows
  /// ([enforcePlaybackCacheBudget] keeps by the same two).
  ///
  /// 🚨What a panel cuts its picture from and leaves (`PanelPictures`,
  /// F-533): a storyboard's fifty cuts are fifty frames no one plays.
  /// 🔬↩️They stayed on the line, let go of only past it — Surface Pro 11,
  /// S5_BA with the storyboard open, 2026-11-05: 44 more pictures held at
  /// the first stroke, 1,611 → 2,596MB, and rss 6.1–6.3 → 7.6–7.8GB where
  /// the GPU's pictures are the RAM's.
  void letGoUnwanted(FramePictureKey key) {
    if (_run.pictures.wantedAt(_run.demand)(key) == null) {
      _renderCaches.framePictureStore.letGoUnpinned(key);
    }
  }

  @override
  bool makeRoomFor({required int bytes, required int step}) =>
      _playbackCacheBudgetEnforcer.makeRoomFor(
        bytes: bytes,
        step: step,
        within: this.bytes,
        wantedAt: _run.pictures.wantedAt(_run.demand),
      );

  /// The OS memory warning, the playback caches' share: the enforcer
  /// lowers its cap, and the trim runs against the lowered cap at once —
  /// the frame's nodes held let go of first, as they only make a stroke's
  /// steps cheaper.
  void respondToMemoryPressure() {
    _run.pictures.letGoOfNodes();
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
  ///
  /// 🗣️AND WHILE A HAND MOVES WHAT THE FRAMES ARE MADE OF, THE CUT IT IS IN
  /// STANDS NOT READY, COUNTED ONCE IT LETS GO (F-620-Q3 = 2, 유저
  /// 2026-11-19 「끄는 동안은 세지 않는다 — 띠는 그 컷 전체를 「준비 안
  /// 됨」으로」): a value dragged changes the tree at every step, and every
  /// step counted the bar anew — 🔬~7 ms of the UI thread a value (Surface,
  /// S5_BA cut 352). Under a hand whose tree still stands — a scrub, a
  /// stroke — the bar counts as ever ([_handMovedTheFrames]).
  ///
  /// 🗣️AND ONLY WHERE THE FRAMES MOVED (F-620-Q4 = 1, 유저 2026-11-19
  /// 「카메라는 초록 그대로」): a hand that moves the tree and none of the
  /// frames' pictures — the open cut's camera, which a frame is not made
  /// of — counts as ever, and its bar stays as the frames stand. ↩️It asked
  /// the tree alone: a camera dragged stood the cut not ready wherever the
  /// bar happened to be asked under it, and green wherever nothing asked —
  /// two answers to one drag (검증/서피스 19:30, F-620).
  List<ReadyRun> playbackReadyRunsForCut(
    Cut cut,
    int start,
    int end, {
    required bool paintPaper,
  }) {
    _hearTheHand();
    if (cut.id == _project.activeCutOrNull?.id && _handMovedTheFrames()) {
      _countOwed = true;
      return const [];
    }
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
      appendReadyRun(runs, (
        startIndex: span.start,
        endIndexExclusive: span.endExclusive,
        unreadable: unreadable,
      ));
    }
    return runs;
  }

  /// What a bar that counts the frames ready hears: whatever moves where a
  /// frame stands ([FramePictures.standingMoved]), and a hand letting go of
  /// a count put off under it ([playbackReadyRunsForCut]).
  Listenable get readinessMoved {
    _hearTheHand();
    return _readinessMoved;
  }

  late final Listenable _readinessMoved = Listenable.merge([
    _run.pictures.standingMoved,
    _countDue,
  ]);

  /// The tree the frames were made of as the hand came down
  /// ([FramePictures.treeStamp]) — null while no hand is on.
  Object? _treeUnderTheHand;

  /// The key of the frame the warmer stood on as the hand came down — the
  /// open cut's first where it stood on none — as the canvas showed it
  /// ([_keyStoodOn]): what says whether the frames moved under the hand,
  /// the tree having moved. A value is dragged at the frame stood on, and
  /// a frame the camera places nothing on keeps its key.
  FramePictureKey? _keyUnderTheHand;

  /// Whether a bar was answered not ready under the hand, to be counted
  /// once it lets go ([_countDue]).
  bool _countOwed = false;

  final ValueNotifier<int> _countDue = ValueNotifier<int>(0);

  bool _hearing = false;

  /// The hand, heard from the first asking on: the run's scheduler is made
  /// after this budget ([PlaybackRun.handOn]), so the constructor cannot.
  void _hearTheHand() {
    if (_hearing) {
      return;
    }
    _hearing = true;
    _run.handOn.addListener(_handMoved);
    _handMoved();
  }

  void _handMoved() {
    if (_run.handOn.value) {
      _treeUnderTheHand = _run.pictures.treeStamp?.call();
      _keyUnderTheHand = _keyStoodOn();
      return;
    }
    _treeUnderTheHand = null;
    _keyUnderTheHand = null;
    if (_countOwed) {
      _countOwed = false;
      _countDue.value += 1;
    }
  }

  /// [_keyUnderTheHand] as it stands now — null without an open cut.
  ///
  /// 🚨SIGNED AS THE CANVAS SHOWS IT ([PlaybackRun.stackShown]), not as the
  /// cut stores it: a value dragged — the cel number's box, a lane's colour
  /// wheel — is shown, not written, till the hand lets go. ↩️Signed off the
  /// stored cut ([FramePictures.keyOf]), it never moved under such a drag
  /// and the bar stood full through it (🔬검증/서피스 21:36, F-620: 673/673
  /// at its lowest on d8b74fb46, 0 on 8818dd306) — the pins moved the
  /// frames by the paper's colour, which the stored cut reads.
  FramePictureKey? _keyStoodOn() {
    final cut = _project.activeCutOrNull;
    if (cut == null) {
      return null;
    }
    return _run.pictures.keyOfStack(
      _run.stackShown(),
      _asTheBarAsks(cut, frameStoodOn(_run.demand, cut.id)),
    );
  }

  /// Whether a hand is on and the frames have moved since it came down:
  /// what it shows in flight ([PlaybackRun.framesInFlight]), or the tree
  /// and the key of the frame stood on ([_keyUnderTheHand]).
  ///
  /// 🔬관제 11-19 22:4x (「어느 값이든 그림이 바뀌면 비고」 — every door, every
  /// family): ↩️the frame stood on alone was asked, as if every value were
  /// dragged there — a key's handle, the frames between two keys moved and
  /// the key's own frame not, left the bar full, and a row's opacity slider
  /// moved no stamp at all. What is shown in flight says so of itself; the
  /// key of the frame stood on answers for what is written under the hand.
  bool _handMovedTheFrames() {
    final under = _treeUnderTheHand;
    if (under == null) {
      return false;
    }
    if (_run.framesInFlight()) {
      return true;
    }
    if (_run.pictures.treeStamp?.call() == under) {
      return false;
    }
    final stood = _keyUnderTheHand;
    return stood != null && _keyStoodOn() != stood;
  }

  /// The frame of [cutId] the warmer stands on — what [demand] shows first
  /// ([FrameDemand.picturesAt] 0, the playhead's) — or its first where it
  /// shows none of it.
  @visibleForTesting
  static int frameStoodOn(FrameDemand? demand, CutId cutId) =>
      demand
          ?.picturesAt(0)
          ?.where((shown) => shown.cut.id == cutId)
          .firstOrNull
          ?.frameIndex ??
      0;

  /// [cut]'s frame [frameIndex] as the timeline's bar asks for it: on its
  /// paper, no ghosts ([playbackReadyRuns]).
  static DemandedPicture _asTheBarAsks(Cut cut, int frameIndex) => (
    cut: cut,
    frameIndex: frameIndex,
    paintPaper: true,
    ghosts: FrameGhosts.none,
  );
}
