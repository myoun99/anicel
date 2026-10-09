import 'package:flutter/foundation.dart';

import '../../models/cut.dart';
import '../../models/cut_id.dart';
import 'active_cut_controllers.dart';
import '../../services/playback/playback_frame_mapping.dart'
    show PlaybackPosition;
import 'playback_own_frame.dart';
import 'playback_rig.dart';
import 'session_roles.dart';

/// Where the playhead stands on its track: the cut under it, the frame that
/// cut starts on, and the playhead's frame inside it — a frame of the cut's
/// OWN, which begins before [startFrame] in a cut an O.L arrives into
/// (`TrackFrameAxis`).
typedef CutUnderPlayheadPosition = ({Cut cut, int startFrame, int localFrame});

/// The CUT UNDER THE PLAYHEAD — one answer for every surface that shows the
/// cut being looked at: the active cut at the editing playhead, none where
/// a live scrub stands in a gap, and while a run plays, the cut and the
/// frame it plays.
///
/// F-90 (유저 2026-09-12): 「재생시에 컷 넘어가면 타임시트패널도 다음컷 시트
/// 표시해주는데 왜 룰러 스크럽때는 그게 안되는건지? 법 하나로 통일」.
///
/// ↩️It reconciled two crossings that left the active cut behind: playback's
/// follow switched it QUIETLY (R12-B), and a scrub parked over another cut's
/// frames and left it alone (UI-R7 #9) — so 「the cut being looked at」 and
/// 「the cut open for editing」 were two answers, and every surface showing
/// the first had to be wired here, one at a time. Since I-57 ② both
/// crossings land the cut they reach (유저 10-08 · 10-09;
/// [FrameScrub.scrubGlobalFrame], the session's `followPlaybackCut`), so
/// the two answers are one but in a gap, and but for the frame a run
/// stands on between its ticks.
///
/// [listenable] moves on CROSSINGS only. A playback tick or a scrub move
/// inside the cut it last named costs two integer comparisons, so a panel
/// turns over once per cut and never rebuilds per frame.
class CutUnderPlayhead {
  CutUnderPlayhead({
    required ProjectAccess project,
    required TimelineAccess timeline,
    required ActiveCutControllers controllers,
    required ValueListenable<bool> scrubbing,
    required PlaybackRig playbackRig,
  }) : _project = project,
       _timeline = timeline,
       _controllers = controllers,
       _scrubbing = scrubbing,
       _playbackRig = playbackRig;

  final ProjectAccess _project;
  final TimelineAccess _timeline;
  final ActiveCutControllers _controllers;

  /// [FrameScrub.active] — the one thing this read from `SessionInternals`,
  /// so it takes that and nothing else.
  final ValueListenable<bool> _scrubbing;

  final PlaybackRig _playbackRig;

  final ValueNotifier<CutId?> _cutId = ValueNotifier<CutId?>(null);

  /// The track frames `[_start, _end)` of the cut last published — what a
  /// playing playhead is checked against before anything is resolved again
  /// (a parked one stands in a gap, outside every cut).
  int _start = 0;
  int _end = -1;

  /// The id of the cut [resolve] names, published when it changes.
  ValueListenable<CutId?> get listenable => _cutId;

  final ValueNotifier<String> _cutName = ValueNotifier<String>('');

  /// The NAME of the cut [resolve] names, empty where it names none (a gap),
  /// published when it changes: at a crossing, played or scrubbed over, and
  /// at a rename.
  ValueListenable<String> get cutName => _cutName;

  CutUnderPlayheadPosition? resolve() {
    if (_playing) {
      final position = _playbackRig.playback.position;
      if (position == null) {
        return null;
      }
      return (
        cut: position.cut,
        startFrame: position.globalFrameIndex - position.localFrameIndex,
        localFrame: _ownFrameOf(position),
      );
    }
    if (liveParkedFrame != null) {
      // A live scrub parks only in a gap: no cut there.
      return null;
    }
    final cut = _project.activeCutOrNull;
    if (cut == null) {
      return null;
    }
    return (
      cut: cut,
      startFrame: _project.activeCutGlobalStartFrame,
      localFrame: _controllers.timelineController.currentFrameIndex,
    );
  }

  /// The playhead's frame inside the cut [resolve] names — cheap enough for
  /// a paint per tick: playback's own local frame, the editing playhead
  /// otherwise.
  int get localFrame {
    final editing = _controllers.timelineController.currentFrameIndex;
    if (_playing) {
      final position = _playbackRig.playback.position;
      return position == null ? editing : _ownFrameOf(position);
    }
    return editing;
  }

  /// A LIVE scrub's parked track frame — always a gap since I-57 ②; null
  /// when no drag in progress parks the playhead. Only a live scrub asks
  /// the parked question: a committed parking means there is no cut here
  /// (a gap, or the V-row eye's hidden picture).
  int? get liveParkedFrame =>
      _scrubbing.value ? _timeline.editingSession.gapGlobalFrame : null;

  /// Re-answers after a playback tick, a move of the scrub's parking, or the
  /// scrub starting or ending; inside the published cut it returns at once.
  void sync() {
    final frame =
        _playbackRig.playback.globalFrameIndexListenable.value ??
        liveParkedFrame;
    if (frame != null && frame >= _start && frame < _end) {
      return;
    }
    _publish();
  }

  /// Re-answers after a session change, which can open another cut or
  /// change this one's length whatever the playhead did.
  void resync() => _publish();

  void _publish() {
    final at = resolve();
    _start = at?.startFrame ?? 0;
    _end = at == null ? -1 : at.startFrame + at.cut.duration;
    _cutId.value = at?.cut.id;
    _cutName.value = at?.cut.name ?? '';
  }

  void dispose() {
    _cutId.dispose();
    _cutName.dispose();
  }

  /// The frame of its cut's own a playing [position] stands on
  /// ([playbackOwnFrameOf]).
  int _ownFrameOf(PlaybackPosition position) => playbackOwnFrameOf(
    position,
    playback: _playbackRig.playback,
    axis: _timeline.trackFrameAxis(),
  );

  bool get _playing =>
      _playbackRig.playback.globalFrameIndexListenable.value != null;
}
