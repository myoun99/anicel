/// Whether a hand that went [first] along one way and [second] along the
/// other went further along the first — a tie is the first's.
///
/// ONE answer for which way a hand went: a drag kept to it
/// ([keptToOneWay]), and the way a two-finger flip takes for good from its
/// first move.
bool wentFurtherAlongFirst(double first, double second) =>
    first.abs() >= second.abs();

/// A hand's travel, [first] along one way and [second] along the other,
/// kept to the one it went further along ([wentFurtherAlongFirst]) — the
/// other part 0.
///
/// ONE answer for every drag that keeps to one way: Shift on a canvas
/// drag that moves something (I-136, 유저 2026-10-27: 「x,y가 있다치면 x
/// 안건들고 y만 이동한다던가」), Shift on a graph's keys (I-3 ③, AE's
/// Shift-drag), and a pair of scales scrubbed one number at a time.
(double, double) keptToOneWay(double first, double second) =>
    wentFurtherAlongFirst(first, second) ? (first, 0.0) : (0.0, second);
