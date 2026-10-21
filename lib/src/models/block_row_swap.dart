import 'dart:collection';

import 'audio_clip.dart';
import 'block_run_move.dart';
import 'cel_bank_lanes.dart';
import 'frame_id.dart';
import 'timeline_coverage.dart';
import 'timeline_exposure.dart';

/// What blocks laid on another row do with the blocks already there.
///
/// 🗣️F-384 (유저 2026-10-17): 「좌우 이동이 서로 위치 바꾸는것처럼 위아래
/// 행이동도 위아래 위치바꾸는느낌으로 모든 블록이동 법 통일」 — and
/// F-384-Q1 (2026-10-21): 「덮인 블록이 떠난 자리로 — 자리 바꾸기」. A MOVE
/// swaps ([LandingSwapsThem]); a file or a medium put on a row is no move
/// but an insertion, and keeps the push ([LandingPushesThem]).
sealed class LandingOnBlocks {
  const LandingOnBlocks();
}

/// The blocks landed on make way — the push an insertion makes (R12-②,
/// [startsClearingFrontier]).
final class LandingPushesThem extends LandingOnBlocks {
  const LandingPushesThem();
}

/// The blocks landed on go back to the row the move left, each on its own
/// frames ([blocksLandedOn], [timelineTakingBack]) — the move's law
/// (F-384).
///
/// [bank] answers the landing row's other lanes: a cel one of them still
/// shows stays where it is, and the move is refused rather than split the
/// link — the rule the moved cels follow (F-136).
final class LandingSwapsThem extends LandingOnBlocks {
  const LandingSwapsThem(this.bank);

  final CelBankLanes bank;
}

/// The blocks of [row] that blocks laid at [spans] land on — each span
/// alone, so a block standing in a gap between two of them is not landed
/// on, and stays (F-384-Q1: 「덮이지 않은 블록은 그대로」).
List<TimelineDrawingBlock> blocksLandedOn(
  Iterable<TimelineDrawingBlock> row,
  Iterable<({int start, int length})> spans,
) => [
  for (final block in row)
    if (spans.any(
      (span) =>
          span.start < block.endIndexExclusive &&
          block.startIndex < span.start + span.length,
    ))
      block,
];

/// [row] taking [returned] back, each on its own frames: a block of the
/// row one reaches makes way past it, and the push runs on as an
/// insertion's does ([startsClearingFrontier]) — the empty space absorbs it
/// before the next block moves.
///
/// ⚖️Mine, not the user's: the way the row makes room is always later.
/// A push toward frame 0 can meet the wall, and a block sent back has
/// nowhere else to stand.
SplayTreeMap<int, TimelineExposure> timelineTakingBack(
  Map<int, TimelineExposure> row,
  Iterable<TimelineDrawingBlock> returned,
) {
  var own = [
    for (final block in drawingBlocks(SplayTreeMap.of(row)))
      (start: block.startIndex, entry: block.entry),
  ];
  final back = [...returned]
    ..sort((a, b) => a.startIndex.compareTo(b.startIndex));
  for (final block in back) {
    final first = own.indexWhere(
      (mine) => mine.start + mine.entry.length! > block.startIndex,
    );
    if (first < 0) {
      continue;
    }
    final reached = own.sublist(first);
    final starts = startsClearingFrontier([
      for (final mine in reached)
        (start: mine.start, length: mine.entry.length!),
    ], frontier: block.endIndexExclusive);
    own = [
      ...own.sublist(0, first),
      for (final (position, mine) in reached.indexed)
        (start: starts[position], entry: mine.entry),
    ];
  }
  return SplayTreeMap.of({
    for (final mine in own) mine.start: mine.entry,
    for (final block in back) block.startIndex: block.entry,
  });
}

/// The sounds of [clips] anchored to [cels] — what a cel carries when it
/// changes rows (an SE block's take anchors to its cel,
/// [AudioClip.frameId]).
List<AudioClip> clipsAnchoredTo(Iterable<AudioClip> clips, Set<FrameId> cels) =>
    [
      for (final clip in clips)
        if (cels.contains(clip.frameId)) clip,
    ];
