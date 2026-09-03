import 'layer.dart';
import 'timeline_coverage.dart';

/// The uncovered runs of [layer]'s timeline inside
/// `[startIndex, endIndexExclusive)` — the index space is whatever the
/// timeline's own keys speak (cut-local for cut layers, GLOBAL for track SE
/// rows), which is what lets #16's track rung and the cell path share one
/// walk.
///
/// D20 (2026-08-18) rewrote the coverage half: GHOST coverage is authoring
/// room — 「고스트일 뿐이니 생성 허용」 — the same sentence
/// `TimelineController.canCreateDrawingAt` reads, so the single-cell verb
/// and the range verb cannot answer "is this cell free" differently. (The
/// old comment said the opposite: "ghost coverage counts as covered".) A
/// range over a repeat/hold tail therefore fills the projected cells with
/// authored ones, and the rederive pass re-clamps the projection around
/// them.
///
/// Lived in the session manager until 2026-09-03 (the audit's Round 6); it
/// touches nothing of the session's, so it lives with the coverage law it
/// reads.
List<({int startIndex, int length})> emptyGapsBetween(
  Layer layer,
  int startIndex,
  int endIndexExclusive,
) {
  final gaps = <({int startIndex, int length})>[];
  int? gapStart;
  for (var index = startIndex; index <= endIndexExclusive; index += 1) {
    final block = index >= endIndexExclusive || index < 0
        ? null
        : coveringDrawingBlockAt(layer.timeline, index);
    final covered =
        index >= endIndexExclusive ||
        index < 0 ||
        (block != null && !block.entry.ghost);
    if (!covered) {
      gapStart ??= index;
      continue;
    }
    if (gapStart != null) {
      gaps.add((startIndex: gapStart, length: index - gapStart));
      gapStart = null;
    }
  }
  return gaps;
}
