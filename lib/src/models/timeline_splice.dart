import 'dart:collection';

import 'timeline_exposure.dart';

/// 🚨★★★ THE ONE SPLICE — 유저 확정 2026-08-13 (T2·T3).
///
/// > 「대상이 복사 길이보다 짧으면 그 부분은 살려서 밀어. 반대 상황에서 여백
/// > 생기면 당기고. 왜냐면 뭘 선택하든 덮어써버리면 **선택범위를 조절하는
/// > 의미가 통째로 사라지잖아.**」
///
/// ★**끼워넣기와 갈아끼우기는 두 동사가 아니다.** Both are 「lift N cells,
/// then put the clip in their place」 and they differ only in N:
///
/// | verb | N |
/// |---|---|
/// | 붙여넣기, 선택 없음 | 0 — nothing comes out, everything after moves right |
/// | 붙여넣기, 선택 있음 | the selection's length — 갈아끼우기 |
/// | 잘라내기 | the selection's length, with no clip going in |
///
/// The length difference is absorbed by the TAIL: a longer clip pushes, a
/// shorter one pulls. ⛔Nothing outside the lifted run is ever overwritten —
/// that is the whole point of having chosen a range.
///
/// ⛔**THE CUT'S LENGTH IS NEVER ASKED.** 「컷 길이는 소재와 관계없다」 is a
/// global law of this app: `Cut.duration` is the 尺 and the drawn range is
/// separate, so a push that carries blocks past the end line is correct and
/// clamping it here would be the violation. There is deliberately no
/// `duration` parameter in this file.
///
/// ⚠️GHOSTS are not spliced. They are DERIVED (the run-behaviour rederive
/// pass wipes and rebuilds them on every edit), so a splice moves authored
/// entries only and lets that pass answer for the rest. Copying a ghost
/// would author what the model defines as un-authored.

/// What one copy or cut lifted off ONE row.
///
/// Offsets are relative to the run's own start, so the clip does not
/// remember where it came from — 「블록 자체를 복붙한다」 means the block and
/// its 코마, not its address. Empty cells inside the run are represented by
/// the absence of an entry, exactly as they are in a live row, so a copied
/// gap reproduces as a gap.
class TimelineClipRow {
  TimelineClipRow({required Map<int, TimelineExposure> exposures, required this.length})
    : assert(length >= 0, 'A clip run cannot be shorter than nothing.'),
      exposures = SplayTreeMap<int, TimelineExposure>.from(exposures);

  const TimelineClipRow.empty() : exposures = const {}, length = 0;

  /// Offset from the run start → the authored entry beginning there.
  final Map<int, TimelineExposure> exposures;

  /// How many CELLS the run spans, gaps and trailing blanks included. Not
  /// derivable from [exposures]: a run may end in empty cells, and those
  /// cells are part of what was selected.
  final int length;

  bool get isEmpty => length == 0;
}

/// Makes [index] a block BOUNDARY.
///
/// A block covering [index] strictly inside becomes two entries over the
/// same cel; a block that already starts there, an empty cell, and an index
/// outside every block are all already boundaries and pass through.
///
/// ⚠️The MEMO and the breakdown dots stay with the HEAD. Both are
/// block-owned, and a split is one block becoming two — there is no rule
/// saying which half inherits an authored note, so this follows the
/// existing paste-split precedent rather than inventing one. The dots
/// divide themselves correctly on their own: they are offsets from the
/// block start, and `copyWith(length:)` drops the ones the shortened head
/// no longer contains.
SplayTreeMap<int, TimelineExposure> splitTimelineAt(
  Map<int, TimelineExposure> timeline,
  int index,
) {
  final next = SplayTreeMap<int, TimelineExposure>.from(timeline);
  final covering = _coveringEntry(next, index);
  if (covering == null || covering.key == index) {
    return next;
  }
  final entry = covering.value;
  final frameId = entry.frameId;
  if (frameId == null) {
    return next;
  }
  final endExclusive = covering.key + (entry.length ?? 1);
  next[covering.key] = entry.copyWith(length: index - covering.key);
  next[index] = TimelineExposure.drawing(
    frameId,
    length: endExclusive - index,
    breakdownOffsets: [
      for (final offset in entry.breakdownOffsets)
        if (offset > index - covering.key) offset - (index - covering.key),
    ],
  );
  return next;
}

/// Everything starting at or after [index] moves by [delta] cells.
///
/// Iteration order matters: moving right walks the keys backwards so a
/// block never lands on one that has not moved yet, and moving left walks
/// forwards for the same reason.
SplayTreeMap<int, TimelineExposure> shiftTimelineFrom(
  Map<int, TimelineExposure> timeline,
  int index,
  int delta,
) {
  if (delta == 0) {
    return SplayTreeMap<int, TimelineExposure>.from(timeline);
  }
  final next = SplayTreeMap<int, TimelineExposure>.from(timeline);
  final moving = next.keys.where((key) => key >= index).toList(growable: false);
  final order = delta > 0 ? moving.reversed : moving;
  for (final key in order) {
    final entry = next.remove(key);
    if (entry == null) {
      continue;
    }
    final landing = key + delta;
    if (landing < 0) {
      continue;
    }
    next[landing] = entry;
  }
  return next;
}

/// Reads [count] cells starting at [index] off the row, without changing it.
///
/// Boundaries are split first, so a range that starts or ends inside a hold
/// carries the PIECE it selected — 「덮어쓰고싶은 만큼만 선택범위로 잘
/// 선택하면 최상의 조합」 only works if the range means exactly its cells.
TimelineClipRow captureTimelineRun({
  required Map<int, TimelineExposure> timeline,
  required int index,
  required int count,
}) {
  if (count <= 0) {
    return const TimelineClipRow.empty();
  }
  var bounded = splitTimelineAt(timeline, index);
  bounded = splitTimelineAt(bounded, index + count);
  return TimelineClipRow(
    exposures: {
      for (final entry in bounded.entries)
        if (entry.key >= index && entry.key < index + count)
          entry.key - index: entry.value,
    },
    length: count,
  );
}

/// THE splice: lift [liftCount] cells at [index], put [clip] in their place.
///
/// Both halves are optional in practice — a null [clip] with a positive
/// [liftCount] is 잘라내기's model half, and a zero [liftCount] with a clip
/// is 끼워넣기 — which is why they are one function rather than three.
SplayTreeMap<int, TimelineExposure> spliceTimeline({
  required Map<int, TimelineExposure> timeline,
  required int index,
  int liftCount = 0,
  TimelineClipRow? clip,
}) {
  var next = SplayTreeMap<int, TimelineExposure>.from(timeline);
  if (liftCount > 0) {
    next = splitTimelineAt(next, index);
    next = splitTimelineAt(next, index + liftCount);
    next.removeWhere((key, _) => key >= index && key < index + liftCount);
    next = shiftTimelineFrom(next, index + liftCount, -liftCount);
  } else {
    // No lift, but the insertion point still has to BE a boundary or the
    // clip would land in the middle of a hold and leave the tail of that
    // hold sitting after it with no start of its own.
    next = splitTimelineAt(next, index);
  }
  final inserting = clip;
  if (inserting == null || inserting.isEmpty) {
    return next;
  }
  next = shiftTimelineFrom(next, index, inserting.length);
  for (final entry in inserting.exposures.entries) {
    next[index + entry.key] = entry.value;
  }
  return next;
}

MapEntry<int, TimelineExposure>? _coveringEntry(
  SplayTreeMap<int, TimelineExposure> timeline,
  int index,
) {
  final startAtOrBefore = timeline.lastKeyBefore(index + 1);
  if (startAtOrBefore == null) {
    return null;
  }
  final entry = timeline[startAtOrBefore];
  if (entry == null || !entry.isDrawing) {
    return null;
  }
  if (startAtOrBefore + (entry.length ?? 1) <= index) {
    return null;
  }
  return MapEntry(startAtOrBefore, entry);
}
