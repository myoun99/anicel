import 'package:flutter/foundation.dart';

import '../playback/canvas_playback_controller.dart' show PlaybackScope;
import 'playback_rig.dart';
import 'session_roles.dart';

/// WHERE THE PLAYHEAD IS DRAWN, as the two value channels a frame axis
/// reads it from: [cutFrame] for the axes that count the active cut's own
/// frames (the timeline, the x-sheet, and the row either folds into), and
/// [trackFrame] for the one that counts the track's (the storyboard, and
/// the row it folds into).
///
/// 🚨ONE OBJECT FOR A PANEL AND FOR THE ROW IT FOLDS INTO (유저 2026-09-27,
/// folded-row-playhead-during-playback-Q1: 「재생을 따른다」 — 「접힌
/// 오버레이도 재생헤드나 인덱스나 스크롤이동이나 다 구조적으로 동기화」).
/// Each tab host used to derive its own channel, and the folded row — built
/// by the workspace, not by either host — had only the editing cursor to
/// read: it stood where playback had started while the open panel ran with
/// the film (measured 09-27: playing frame 150, folded playhead 0).
///
/// Cheap per tick on purpose: a tick reads playback's own position, and the
/// track's layout is [TimelineAccess.trackFrameAxis]'s memo. Both channels
/// are value notifiers, so a tick that leaves one where it stands fires
/// nothing on it.
class PlayheadCursors {
  PlayheadCursors({
    required ProjectAccess project,
    required SelectionAccess selection,
    required TimelineAccess timeline,
    required PlaybackRig playbackRig,
  }) : _project = project,
       _selection = selection,
       _timeline = timeline,
       _playbackRig = playbackRig {
    // Answered at construction, so a teardown never builds a channel only
    // to dispose it.
    sync();
  }

  final ProjectAccess _project;
  final SelectionAccess _selection;
  final TimelineAccess _timeline;
  final PlaybackRig _playbackRig;

  late final ValueNotifier<int> _cutFrame = ValueNotifier<int>(cutFrameNow());
  late final ValueNotifier<int?> _trackFrame = ValueNotifier<int?>(
    trackFrameNow(),
  );

  /// The active cut's frame the playhead stands on — what the timeline's
  /// playhead, rulers, lane values and frame counter follow, and the row
  /// the timeline folds into with them. Playback ticks and editing seeks
  /// land HERE — never as a panel rebuild; that is the whole
  /// playback-performance architecture.
  ValueListenable<int> get cutFrame => _cutFrame;

  /// The track's frame the storyboard draws its playhead on; null when
  /// there is nowhere to draw it (no cut and no parking).
  ValueListenable<int?> get trackFrame => _trackFrame;

  /// [cutFrame]'s answer, asked now: playback's own local frame while it
  /// plays, the editing playhead otherwise.
  int cutFrameNow() {
    final editing = _selection.currentFrameIndex;
    if (_playbackRig.playback.globalFrameIndexListenable.value == null) {
      return editing;
    }
    return _playbackRig.playback.position?.localFrameIndex ?? editing;
  }

  /// [trackFrame]'s answer, asked now: the playback position while playback
  /// is active (an activeCut-scope playlist is rebased to frame 0, so it is
  /// mapped through the cut's slot on the track), the editing playhead
  /// otherwise. An over-end playhead on the track's LAST cut stays
  /// unclamped — it lives in the endless runway, exactly like the timeline
  /// shows it.
  int? trackFrameNow() {
    final playback = _playbackRig.playback;
    // All-cuts playback speaks TRACK-GLOBAL frames directly — including the
    // GAP frames between cuts, where there is no cut position to map
    // through (R10-⑤: the ruler must keep moving through gaps).
    if (playback.isActive && playback.scope == PlaybackScope.allCuts) {
      final global = playback.globalFrameIndexListenable.value;
      if (global != null) {
        return global;
      }
    }
    final axis = _timeline.trackFrameAxis();
    final position = playback.isActive ? playback.position : null;
    if (position == null) {
      // Editing playhead: a GAP PARKING reads its exact stored global
      // (R16-⑥); otherwise the playhead clamps to the CUT's last frame
      // (UI-R9 #4 — the timeline's over-end runway is a clipped view of
      // the cut, never the trailing gap). No cut + no parking = no playhead.
      // ★The storyboard's flip starts from this very answer.
      return axis.storyboardFrameOf(
        parkedGlobalFrame: _selection.gapGlobalFrame,
        activeCutId: _project.activeCutId,
        localFrame: _selection.currentFrameIndex,
      );
    }
    for (final entry in axis.entries) {
      if (entry.cutId == position.cutId) {
        final maxLocal = entry.duration > 0 ? entry.duration - 1 : 0;
        return entry.startFrame +
            position.localFrameIndex.clamp(0, maxLocal);
      }
    }
    return null;
  }

  /// Re-answers both — the session wires this to every channel either can
  /// move on.
  void sync() {
    _cutFrame.value = cutFrameNow();
    _trackFrame.value = trackFrameNow();
  }

  void dispose() {
    _cutFrame.dispose();
    _trackFrame.dispose();
  }
}
