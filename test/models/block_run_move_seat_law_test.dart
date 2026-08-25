import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/block_run_move.dart';

/// R4q-unify — **the swap happens where the hand is.**
///
/// 유저 2026-08-24, 📷3장: 「①시작 ②한 칸 이동(아직 여유 있음) ③한 칸 더 →
/// 그림5가 선택 왼쪽으로 튄다. 두 칸 더 갔을 때 밀려야 맞다」. The suspect on
/// the card was `seatStartFor` adding `slots[rank].leadingGap`, i.e. an
/// off-by-one when a GAP sits between the run and its neighbour — and the card
/// says ⛔단정하지 말고 재현부터.
///
/// So this is the reproduction, stated as the rule's own words rather than as
/// one screenshot's numbers (T14, ⛔재론 금지):
///
/// > **a run swaps when the cursor reaches the seat it will SIT IN after the
/// > swap** … the block is therefore exactly under the hand at the instant it
/// > moves.
///
/// ⇒ At the exact delta where the order flips, the run's new start must equal
/// where the hand asked for it. One frame early and the block appears to jump
/// out from under the cursor, which is what the screenshots show.
void main() {
  /// Every layout of three blocks 1–3 frames long with gaps up to 2 in each
  /// slot — 729 layouts, small enough to enumerate and wide enough that a gap
  /// sits in each of the three places it can sit, beside blocks of every
  /// relative length. Crossed with every contiguous run in them.
  Iterable<List<BlockMoveSlot>> layouts() sync* {
    for (var a = 0; a <= 2; a += 1) {
      for (var b = 0; b <= 2; b += 1) {
        for (var c = 0; c <= 2; c += 1) {
          for (var la = 1; la <= 3; la += 1) {
            for (var lb = 1; lb <= 3; lb += 1) {
              for (var lc = 1; lc <= 3; lc += 1) {
                yield [
                  (leadingGap: a, length: la),
                  (leadingGap: b, length: lb),
                  (leadingGap: c, length: lc),
                ];
              }
            }
          }
        }
      }
    }
  }

  int startOfSlot(List<BlockMoveSlot> slots, int index) {
    var at = 0;
    for (var i = 0; i <= index; i += 1) {
      at += slots[i].leadingGap;
      if (i < index) {
        at += slots[i].length;
      }
    }
    return at;
  }

  test('wherever the order flips, the run lands under the hand', () {
    final offenders = <String>[];

    for (final slots in layouts()) {
      for (var run = 0; run < slots.length; run += 1) {
        // Multi-block runs too: the screenshots are of a SELECTION being
        // dragged, and a run of two is where a rank and a length can
        // disagree.
        for (var runEnd = run; runEnd < slots.length; runEnd += 1) {
        final from = startOfSlot(slots, run);
        for (var delta = -8; delta <= 8; delta += 1) {
          final layout = planBlockRunMove(
            slots: slots,
            runStart: run,
            runEnd: runEnd,
            frameDelta: delta,
          );
          if (!layout.isReorder) {
            continue;
          }
          final previous = planBlockRunMove(
            slots: slots,
            runStart: run,
            runEnd: runEnd,
            frameDelta: delta > 0 ? delta - 1 : delta + 1,
          );
          // The FIRST delta of this direction that reorders — the instant the
          // rule is about.
          if (previous.isReorder) {
            continue;
          }
          final landed = layout.startOf(run);
          if (landed != from + delta) {
            offenders.add(
              'gaps ${[for (final s in slots) s.leadingGap]} '
              'lengths ${[for (final s in slots) s.length]} '
              'run $run..$runEnd delta $delta: '
              'asked ${from + delta}, landed $landed',
            );
          }
        }
        }
      }
    }

    expect(
      offenders,
      isEmpty,
      reason: 'the swap is measured at the seat the run will SIT IN, so the '
          'run is under the cursor at the instant it takes it. A landing '
          'that differs is the block jumping out from under the hand',
    );
  });
}

/// 🔍**The card's suspect was wrong, and this file is the measurement.**
///
/// R4q-unify named `seatStartFor`'s `slots[rank].leadingGap` and asked for a
/// reproduction before any conclusion. Across every layout above — gaps in all
/// three slots, blocks of every relative length, every contiguous run, every
/// delta from −8 to +8 — the rank flips exactly where the rule says it does.
/// The planner is not where the reported jump comes from.
///
/// ⚠️So the remaining suspects are the two things this file cannot see: the
/// caller that BUILDS the slots out of a row's exposures (where a gap becomes
/// a `leadingGap`), and the delta the pointer produces. Whoever picks this up
/// starts there, with the screenshots — and not by re-reading the planner,
/// which now has a test saying it is right.
