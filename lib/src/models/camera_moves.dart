import '../core/neighbour_pairs.dart';
import 'canvas_point.dart';
import 'transform_track.dart';

/// One stretch of a camera between two of its keys — from the key on
/// [from] to the next, on [to] — and the move it makes there, as the
/// glossary's id ([term]).
typedef CameraMove = ({int from, int to, String term});

/// THE CAMERA'S MOVES AS THE SHEET NAMES THEM (I-73 ⑤): each stretch
/// between two of [track]'s keys that moves, with its term.
///
/// 🗣️유저 2026-10-08: 「이 선 중앙에 카메라 움직임에 따라 지시명도
/// 적을거거든? 상하좌우로만 움직이면 팬, 확대가 있으면 상화좌우 있더라도
/// T.U, 축소면 같은규칙으로 T.B 이렇게? … 이거는 타임시트패널에도 동일하게
/// 표기하게할거야. 지시로서」 · 「3. 회전도 PAN으로 인식하도록」 — the
/// zoom growing is T.U and shrinking T.B, whatever moves with it; any other
/// move, of the position or the turn, is PAN. A stretch that does not move
/// has no term, only its line.
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
      if (cameraMoveTermBetween(_poseAt(track, from), _poseAt(track, to - 1))
          case final term?)
        (from: from, to: to, term: term),
  ];
}

/// The glossary's id for the move from [from] to [to]
/// (`CameraInstructionSet.standard`): 'tu' where the zoom grows, 'tb' where
/// it shrinks, 'pan' where only the position or the turn changes — null
/// where nothing does.
String? cameraMoveTermBetween(TransformPose from, TransformPose to) {
  if (to.scaleX > from.scaleX) {
    return 'tu';
  }
  if (to.scaleX < from.scaleX) {
    return 'tb';
  }
  return to.center != from.center ||
          to.rotationDegrees != from.rotationDegrees
      ? 'pan'
      : null;
}

/// [track] as it plays on [frame]. A lane with no key resolves to the same
/// rest on every frame, which is all a comparison of two frames needs.
TransformPose _poseAt(TransformTrack track, int frame) => track.resolveAt(
  frameIndex: frame,
  orElse: () => TransformPose(center: CanvasPoint(x: 0, y: 0)),
);
