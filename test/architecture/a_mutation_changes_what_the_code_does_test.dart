@TestOn('vm')
library;

import 'package:flutter_test/flutter_test.dart';

import '../../tool/mutations.dart';

/// 🚨★★★THE GENERATOR THE EVIDENCE RESTS ON.
///
/// The repo's rule is that a passing test proves nothing and a failing one on
/// turned-off code proves everything. `tool/mutations.dart` produces the
/// turning-off. If it emits an edit that does not change behaviour, every
/// "SURVIVED" it reports is a lie about the suite; if it emits one that does
/// not compile, every "KILLED" is.
///
/// ⚠️`test/architecture/` and not `test/tool/` — see
/// `the_code_map_counts_what_is_there_test.dart` for why.
void main() {
  group('the premise', () {
    test('an ordinary expression yields candidates at all', () {
      // ⛔Every 「X is not mutated」 case below passes on a generator that
      // returns nothing, which is the failure mode this repo keeps meeting.
      expect(mutationsIn('bool f(int a) => a < 3;'), isNotEmpty);
    });
  });

  group('what gets mutated', () {
    List<String> kindsIn(String source) =>
        mutationsIn(source).map((m) => '${m.kind}:${m.was}>${m.replacement}')
            .toList();

    test('a comparison loosens or tightens by one', () {
      expect(kindsIn('bool f(int a) => a < 3;'), ['comparison:<><=']);
      expect(kindsIn('bool f(int a) => a >= 3;'), ['comparison:>=>>']);
    });

    test('equality flips', () {
      expect(kindsIn('bool f(int a) => a == 3;'), ['equality:==>!=']);
      expect(kindsIn('bool f(int a) => a != 3;'), ['equality:!=>==']);
    });

    test('a logical operator swaps, which changes which guard wins', () {
      expect(
        kindsIn('bool f(int a) => a > 0 && a < 9;'),
        containsAll(<String>['logic:&&>||']),
      );
    });

    test('a boolean literal flips wherever it is written', () {
      expect(kindsIn('const bool x = true;'), ['boolean:true>false']);
      expect(kindsIn('void f({bool a = false}) {}'), ['boolean:false>true']);
    });

    test('every operator in a chain is its own candidate', () {
      // ⚠️One mutation per site, not one per expression: a suite can pin the
      // first guard of a condition and miss the second entirely.
      final found = mutationsIn('bool f(int a) => a > 0 && a < 9 || a == 5;');
      expect(found.map((m) => m.was).toList(), ['>', '&&', '<', '||', '==']);
    });

    test('candidates come back in source order', () {
      final found = mutationsIn('bool f(int a) => a > 0 && a < 9;');
      for (var i = 1; i < found.length; i += 1) {
        expect(found[i].offset, greaterThan(found[i - 1].offset));
      }
    });

    test('each candidate carries the line it is on', () {
      final found = mutationsIn('bool f(int a) {\n  return a < 3;\n}');
      expect(found.single.line, 2);
    });
  });

  group('what is left alone', () {
    test('arithmetic is not touched', () {
      // ⛔Deliberate, and the header says why: `+` ↔ `-` does not compile
      // over String or List and this codebase uses `+` on both. Adding it
      // needs type resolution, not a token swap.
      expect(mutationsIn('int f(int a) => a + 1;'), isEmpty);
      expect(mutationsIn("String f(String a) => a + 'x';"), isEmpty);
    });

    test('a file that does not parse yields nothing rather than nonsense', () {
      // 🚨THE FIXTURE MUST CONTAIN SOMETHING MUTABLE, or this passes with the
      // parse-error guard switched off. 🧪It did: the first version was
      // `'class Oops { void f( { } }} )]'`, which has no comparison and no
      // boolean in it, so a partial tree yielded nothing either way and a
      // mutation of the guard survived. The valid half below carries a `<`
      // and a `true`, so a generator that read the broken tree would say so.
      const broken = '''
bool ok(int a) => a < 3;
const bool flag = true;
class Oops { void f( { } }} )]
''';
      expect(mutationsIn(broken), isEmpty);
      // ⚠️And the same source WITHOUT the broken tail does yield them, so the
      // emptiness above is the guard and not the fixture.
      expect(
        mutationsIn('bool ok(int a) => a < 3;\nconst bool flag = true;\n'),
        hasLength(2),
      );
    });

    test('an empty file yields nothing', () {
      expect(mutationsIn(''), isEmpty);
    });
  });

  group('applying one', () {
    test('the edit lands exactly where it said', () {
      const source = 'bool f(int a) => a < 3;';
      final m = mutationsIn(source).single;
      expect(m.applyTo(source), 'bool f(int a) => a <= 3;');
    });

    test('applying to changed text throws instead of editing blind', () {
      // 🚨★★★THE FAILURE THIS PREVENTS: a runner that reverted badly, or
      // mutated a file two edits deep, would silently write a change nobody
      // predicted and then report the RESULT against the mutation it meant
      // to make. Offsets are only meaningful against the source they came
      // from, so applying carries a proof that it still is.
      const source = 'bool f(int a) => a < 3;';
      final m = mutationsIn(source).single;
      expect(
        () => m.applyTo('bool f(int a) => a > 3;'),
        throwsA(isA<StateError>()),
      );
    });

    test('applying twice is refused, not doubled', () {
      // 🧪The measured failure: this produced 「a <== 3」 and said nothing,
      // because the guard compared one character and `<=` starts with `<`.
      const source = 'bool f(int a) => a < 3;';
      final m = mutationsIn(source).single;
      final once = m.applyTo(source);
      expect(m.applyTo(source), 'bool f(int a) => a <= 3;');
      expect(() => m.applyTo(once), throwsA(isA<StateError>()));
    });

    test('a SHORTENING mutation applies once and is then refused too', () {
      // 🧪The opposite failure, from the first attempt at the fix above: a
      // guard asking 「is `>` already there」 sees that `>=` starts with `>`
      // and refuses a mutation nobody had made. The two cases together are
      // why the guard reads a whole token.
      const source = 'bool f(int a) => a >= 3;';
      final m = mutationsIn(source).single;
      expect(m.applyTo(source), 'bool f(int a) => a > 3;');
      expect(() => m.applyTo(m.applyTo(source)), throwsA(isA<StateError>()));
    });

    test('a boolean flip is refused a second time as well', () {
      const source = 'const bool x = true;';
      final m = mutationsIn(source).single;
      expect(m.applyTo(source), 'const bool x = false;');
      expect(() => m.applyTo(m.applyTo(source)), throwsA(isA<StateError>()));
    });
  });

  group('over real source', () {
    test('a realistic guard yields one candidate per operator', () {
      const source = '''
class Thing {
  bool visible = true;

  bool shouldPaint(int index, int count) {
    if (index < 0 || index >= count) return false;
    return visible && count != 0;
  }
}
''';
      final found = mutationsIn(source);
      expect(
        found.map((m) => m.was).toList(),
        ['true', '<', '||', '>=', 'false', '&&', '!='],
      );
      // ⚠️And every one of them lands: a candidate that cannot be applied is
      // a candidate that would waste a whole test run.
      for (final m in found) {
        expect(() => m.applyTo(source), returnsNormally);
      }
    });
  });
}
