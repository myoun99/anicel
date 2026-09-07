import 'dart:math' as math;

import '../../models/cut.dart';
import '../../models/layer.dart';
import '../../models/transition_geometry.dart';
import 'camera.dart';
import 'editor_app_settings.dart';
import 'session_roles.dart';
import 'track_se_display.dart';
import 'transitions.dart';

/// HOW MUCH FILM THE ACTIVE CUT IS, and which rows it shows — the derived
/// read-model of the cut the user is standing in. Read-only: nothing here
/// commands, so nothing here notifies.
///
/// 🚨A collaborator carved out of `EditorSessionManager` (G3 of the
/// god-object decomposition, round 8). It names the roles it needs in its
/// constructor plus the three siblings that supply the material the
/// numbers are made of — the track-owned rows, the transitions that
/// lengthen the drawn count, and the camera's instruction set that names
/// them.
class ActiveCutSpan {
  ActiveCutSpan({
    required ProjectAccess project,
    required SelectionAccess selection,
    required EditorAppSettings appSettings,
    required Camera camera,
    required TrackSeDisplay trackSe,
    required Transitions transitions,
  }) : _project = project,
       _selection = selection,
       _appSettings = appSettings,
       _camera = camera,
       _trackSe = trackSe,
       _transitions = transitions;

  final ProjectAccess _project;
  final SelectionAccess _selection;
  final EditorAppSettings _appSettings;
  final Camera _camera;
  final TrackSeDisplay _trackSe;
  final Transitions _transitions;

  /// Every row the ACTIVE cut SHOWS — the cut's own layers plus the
  /// TRACK-owned rows that join them, which is exactly what
  /// `LayerController.layers` composes.
  ///
  /// 🚨H17 (유저 2026-08-22): 「**트랜지션 레이어에 서있을때 엔드라인 드래그로
  /// 조작하면 액티브레이어가 액션레이어로 바뀜.** 또 통일안하고 멋대로 이상한
  /// 규칙 만들어낸흔적」.
  ///
  /// ⛔`activeCutHasLayer` USED TO RE-DERIVE THIS MEMBERSHIP BY KIND, and
  /// had been told about only two of the three sources: the cut's layers,
  /// and track-SE rows (a hand-written arm added by W4). The track
  /// TRANSITION row joined the composed list later 「on the same terms as
  /// the SE rows」 and this predicate was never told — so standing on it and
  /// committing ANY cut command answered "that layer is gone", the rebuilt
  /// controller started with no preference, and `_activeLayerId ??=
  /// layers.first.id` handed the active row to the bottom of the raw list:
  /// the action layer.
  ///
  /// 🧪Measured, not reasoned: the transition row is still in `layers` the
  /// whole time, and `currentRow` never moved — only the ACTIVE layer did,
  /// and only for this one row kind (camera and SE both survive the same
  /// drag). A fourth row kind must join HERE, next to the composition it
  /// mirrors, rather than buying another arm on a predicate.
  List<Layer> get activeCutRowLayers {
    final cut = _project.activeCutOrNull;
    if (cut == null) {
      return const [];
    }
    return [
      ...cut.layers,
      ..._trackSe.trackSeDisplayLayers,
      _transitions.trackTransitionDisplayLayer,
    ];
  }

  int get activeCutPlaybackFrameCount =>
      math.max(1, _project.activeCutOrNull?.duration ?? 1);

  /// How many frames the active cut is DRAWN for: its conte 尺 plus the
  /// のりしろ every transition span crossing one of its boundaries asks for.
  /// Equal to [activeCutPlaybackFrameCount] whenever nothing crosses.
  ///
  /// ★The same number the sheet pages by and prints in parentheses
  /// (`2+0 (2+12)`), read from the same derivation — the ruler's blue line and
  /// the sheet's row count cannot disagree about how much there is to draw.
  int get activeCutDrawnFrameCount {
    final cut = _project.activeCutOrNull;
    if (cut == null) {
      return activeCutPlaybackFrameCount;
    }
    final start = _project.activeCutGlobalStartFrame;
    return cutTransitionHandles(
      cutStart: start,
      cutEnd: start + cut.duration,
      spans: _transitions.activeTrackTransitionSpans,
    ).drawnFrames(activeCutPlaybackFrameCount);
  }

  /// What the ruler writes across that margin: the TERM that asked for it, then
  /// the word — "O.L のりしろ", "O.L 여백" (user 2026-08-10, "그럼 뭐때문에 여백
  /// 길이가 생겼는지 아니까"). Empty when nothing crosses this cut.
  ///
  /// Every span that FIRES on this cut is named, not just one: head and tail
  /// handles add up, so with a transition at each boundary no single term set
  /// the length and claiming one would be a half-truth.
  String get activeCutNoriShiroLabel {
    final cut = _project.activeCutOrNull;
    if (cut == null) {
      return '';
    }
    final start = _project.activeCutGlobalStartFrame;
    final end = start + cut.duration;
    final terms = <String>[];
    for (final entry in _selection.activeTrack.transitionLayer.instructions
        .entries) {
      if (!transitionSpanFires(
        span: _transitions.transitionSpanOf(entry),
        cutStart: start,
        cutEnd: end,
      )) {
        continue;
      }
      final term = entry.value.displayLabel(
        _camera.cameraInstructionSet.defById(entry.value.instructionId),
      );
      if (term.isNotEmpty && !terms.contains(term)) {
        terms.add(term);
      }
    }
    if (terms.isEmpty) {
      return '';
    }
    return '${terms.join('/')} ${_appSettings.uiStrings.tlNoriShiro}';
  }

  /// R27 #31: the cut an EXPORT anchors on. Parking the playhead in a gap
  /// leaves no active cut, but that is a playhead position — not "no
  /// film" — so the export window must still open (it used to throw
  /// `requireActiveCut` straight through the dialog's build and take the
  /// whole app down with it). Falls back to the first cut on the axis;
  /// null only when the project genuinely has no cuts at all, which is
  /// what disables the Export entry point.
  Cut? get exportAnchorCutOrNull {
    final active = _project.activeCutOrNull;
    if (active != null) {
      return active;
    }
    for (final track in _project.repository.requireProject().tracks) {
      if (track.cuts.isNotEmpty) {
        return track.cuts.first;
      }
    }
    return null;
  }

  /// Whether an export would run off [exportAnchorCutOrNull]'s FALLBACK
  /// rather than a live selection — the window then defaults its scope to
  /// the whole project instead of silently exporting a cut the user is
  /// not standing on.
  bool get exportAnchorIsFallback =>
      _project.activeCutOrNull == null && exportAnchorCutOrNull != null;
}
