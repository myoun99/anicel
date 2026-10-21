/// [done] of [total] as a share — all of it when there was nothing to
/// count: a piece with nothing to do is done.
double doneShare(int done, int total) => total <= 0 ? 1 : done / total;

/// [fraction] of a piece told as the whole run's 0–1, the piece holding
/// [from]–[to] of the bar.
///
/// A run's progress is ONE bar: each piece of it fills its own share and
/// tells how far it is as its own 0–1 — a save's entries, the import
/// window's folder, pool and files, a batch of rows baked in place. One
/// law, so no two bars read a piece differently.
double runShare(
  double fraction, {
  required double from,
  required double to,
}) => from + fraction.clamp(0.0, 1.0) * (to - from);

/// [fraction] of the [index]th of [count] even pieces, told as the whole
/// run's 0–1 ([runShare]).
double pieceShare(
  double fraction, {
  required int index,
  required int count,
}) => runShare(fraction, from: index / count, to: (index + 1) / count);
