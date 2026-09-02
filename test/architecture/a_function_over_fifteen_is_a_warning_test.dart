@TestOn('vm')
library;

import 'package:flutter_test/flutter_test.dart';

import '../../tool/code_map.dart';

/// ⚠️A FUNCTION OVER COGNITIVE COMPLEXITY 15 IS A WARNING — NOT A GATE.
///
/// The coding rules of 2026-09-02 (CLAUDE.md 「엉클밥 규칙」, commit 401730d0):
/// 「복잡도는 「인지 복잡도 15」를 경고선으로 쓴다 … ⛔게이트로 걸지 않는다 —
/// 걸면 감사가 숫자 맞추기가 되고 이해도가 떨어지는 분할이 나온다」. 15 is not
/// an arbitrary number: it is the default of the metric's own authors
/// (SonarSource S3776). The reasoning is in `complexity-and-mutation-metrics.md`.
///
/// ## What this test does, and does not
///
/// It reads the map (`tool/code_map.dart` is the one place cognitive
/// complexity is computed — see its header for the rules) and PRINTS every
/// function over the line, worst first, so the number is in front of whoever
/// runs the suite. It fails only if the tree could not be read: an empty walk
/// that "warns of nothing" would be a lie, and that is the one thing it
/// refuses to say.
///
/// ⛔It does not fail on the count. The gate this replaced (a ratchet at 6,
/// switched on and off the same day) made every function over the line a
/// build failure — and Beck's order (`when-rules-conflict.md`: tests →
/// intent → duplication → minimum) says a split that lowers the number and
/// hides the intent is a loss. The audit reads this list to CHOOSE targets;
/// it does not chase it.
///
/// 🧪Measured the day the metric changed: 10,636 functions; over 6 by
/// cognitive 1,071, over 15 about 350 — the tail is the god objects
/// (`editor_session_manager.dart`) and the reference kernels, which the
/// audit reaches from the outside in.
void main() {
  const warningLine = 15;

  late CodeMap map;

  setUpAll(() => map = CodeMap.walk('lib'));

  test('the premise: the tree was read', () {
    expect(map.unreadable, isEmpty, reason: map.unreadable.toString());
    expect(map.functions.length, greaterThan(9000));
  });

  test('what is over the warning line, worst first (a report, not a gate)', () {
    final over = [
      for (final f in map.functions)
        if (f.cognitive > warningLine) f,
    ]..sort((a, b) => b.cognitive.compareTo(a.cognitive));
    final lines = [
      for (final f in over.take(40))
        '  ${f.cognitive.toString().padLeft(4)}  ${f.lines.toString().padLeft(5)}L  '
            '${f.file}::${f.qualified}',
    ];
    // ignore: avoid_print
    print(
      '⚠️ ${over.length} of ${map.functions.length} functions read above '
      'cognitive complexity $warningLine (the warning line, not a gate). '
      'Worst ${lines.length}:\n${lines.join('\n')}',
    );
    // The only assertion: the report is about something. A ceiling nothing
    // exceeds would mean the number, not the code, is wrong.
    expect(over, isNotEmpty);
  });
}
