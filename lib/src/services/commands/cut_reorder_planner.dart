import '../../models/cut_id.dart';
import '../../models/project.dart';
import '../../models/track_id.dart';

class CutPosition {
  const CutPosition({
    required this.trackId,
    required this.cutId,
    required this.cutIndex,
    required this.cutCount,
  });

  final TrackId trackId;
  final CutId cutId;
  final int cutIndex;
  final int cutCount;
}

class CutReorderPlanner {
  const CutReorderPlanner();

  CutPosition? findCutPosition({
    required Project project,
    required CutId cutId,
  }) {
    for (final track in project.tracks) {
      final cutIndex = track.cuts.indexWhere((cut) => cut.id == cutId);
      if (cutIndex != -1) {
        return CutPosition(
          trackId: track.id,
          cutId: cutId,
          cutIndex: cutIndex,
          cutCount: track.cuts.length,
        );
      }
    }

    return null;
  }

  CutPosition requireCutPosition({
    required Project project,
    required CutId cutId,
  }) {
    final position = findCutPosition(project: project, cutId: cutId);
    if (position == null) {
      throw StateError('Cut not found: $cutId');
    }
    return position;
  }

  bool canMoveLeft(CutPosition position) => position.cutIndex > 0;

  bool canMoveRight(CutPosition position) =>
      position.cutIndex < position.cutCount - 1;

  int moveLeftTargetIndex(CutPosition position) {
    if (!canMoveLeft(position)) {
      throw StateError('Cut cannot move left from index ${position.cutIndex}.');
    }
    return position.cutIndex - 1;
  }

  int moveRightTargetIndex(CutPosition position) {
    if (!canMoveRight(position)) {
      throw StateError(
        'Cut cannot move right from index ${position.cutIndex} of '
        '${position.cutCount}.',
      );
    }
    return position.cutIndex + 1;
  }
}
