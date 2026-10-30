import '../core/neighbour_pairs.dart';
import 'camera_instruction.dart';
import 'canvas_point.dart';
import 'transform_track.dart';

/// One stretch of a camera between two of its keys — from the key on
/// [from] to the next, on [to] — and the move it makes there, as the
/// glossary's id ([term]); [turning] where the turn changes along with it.
typedef CameraMove = ({int from, int to, String term, bool turning});

/// The glossary's id for a turn alone (`CameraInstructionSet.standard`).
const cameraTurnTerm = 'rotate';

/// The glossary's id for a camera standing still
/// (`CameraInstructionSet.standard`): what the conte writes beside a move,
/// where the same cell has none (I-93, `conteCameraStretches`).
const cameraFixTerm = 'fix';

/// THE CAMERA'S MOVES AS THE SHEET NAMES THEM (I-73 ⑤): each stretch
/// between two of [track]'s keys that moves, with its term.
///
/// 🗣️유저 2026-10-08: 「이 선 중앙에 카메라 움직임에 따라 지시명도
/// 적을거거든? 상하좌우로만 움직이면 팬, 확대가 있으면 상화좌우 있더라도
/// T.U, 축소면 같은규칙으로 T.B 이렇게? … 이거는 타임시트패널에도 동일하게
/// 표기하게할거야. 지시로서」 — the zoom growing is T.U and shrinking T.B,
/// whatever moves with it; the position alone is PAN. A stretch that does
/// not move has no term, only its line.
///
/// 🗣️I-89 (유저 2026-10-10): 「그리고 회전은 모아트기준대로 하자」 — the
/// turn alone is 回転, and a T.U · T.B · PAN the turn changes along with
/// is written after 回転 (「回転 T.B」, [cameraMoveWord]). ↩️「3. 회전도
/// PAN으로 인식하도록」(10-08): the turn was a PAN.
///
/// Judged by what PLAYS, not by the keys' numbers: the pose on the
/// stretch's first frame against the pose on its last before the next key.
/// A HOLD key freezes the camera until the next one, so the stretch after
/// it has no term though the next key holds another pose — it jumps there,
/// it does not move.
List<CameraMove> cameraMoves(TransformTrack track) {
  final keys = track.keyedFrames.toList(growable: false);
  return [
    for (final (from, to) in neighbourPairs(keys))
      if (_moveBetween(_poseAt(track, from), _poseAt(track, to - 1))
          case (:final term, :final turning))
        (from: from, to: to, term: term, turning: turning),
  ];
}

/// What [move] is written as, in the glossary [defById] reads: its term's
/// name, after 回転's where the turn changes along with it — the camera
/// row's lane, the timesheet and the conte read this one word.
String cameraMoveWord(
  CameraMove move,
  CameraInstructionDef? Function(String id) defById,
) {
  final word = instructionTermName(move.term, defById(move.term));
  if (!move.turning) {
    return word;
  }
  final turn = instructionTermName(cameraTurnTerm, defById(cameraTurnTerm));
  return '$turn $word';
}

/// The glossary's id for the move from [from] to [to]
/// (`CameraInstructionSet.standard`): 'tu' where the zoom grows, 'tb' where
/// it shrinks, 'pan' where only the position changes — each [turning]
/// where the turn changes too — and [cameraTurnTerm] where the turn alone
/// does; null where nothing does.
({String term, bool turning})? _moveBetween(
  TransformPose from,
  TransformPose to,
) {
  final turning = to.rotationDegrees != from.rotationDegrees;
  final term = to.scaleX > from.scaleX
      ? 'tu'
      : to.scaleX < from.scaleX
      ? 'tb'
      : to.center != from.center
      ? 'pan'
      : null;
  if (term == null) {
    return turning ? (term: cameraTurnTerm, turning: false) : null;
  }
  return (term: term, turning: turning);
}

/// [track] as it plays on [frame]. A lane with no key resolves to the same
/// rest on every frame, which is all a comparison of two frames needs.
TransformPose _poseAt(TransformTrack track, int frame) => track.resolveAt(
  frameIndex: frame,
  orElse: () => TransformPose(center: CanvasPoint(x: 0, y: 0)),
);
