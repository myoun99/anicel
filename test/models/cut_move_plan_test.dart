import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/cut_move_plan.dart';

/// The ONE rule a cut drag follows: the run's rank among the cuts it is not
/// part of, read against their ORIGINAL midpoints. Same rank re-times, a
/// different rank reorders.
void main() {
  const a = CutId('a');
  const b = CutId('b');
  const c = CutId('c');

  /// Three 10-frame cuts, back to back: a[0,10) b[10,20) c[20,30).
  List<CutMoveSlot> packed() => const [
    (id: a, leadingGapFrames: 0, duration: 10),
    (id: b, leadingGapFrames: 0, duration: 10),
    (id: c, leadingGapFrames: 0, duration: 10),
  ];

  test('no delta plans nothing', () {
    final plan = planCutMove(
      slots: packed(),
      runStart: 1,
      runEnd: 1,
      frameDelta: 0,
    );

    expect(plan.isReorder, isFalse);
    expect(plan.gaps, isEmpty);
  });

  test('a drag into free space re-times: the gap grows and the follower '
      'holds still', () {
    // a[0,10) — 8-frame gap — b[18,28) c[28,38).
    final slots = [
      (id: a, leadingGapFrames: 0, duration: 10),
      (id: b, leadingGapFrames: 8, duration: 10),
      (id: c, leadingGapFrames: 0, duration: 10),
    ];

    final plan = planCutMove(
      slots: slots,
      runStart: 1,
      runEnd: 1,
      frameDelta: -5,
    );

    expect(plan.isReorder, isFalse);
    // b starts at 13 now; c must stay at 28, so its gap opens by 5.
    expect(plan.gaps, {b: 3, c: 5});
  });

  test('a drag stops at contact instead of pushing the neighbour', () {
    final slots = [
      (id: a, leadingGapFrames: 0, duration: 10),
      (id: b, leadingGapFrames: 8, duration: 10),
      (id: c, leadingGapFrames: 0, duration: 10),
    ];

    // Dragging b 12 left would put it over a; it lands touching a instead,
    // and a is untouched. (Twenty would carry b past a's midpoint, which is
    // the reorder case below.)
    final plan = planCutMove(
      slots: slots,
      runStart: 1,
      runEnd: 1,
      frameDelta: -12,
    );

    expect(plan.isReorder, isFalse);
    expect(plan.gaps, {b: 0, c: 8});
  });

  test('reaching past the neighbour\'s midpoint reorders instead', () {
    // b's midpoint sits at 15, a's at 5. Dragging a right by 10 puts its
    // own midpoint at 15 — level with b's, so a lands after b.
    final plan = planCutMove(
      slots: packed(),
      runStart: 0,
      runEnd: 0,
      frameDelta: 10,
    );

    expect(plan.order, [b, a, c]);
    expect(plan.gaps, isEmpty);
  });

  test("the flip point is the SEAT — the neighbour's length away", () {
    // 🚨T14 (유저 확정 2026-08-14): a run swaps once the cursor reaches the
    // seat it will sit in afterwards, so the travel a swap costs is the
    // NEIGHBOUR's length. c back over b lands on frame 10, and ten frames
    // is what it asks for.
    //
    // ⛔This used to want ELEVEN. The rule compared midpoints, and a
    // midpoint had to be strictly cleared. On this fixture every cut is the
    // same length, so (mine + neighbour) ÷ 2 and the seat both land on 10
    // and the two rules differ by exactly that one frame — which is why
    // this is the only case in the file that moved.
    final onTheSeat = planCutMove(
      slots: packed(),
      runStart: 2,
      runEnd: 2,
      frameDelta: -10,
    );
    expect(onTheSeat.order, [a, c, b]);

    final short = planCutMove(
      slots: packed(),
      runStart: 2,
      runEnd: 2,
      frameDelta: -9,
    );
    expect(short.isReorder, isFalse);
    // c already touches b, so there is nowhere left to go: no edit at all.
    expect(short.gaps, isEmpty);
  });

  test('a selected RUN reorders as one unit, keeping its own order', () {
    // [a, b] dragged right past c: c's midpoint is 25, the run's own is
    // 10 — fifteen frames of travel puts them level.
    final plan = planCutMove(
      slots: packed(),
      runStart: 0,
      runEnd: 1,
      frameDelta: 15,
    );

    expect(plan.order, [c, a, b]);
  });

  test('a run re-times as one unit, carrying its own length', () {
    // a[0,10) b[10,20) — 6-frame gap — c[26,36).
    final slots = [
      (id: a, leadingGapFrames: 0, duration: 10),
      (id: b, leadingGapFrames: 0, duration: 10),
      (id: c, leadingGapFrames: 6, duration: 10),
    ];

    final plan = planCutMove(
      slots: slots,
      runStart: 0,
      runEnd: 1,
      frameDelta: 4,
    );

    expect(plan.isReorder, isFalse);
    // The pair starts at 4; c holds at 26, so its gap shrinks by 4.
    expect(plan.gaps, {a: 4, c: 2});
  });

  test('a drag off the left edge lands at frame zero', () {
    final plan = planCutMove(
      slots: packed(),
      runStart: 0,
      runEnd: 0,
      frameDelta: -50,
    );

    expect(plan.isReorder, isFalse);
    expect(plan.gaps, isEmpty);
  });

  test('the last cut may run off the end — nothing bounds it there', () {
    final plan = planCutMove(
      slots: packed(),
      runStart: 2,
      runEnd: 2,
      frameDelta: 40,
    );

    expect(plan.isReorder, isFalse);
    expect(plan.gaps, {c: 40});
  });
}
