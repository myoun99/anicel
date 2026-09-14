import 'frame_id.dart';
import 'timeline_exposure.dart';

/// Whether an AUTHORED exposure in [lane] still points at [frameId] — the
/// question every cel-lifetime decision is really asking.
///
/// 🚨⛔`!ghost`, and the filter is the whole fix for a measured defect.
/// A ghost is DERIVED: a repeat run recomputes its instances from the
/// authored exposure that owns them. Counting one as a reference means
/// "keep this cel because something that only exists while the cel's own
/// block exists is pointing at it" — circular, and it comes apart the
/// moment the block goes. Put an end-hold on an animation row and delete
/// the cel and you got `frames=1 / timeline={}`: the ghosts kept the cel
/// alive through the delete, then re-derived themselves out of existence
/// and left it orphaned.
///
/// ⚠️Measured before changing it, because the note that filed this said
/// "셀뱅크·undo 파급이라 별도 라운드": there is none. [BrushFrameStore]
/// has no removal API at all (it is append-only), so what leaves
/// `layer.frames` frees nothing there either way; and all three callers
/// build an `after` layer for a command whose undo restores `before`
/// wholesale, so the shape of an undo step does not change. The blast
/// radius is `layer.frames` and nothing else.
///
/// ⛔And no caller wants the other answer. Deletion, splice and relink
/// each ask "is this cel still spoken for by something a person wrote";
/// a ghost is never that.
bool laneExposesFrame(Map<int, TimelineExposure> lane, FrameId frameId) =>
    lane.values.any(
      (exposure) =>
          exposure.isDrawing && !exposure.ghost && exposure.frameId == frameId,
    );

/// The lanes ONE cel bank is exposed through, besides the row being edited.
///
/// 🚨★F-136 (유저 2026-09-14): 「컷2에서 A레이어의 프레임 1을 지웠다고
/// 컷1에서도 삭제되거든? … 같은 컷 내에서 프레임1이 두개있을때, 한 프레임
/// 1을 삭제한다고 다른게 삭제되지않잖아. 똑같은거니까 법 통일해서 해결」 —
/// 「링크컷으로 연결되있을때」.
///
/// A linked row's cels live in a bank its link group SHARES ("레인만 각자,
/// 나머지는 하나" — `UpdateLayerTimelineCommand`), and every member keeps
/// its own lane. The cel-lifetime decisions used to ask the edited row's
/// lane alone, so a delete in one 겸용 cut took the cel out of the bank and
/// the bank's mirror swept every other cut's blocks of it. ONE question
/// now, for the second 「1」 on the same row and for a 겸용 sibling alike:
/// does SOME lane of the bank still expose the cel?
///
/// [others] never holds the edited row's own lane: that one is the edit's
/// AFTER, which only the caller has.
class CelBankLanes {
  const CelBankLanes(this.others);

  /// A bank no other row shares — every unlinked row's.
  static const unshared = CelBankLanes([]);

  final List<Map<int, TimelineExposure>> others;

  /// Whether [frameId] is still exposed by some lane of the bank once
  /// [lane] is the edited row's own.
  bool exposes(FrameId frameId, {required Map<int, TimelineExposure> lane}) =>
      laneExposesFrame(lane, frameId) ||
      others.any((other) => laneExposesFrame(other, frameId));
}
