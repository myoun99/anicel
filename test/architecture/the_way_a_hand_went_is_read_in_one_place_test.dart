import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../helpers/dart_sources.dart';
import '../helpers/source_ledger.dart';

/// 🚨WHICH WAY A HAND WENT FURTHER IS READ IN ONE PLACE —
/// `wentFurtherAlongFirst`, and the drag kept to it, `keptToOneWay`.
///
/// `a.abs() >= b.abs()` was written out three times — a graph's Shift
/// (I-3 ③), a pair of scales scrubbed one number at a time, a two-finger
/// flip's way — and the canvas's Shift would have been the fourth (I-136,
/// 유저 2026-10-27: 「캔버스에서 어떤 조작 할때도 쉬프트 통해 누른상태면
/// 한쪽으로만」). A tie went to the first way in all three, and nothing
/// but each copy said so.
///
/// ⚠️`>` is not this: keeping the larger of two (`by.abs() > was.abs()`)
/// asks which is bigger, not which way a hand went.
void main() {
  const home = 'lib/src/core/one_way.dart';

  /// Two magnitudes compared, the first at least the second.
  final aWayChosen = RegExp(r'\.abs\(\)\s*>=\s*[\w.]+\.abs\(\)');

  /// The lines of [source] — its comments aside — that read a way by hand.
  List<int> waysIn(String source) {
    final code = codeOfLines(source);
    return [
      for (final m in aWayChosen.allMatches(code))
        '\n'.allMatches(code.substring(0, m.start)).length + 1,
    ];
  }

  test('premise: the home reads it once', () {
    expect(waysIn(File(home).readAsStringSync()), hasLength(1));
  });

  test('premise: the scan sees the spellings it took out', () {
    const spelled = [
      'final alongAcross = dragDelta.dx.abs() >= dragDelta.dy.abs();',
      'return along.abs() >= across.abs()',
      'final horizontal = firstMovedDelta.dx.abs() >= '
          'firstMovedDelta.dy.abs();',
    ];
    for (final source in spelled) {
      expect(waysIn(source), hasLength(1), reason: source);
    }
    expect(waysIn('if (was == null || by.abs() > was.abs()) {'), isEmpty);
    expect(waysIn('// along.abs() >= across.abs()'), isEmpty);
  });

  test('no file but the home reads a way by hand', () {
    final offenders = <String>[
      for (final file in dartFilesUnder('lib'))
        if (libPath(file) != home)
          for (final line in waysIn(file.readAsStringSync()))
            '${libPath(file)}:$line',
    ];
    expect(offenders, isEmpty, reason: 'reach for keptToOneWay');
  });
}
