import 'package:flutter_test/flutter_test.dart';

import '../helpers/source_ledger.dart';

/// 🚨A LEDGER IS COMPARED ONE WAY — `test/helpers/source_ledger.dart`
/// (board `ledger-ratchets-count-by-hand`, 2026-10-23).
///
/// Every ratchet that keeps a ledger hands what its scan found to these, so
/// a comparison that let one kind of drift through would let it through for
/// all of them at once. So each kind is planted here, and each must fail.
void main() {
  /// Fails as a test fails, its message holding every one of [lines].
  Matcher failsSaying(List<String> lines) => throwsA(
    isA<TestFailure>().having(
      (failure) => failure.message,
      'message',
      allOf([for (final line in lines) contains(line)]),
    ),
  );

  group('a count', () {
    const ledger = {'a.dart': 2, 'b.dart': 1};
    void compare(Map<String, int> found, {Map<String, List<int>>? hits}) =>
        expectCountsMatchLedger(
          found,
          ledger,
          grew: 'GREW',
          paidOff: 'PAID OFF',
          hits: hits,
        );

    test('that matches its ledger passes', () {
      compare({'a.dart': 2, 'b.dart': 1});
    });

    test('in a file the ledger does not name fails as grown', () {
      expect(
        () => compare({'a.dart': 2, 'b.dart': 1, 'new.dart': 1}),
        failsSaying(['GREW', 'new.dart: found 1, ledger 0']),
      );
    });

    test('grown past its ledger fails as grown', () {
      expect(
        () => compare({'a.dart': 3, 'b.dart': 1}),
        failsSaying(['GREW', 'a.dart: found 3, ledger 2']),
      );
    });

    test('shrunk under its ledger fails as paid off', () {
      expect(
        () => compare({'a.dart': 1, 'b.dart': 1}),
        failsSaying(['PAID OFF', 'a.dart: found 1, ledger 2']),
      );
    });

    test('gone from a ledgered file fails as paid off', () {
      expect(
        () => compare({'a.dart': 2}),
        failsSaying(['PAID OFF', 'b.dart: found 0, ledger 1']),
      );
    });

    test('names where each hit stands', () {
      expect(
        () => compare(
          {'a.dart': 3, 'b.dart': 1},
          hits: {
            'a.dart': [4, 9, 12],
          },
        ),
        failsSaying(['a.dart:4', 'a.dart:9', 'a.dart:12']),
      );
    });
  });

  group('a set', () {
    const ledger = [('a.dart', 'x'), ('b.dart', 'y')];
    void compare(List<(String, String)> found) => expectSetMatchesLedger(
      found,
      ledger,
      unledgered: 'UNLEDGERED',
      paidOff: 'PAID OFF',
    );

    test('that matches its ledger passes, in any order', () {
      compare([('b.dart', 'y'), ('a.dart', 'x')]);
    });

    test('with an item the ledger does not name fails as unledgered', () {
      expect(
        () => compare([('a.dart', 'x'), ('b.dart', 'y'), ('c.dart', 'z')]),
        failsSaying(['UNLEDGERED', '(c.dart, z)']),
      );
    });

    test('without an item the ledger names fails as paid off', () {
      expect(
        () => compare([('a.dart', 'x')]),
        failsSaying(['PAID OFF', '(b.dart, y)']),
      );
    });
  });

  group('a line', () {
    test('is cut at its first comment', () {
      expect(codeOf('final a = 1; // one // two'), 'final a = 1; ');
      expect(codeOf('// all of it'), '');
    });

    test('without a comment is left whole', () {
      expect(codeOf("final a = 'b';"), "final a = 'b';");
    });

    test('of a source is cut each on its own, the lines kept', () {
      expect(codeOfLines('a // x\nb\n// c\nd'), 'a \nb\n\nd');
    });
  });

  group('a reason', () {
    test('that says why passes', () {
      expectEveryEntrySaysWhy({
        'a.dart': 'a reason long enough to say why it is here',
      });
    });

    test('that fills a slot fails', () {
      expect(
        () => expectEveryEntrySaysWhy({'a.dart': 'because'}),
        failsSaying(['a.dart needs a reason, not a slot']),
      );
    });
  });
}
