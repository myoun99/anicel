/// THE block-snapping rule for range selections, shared by every axis that
/// has one: a layer's exposure cells, its instruction events, and a track's
/// cuts on the storyboard.
///
/// The rule itself is one sentence (UI-R8): a span that half-covers a block
/// extends through it — blocks never split. Everything axis-specific stays
/// outside, in how a caller resolves its own material into [RangeBlock]s.
library;

import 'dart:math' as math;

/// One block on an index axis: `[startIndex, endIndexExclusive)`.
class RangeBlock {
  const RangeBlock({
    required this.startIndex,
    required this.endIndexExclusive,
    this.extendsSelection = true,
  }) : assert(endIndexExclusive > startIndex, 'A block must cover a cell.');

  final int startIndex;
  final int endIndexExclusive;

  /// Whether covering one of this block's cells pulls the WHOLE block into
  /// the span. GHOST exposures are text-only (UI-R23 #6) — they read as
  /// empty cells for the snap and never extend anything, though a span may
  /// still land on them and carry them along.
  final bool extendsSelection;

  int get length => endIndexExclusive - startIndex;

  bool covers(int index) => index >= startIndex && index < endIndexExclusive;

  @override
  String toString() =>
      'RangeBlock([$startIndex, $endIndexExclusive)'
      '${extendsSelection ? '' : ', ghost'})';
}

/// A snapped span: `[startIndex, endIndexExclusive)`.
typedef RangeSpan = ({int startIndex, int endIndexExclusive});

/// One lane's "what block covers this cell" lookup.
///
/// A RESOLVER rather than a materialised list on purpose: the callers'
/// material is already indexed (a `SplayTreeMap`'s navigation methods, a
/// track's cut axis), the snap runs per drag STEP, and building a list of
/// every block on the row each step would turn an O(log n) question into an
/// O(n) allocation on exactly the rows that are long.
typedef RangeBlockAt = RangeBlock? Function(int index);

/// Snaps the raw dragged span between [anchorIndex] and [headIndex] to whole
/// blocks. Each entry of [lanes] resolves one run of blocks — a layer's
/// exposures and its instruction events are two lanes because they may
/// overlap EACH OTHER while each stays clean on its own.
///
/// Only the span's EDGE cells are asked: a block that overlaps the span
/// without covering an edge is already inside it, and one that reaches past
/// an edge necessarily covers that edge. Growth repeats until stable, since
/// extending for one lane can uncover a block in another; every pass only
/// grows the span, so the loop terminates. Returns null when the span
/// covers nothing.
RangeSpan? snapSpanToBlocks({
  required List<RangeBlockAt> lanes,
  required int anchorIndex,
  required int headIndex,
}) {
  var start = math.max(0, math.min(anchorIndex, headIndex));
  var endExclusive = math.max(anchorIndex, headIndex) + 1;
  if (endExclusive <= start) {
    return null;
  }

  var changed = true;
  while (changed) {
    changed = false;
    for (final blockAt in lanes) {
      final startBlock = blockAt(start);
      if (startBlock != null &&
          startBlock.extendsSelection &&
          startBlock.startIndex < start) {
        start = startBlock.startIndex;
        changed = true;
      }
      final endBlock = blockAt(endExclusive - 1);
      if (endBlock != null &&
          endBlock.extendsSelection &&
          endBlock.endIndexExclusive > endExclusive) {
        endExclusive = endBlock.endIndexExclusive;
        changed = true;
      }
    }
  }

  return (startIndex: start, endIndexExclusive: endExclusive);
}

/// The unit ONE cell stands for: the block covering it, or the cell itself —
/// and whether it IS a block.
typedef StandingUnit = ({int startIndex, int endIndexExclusive, bool block});

/// The unit the cell [index] stands for across [lanes] — what a click there
/// selects ([snapSpanToBlocks] of that one cell: its block, or the one cell,
/// F-175) — and whether it is a BLOCK the row draws as one.
///
/// 🗣️F-268 (유저 2026-10-03): 「재생헤드에 서있는곳을 바탕색으로 칠하는거,
/// 블록에선 블록이 꼭짓점 둥그니까 괜찮은데 빈칸은 각진 사각형이기때문에
/// 그에맞춰 사각형으로 칠하도록」. What the wash wears follows what it stands
/// on, so the unit says which it is. A GHOST's cell is a cell: ghosts are
/// text-only and read as empty to the snap ([RangeBlock.extendsSelection]).
StandingUnit standingUnitAt({
  required List<RangeBlockAt> lanes,
  required int index,
}) {
  final span = snapSpanToBlocks(
    lanes: lanes,
    anchorIndex: index,
    headIndex: index,
  );
  return (
    startIndex: span?.startIndex ?? index,
    endIndexExclusive: span?.endIndexExclusive ?? index + 1,
    block: lanes.any((blockAt) => blockAt(index)?.extendsSelection ?? false),
  );
}
