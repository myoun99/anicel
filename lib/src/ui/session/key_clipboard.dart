import 'lane_homes.dart' show KeyCopy, LaneKeys;
import 'lane_verbs.dart';
import 'session_roles.dart';

/// THE KEY BOARD — the keys the last copy on a lane row took, the APP's
/// like the frame and the row boards beside it (`AppClipboard`: one copy in
/// hand, whichever board took it).
class KeyBoard {
  KeyCopy? _copy;

  /// What this board taking a copy lets go of: the pill's other boards
  /// (`AppClipboard`).
  void Function()? onTake;

  void _take(KeyCopy copy) {
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

  /// What a copy here takes: the lanes, each with its keys, and the frames
  /// it spans — null where the press stands on no lane, or on lanes with no
  /// key in reach.
  KeyCopy? get _copyHere => switch (_laneVerbs.laneVerbRange) {
    final lane? => _laneVerbs.keyCopyOf(lane),
    null => null,
  };

  /// Whether a copy here takes keys — the lane half of the shared pill's
  /// copy, asked before the frame board's ([FrameClipboard.timelinePlace]
  /// stands down on a lane).
  bool get canCopy => _copyHere != null;

  void copy() {
    final copy = _copyHere;
    if (copy == null) {
      return;
    }
    _board._take(copy);
    _changes.notifyChanged();
  }

  /// 잘라내기 of keys: the copy's keys in hand, and those keys — every key
  /// the range covers on the lanes it reaches, the very reach and the very
  /// keys [copy] takes — off their lanes, as ONE step
  /// ([LaneVerbs.removeLaneKeysForSelection]). Gated by [canCopy]: where a
  /// copy takes keys, the cut lifts them.
  ///
  /// ⛔Not the lane's Delete ([LaneVerbs.deleteForLaneSelection]): over an
  /// fx header that takes the EFFECT, which no copy of keys holds — and a
  /// cut lifts only what it banked (결정 14 ②ⓐ, `FrameClipboard.cutAt`).
  void cut() {
    final lane = _laneVerbs.laneVerbRange;
    final copy = _copyHere;
    if (lane == null || copy == null) {
      return;
    }
    _board._take(copy);
    _laneVerbs.removeLaneKeysForSelection(lane);
    _changes.notifyChanged();
  }

  /// Whether the hand holds keys.
  bool get holdsKeys => _board._copy != null;

  /// Whether a paste here puts keys down — on the lanes the press stands
  /// on, the frame paste's way ([LaneVerbs.pasteLaneKeys]).
  bool get canPasteIndependent => switch (_board._copy) {
    final copy? => _laneVerbs.canPasteLaneKeys(copy),
    null => false,
  };

  /// 독립 붙여넣기 of the keys in hand: each a value of its own, named by
  /// none (유저 확정, of frames: 「독립 붙여넣기 = 그냥 복제」).
  void pasteIndependent() {
    if (_board._copy case final copy?) {
      _laneVerbs.pasteLaneKeys(copy);
    }
  }

  /// Whether a 링크 붙여넣기 here has a name to keep: the keys in hand carry
  /// one, and a paste here puts them down. With none the press would be the
  /// independent paste under another button, and that button alone is lit
  /// — the frame board's law (F-115).
  bool get canPasteLinked => switch (_board._copy) {
    final copy? =>
      copy.lanes.any(
            (lane) => lane.keys.values.any((key) => key.name != null),
          ) &&
          _laneVerbs.canPasteLaneKeys(copy),
    null => false,
  };

  /// 링크 붙여넣기 of the keys in hand ([LaneVerbs.pasteLinkedLaneKeys]):
  /// null when it pasted, or the names it would join at another value,
  /// writing nothing, where [joinTakenNames] was not given.
  Set<String>? pasteLinked({bool joinTakenNames = false}) =>
      switch (_board._copy) {
        final copy? => _laneVerbs.pasteLinkedLaneKeys(
          copy,
          joinTakenNames: joinTakenNames,
        ),
        null => null,
      };

  /// The keys in hand, lane by lane, as frames from the copy's first —
  /// empty when the hand holds none.
  Map<String, Set<int>> get bankedKeyFrames => {
    for (final lane in _board._copy?.lanes ?? const <LaneKeys>[])
      lane.laneId: lane.keys.keys.toSet(),
  };
}
