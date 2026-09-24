import 'package:flutter/foundation.dart';

import '../../models/cut.dart';
import '../../models/cut_id.dart';
import 'active_cut_controllers.dart';
import 'playback_rig.dart';
import 'session_roles.dart';

/// Where the playhead stands on its track: the cut under it, the frame that
/// cut starts on, and the playhead's frame inside it.
typedef CutUnderPlayheadPosition = ({Cut cut, int startFrame, int localFrame});

/// The CUT UNDER THE PLAYHEAD — one answer for every surface that shows the
/// cut being looked at rather than the cut open for editing.
///
/// F-90 (유저 2026-09-12): 「재생시에 컷 넘어가면 타임시트패널도 다음컷 시트
/// 표시해주는데 왜 룰러 스크럽때는 그게 안되는건지? 법 하나로 통일」.
///
/// Measured first (09-16), neither did. Playback's own follow switches the
/// active cut QUIETLY (R12-B), so a sheet rebuilt by the session's notify
/// kept printing the cut being left and turned over only when the crossing
/// also turned its PAGE. A scrub leaves the active cut alone on purpose
/// ([FrameScrub.scrubGlobalFrame], UI-R7 #9), so nothing turned it at all.
///
/// One rule for the three moments: PLAYING, the playing position's cut; in
/// a LIVE scrub parked off the active cut's territory, the cut of the parked
/// frame — none over a gap; otherwise the active cut at the editing
/// playhead.
///
/// [listenable] moves on CROSSINGS only. A playback tick or a scrub move
/// inside the cut it last named costs two integer comparisons, so a panel
/// turns over once per cut and never rebuilds per frame — the cost R12-B
/// keeps the follow itself quiet to avoid.
class CutUnderPlayhead {
  CutUnderPlayhead({
    required ProjectAccess project,
    required SelectionAccess selection,
    required TimelineAccess timeline,
    required ActiveCutControllers controllers,
    required ValueListenable<bool> scrubbing,
    required PlaybackRig playbackRig,
  }) : _project = project,
       _selection = selection,
       _timeline = timeline,
       _controllers = controllers,
       _scrubbing = scrubbing,
       _playbackRig = playbackRig;

  final ProjectAccess _project;
  final SelectionAccess _selection;
  final TimelineAccess _timeline;
  final ActiveCutControllers _controllers;

  /// [FrameScrub.active] — the one thing this read from `SessionInternals`,
  /// so it takes that and nothing else.
  final ValueListenable<bool> _scrubbing;

  final PlaybackRig _playbackRig;

  final ValueNotifier<CutId?> _cutId = ValueNotifier<CutId?>(null);

  /// The track frames `[_start, _end)` of the cut last published — what a
  /// playing or parked playhead is checked against before anything is
  /// resolved again.
  int _start = 0;
  int _end = -1;

  /// The id of the cut [resolve] names, published when it changes.
  ValueListenable<CutId?> get listenable => _cutId;

  CutUnderPlayheadPosition? resolve() {
    if (_playing) {
      final position = _playbackRig.playback.position;
      if (position == null) {
        return null;
      }
      return (
        cut: position.cut,
        startFrame: position.globalFrameIndex - position.localFrameIndex,
        localFrame: position.localFrameIndex,
      );
    }
    final parkedFrame = liveParkedFrame;
    if (parkedFrame != null) {
      return atTrackFrame(parkedFrame);
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
  /// a paint per tick: playback's own local frame, a parked frame against the
  /// published cut's start, the editing playhead otherwise.
  int get localFrame {
    final editing = _controllers.timelineController.currentFrameIndex;
    if (_playing) {
      return _playbackRig.playback.position?.localFrameIndex ?? editing;
    }
    final parked = liveParkedFrame;
    return parked != null && parked >= _start && parked < _end
        ? parked - _start
        : editing;
  }

  /// A LIVE scrub's parked track frame; null when no drag in progress parks
  /// the playhead. Only a live scrub asks the parked question: a committed
  /// parking means there is no cut here (a gap, or the V-row eye's hidden
  /// picture).
  int? get liveParkedFrame =>
      _scrubbing.value ? _selection.gapGlobalFrame : null;

  /// The cut the active track shows at [globalFrame]; null over a gap.
  CutUnderPlayheadPosition? atTrackFrame(int globalFrame) {
    // 🚨[TrackFrameAxis.ownerOf] hands a gap frame to the PRECEDING cut on
    // purpose (its over-end runway) — it is an addressing rule, not a
    // containment test. [TrackFrameAxis.isGap] is the containment test, and
    // it is the same pair [selectGlobalFrame] asks, so what the drag frames
    // and what the release lands cannot disagree.
    final axis = _timeline.trackFrameAxis();
    final owner = axis.isGap(globalFrame) ? null : axis.ownerOf(globalFrame);
    if (owner == null) {
      return null;
    }
    return (
      cut: owner.cut,
      startFrame: owner.startFrame,
      localFrame: globalFrame - owner.startFrame,
    );
  }

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
  }

  void dispose() => _cutId.dispose();

  bool get _playing =>
      _playbackRig.playback.globalFrameIndexListenable.value != null;
}
