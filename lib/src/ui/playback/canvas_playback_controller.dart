import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

import '../../models/cut_id.dart';
import '../../models/project.dart';
import '../../models/project_frame_rate.dart';
import '../../models/track_id.dart';
import '../../models/track_transitions.dart'
    show cutDrawnFrameCount, cutMediaStartFrame, cutTransitionHandlesIn;
import '../../services/playback/playback_frame_mapping.dart';
import '../../models/storyboard_timeline_layout.dart';
import 'playback_transport.dart';
import 'looking_ticker.dart';

/// What plays: the active cut (timeline context) or every cut of the active
/// track in sequence (storyboard context).
enum PlaybackScope { activeCut, allCuts }

enum PlaybackLoopMode { loop, once }

/// What a run's clock says when it is looked at.
///
/// [globalFrame] is the playlist frame the run is on by that clock;
/// [ended], that the clock has run past the run's end — which ends a run
/// that plays once, and is the lap wrapping for one that loops.
///
/// Both clocks say it. The device's is the audio-master clock (audio
/// program wiring): its frame is the one containing what is being HEARD
/// right now, and the device transport produces it. The wall clock's is
/// the controller's own, read when no device carries the run.
class ClockReading {
  const ClockReading({required this.globalFrame, this.ended = false});

  final int globalFrame;
  final bool ended;
}

/// Real-time canvas playback state machine.
///
/// Frame indexes derive from the ticker's wall-clock elapsed time, so when
/// the app's own frames fall behind, playback frames are skipped rather than
/// time stretched (Premiere/AE behavior). Notifies only when the resolved
/// frame actually changes; the heavyweight session playhead syncs once via
/// [onStopped].
///
/// A frame whose PICTURE is not made yet is another matter, and the owner's
/// to say ([waitsOn]): the clock stands on it until it is.
class CanvasPlaybackController extends ChangeNotifier
    implements PlaybackTransport {
  CanvasPlaybackController({
    required this.resolveProject,
    required this.resolveActiveCutId,
    required this.resolveActiveTrackId,
    required this.resolveFrameRate,
    this.onStopped,
    this.onStoppedInGap,
    this.onPlaylistWarmRequested,
  });

  final Project Function() resolveProject;

  /// Null = the session stands in a gap (no active cut, UI-R9 #3): an
  /// active-cut-scoped [play] resolves an empty playlist and no-ops.
  final CutId? Function() resolveActiveCutId;
  final TrackId Function() resolveActiveTrackId;
  final ProjectFrameRate Function() resolveFrameRate;

  /// Fired on [stop] with the last position so the owner can sync the real
  /// playhead (and switch the active cut after a play-all run).
  final void Function(PlaybackPosition lastPosition)? onStopped;

  /// Fired on [stop] when the last frame was a playlist GAP (no position):
  /// the owner parks the editing playhead there with NO active cut
  /// (UI-R9 #3 — stopping in a gap matches the editing gap semantics).
  final void Function(int globalFrame)? onStoppedInGap;

  /// Fired on [play], the run's playlist and first frame in hand, so the
  /// owner can have the warmer follow it from there.
  final void Function(
    List<StoryboardTimelineLayoutEntry> playlist,
    PlaybackScope scope,
    int startGlobalFrame,
  )?
  onPlaylistWarmRequested;

  /// The audio-master clock, set by the owner when a device transport
  /// carries playback. Read EVERY tick: non-null readings drive the
  /// picture from samples handed to the audio device ("the picture
  /// follows the sound"); null falls back to the wall-clock derivation.
  /// The ticker keeps running either way — it is the polling cadence, the
  /// clock is whose TIME gets shown.
  ClockReading? Function()? resolveAudioClock;

  /// Asked of every frame the run would stand on: whether its clock must
  /// WAIT there — the frame's picture is not made yet, or (rendering first)
  /// what lies ahead of it is not. `placed` when someone PUT the run on the
  /// frame — play was pressed there, the ruler was dragged there — rather
  /// than its clock reaching it. Null = the clock never waits.
  ///
  /// 유저 2026-10-08: 「거슬리는건 재생했는데 재생바는 지나가고있는데 그림이
  /// 없어서 비어있다던가」 · 「안구워진곳에 닿으면 그 자리에서 만들어서
  /// 보여주기때문에 그 자리에서 멈췃다가 구워지면 이어서 재생」. The playhead
  /// stops ON the frame that is not there — it does not pass it — and
  /// [lookAgain] is how it hears the picture has come.
  bool Function(int playlistFrame, {required bool placed})? waitsOn;

  /// Fired on every explicit seek with the clamped target frame, so a
  /// device transport can move without inferring the jump from frame
  /// deltas. (With the audio clock driving the picture, an un-forwarded
  /// seek would simply snap back to the device's position on the next
  /// tick.)
  void Function(int globalFrame)? onSeeked;

  TickerProvider? _vsync;

  /// The run's clock: looked at on every vsync — and a vsync it was only
  /// looked at on is not drawn ([LookingTicker]).
  late final LookingTicker _clock = LookingTicker(_onTick);

  final ValueNotifier<int?> _localFrameIndex = ValueNotifier<int?>(null);

  /// The playing cut's local frame index, `null` while playback is inactive.
  ///
  /// Playback-only signal for the timeline playhead: subscribing here lets
  /// the playhead follow every tick WITHOUT rebuilding the whole editor
  /// (never route ticks through the session's notifyListeners).
  ValueListenable<int?> get localFrameIndexListenable => _localFrameIndex;

  final ValueNotifier<int?> _globalFrameIndexNotifier = ValueNotifier<int?>(
    null,
  );

  /// The playlist-global frame index, `null` while playback is inactive.
  ///
  /// Superset signal of [localFrameIndexListenable]: it also fires on
  /// cross-cut seeks that happen to land on the same local frame (the
  /// storyboard playhead follows this one).
  ValueListenable<int?> get globalFrameIndexListenable =>
      _globalFrameIndexNotifier;

  final ValueNotifier<bool> _isActiveNotifier = ValueNotifier<bool>(false);

  /// Fires only when playback mode is entered/left — the canvas area swaps
  /// its content on this instead of listening to every tick (subscribing the
  /// whole canvas subtree to ticks rebuilt it at fps and caused real frame
  /// drops).
  @override
  ValueListenable<bool> get isActiveListenable => _isActiveNotifier;

  bool _waiting = false;

  /// Whether the run's clock stands on its frame, waiting for the picture
  /// ([waitsOn]).
  ///
  /// 🚨WAITING IS NOT PAUSED, and T28 stands: playing, or not. Nobody can
  /// put a run into this state or take it out — there is no button for it —
  /// and it ends by itself the moment the picture lands. [isPlaying] stays
  /// true through it; what stands is the clock, and with it the sound.
  bool get isWaiting => _waiting;

  List<StoryboardTimelineLayoutEntry>? _playlist;
  PlaybackScope _scope = PlaybackScope.activeCut;
  PlaybackLoopMode _loopMode = PlaybackLoopMode.loop;
  int _baseGlobalFrame = 0;
  int _currentGlobalFrame = 0;
  int _droppedFrames = 0;

  /// Frames skipped to keep real time during the CURRENT loop pass
  /// (DaVinci-style dropped frame indicator); resets on every wrap-around
  /// and on play/seek. Counted where the playhead moves ([_goTo]): a frame
  /// the run WAITS before is not one it skipped.
  int get droppedFrames => _droppedFrames;

  /// 🚨★★★ T28 — PLAYING, OR NOT. There is no third state.
  ///
  /// 유저 확정 2026-08-13: 「재생, 일시정지상태의 **필요성을 못느끼겠음**.
  /// 삭제하고 **재생/정지 상태만** 남김 … 일시정지는 **버그도많고** 굳이?
  /// tvp에서도 일시정지기능 한번도 활용안해봄 … **비디오 재생이라면
  /// 일시정지가 의미가 있겠지만 애니메이션에서는 애초에 재생아닌상태가
  /// 일시정지상태나 다름없음**」
  ///
  /// ★The argument is about the domain, not about a button. A video's
  /// "where it stopped" is a state you have to keep; an animation's playhead
  /// is ALWAYS standing somewhere, so 「정지」 and 「일시정지」 were two names
  /// for one state. Removing pause deletes a state, not a feature.
  ///
  /// ⛔[isActive] and [isPlaying] are now the SAME question, and both stay
  /// only because half the codebase asks it each way. Anything written as
  /// `isActive && !isPlaying` describes a state that can no longer occur —
  /// treat such a gate as a bug rather than bringing pause back to satisfy
  /// it.
  bool get isActive => _playlist != null;

  @override
  bool get isPlaying => _playlist != null;
  PlaybackScope get scope => _scope;

  /// The track frame [playlistFrame] of this run shows. The all-cuts
  /// playlist IS the track axis; a cut played alone starts where its
  /// material does — ahead of its conte start in a cut an O.L arrives into
  /// ([cutMediaStartFrame], F-227 ④) — so a take or a cue stated on the
  /// track lands where the picture and the sound are.
  int trackFrameOf(int playlistFrame) {
    if (_scope == PlaybackScope.allCuts) {
      return playlistFrame;
    }
    final cutId = resolveActiveCutId();
    final start = cutId == null
        ? null
        : cutMediaStartFrame(resolveProject(), cutId);
    return (start ?? 0) + playlistFrame;
  }

  PlaybackLoopMode get loopMode => _loopMode;
  set loopMode(PlaybackLoopMode mode) {
    if (_loopMode == mode) {
      return;
    }
    _loopMode = mode;
    notifyListeners();
  }

  List<StoryboardTimelineLayoutEntry> get playlist =>
      List.unmodifiable(_playlist ?? const []);

  PlaybackPosition? get position {
    final playlist = _playlist;
    if (playlist == null) {
      return null;
    }
    return resolvePlaybackPosition(
      playlist: playlist,
      globalFrameIndex: _currentGlobalFrame,
    );
  }

  /// The playlist frame the run stands on — where it stood last, once it
  /// has stopped.
  int get playlistFrame => _currentGlobalFrame;

  /// The run's frames, the all-cuts scope's trailing gap included; 0 while
  /// nothing plays.
  int get totalFrames {
    final playlist = _playlist;
    return playlist == null ? 0 : _playbackTotalFrames(playlist);
  }

  /// The playback view provides vsync; transport controls can call [play]
  /// before or after attachment (ticking starts once both are ready).
  void attachTicker(TickerProvider vsync) {
    _vsync = vsync;
    if (isPlaying && !_waiting && !_clock.isRunning) {
      _startTicker();
    }
  }

  void detachTicker() {
    _stopTicker();
    _vsync = null;
  }

  /// The run's TOTAL frames: the playlist's content plus — for the
  /// all-cuts scope — the movie's TRAILING GAP (UI-R20 #3: the final
  /// length is authored past the last cut; those frames play as the
  /// gap void, exactly like mid-track gaps).
  int _playbackTotalFrames(List<StoryboardTimelineLayoutEntry> playlist) {
    final base = playlistTotalFrames(playlist);
    if (base == 0 || _scope != PlaybackScope.allCuts) {
      return base;
    }
    return base + resolveProject().trailingFrames;
  }

  void play({required PlaybackScope scope, int? startGlobalFrame}) {
    final playlist = _buildPlaylist(scope);
    if (playlistTotalFrames(playlist) == 0) {
      return;
    }
    _scope = scope;
    _playlist = playlist;
    _droppedFrames = 0;
    _currentGlobalFrame = (startGlobalFrame ?? 0).clamp(
      0,
      _playbackTotalFrames(playlist) - 1,
    );
    onPlaylistWarmRequested?.call(playlist, scope, _currentGlobalFrame);

    _standHere();
    _syncFrameNotifiers();
    _isActiveNotifier.value = true;
    notifyListeners();
  }

  /// The run stands on its frame by someone's hand — play was pressed
  /// there, the ruler was dragged there: its clock starts from this frame,
  /// or waits on it for its picture.
  void _standHere() {
    _waiting = waitsOn?.call(_currentGlobalFrame, placed: true) ?? false;
    if (_waiting) {
      _stopTicker();
    } else {
      // A fresh ticker, so its elapsed epoch rebases on this frame.
      _startTicker();
    }
  }

  /// A picture landed, or the warmer came to rest: a run that waits looks
  /// again, and goes on from the frame it stands on if it need wait no
  /// longer — a whole frame's time from here, as if the clock had been
  /// stopped and started.
  void lookAgain() {
    if (!_waiting || _playlist == null) {
      return;
    }
    if (waitsOn?.call(_currentGlobalFrame, placed: false) ?? false) {
      return;
    }
    _waiting = false;
    _startTicker();
    notifyListeners();
  }

  /// Jumps playback to a frame of the currently playing cut (ruler scrubs
  /// during playback); keeps playing/paused state.
  void seekToLocalFrame(int localFrameIndex) {
    final playlist = _playlist;
    final current = position;
    if (playlist == null || current == null) {
      return;
    }
    for (final entry in playlist) {
      if (current.globalFrameIndex >= entry.startFrame &&
          current.globalFrameIndex < entry.endFrame) {
        final clamped = localFrameIndex.clamp(0, entry.duration - 1);
        seekToGlobalFrame(entry.startFrame + clamped);
        return;
      }
    }
  }

  /// Jumps playback to a playlist-global frame (storyboard ruler seeks can
  /// cross cut boundaries); keeps playing/paused state.
  void seekToGlobalFrame(int globalFrameIndex) {
    final playlist = _playlist;
    if (playlist == null) {
      return;
    }
    final total = _playbackTotalFrames(playlist);
    if (total == 0) {
      return;
    }
    _currentGlobalFrame = globalFrameIndex.clamp(0, total - 1);
    _droppedFrames = 0;
    if (isPlaying) {
      _standHere();
    }
    onSeeked?.call(_currentGlobalFrame);
    _syncFrameNotifiers();
    notifyListeners();
  }

  /// ⛔`pause()` and `resume()` are GONE (T28). They were the two doors of a
  /// state this app does not have; see [isActive]. Stopping leaves the
  /// playhead exactly where it was — 「재생아닌상태가 일시정지상태나
  /// 다름없음」 is the whole argument, and it only holds if stop does not
  /// rewind.
  @override
  void stop() {
    if (!isActive) {
      return;
    }
    final lastPosition = position;
    final lastGlobal = _playlist == null ? null : _currentGlobalFrame;
    _stopTicker();
    _playlist = null;
    _waiting = false;
    _syncFrameNotifiers();
    _isActiveNotifier.value = false;
    notifyListeners();
    if (lastPosition != null) {
      onStopped?.call(lastPosition);
    } else if (lastGlobal != null) {
      onStoppedInGap?.call(lastGlobal);
    }
  }

  @override
  void dispose() {
    _stopTicker();
    _localFrameIndex.dispose();
    _globalFrameIndexNotifier.dispose();
    _isActiveNotifier.dispose();
    super.dispose();
  }

  void _syncFrameNotifiers() {
    _localFrameIndex.value = position?.localFrameIndex;
    _globalFrameIndexNotifier.value = _playlist == null
        ? null
        : _currentGlobalFrame;
  }

  /// The playlist [play] would run for [scope] — the audio scrubber builds
  /// its schedule from the same shape, so scrubbed sound and played sound
  /// can never disagree about what sits where.
  List<StoryboardTimelineLayoutEntry> playlistForScope(PlaybackScope scope) =>
      _buildPlaylist(scope);

  List<StoryboardTimelineLayoutEntry> _buildPlaylist(PlaybackScope scope) {
    switch (scope) {
      case PlaybackScope.activeCut:
        final activeCutId = resolveActiveCutId();
        final project = resolveProject();
        for (final entry in buildStoryboardTimelineLayout(project)) {
          if (entry.cutId == activeCutId) {
            // 🗣️F-227 (유저 2026-09-29): 「재생도 타임라인패널의 재생이면 여백까지
            // 재생」 — the cut plays every frame it is DRAWN for, through the
            // のりしろ an O.L asks of it, not to the red line.
            final duration = cutDrawnFrameCount(project, entry.cutId)!;
            return [
              StoryboardTimelineLayoutEntry(
                trackId: entry.trackId,
                cutId: entry.cutId,
                trackIndex: entry.trackIndex,
                cutIndex: entry.cutIndex,
                startFrame: 0,
                endFrame: duration,
                duration: duration,
                cut: entry.cut,
                // Its frame 0 is where its material starts — ahead of the
                // conte start in a cut an O.L arrives into — so the sound
                // plays from there too.
                mediaLead: cutTransitionHandlesIn(project, entry.cutId).head,
              ),
            ];
          }
        }
        return const [];
      case PlaybackScope.allCuts:
        final trackId = resolveActiveTrackId();
        return buildStoryboardTimelineLayout(
          resolveProject(),
        ).where((entry) => entry.trackId == trackId).toList();
    }
  }

  void _startTicker() {
    final vsync = _vsync;
    if (vsync == null) {
      return;
    }
    _baseGlobalFrame = _currentGlobalFrame;
    _clock.start(vsync);
  }

  /// Every way a run's clock ends — stopped, dragged, stood on a frame to
  /// wait, its view gone, the controller itself — comes through here.
  void _stopTicker() => _clock.stop();

  void _onTick(Duration elapsed) {
    final playlist = _playlist;
    if (playlist == null) {
      return;
    }
    final total = _playbackTotalFrames(playlist);
    // 🚨ONE LAW FOR BOTH CLOCKS: each is read on EVERY vsync, so its frame
    // changes on the first vsync it is due on, and what it says is followed
    // the one way. (What looking that often costs the screen is not paid:
    // [LookingTicker].) ↩️For a day each slept between frames and a timer
    // woke it; before that the device was asked every 3ms off the ticker.
    // Both changed frames late — `LookOnlyFrames` has the measurements.
    //
    // ⚠️In the app the device's is the clock of every run, silent ones
    // too: an empty schedule uploads like any other and rides the device.
    // When the app's frames fall behind it, playback frames are dropped —
    // the sound is not made to wait for them. It waits only where the
    // picture itself is not made ([waitsOn]), and then the device is
    // stopped with the clock ([isWaiting]).
    final says = resolveAudioClock?.call() ?? _wallClock(elapsed, total);
    if (says.ended && _loopMode == PlaybackLoopMode.once) {
      _endAt(total);
      return;
    }
    // A reading past either end is the end it is past; a step back is the
    // lap wrapping, and [_goTo] goes round the end to it.
    _goTo(says.globalFrame.clamp(0, total - 1), total);
  }

  /// What the wall clock says [elapsed] after the run's ticker started on
  /// [_baseGlobalFrame]: the frames that time holds, folded into the run.
  ClockReading _wallClock(Duration elapsed, int total) {
    final frame =
        _baseGlobalFrame + elapsedToGlobalFrame(elapsed, resolveFrameRate());
    return ClockReading(globalFrame: frame % total, ended: frame >= total);
  }

  /// A run that plays once has run out: it stops on its last frame — once
  /// that frame has been shown.
  void _endAt(int total) {
    _goTo(total - 1, total);
    if (!_waiting) {
      stop();
    }
  }

  /// The clock says [frame]. The run goes there — unless a frame on the way
  /// has no picture yet, and then it stands on THAT frame ([waitsOn]): a
  /// tick that came late does not carry the playhead over a picture that
  /// was never shown.
  ///
  /// 🚨[droppedFrames] IS COUNTED HERE, OFF THE WAY THE PLAYHEAD WENT: the
  /// frames it passed without standing on them. A move that wraps starts
  /// the new pass's count, and counts nothing. ↩️Each clock kept its own
  /// count off its own raw readings — the wall clock by lap, the device by
  /// a step back — and with a run that can wait both were wrong the same
  /// way: they counted the frames a run then WAITED before, which it went
  /// on to show. Each also left a last reading behind, which a run going on
  /// from a wait had to remember to forget.
  void _goTo(int frame, int total) {
    final from = _currentGlobalFrame;
    // The frames on the way, in the order the run plays them, the clock's
    // own last. Either clock only ever moves on — a step back is the lap
    // wrapping — so the way from here to there is forwards, round the end.
    //
    // 🚨COUNTED, not walked 「until it gets there」: a frame outside the run
    // is never got to, and that walk never ended — found by a mutant that
    // took the clamp off the device's reading and hung its test, which in
    // the app is a frozen window. However far the frame is, it is fewer
    // steps ahead than the run has frames.
    final ahead = (frame - from) % total;
    var landing = from;
    var passed = -1;
    var waits = false;
    for (var step = 0; step < ahead && !waits; step += 1) {
      landing = (landing + 1) % total;
      passed += 1;
      waits = waitsOn?.call(landing, placed: false) ?? false;
    }
    if (landing < from) {
      _droppedFrames = 0;
    } else if (passed > 0) {
      _droppedFrames += passed;
    }
    if (waits) {
      _waitOn(landing);
    } else {
      _setFrame(landing);
    }
  }

  void _waitOn(int frame) {
    _waiting = true;
    _stopTicker();
    _currentGlobalFrame = frame;
    _syncFrameNotifiers();
    notifyListeners();
  }

  void _setFrame(int frame) {
    if (frame == _currentGlobalFrame) {
      return;
    }
    _currentGlobalFrame = frame;
    _syncFrameNotifiers();
    notifyListeners();
  }
}
