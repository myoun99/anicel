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
/// spawns no process (tests_do_not_race_the_code_test). What it DOES is
/// `bash tool/lane_test.sh`, by hand: scratch repositories, and a `flutter`
/// that writes down every call and can edit, commit or fail during
/// analyze. A land refuses all three (the script before refusal 7 landed
/// all three), and a gate stamps nothing for any of them (2026-10-08: 70
/// checks; the script before these changes fails 38 of them).
void main() {
  final codeOf = LaneScript(File('tool/lane.sh').readAsStringSync()).codeOf;
  int at(List<String> code, String text) =>
      code.indexWhere((line) => line.contains(text));

  /// The lines of [code] that run something IN the lane: flutter from
  /// inside it, the native build and tests, and the GPU engine crate's.
  List<int> runsIn(List<String> code) => [
    for (var i = 0; i < code.length; i++)
      if (code[i].contains(r'(cd "$p" &&') ||
          code[i].contains('cmd_native') ||
          code[i].contains('cmd_crate') ||
          code[i].contains('crate_gate'))
        i,
  ];

  group('the gates', () {
    // Late, so the LIVENESS expect in `codeOf` runs inside a test.
    late final gates = codeOf('gates');

    test('LIVENESS — analyze with no arguments, the architecture tests, '
        'the native build of a lane that touched the C, and the crate\'s '
        'tests of a lane that touched the crate or its ledger', () {
      final all = gates.join('\n');
      // Offline (관제 2026-11-06): what the lane resolved from this
      // machine's pub cache, and neither gate resolves it again.
      expect(all, contains(r'resolve_offline "$p" 3'));
      expect(all, contains(r'(cd "$p" && flutter analyze --no-pub)'));
      expect(
        all,
        contains(r'(cd "$p" && flutter test --no-pub test/architecture)'),
      );
      expect(all, contains(r'lane_touched "$p" packages/qa_native/src'));
      expect(all, contains(r'cmd_native "$name"'));
      expect(all, contains(r'crate_gate "$name" "$p"'));
      final crate = codeOf('crate_gate').join('\n');
      expect(
        crate,
        contains(
          r'lane_touched "$p" packages/gpu_engine/rust '
          'test/fixtures/fingerprints.json',
        ),
      );
      expect(crate, contains('    packages/qa_native/src; then'));
      expect(crate, contains(r'cmd_crate "$name"'));
    });

    // native-to-rust (관제 2026-11-06): the native crates are held to the
    // engine the C builds — a key built from other C holds them to the
    // wrong answers.
    test('🚨the crate\'s tests are held to this lane\'s C: its engine is '
        'built from it before cargo runs', () {
      final crate = codeOf('cmd_crate');
      final ensured = at(crate, r'ensure_engine "$p" || die');
      expect(ensured, isNot(-1));
      expect(ensured, lessThan(at(crate, r'"$ROOT/tool/cargo_turn.sh"')));
    });

    // 저장 2026-11-05: four Dart files, opened before the trunk took crate
    // commits, were refused for want of cargo — two dots read the trunk's
    // commits as the lane's.
    test('🚨a lane pays for what IT changed: three dots, from where it left '
        'the trunk', () {
      expect(
        at(
          codeOf('lane_touched'),
          r'diff --name-only "$TRUNK"...HEAD -- "$@"',
        ),
        isNot(-1),
      );
      expect(
        File('tool/lane.sh').readAsStringSync(),
        isNot(contains(r'diff --name-only "$TRUNK" HEAD')),
      );
    });

    // 관제 2026-11-05 (i163-dropper-no-paper): a red architecture run with no
    // [E] line showed nothing, and its output was removed.
    test('a red gate keeps its whole output in the lane, and shows its tail '
        'when no test says [E]', () {
      final kept = at(
        gates,
        r'cp "$out/architecture" "$p/build/lane-architecture.log"',
      );
      expect(kept, isNot(-1));
      expect(at(gates, r'rm -rf "$out"'), greaterThan(kept));
      expect(
        at(gates, r'tail -20 "$p/build/lane-architecture.log"'),
        isNot(-1),
      );
    });

    // 관제 2026-11-05: the grid kernel's X3507 was red in release alone — a
    // debug build's wgpu compiles shaders with optimizations skipped.
    test('🚨the crate\'s tests run in release as well as debug', () {
      final crate = codeOf('cmd_crate');
      expect(at(crate, 'for profile in debug release; do'), isNot(-1));
      expect(
        at(crate, r'[ "$profile" = release ] && flag=--release'),
        isNot(-1),
      );
      expect(
        at(crate, r'test --locked --offline --workspace ${flag:+"$flag"}'),
        isNot(-1),
        reason: 'every crate of the workspace, not its default members — '
            'and offline: a download is the user\'s to allow (관제 '
            '2026-11-06)',
      );
    });

    // 관제 2026-11-07: told `cargo fetch --locked`, the Surface fetched 29
    // crates for Linux, the Mac and Android that nobody had allowed.
    test('🚨a crate not downloaded is named, and fetched, for this '
        'machine\'s platform alone', () {
      expect(
        at(
          codeOf('cmd_crate'),
          r'cargo fetch --locked --target $(host_triple))',
        ),
        isNot(-1),
      );
      final list = codeOf('crates_not_here');
      expect(at(list, r'bash "$ROOT/tool/run.sh" crates_for_host'), isNot(-1));
      expect(
        at(list, 'cargo metadata --locked --offline --no-deps'),
        isNot(-1),
        reason: 'the members\' manifests, read without opening a crate',
      );
    });

    test('🚨are run from ONE place: the gate command runs nothing in the '
        'lane by itself, and the land only the crate\'s tests', () {
      for (final command in ['cmd_land', 'cmd_gate']) {
        expect(
          at(codeOf(command), r'gates "$name" "$p"'),
          isNot(-1),
          reason: '$command runs them through the one function',
        );
      }
      expect(runsIn(codeOf('cmd_gate')), isEmpty);
      final land = codeOf('cmd_land');
      expect(
        [for (final i in runsIn(land)) land[i].trim()],
        [r'crate_gate "$name" "$p"'],
        reason: 'a stamped land runs refusal 8 — the same function the '
            'gates run it through',
      );
    });

    // 2026-10-08 (card a-sent-lane-is-gated-once): the script measured
    // nothing and lowered nothing — every session wrapped it in a waiter of
    // its own, so a land waited for one of the four places like any run.
    test('🚨ask the machine for room before anything runs in the lane — and '
        'this shell is lowered only after it has asked', () {
      final asks = at(gates, r'room_first "${3:-}"');
      final lowered = at(gates, 'at_idle');

      expect(asks, isNot(-1));
      expect(lowered, greaterThan(asks));
      expect(runsIn(gates).first, greaterThan(lowered));
    });

    test('a land asks for the headroom alone; a gate, for a place as '
        'well', () {
      expect(at(codeOf('cmd_land'), r'gates "$name" "$p" land'), isNot(-1));
      expect(at(codeOf('cmd_gate'), r'gates "$name" "$p" gate'), isNot(-1));

      final room = codeOf('room_first');
      expect(at(room, r'[ "$1" = land ] && flag=--land'), isNot(-1));
      expect(
        at(room, r'bash "$ROOT/tool/run.sh" flutter_room ${flag:+"$flag"}'),
        isNot(-1),
      );
    });

    test('⛔a room that cannot be measured launches nothing: 「no room」 is '
        'the only answer that waits', () {
      final room = codeOf('room_first');
      final refused = at(room, r'[ "$rc" -eq 1 ] || die');

      expect(refused, isNot(-1));
      expect(at(room, 'sleep 20'), greaterThan(refused));
    });

    test('a land that waits for room keeps its turn its own', () {
      final room = codeOf('room_first');

      expect(at(room, r'[ -z "$HELD_TURN" ] || touch "$HELD_TURN"'), isNot(-1));
      expect(at(codeOf('land_turn'), r'HELD_TURN="$turn"'), isNot(-1));
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

    test('🚨a stamped land still runs the crate\'s tests HERE, and asks '
        'again of its commit before the merge', () {
      // 관제 2026-11-05: surface11/fx-line-box pinned a ledger row on the
      // Surface's GPU and landed on its stamp, this machine's never asked.
      final stamped = at(land, r'if [ "$(gated_at "$name")" = "$head" ] \');
      final otherwise = land.indexWhere((line) => line.trim() == 'else');
      final crate = at(land, r'crate_gate "$name" "$p"');
      expect(crate, inExclusiveRange(stamped, otherwise));
      expect(
        at(land, r'unmoved_since "$p" "$head" land'),
        inExclusiveRange(crate, otherwise),
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

    test('⛔is no branch: it is kept beside the branches, where no pattern '
        'of lanes — `backup`, `list`, the mirror\'s copies — can take it '
        'for one', () {
      final script = File('tool/lane.sh').readAsStringSync();
      final kept = RegExp(
        r'^gate_ref\(\) \{ echo "(refs/[^"]+)/\$1"; \}$',
        multiLine: true,
      ).firstMatch(script.replaceAll('\r\n', '\n'));
      expect(kept, isNotNull, reason: 'LIVENESS — the stamp has one home');
      expect(kept!.group(1), isNot(startsWith('refs/heads')));
      expect(kept.group(1), isNot(startsWith('refs/tags')));
    });

    test('goes when its lane does: a lane that landed, and a lane that was '
        'dropped, leave no stamp for a later lane of that name', () {
      const gone = r'update-ref -d "$(gate_ref "$name")"';
      final land = codeOf('cmd_land');
      expect(at(land, gone), greaterThan(at(land, 'merge --ff-only')));
      expect(at(codeOf('cmd_drop'), gone), isNot(-1));
    });

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
