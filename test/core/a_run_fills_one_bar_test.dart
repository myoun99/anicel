import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/core/progress_share.dart';

/// A run's progress is ONE bar: each piece fills its own share of it — a
/// save's entries, the import window's folder, pool and files, a batch of
/// rows baked in place — so a piece's 0–1 is told the same way everywhere.
void main() {
  test('a piece told as the run: its fraction of the stretch it holds', () {
    expect(runShare(0, from: 0.2, to: 0.6), 0.2);
    expect(runShare(0.5, from: 0.2, to: 0.6), closeTo(0.4, 1e-9));
    expect(runShare(1, from: 0.2, to: 0.6), closeTo(0.6, 1e-9));
  });

  test('a piece never tells more of the bar than it holds, nor less', () {
    expect(runShare(1.5, from: 0.2, to: 0.6), closeTo(0.6, 1e-9));
    expect(runShare(-1, from: 0.2, to: 0.6), 0.2);
  });

  test('the second of four even pieces, half done, is three eighths', () {
    expect(pieceShare(0.5, index: 1, count: 4), 0.375);
    expect(pieceShare(0, index: 0, count: 4), 0);
    expect(pieceShare(1, index: 3, count: 4), 1);
  });

  test('done of total — and a piece with nothing to count is done', () {
    expect(doneShare(1, 4), 0.25);
    expect(doneShare(0, 0), 1);
  });
}
