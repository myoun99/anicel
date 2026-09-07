import '../../models/track_frame_axis.dart';
import '../../models/track_id.dart';
import 'session_roles.dart';

/// WHERE A NEW CUT LANDS — the one expression behind both the Create Cut
/// pill's enabled state and the verb's dispatch (T25: 버튼 근거와 디스패치
/// 근거는 같은 문장 하나). Read-only: it plans, it does not commit.
///
/// 🚨A collaborator carved out of `EditorSessionManager` (G3 of the
/// god-object decomposition, round 8). Roles only — it asks what is
/// selected and where the playhead is, and nothing else.
class CutPlacement {
  CutPlacement({
    required SelectionAccess selection,
    required TimelineAccess timeline,
  }) : _selection = selection,
       _timeline = timeline;

  final SelectionAccess _selection;
  final TimelineAccess _timeline;

  /// #18 — WHERE Create Cut lands right now, or null when nowhere.
  ///
  /// 유저: 「인덱스를 갭에 둔 상태로 컷생성도안되고 선택범위하고 컷생성도안됨.
  /// (…) 갭에서 컷생성누르면 스토리보드엔 컷 안생기는데 버튼쪽(…)은 활성화됨.」
  ///
  /// The old path asked NOTHING: `createCut()` took no arguments, the
  /// coordinator anchored on the active cut alone, and a gap press
  /// appended at the track's end — the cut did not fail to appear, it
  /// appeared somewhere else, which is why the frame buttons lit up.
  ///
  /// ★The same ladder as `deleteSubject`/`editInstanceSubject`, the same
  /// order: the RANGE speaks first (it was said out loud), the parked
  /// playhead second, the active cut last. And per T25, this ONE
  /// expression answers both the pill button's enabled and the verb's
  /// dispatch — two sources is exactly how the button lied in the gap.
  ///
  /// The range rung answers only when the range lies entirely in EMPTY
  /// track space — a cut cannot be created over cuts, and saying null
  /// here is what turns the button off instead of letting it lie.
  ({TrackId trackId, int? index, int leadingGapFrames, int? duration})?
  get cutCreationPlan {
    final range = _selection.trackFrameRangeSelection.value;
    if (range != null && range.trackId == _selection.selectedTrackId) {
      final axis = _timeline.trackFrameAxis();
      if (axis.cutsIn(range.startFrame, range.endFrameExclusive).isNotEmpty) {
        return null;
      }
      return _cutCreationAt(
        axis,
        range.startFrame,
        duration: range.endFrameExclusive - range.startFrame,
      );
    }
    final parked = _selection.gapGlobalFrame;
    if (parked != null) {
      return _cutCreationAt(
        _timeline.trackFrameAxis(),
        parked,
        duration: null,
      );
    }
    // The active-cut posture keeps its shape: the coordinator anchors to
    // the right of the active cut (or the track's end), unchanged.
    return (
      trackId: _selection.selectedTrackId,
      index: null,
      leadingGapFrames: 0,
      duration: null,
    );
  }

  /// The insertion a GLOBAL frame names: in front of the first cut that
  /// starts past it, with the walk-in distance from the gap's start as
  /// the new cut's own leading gap. The frame is in a gap by the callers'
  /// construction, so `gapStart <= globalFrame` always holds.
  ({TrackId trackId, int? index, int leadingGapFrames, int? duration})
  _cutCreationAt(TrackFrameAxis axis, int globalFrame, {int? duration}) {
    var index = 0;
    var gapStart = 0;
    for (final entry in axis.entries) {
      if (entry.startFrame > globalFrame) {
        break;
      }
      index += 1;
      gapStart = entry.endFrame;
    }
    return (
      trackId: _selection.selectedTrackId,
      index: index,
      leadingGapFrames: globalFrame - gapStart,
      duration: duration,
    );
  }

  /// The pill button reads THIS — the same sentence the verb runs on.
  bool get canCreateCut => cutCreationPlan != null;
}
