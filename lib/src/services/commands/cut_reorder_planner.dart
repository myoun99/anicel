import '../project_lookup.dart' show CutPosition;

export '../project_lookup.dart' show CutPosition;

/// Which way a cut steps in its track.
enum CutMoveDirection {
  left(step: -1),
  right(step: 1);

  const CutMoveDirection({required this.step});

  /// How far the cut's index moves — the whole of the difference between
  /// the two directions.
  final int step;
}

class CutReorderPlanner {
  const CutReorderPlanner();

  /// Whether the cut at [position] has somewhere to go in [direction].
  bool canMove(CutPosition position, CutMoveDirection direction) {
    final target = position.cutIndex + direction.step;
    return target >= 0 && target < position.cutCount;
  }

  /// Where the cut at [position] lands moving one step in [direction].
  ///
  /// ⛔LEFT AND RIGHT ARE ONE LAW WITH THE SIGN FLIPPED. Written apart,
  /// the two guards drifted: the left one read `cutIndex > 0` and the
  /// right one `cutIndex < cutCount - 1`, which is the same sentence said
  /// two ways, and only one of them mentioned the count it depends on.
  int moveTargetIndex(CutPosition position, CutMoveDirection direction) {
    if (!canMove(position, direction)) {
      throw StateError(
        'Cut cannot move ${direction.name} from index ${position.cutIndex} '
        'of ${position.cutCount}.',
      );
    }
    return position.cutIndex + direction.step;
  }
}
