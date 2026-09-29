import 'dart:collection';

import 'block_run_move.dart';
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
/// | 붙여넣기, 선택 없음 | 0 — nothing comes out, and what follows moves only as far as the clip reaches it; INSIDE a block, the rest of that block (F-236) |
/// | 붙여넣기, 선택 있음 | the selection's length — 갈아끼우기 |
/// | 잘라내기 | the selection's length, with no clip going in |
///
/// 🗣️F-235 (유저 2026-09-29): 「블록, 빈 공간에 붙여넣는건데 대체 왜 뒤가
/// 밀려나냐니까? 컷블록이든 프레임이든」 · 「겹치는 공간이 전혀 없는
/// 붙여넣기인데도 뒤가 밀려나니까 하는소리임」. ↩️N = 0 moved EVERYTHING
/// after the insertion point right by the clip's length, into empty space
/// or not; it pushes the way every other insertion does now
/// ([clearTimelineFrom]).
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
  TimelineClipRow({
    required Map<int, TimelineExposure> exposures,
    required this.length,
    required this.timed,
  }) : assert(length >= 0, 'A clip run cannot be shorter than nothing.'),
       exposures = SplayTreeMap<int, TimelineExposure>.from(exposures);

  const TimelineClipRow.empty()
    : exposures = const {},
      length = 0,
      timed = true;

  /// ONE comma of [exposure]'s drawing, without its timing — what a copy
  /// with nothing selected banks (F-152, 유저 2026-09-16: 「그냥 그곳에
  /// 서있을떄 복사한거면 … 붙혀넣을때 1콤마로서 붙혀넣게」).
  TimelineClipRow.untimed(TimelineExposure exposure)
    : exposures = {0: exposure.copyWith(length: 1)},
      length = 1,
      timed = false;

  /// Offset from the run start → the authored entry beginning there.
  final Map<int, TimelineExposure> exposures;

  /// How many CELLS the run spans, gaps and trailing blanks included. Not
  /// derivable from [exposures]: a run may end in empty cells, and those
  /// cells are part of what was selected.
  final int length;

  /// Whether the commas are part of what was copied — a run taken off a
  /// selection keeps them where it lands (「해당 블록을 선택해서 복사하면
  /// 콤마 유지되도록」); an [untimed] comma takes the length of the place it
  /// lands in, when that place is the rest of a block ([spliceTimeline]).
  final bool timed;

  bool get isEmpty => length == 0;

  /// This clip carrying [exposures] instead — the same run, the same
  /// timing, other entries (a paste re-spelling or re-minting what it lands).
  TimelineClipRow withExposures(Map<int, TimelineExposure> exposures) =>
      TimelineClipRow(exposures: exposures, length: length, timed: timed);
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

/// The block [index] stands inside, from [index] on, made [exposure]'s
/// drawing — THE division an added frame makes (user's rule 2026-07-27:
/// `1-----` with the cursor on the third frame becomes `1--o--`, the new
/// drawing taking over the rest of the hold), and an untimed paste landing
/// there makes the same one (F-236).
///
/// The dots past [index] stay with the frames they time; the head keeps
/// the memo ([splitTimelineAt]). [index] must be strictly inside a block
/// ([restOfBlockAt] is positive).
SplayTreeMap<int, TimelineExposure> blockRestTakenBy(
  Map<int, TimelineExposure> timeline,
  int index,
  TimelineExposure exposure,
) {
  assert(restOfBlockAt(timeline, index) > 0, 'not inside a block');
  final next = splitTimelineAt(timeline, index);
  final rest = next[index]!;
  next[index] = exposure.copyWith(
    length: rest.length,
    breakdownOffsets: rest.breakdownOffsets,
  );
  return next;
}

/// How many cells of the block [index] stands STRICTLY inside are left from
/// [index] on — 0 at a block's head, in an empty cell, or past every block.
int restOfBlockAt(Map<int, TimelineExposure> timeline, int index) {
  final covering = _coveringEntry(
    timeline is SplayTreeMap<int, TimelineExposure>
        ? timeline
        : SplayTreeMap<int, TimelineExposure>.from(timeline),
    index,
  );
  if (covering == null || covering.key == index) {
    return 0;
  }
  return covering.key + (covering.value.length ?? 1) - index;
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

/// Everything starting at or after [index] made to clear [frontier] — THE
/// push an insertion makes ([startsClearingFrontier]): the empty cells
/// ahead of each block absorb it before it reaches the block behind them,
/// and a block it never reaches stays where it is.
SplayTreeMap<int, TimelineExposure> clearTimelineFrom(
  Map<int, TimelineExposure> timeline,
  int index, {
  required int frontier,
}) {
  final next = SplayTreeMap<int, TimelineExposure>();
  final downstream = <int>[];
  for (final key in SplayTreeMap<int, TimelineExposure>.from(timeline).keys) {
    if (key < index) {
      next[key] = timeline[key]!;
    } else {
      downstream.add(key);
    }
  }
  final starts = startsClearingFrontier([
    for (final key in downstream) (start: key, length: timeline[key]!.length!),
  ], frontier: frontier);
  for (final (position, key) in downstream.indexed) {
    next[starts[position]] = timeline[key]!;
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
    timed: true,
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
  final inserting = clip;
  final replacing = inserting != null && !inserting.isEmpty;
  if (liftCount == 0 && replacing) {
    final inside = _insertedInsideABlock(timeline, index, inserting);
    if (inside != null) {
      return inside;
    }
  }
  var next = SplayTreeMap<int, TimelineExposure>.from(timeline);
  if (liftCount > 0) {
    next = splitTimelineAt(next, index);
    next = splitTimelineAt(next, index + liftCount);
    next.removeWhere((key, _) => key >= index && key < index + liftCount);
    // 🚨★★★A LIFT WITH NOTHING GOING BACK IN LEAVES A HOLE (유저 08-15 ⑳:
    // 「프레임 잘라내기하면 뒤 프레임을 앞당김. 이딴거 누가넣으랫지? 삭제는
    // 잘만 해당 위치 블록만 삭제하고 다른거 위치 안건드는데」).
    //
    // ⛔The pull-in was MINE. E(T2·T3) built the splice as "the length
    // difference is absorbed behind" — push when longer, pull when shorter —
    // and defined 잘라내기 as a splice with no clip, so cutting dragged the
    // rest of the row forward. Symmetry made it look right; nobody asked
    // for it.
    //
    // ⚠️The push STAYS, because that half the user did confirm (T3:
    // 「현재 인덱스에 블록이 있으면 그 블록의 앞부분에 끼워넣는다. 즉 뒤를
    // 민다」). So the difference is only absorbed when something is actually
    // going back in — a REPLACE still closes its own gap, and a plain lift
    // is a delete that happens to keep what it took.
    if (replacing) {
      next = shiftTimelineFrom(next, index + liftCount, -liftCount);
    }
  } else {
    // No lift, but the insertion point still has to BE a boundary or the
    // clip would land in the middle of a hold and leave the tail of that
    // hold sitting after it with no start of its own.
    next = splitTimelineAt(next, index);
  }
  if (!replacing) {
    return next;
  }
  // A replace absorbs its own difference in the tail (the T2·T3 table
  // above); a bare insert pushes the way every insertion does (F-235).
  next = liftCount > 0
      ? shiftTimelineFrom(next, index, inserting.length)
      : clearTimelineFrom(next, index, frontier: index + inserting.length);
  for (final entry in inserting.exposures.entries) {
    next[index + entry.key] = entry.value;
  }
  return next;
}

/// [clip] inserted at [index] when that is INSIDE a block — null anywhere
/// else, where the insert is the plain one.
///
/// 🗣️F-236 (유저 2026-09-29): 「블록 중간에 붙여넣는거랑 프레임 추가랑 똑같은
/// 법 통일」 — an insert that lands inside a block replaces the rest of that
/// block, as an added frame does. What the clip brings decides the length
/// (F-236-Q1): a comma copied standing has no timing and takes the rest of
/// the hold — the very division an added frame makes ([blockRestTakenBy]);
/// a run copied off a selection keeps its commas and the tail absorbs the
/// difference, as every replace does (T2·T3): 「선택범위로 코마정보가
/// 있을때만 코마대로 유지해서 붙여넣어서 뒤가 짧으면 당기고 부족하면 밀고」.
/// ↩️The block was split and its rest pushed on behind the clip, so the
/// same drawing came back after it (`1--AB1--`).
SplayTreeMap<int, TimelineExposure>? _insertedInsideABlock(
  Map<int, TimelineExposure> timeline,
  int index,
  TimelineClipRow clip,
) {
  final rest = restOfBlockAt(timeline, index);
  if (rest == 0) {
    return null;
  }
  return clip.timed
      ? spliceTimeline(
          timeline: timeline,
          index: index,
          liftCount: rest,
          clip: clip,
        )
      : blockRestTakenBy(timeline, index, clip.exposures[0]!);
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
