import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 🚨★★★**AN OPEN EDIT MEETS AN INTERRUPTION IN EXACTLY TWO WAYS, THROUGH
/// ONE DOOR.**
///
/// 🗣️유저 2026-09-22: 「변형중 프레임 이동 등 **가능한동작이면 가능하게
/// 냅두고, 불가능한 동작이면 마지막 변형대로 커밋**하라고 내가 말하지않았냐?
/// **두개로 딱 나누라고**?」 · 「**입구를 딱 깔끔하게 두개로만 나눠서 절대
/// 다른 상황 생겨도 대처가능하게**해」 · 「**입구도 하나로 나누고 거기서
/// 분기시키는게 깔끔**할거같긴한데 그런부분 맡길테니」.
///
/// ⛔**AND IT IS THE WHOLE FAMILY, NOT THE ROUTES ANYONE LISTED.** 유저, the
/// same minute: 「**b랑 e만막고 다른 경로 안막는 멍청한짓은 안하길바란다**」.
/// That is what a source scan is for: a new caller — a panel, a shortcut, a
/// host nobody has written yet — cannot quietly grow a third answer.
///
/// 🧪The three answers this replaced, measured on 09-22: a frame walk
/// carried, an open box on a tool change committed, a pending move on that
/// same change opened a DIALOG, and the same switch to a painting tool
/// reached `dispose` and landed both silently.
void main() {
  final source = File(
    'lib/src/ui/canvas/canvas_selection_layer.dart',
  ).readAsStringSync();

  test('the enum names exactly two answers', () {
    final start = source.indexOf('enum SessionInterruption {');
    expect(start, isNonNegative, reason: 'the two answers have a type');
    final body = source.substring(start, source.indexOf('\n}', start));
    final values = RegExp(r'^  (\w+),$', multiLine: true)
        .allMatches(body)
        .map((m) => m.group(1)!)
        .toList();
    expect(
      values,
      ['carry', 'land'],
      reason:
          '⛔A third value is a third answer. 유저 asked for two — if a '
          'situation genuinely needs something else, that is a question for '
          'them, not a value added here.',
    );
  });

  test('every interruption goes through the one door', () {
    // ⚠️CODE ONLY. A doc comment that points at `[SessionInterruption.land]`
    // is prose about the law, not a second way of obeying it — and counting
    // one as a caller is how this scan first failed.
    final code = source
        .split('\n')
        .where((line) => !line.trimLeft().startsWith('///'))
        .join('\n');
    // The door's own branch is the only place these two may be named.
    final calls = RegExp(r'SessionInterruption\.(carry|land)')
        .allMatches(code)
        .length;
    final inTheDoor = RegExp(r'case SessionInterruption\.(carry|land):')
        .allMatches(code)
        .length;
    final callers = RegExp(r'_interrupted\(SessionInterruption\.(carry|land)\)')
        .allMatches(code)
        .length;

    expect(inTheDoor, 2, reason: 'the branch handles both, exhaustively');
    expect(
      calls - inTheDoor,
      callers,
      reason:
          '⛔Something named an answer without going through _interrupted. '
          'Every site says WHICH bucket it is and the door does the rest.',
    );
    expect(
      callers,
      greaterThanOrEqualTo(3),
      reason:
          '⛔전제: the routes really are wired here — a frame walk, a tool '
          'change and an unmount at least',
    );
  });

  test('⛔nothing asks the user instead of picking a bucket', () {
    expect(
      source.contains('askConfirm'),
      isFalse,
      reason:
          '⛔A dialog is a THIRD answer. The R17-① 확정/되돌리기 prompt lived '
          'here and 유저 struck it down: 「두개로 딱 나누라고」.',
    );
  });
}
