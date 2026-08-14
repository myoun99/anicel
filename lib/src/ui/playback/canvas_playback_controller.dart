import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

import '../../models/cut_id.dart';
import '../../models/project.dart';
import '../../models/project_frame_rate.dart';
import '../../models/track_id.dart';
import '../../services/playback/playback_frame_mapping.dart';
import '../storyboard_timeline_layout.dart';

/// What plays: the active cut (timeline context) or every cut of the active
/// track in sequence (storyboard context).
enum PlaybackScope { activeCut, allCuts }

enum PlaybackLoopMode { loop, once }

/// One reading of the audio-master clock (audio program wiring).
///
/// [globalFrame] is the playlist frame containing what is being HEARD
/// right now; [ended] reports that a non-looping transport ran out. The
/// device transport produces these; the controller consumes them instead
/// of its wall clock whenever they are available.
class AudioClockStatus {
  const AudioClockStatus({required this.globalFrame, this.ended = false});

  final int globalFrame;
  final bool ended;
}

/// Real-time canvas playback state machine.
///
/// Frame indexes derive from the ticker's wall-clock elapsed time, so when
/// rendering falls behind, frames are skipped rather than time stretched
/// (Premiere/AE behavior). Notifies only when the resolved frame actually
/// changes; the heavyweight session playhead syncs once via [onStopped].
class CanvasPlaybackController extends ChangeNotifier {
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

  /// Fired on [play] so the prerender scheduler can warm the playlist;
  /// [startGlobalFrame] lets warming run playhead-forward (wrapping) so the
  /// frames about to play always warm first.
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
  AudioClockStatus? Function()? resolveAudioClock;

  /// Fired on every explicit seek with the clamped target frame, so a
  /// device transport can move without inferring the jump from frame
  /// deltas. (With the audio clock driving the picture, an un-forwarded
  /// seek would simply snap back to the device's position on the next
  /// tick.)
  void Function(int globalFrame)? onSeeked;

  TickerProvider? _vsync;
  Ticker? _ticker;

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
  ValueListenable<bool> get isActiveListenable => _isActiveNotifier;

  List<StoryboardTimelineLayoutEntry>? _playlist;
  PlaybackScope _scope = PlaybackScope.activeCut;
  PlaybackLoopMode _loopMode = PlaybackLoopMode.loop;
  int _baseGlobalFrame = 0;
  int _currentGlobalFrame = 0;
  int _droppedFrames = 0;
  int? _lastRawFrame;
  int _lastLap = 0;

  /// Frames skipped to keep real time during the CURRENT loop pass
  /// (DaVinci-style dropped frame indicator); resets on every wrap-around
  /// and on play/seek.
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

  bool get isPlaying => _playlist != null;
  PlaybackScope get scope => _scope;

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

  /// The playback view provides vsync; transport controls can call [play]
  /// before or after attachment (ticking starts once both are ready).
  void attachTicker(TickerProvider vsync) {
    _vsync = vsync;
    if (isPlaying && _ticker == null) {
      _startTicker();
    }
  }

  void detachTicker() {
    _ticker?.dispose();
    _ticker = null;
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
    _resetDropAccounting();
    _currentGlobalFrame = (startGlobalFrame ?? 0).clamp(
      0,
      _playbackTotalFrames(playlist) - 1,
    );
    onPlaylistWarmRequested?.call(playlist, scope, _currentGlobalFrame);

    _startTicker();
    _syncFrameNotifiers();
    _isActiveNotifier.value = true;
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
    _resetDropAccounting();
    if (isPlaying) {
      // Restart the ticker so its elapsed epoch rebases on the new frame.
      _startTicker();
    }
    onSeeked?.call(_currentGlobalFrame);
    _syncFrameNotifiers();
    notifyListeners();
  }

  void _resetDropAccounting() {
    _droppedFrames = 0;
    _lastRawFrame = null;
    _lastLap = 0;
  }

  /// ⛔`pause()` and `resume()` are GONE (T28). They were the two doors of a
  /// state this app does not have; see [isActive]. Stopping leaves the
  /// playhead exactly where it was — 「재생아닌상태가 일시정지상태나
  /// 다름없음」 is the whole argument, and it only holds if stop does not
  /// rewind.
  void stop() {
    if (!isActive) {
      return;
    }
    final lastPosition = position;
    final lastGlobal = _playlist == null ? null : _currentGlobalFrame;
    _stopTicker();
    _playlist = null;
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
    _ticker?.dispose();
    _ticker = null;
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
        for (final entry in buildStoryboardTimelineLayout(resolveProject())) {
          if (entry.cutId == activeCutId) {
            final duration = math.max(1, entry.cut.duration);
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
    _ticker?.dispose();
    _baseGlobalFrame = _currentGlobalFrame;
    _ticker = vsync.createTicker(_onTick)..start();
  }

  void _stopTicker() {
    _ticker?.dispose();
    _ticker = null;
  }

  void _onTick(Duration elapsed) {
    final playlist = _playlist;
    if (playlist == null) {
      return;
    }
    final total = _playbackTotalFrames(playlist);
    final audio = resolveAudioClock?.call();
    if (audio != null) {
      _onAudioClockTick(audio, total);
      return;
    }
    var frame =
        _baseGlobalFrame + elapsedToGlobalFrame(elapsed, resolveFrameRate());
    // Dropped-frame accounting on the raw (pre-wrap) frame: any advance of
    // more than one frame between ticks means rendering fell behind. The
    // counter reports the CURRENT loop pass only, resetting on wrap.
    final lap = frame ~/ math.max(1, total);
    if (lap != _lastLap) {
      _droppedFrames = 0;
      _lastRawFrame = null;
      _lastLap = lap;
    }
    final lastRawFrame = _lastRawFrame;
    if (lastRawFrame != null && frame > lastRawFrame + 1) {
      _droppedFrames += frame - lastRawFrame - 1;
    }
    _lastRawFrame = frame;
    if (frame >= total) {
      if (_loopMode == PlaybackLoopMode.loop) {
        frame %= total;
      } else {
        _setFrame(total - 1);
        stop();
        return;
      }
    }
    _setFrame(frame);
  }

  /// The audio-master tick: the picture shows whatever frame the device
  /// says is being heard. When rendering falls behind, frames are dropped
  /// — the sound is never made to wait.
  void _onAudioClockTick(AudioClockStatus audio, int total) {
    if (audio.ended && _loopMode == PlaybackLoopMode.once) {
      _setFrame(total - 1);
      stop();
      return;
    }
    var frame = audio.globalFrame;
    if (frame >= total) {
      frame = total - 1;
    }
    if (frame < 0) {
      frame = 0;
    }
    // A backward step is the loop wrapping (the transport wraps the
    // position itself): a fresh pass, like the wall clock's lap reset.
    final lastRawFrame = _lastRawFrame;
    if (lastRawFrame != null && frame < lastRawFrame) {
      _droppedFrames = 0;
    } else if (lastRawFrame != null && frame > lastRawFrame + 1) {
      _droppedFrames += frame - lastRawFrame - 1;
    }
    _lastRawFrame = frame;
    _setFrame(frame);
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
