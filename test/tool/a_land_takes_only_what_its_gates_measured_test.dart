import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../helpers/lane_script.dart';

/// 🚨lane-land-edited-under-its-gates (2026-09-30): while a land sat in
/// `flutter analyze`, its author fixed the red architecture test in the
/// lane, uncommitted. The gates read the working tree and passed; the merge
/// takes commits only, so master got them without the fix, and the forced
/// worktree removal destroyed it (66e598ba4, repaired by 6ab4facd1).
/// Refusal 7 asks again after the last gate: is HEAD still the commit that
/// was read before the first, and does the tree hold exactly that.
///
/// ↩️Until 2026-10-08 the gates and the asking-again were lines of `land`
/// itself. They are functions now — `gates`, `unmoved_since` — because a
/// second command runs them: `gate`, which stamps the commit the gates
/// passed on so that the trunk's machine does not measure a sent lane twice
/// (card a-sent-lane-is-gated-once). A stamp is the same promise a merge
/// is — 「this commit was measured」 — so it stands behind the same refusal.
///
/// ⚠️These pin WHERE the script asks, not what it does next — the suite
/// spawns no process (tests_do_not_race_the_code_test). What it does was
/// run by hand in scratch repositories, with a `flutter` that edited,
/// committed or failed during analyze: a land refused all three (and the
/// script before refusal 7 landed all three), and a gate stamped nothing
/// for any of them (2026-10-08, 56 checks; the script before that change
/// fails 31 of them).
void main() {
  final codeOf = LaneScript(File('tool/lane.sh').readAsStringSync()).codeOf;
  int at(List<String> code, String text) =>
      code.indexWhere((line) => line.contains(text));

  /// The lines of [code] that run something IN the lane: flutter from
  /// inside it, and the native build and tests.
  List<int> runsIn(List<String> code) => [
    for (var i = 0; i < code.length; i++)
      if (code[i].contains(r'(cd "$p" &&') || code[i].contains('cmd_native'))
        i,
  ];

  group('the gates', () {
    // Late, so the LIVENESS expect in `codeOf` runs inside a test.
    late final gates = codeOf('gates');

    test('LIVENESS — analyze with no arguments, the architecture tests, '
        'and the native build of a lane that touched the C', () {
      final all = gates.join('\n');
      expect(all, contains(r'(cd "$p" && flutter analyze)'));
      expect(all, contains(r'(cd "$p" && flutter test test/architecture)'));
      expect(all, contains(r'cmd_native "$name"'));
    });

    test('🚨are run from ONE place: neither the land nor the gate command '
        'runs anything in the lane by itself', () {
      for (final command in ['cmd_land', 'cmd_gate']) {
        expect(runsIn(codeOf(command)), isEmpty, reason: command);
        expect(
          at(codeOf(command), r'gates "$name" "$p"'),
          isNot(-1),
          reason: '$command runs them through the one function',
        );
      }
    });
  });

  group('asking again', () {
    late final asks = codeOf('unmoved_since');

    test('reads HEAD and compares it with the commit it was handed', () {
      final read = at(asks, r'now="$(git -C "$p" rev-parse HEAD)"');
      final compared = at(asks, r'[ "$now" = "$measured" ] || die');
      expect(read, isNot(-1));
      expect(compared, greaterThan(read));
    });

    test('and the tree must be clean — through the same check that ran '
        'before the first gate', () {
      final clean = at(asks, r'lane_is_clean "$p" || die');
      expect(clean, greaterThan(at(asks, r'[ "$now" = "$measured" ] || die')));
      expect(
        at(asks, 'status --short'),
        -1,
        reason: 'a second, inline clean check is a copy that can drift from '
            'lane_is_clean',
      );
    });
  });

  group('a land', () {
    late final land = codeOf('cmd_land');
    late final rebase = at(land, r'rebase "$TRUNK"');
    late final gated = at(land, r'gates "$name" "$p"');
    late final merge = at(land, 'merge --ff-only');

    test('LIVENESS — rebases, runs its gates, then merges', () {
      expect(rebase, isNot(-1));
      expect(gated, greaterThan(rebase));
      expect(merge, greaterThan(gated));
    });

    test('the commit the gates measure is read after the rebase, before '
        'the gates', () {
      expect(
        at(land, r'measured="$(git -C "$p" rev-parse HEAD)"'),
        inExclusiveRange(rebase, gated),
      );
    });

    test('after the gates and before the merge it asks again, of that '
        'commit', () {
      expect(
        at(land, r'unmoved_since "$p" "$measured" land'),
        inExclusiveRange(gated, merge),
      );
    });

    test('the tree is clean before anything is rebased or measured', () {
      final clean = at(land, r'lane_is_clean "$p" || die');
      expect(clean, isNot(-1));
      expect(clean, lessThan(rebase));
      expect(clean, lessThan(at(land, 'gated_at')));
    });

    test('🚨is not measured a second time ONLY when both hold: its stamp '
        'names its very commit, and the trunk has not moved from under '
        'it — everything else is rebased and measured, as before', () {
      // 유저 2026-10-08, as the 관제 session wrote it down: 「다 권하는대로
      // 하자. 낭비없애자고」 — four of seven sent lanes had been measured a
      // second time on the commit their machine measured them on.
      final read = at(land, r'head="$(git -C "$p" rev-parse HEAD)"');
      final stamped = at(land, r'if [ "$(gated_at "$name")" = "$head" ] \');
      final onTrunk = at(
        land,
        r'&& git -C "$p" merge-base --is-ancestor "$TRUNK" HEAD; then',
      );
      expect([read, stamped, onTrunk], everyElement(isNot(-1)));
      expect(read, lessThan(stamped));
      expect(onTrunk, stamped + 1, reason: 'one `if`, both conditions');

      final otherwise = land.indexWhere((line) => line.trim() == 'else');
      final done = land.indexWhere((line) => line.trim() == 'fi', otherwise);
      expect(otherwise, inExclusiveRange(onTrunk, rebase));
      expect(
        done,
        inExclusiveRange(
          at(land, r'unmoved_since "$p" "$measured" land'),
          merge,
        ),
        reason: 'the rebase, the gates and the asking-again are all of the '
            'else — the merge is after both',
      );
      expect(
        land.sublist(onTrunk + 1, otherwise).join('\n'),
        isNot(contains('git ')),
        reason: 'the stamped road does nothing to the lane on its way to '
            'the merge',
      );
    });

    test('🚨takes its TURN before it reads or changes anything of the lane, '
        'and gives it back however the land ends', () {
      // ↩️Two lands ran side by side, and the one whose gates finished
      // second had its fast-forward refused — its gates thrown away, to be
      // run again (2026-10-08: F-291's land lost that way).
      final turn = at(land, 'land_turn');
      expect(turn, greaterThan(at(land, 'away && die')));
      expect(turn, greaterThan(at(land, r'require_worktree "$p"')));
      expect(turn, lessThan(at(land, r'lane_is_clean "$p" || die')));

      final taking = codeOf('land_turn');
      final taken = at(taking, r'until mkdir "$turn"');
      final handedBack = at(taking, 'trap ');
      expect(taken, isNot(-1));
      expect(handedBack, greaterThan(taken));
      expect(taking[handedBack], contains('EXIT'));
      final all = taking.join('\n');
      expect(
        all,
        contains('--git-common-dir'),
        reason: 'the turn is the repository\'s — one for every worktree and '
            'every session',
      );
      expect(
        all,
        contains(r'! kill -0 "$holder"'),
        reason: 'a killed lander\'s turn is taken over',
      );
      expect(all, contains('-mmin +45'), reason: 'and so is a hung one\'s');
    });
  });

  group('a stamp', () {
    late final gate = codeOf('cmd_gate');

    test('🚨is written for the commit read BEFORE the first gate, after '
        'the asking-again that follows the last', () {
      final clean = at(gate, r'lane_is_clean "$p" || die');
      final read = at(gate, r'measured="$(git -C "$p" rev-parse HEAD)"');
      final gated = at(gate, r'gates "$name" "$p"');
      final asked = at(gate, r'unmoved_since "$p" "$measured" gate');
      final stamped = at(
        gate,
        r'update-ref "$(gate_ref "$name")" "$measured"',
      );
      expect([clean, read, gated, asked, stamped], everyElement(isNot(-1)));
      expect(clean, lessThan(read), reason: 'a dirty lane is not gated');
      expect(read, lessThan(gated));
      expect(gated, lessThan(asked));
      expect(asked, lessThan(stamped));
    });

    test('🚨is MADE by `gate` and by nothing else — the tool\'s word, never '
        'a session\'s — and `receive` alone carries one over from the '
        'machine that made it', () {
      final script = LaneScript(File('tool/lane.sh').readAsStringSync());
      List<String> functionsWhere(bool Function(String line) test) => [
        for (final function in script.functions)
          if (script.codeOf(function).any(test)) function,
      ];
      expect(
        functionsWhere(
          (line) =>
              line.contains('update-ref') &&
              line.contains('gate_ref') &&
              !line.contains('update-ref -d'),
        ),
        ['cmd_gate'],
      );
      expect(
        functionsWhere(
          (line) => line.contains(r':$(gate_ref "$name")"'),
        ),
        ['cmd_receive'],
        reason: 'the one refspec that lands on a stamp',
      );
    });
  });

  test('the check puts the platform folders back and refreshes the stat '
      'cache before it reads the status', () {
    final check = codeOf('lane_is_clean');
    final status = at(check, 'status --short');
    expect(status, isNot(-1));
    final before = inExclusiveRange(-1, status);
    expect(at(check, 'checkout -- linux macos windows'), before);
    expect(at(check, 'update-index -q --really-refresh'), before);
  });
}
