import '../../core/timeline/timeline_defaults.dart';
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
      final axis = _timeline.trackFrameAxis();
      return _cutCreationAt(
        axis,
        parked,
        duration: _lengthThatFits(axis, parked),
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

  /// A new cut's length from a gap parking at [globalFrame]: the default
  /// when it fits in front of the next cut, the room up to that cut when it
  /// does not, and the default (null) past the last cut, where nothing
  /// follows to be pushed.
  ///
  /// 🗣️F-204 (유저 2026-09-28): 「빈공간에서 컷 추가 누르면, 예를들어
  /// 20부터 컷 존재하고 10에서 만들면 1초만큼 강제로 만들어서 뒤를
  /// 밀어버리거든? 그게아니라 기본값만큼 생성할 공간이 없다면 줄이도록.
  /// 10코마의 컷을 만들게 되도록.」 ↩️It always made the default, and the
  /// room the gap lacked became a push ([CutInsertion], #19).
  int? _lengthThatFits(TrackFrameAxis axis, int globalFrame) {
    for (final entry in axis.entries) {
      if (entry.startFrame > globalFrame) {
        final room = entry.startFrame - globalFrame;
        return room < defaultCutDurationFrames ? room : null;
      }
    }
    return null;
  }

  /// The insertion a GLOBAL frame names, in the button's own record
  /// ([_slotAt] says where).
  ({TrackId trackId, int? index, int leadingGapFrames, int? duration})
  _cutCreationAt(TrackFrameAxis axis, int globalFrame, {int? duration}) {
    final slot = _slotAt(axis, globalFrame);
    return (
      trackId: _selection.selectedTrackId,
      index: slot.index,
      leadingGapFrames: slot.leadingGapFrames,
      duration: duration,
    );
  }

  /// The slot a GLOBAL frame names: in front of the first cut that starts
  /// past it, with the walk-in distance from the gap's start as the new
  /// cut's own leading gap. The button's frames are in a gap by its
  /// callers' construction, so `gapStart <= globalFrame` always holds for
  /// them. A DROP may name a cut's own frame: the count is then still the
  /// slot right of that cut, but the walk-in is no distance, and
  /// [cutCreationPlanAt] says 0 there.
  ({int index, int leadingGapFrames}) _slotAt(
    TrackFrameAxis axis,
    int globalFrame,
  ) {
    var index = 0;
    var gapStart = 0;
    for (final entry in axis.entries) {
      if (entry.startFrame > globalFrame) {
        break;
      }
      index += 1;
      gapStart = entry.endFrame;
    }
    return (index: index, leadingGapFrames: globalFrame - gapStart);
  }

  /// Where a new cut lands when a DROP names [globalFrame]: in a gap, the
  /// walk-in from the gap's start; on a cut, right of THAT cut.
  ///
  /// A drop names its frame alone, as the timeline's frame drop names its
  /// cell (`EditorSessionManager.frameDropSpot`) — a live range does not
  /// speak, though [cutCreationPlan] asks it first: that ladder is a
  /// BUTTON's, and a button names no frame (유저 2026-09-12: 「타임라인이랑
  /// 같은 법으로」; measured 2026-09-15: no import path reads a selection).
  ({int index, int leadingGapFrames}) cutCreationPlanAt(int globalFrame) {
    final axis = _timeline.trackFrameAxis();
    final slot = _slotAt(axis, globalFrame);
    return axis.isGap(globalFrame)
        ? slot
        : (index: slot.index, leadingGapFrames: 0);
  }

  /// The pill button reads THIS — the same sentence the verb runs on.
  bool get canCreateCut => cutCreationPlan != null;
}
