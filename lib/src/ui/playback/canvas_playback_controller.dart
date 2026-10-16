import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

import '../../models/cut_id.dart';
import '../../models/project.dart';
import '../../models/project_frame_rate.dart';
import '../../models/track_id.dart';
import '../../models/track_transitions.dart'
    show cutDrawnFrameCount, cutMediaStartFrame;
import '../../services/playback/playback_frame_mapping.dart';
import '../../services/playback/playhead_way.dart';
import '../../models/storyboard_timeline_layout.dart';
import 'playback_transport.dart';
import 'looking_ticker.dart';
import '../present_pacing.dart';

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
/// to say ([waitsOn]): the clock stands before it until it is.
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
  ///
  /// [frameTime] is the moment the frame the tick runs in is SHOWN
  /// ([frameShownAt]): the clock is read at THAT time, not at the moment
  /// the tick happens to run (`FrameTimeOnDevice`) — what is heard as the
  /// picture is seen. Null reads it now.
  ClockReading? Function({Duration? frameTime})? resolveAudioClock;

  /// Asked of every frame the run would stand on: whether its clock must
  /// WAIT there — the frame's picture is not made yet, or (rendering first)
  /// what lies ahead of it is not. `placed` when someone PUT the run on the
  /// frame — play was pressed there, the ruler was dragged there — rather
  /// than its clock reaching it. Null = the clock never waits.
  ///
  /// 유저 2026-10-08: 「거슬리는건 재생했는데 재생바는 지나가고있는데 그림이
  /// 없어서 비어있다던가」 · 「안구워진곳에 닿으면 그 자리에서 만들어서
  /// 보여주기때문에 그 자리에서 멈췃다가 구워지면 이어서 재생」. The playhead
  /// does not pass a frame that is not there: it stands BEFORE it, on the
  /// last frame it showed ([playheadWay] — 유저 2026-10-15, F-365-Q1), and
  /// [lookAgain] is how it hears the picture has come. A run PUT on such a
  /// frame has shown nothing to stand on, and waits on the frame itself.
  /// ↩️It stood ON the frame it waited for, over a picture that was not
  /// that frame's: white paper, at every cut's head on the iPad (F-365).
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

  /// The playlist frame whose picture the run waits for: the one after the
  /// frame it stands on, or that frame itself where the run was put on it.
  /// Null while it does not wait.
  int? _waitingFor;

  /// Whether the run's clock stands, waiting for a picture ([waitsOn]).
  ///
  /// 🚨WAITING IS NOT PAUSED, and T28 stands: playing, or not. Nobody can
  /// put a run into this state or take it out — there is no button for it —
  /// and it ends by itself the moment the picture lands. [isPlaying] stays
  /// true through it; what stands is the clock, and with it the sound.
  bool get isWaiting => _waitingFor != null;

  /// The run, while one plays: the cuts it shows, and the stretch of its
  /// track it plays ([PlaybackWindow]) — one field, so a run never has the
  /// one without the other.
  ({List<StoryboardTimelineLayoutEntry> playlist, PlaybackWindow window})?
  _run;
  PlaybackScope _scope = PlaybackScope.activeCut;
  PlaybackLoopMode _loopMode = PlaybackLoopMode.loop;
  int _baseGlobalFrame = 0;
  int _currentGlobalFrame = 0;
  int _droppedFrames = 0;

  /// Frames skipped to keep real time during the CURRENT loop pass
  /// (DaVinci-style dropped frame indicator); resets on every wrap-around
  /// and on play/seek. Counted where the playhead moves ([_countTheWay]):
  /// a frame the run WAITS before is not one it skipped.
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
  bool get isActive => _run != null;

  @override
  bool get isPlaying => _run != null;
  PlaybackScope get scope => _scope;

  /// The track frame [playlistFrame] of this run shows ([window]): a take
  /// or a cue stated on the track lands where the picture and the sound
  /// are.
  int trackFrameOf(int playlistFrame) =>
      (_run?.window.trackStart ?? 0) + playlistFrame;

  PlaybackLoopMode get loopMode => _loopMode;
  set loopMode(PlaybackLoopMode mode) {
    if (_loopMode == mode) {
      return;
    }
    _loopMode = mode;
    notifyListeners();
  }

  List<StoryboardTimelineLayoutEntry> get playlist =>
      List.unmodifiable(_run?.playlist ?? const []);

  /// The stretch of its track the run plays; null while nothing plays.
  PlaybackWindow? get window => _run?.window;

  PlaybackPosition? get position {
    final run = _run;
    if (run == null) {
      return null;
    }
    return resolvePlaybackPosition(
      playlist: run.playlist,
      globalFrameIndex: _currentGlobalFrame,
    );
  }

  /// The playlist frame the run stands on — where it stood last, once it
  /// has stopped.
  int get playlistFrame => _currentGlobalFrame;

  /// The run's frames ([PlaybackWindow.frames]); 0 while nothing plays.
  int get totalFrames => _run?.window.frames ?? 0;

  /// The run's layer provides vsync ([PlaybackRunLayer]); transport
  /// controls can call [play] before or after attachment (ticking starts
  /// once both are ready).
  void attachTicker(TickerProvider vsync) {
    _vsync = vsync;
    if (isPlaying && !isWaiting && !_clock.isRunning) {
      _startTicker();
    }
  }

  /// Lets the clock's ticker go — unless [vsync] names a provider that no
  /// longer holds it. A mount on its way out is let go of AFTER the one
  /// taking its place has attached (the tree mounts before it unmounts), and
  /// must not take the clock away from it.
  void detachTicker([TickerProvider? vsync]) {
    if (vsync != null && !identical(vsync, _vsync)) {
      return;
    }
    _stopTicker();
    _vsync = null;
  }

  void play({required PlaybackScope scope, int? startGlobalFrame}) {
    final playlist = _buildPlaylist(scope);
    final window = _windowOf(scope, playlist);
    if (window == null || window.frames == 0) {
      return;
    }
    _scope = scope;
    _run = (playlist: playlist, window: window);
    _droppedFrames = 0;
    _currentGlobalFrame = (startGlobalFrame ?? 0).clamp(0, window.frames - 1);
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
    final waits = waitsOn?.call(_currentGlobalFrame, placed: true) ?? false;
    _waitingFor = waits ? _currentGlobalFrame : null;
    if (waits) {
      _stopTicker();
    } else {
      // A fresh ticker, so its elapsed epoch rebases on this frame.
      _startTicker();
    }
  }

  /// A picture landed, or the warmer came to rest: a run that waits looks
  /// again, and if it need wait no longer it goes on — onto the frame it
  /// waited for, which has a whole frame's time from here, as if the clock
  /// had been stopped and started (the media viewer's `_goesOn`).
  ///
  /// ⚠️The frame changes HERE, before anyone is told: the device is armed
  /// again from the frame the run stands on when it hears the wait end
  /// (`AudioDeviceTransport`), and that is the frame whose sound goes with
  /// the picture that came.
  void lookAgain() {
    final waitingFor = _waitingFor;
    if (waitingFor == null) {
      return;
    }
    if (waitsOn?.call(waitingFor, placed: false) ?? false) {
      return;
    }
    _waitingFor = null;
    _countTheWay(to: waitingFor, passed: 0);
    _currentGlobalFrame = waitingFor;
    _startTicker();
    _syncFrameNotifiers();
    notifyListeners();
  }

  /// Jumps playback to a frame of the currently playing cut (ruler scrubs
  /// during playback); keeps playing/paused state.
  void seekToLocalFrame(int localFrameIndex) {
    final run = _run;
    final current = position;
    if (run == null || current == null) {
      return;
    }
    for (final entry in run.playlist) {
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
    final run = _run;
    if (run == null) {
      return;
    }
    _currentGlobalFrame = globalFrameIndex.clamp(0, run.window.frames - 1);
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
    final lastGlobal = _run == null ? null : _currentGlobalFrame;
    _stopTicker();
    _run = null;
    _waitingFor = null;
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
    _globalFrameIndexNotifier.value = _run == null
        ? null
        : _currentGlobalFrame;
  }

  /// The stretch of its track [play] would run for [scope] — the audio
  /// scrubber lays its sound over the same window, so scrubbed sound and
  /// played sound can never disagree about what sits where.
  PlaybackWindow? windowForScope(PlaybackScope scope) =>
      _windowOf(scope, _buildPlaylist(scope));

  /// Where [scope]'s run sits on its track. Null = nothing to play alone:
  /// the session stands in a gap.
  PlaybackWindow? _windowOf(
    PlaybackScope scope,
    List<StoryboardTimelineLayoutEntry> playlist,
  ) {
    final project = resolveProject();
    switch (scope) {
      case PlaybackScope.activeCut:
        if (playlist.isEmpty) {
          return null;
        }
        final alone = playlist.single;
        return PlaybackWindow(
          trackId: alone.trackId,
          // Its frame 0 is where its material starts — ahead of the conte
          // start in a cut an O.L arrives into (F-227 ④) — so the sound
          // plays from there too.
          trackStart: cutMediaStartFrame(project, alone.cutId)!,
          frames: alone.duration,
        );
      case PlaybackScope.allCuts:
        // The movie, to the end line the storyboard draws: past the last
        // cut its trailing frames play as the gap void (UI-R20 #3) — and
        // with no cut at all, those frames alone (F-341).
        return PlaybackWindow(
          trackId: resolveActiveTrackId(),
          trackStart: 0,
          frames: movieEndFrames(project),
        );
    }
  }

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
    final run = _run;
    if (run == null) {
      return;
    }
    final total = run.window.frames;
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
    final says =
        resolveAudioClock?.call(frameTime: frameShownAt()) ??
        _wallClock(elapsed, total);
    final shown = _currentGlobalFrame;
    if (says.ended && _loopMode == PlaybackLoopMode.once) {
      _endAt(total);
    } else {
      // A reading past either end is the end it is past; a step back is the
      // lap wrapping, and [_goTo] goes round the end to it.
      _goTo(says.globalFrame.clamp(0, total - 1), total);
    }
    if (_currentGlobalFrame != shown) {
      lookChangedWhatItShows();
    }
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
    if (!isWaiting) {
      stop();
    }
  }

  /// The clock says [frame]. The run goes there — unless a frame on the way
  /// has no picture yet, and then it stands before THAT frame ([waitsOn],
  /// [playheadWay]).
  void _goTo(int frame, int total) {
    final (:stands, :passed, :waitsFor) = playheadWay(
      from: _currentGlobalFrame,
      to: frame,
      total: total,
      waitsOn: (next) => waitsOn?.call(next, placed: false) ?? false,
    );
    _countTheWay(to: stands, passed: passed);
    if (waitsFor != null) {
      _waitFor(waitsFor, standing: stands);
    } else {
      _setFrame(stands);
    }
  }

  /// 🚨[droppedFrames] IS COUNTED HERE, OFF THE WAY THE PLAYHEAD WENT —
  /// from where it stands [to] where it goes, its clock's way ([_goTo]) or
  /// onto the frame it waited for ([lookAgain]): the [passed] frames gone
  /// over without standing on them. A move that wraps starts the new pass's
  /// count, and counts nothing. ↩️Each clock kept its own count off its own
  /// raw readings — the wall clock by lap, the device by a step back — and
  /// with a run that can wait both were wrong the same way: they counted
  /// the frames a run then WAITED before, which it went on to show. Each
  /// also left a last reading behind, which a run going on from a wait had
  /// to remember to forget.
  void _countTheWay({required int to, required int passed}) {
    if (to < _currentGlobalFrame) {
      _droppedFrames = 0;
    } else {
      _droppedFrames += passed;
    }
  }

  /// The run stands on [standing], where its way stopped, and its clock
  /// with it until [frame]'s picture comes ([lookAgain]).
  void _waitFor(int frame, {required int standing}) {
    _waitingFor = frame;
    _stopTicker();
    _currentGlobalFrame = standing;
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
