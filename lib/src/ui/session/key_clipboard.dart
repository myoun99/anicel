import 'lane_homes.dart' show LaneKeys;
import 'lane_verbs.dart';
import 'session_roles.dart';

/// THE KEY BOARD — the keys the last copy on a lane row took, the APP's
/// like the frame and the row boards beside it (`AppClipboard`: one copy in
/// hand, whichever board took it).
class KeyBoard {
  List<LaneKeys>? _copy;

  /// What this board taking a copy lets go of: the pill's other boards
  /// (`AppClipboard`).
  void Function()? onTake;

  void _take(List<LaneKeys> copy) {
    _copy = copy;
    onTake?.call();
  }

  /// Lets go of what it holds: the hand took a copy of another kind.
  void letGo() => _copy = null;
}

/// The KEY CLIPBOARD — copying the keys of the lane row a press stands on.
///
/// 🗣️F-388 (유저 2026-10-17): 「키도 복붙기능 제대로 만들고 기존것들이랑 법
/// 통일하고」 · I-101 (유저 2026-10-15): 「키 복사(fx든 트랜스폼이든
/// 카메라든 뭐든 법 통일해서), 키의 행(헤더나 멤버든)에 서있거나,
/// 선택하거나. 프레임이랑 동일하게」.
///
/// ★WHAT A COPY TAKES IS THE FRAME BOARD'S RULE (F-152: 「선택안하면
/// 현재프레임, 선택하면 해당 선택한 소재가 기준」): standing on a lane, the
/// keys at the playhead — the one-frame span a lane verb states standing as
/// ([LaneVerbs.laneVerbRange]); with a lane range selected, every key inside
/// it, by its frame from the range's first. A group header stands for its
/// members, the camera row for its transform header — the reach every lane
/// verb has ([LaneVerbs.laneVerbTargets]).
class KeyClipboard {
  KeyClipboard({
    required KeyBoard board,
    required LaneVerbs laneVerbs,
    required ChangeSink changes,
  }) : _board = board,
       _laneVerbs = laneVerbs,
       _changes = changes;

  /// The app's key board — every open project's clipboard reads and writes
  /// the same one (I-7).
  final KeyBoard _board;
  final LaneVerbs _laneVerbs;
  final ChangeSink _changes;

  /// The lanes a copy here takes, each with its keys — null where the press
  /// stands on no lane, or on lanes with no key in reach.
  List<LaneKeys>? get _lanesToCopy {
    final lane = _laneVerbs.laneVerbRange;
    final lanes = lane == null ? null : _laneVerbs.laneKeysCopiedFrom(lane);
    return lanes != null && lanes.any((lane) => lane.keys.isNotEmpty)
        ? lanes
        : null;
  }

  /// Whether a copy here takes keys — the lane half of the shared pill's
  /// copy, asked before the frame board's ([FrameClipboard.timelinePlace]
  /// stands down on a lane).
  bool get canCopy => _lanesToCopy != null;

  void copy() {
    final lanes = _lanesToCopy;
    if (lanes == null) {
      return;
    }
    _board._take(lanes);
    _changes.notifyChanged();
  }

  /// Whether the hand holds keys.
  bool get holdsKeys => _board._copy != null;

  /// The keys in hand, lane by lane, as frames from the copy's first —
  /// empty when the hand holds none.
  Map<String, Set<int>> get bankedKeyFrames => {
    for (final (:laneId, :keys) in _board._copy ?? const <LaneKeys>[])
      laneId: keys.keys.toSet(),
  };
}
