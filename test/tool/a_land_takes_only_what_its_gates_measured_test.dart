import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../helpers/dart_sources.dart';
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
  /// inside it, and the GPU engine crate's tests.
  List<int> runsIn(List<String> code) => [
    for (var i = 0; i < code.length; i++)
      if (code[i].contains(r'(cd "$p" &&') ||
          code[i].contains('cmd_crate') ||
          code[i].contains('crate_gate'))
        i,
  ];

  group('the gates', () {
    // Late, so the LIVENESS expect in `codeOf` runs inside a test.
    late final gates = codeOf('gates');

    test('LIVENESS — analyze with no arguments, the architecture tests, '
        'and the crate\'s tests of a lane that touched the crate, its '
        'ledger or the fx SDK', () {
      final all = gates.join('\n');
      // Offline (관제 2026-11-06): what the lane resolved from this
      // machine's pub cache, and neither gate resolves it again.
      expect(all, contains(r'resolve_offline "$p" 3'));
      expect(all, contains(r'(cd "$p" && flutter analyze --no-pub)'));
      expect(
        all,
        contains(r'(cd "$p" && flutter test --no-pub test/architecture)'),
      );
      expect(all, contains(r'crate_gate "$name" "$p"'));
      final crate = codeOf('crate_gate').join('\n');
      expect(crate, contains(r'lane_touched "$p" "${CRATE_INPUTS[@]}"; then'));
      expect(
        File('tool/lane.sh').readAsStringSync(),
        contains('CRATE_INPUTS=(packages/gpu_engine/rust sdk/fx test/fixtures'),
        reason: 'the crate, the fx SDK, and the ledger with what else the '
            'tests read from outside the crate',
      );
      expect(
        codeOf('crate_input').join('\n'),
        contains(r'for path in "${CRATE_INPUTS[@]}"; do'),
        reason: 'what makes a lane pay is what a green is kept for — one '
            'list (관제 2026-11-14)',
      );
      expect(crate, contains(r'cmd_crate "$name"'));
    });

    // 관제 2026-11-13 (what-still-runs-on-the-cpu): the C engine went, and
    // refusals 5 and 6 with it — once the lane that deleted it had landed,
    // the script was to say nothing of a C engine.
    // ↩️It built one for every lane that touched the C and ran the parity
    // list against it (refusal 5), asked of every engine it handed out
    // whether it was built from the C beside it (refusal 6), and held the
    // crates' tests to the lane's own (native-to-rust, 관제 2026-11-06 — a
    // key built from other C held them to the wrong answers).
    test('⛔nothing in the script builds a C engine, copies one or asks of '
        'one', () {
      final code = [
        for (final line
            in File('tool/lane.sh')
                .readAsStringSync()
                .replaceAll('\r\n', '\n')
                .split('\n'))
          if (!line.trimLeft().startsWith('#')) line,
      ].join('\n');
      expect(
        code,
        contains(r'crate) shift; cmd_crate "$@" ;;'),
        reason: 'LIVENESS — the code is read, its dispatch too',
      );
      for (final gone in [
        'qa_native',
        'cmake',
        'native_standalone',
        'native_engine_provenance',
        'native_parity_tests',
        'QA_REQUIRE_NATIVE',
        'cmd_native',
        'cmd_engine',
      ]) {
        expect(code, isNot(contains(gone)), reason: gone);
      }
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
        at(crate, r'for profile in $todo; do'),
        greaterThan(at(crate, 'for profile in debug release; do')),
        reason: 'each is asked, and whichever this machine has not seen '
            'green with the same input runs',
      );
      expect(
        at(crate, r'[ "$profile" = release ] && flag=--release'),
        isNot(-1),
      );
      expect(
        at(
          crate,
          'test --locked --offline --no-fail-fast --workspace '
          r'${flag:+"$flag"}',
        ),
        isNot(-1),
        reason: 'every crate of the workspace, not its default members — '
            'offline: a download is the user\'s to allow (관제 2026-11-06) '
            '— and past a red one, as the CI runs them (관제 2026-11-07)',
      );
      expect(
        at(crate, r'red="$red $profile"'),
        lessThan(at(crate, 'tests are red in')),
        reason: 'release runs after a red debug, and the refusal names both',
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

    test('a land keeps its turn its own while it moves on and while it '
        'waits — a turn taken for its age is a hung land\'s, never a long '
        'one\'s', () {
      // ↩️관제 2026-11-11 (a-long-land-loses-its-turn-at-45-minutes): the
      // turn was stamped once, when it was taken. A land that touched the
      // crate ran its gates for 48 minutes, the next land took its turn at
      // 45, and that land's fast-forward was refused.
      final alive = codeOf('still_landing');
      final touched = at(alive, r'touch -c "$HELD_TURN"');
      expect(
        touched,
        isNot(-1),
        reason: '-c: a turn that is gone is not made again, as a file',
      );
      // 🚨관제 2026-11-12, same card: a land whose turn was taken over ran its
      // gates on beside the land that took it, to be refused at the
      // fast-forward — it stops at its next step instead.
      final ownsIt = at(
        alive,
        r'[ "$(cat "$HELD_TURN/pid" 2>/dev/null)" = "$$" ] || die',
      );
      expect(
        ownsIt,
        isNot(-1),
        reason: 'a land asks whether the turn is still its own',
      );
      expect(touched, greaterThan(ownsIt), reason: 'before it stamps it');
      final taking = codeOf('land_turn');
      expect(at(taking, r'HELD_TURN="$turn"'), isNot(-1));
      expect(at(taking, r'export LANE_LAND_TURN="$turn"'), isNot(-1));

      List<int> refreshes(List<String> code) => [
        for (var i = 0; i < code.length; i++)
          if (code[i].trim() == 'still_landing') i,
      ];
      bool between(List<String> code, int after, int before) =>
          refreshes(code).any((i) => i > after && i < before);

      final room = codeOf('room_first');
      expect(
        between(room, at(room, 'until seen='), at(room, 'sleep 20')),
        isTrue,
        reason: 'waiting for room',
      );

      final gates = codeOf('gates');
      final crate = at(gates, 'crate_gate');
      expect(crate, isNot(-1));
      expect(
        between(gates, at(gates, r'wait "$architecture"'), crate),
        isTrue,
        reason: 'before the crate',
      );

      // ↩️관제 2026-11-12, same card: `tile-blocks-on-rust`'s native gate
      // alone ran 61 minutes, stamped before and after it only — so it
      // stamped between its steps, and its parity run wrote a beat inside
      // the turn at every batch, till the gate went with the C engine
      // (2026-11-13).
      final crateRun = codeOf('cmd_crate');
      expect(
        between(
          crateRun,
          at(crateRun, r'for profile in $todo; do'),
          at(crateRun, 'test --locked --offline --no-fail-fast'),
        ),
        isTrue,
        reason: 'before each of debug and release that runs',
      );

      // While the crate's run waits for the shared target, in the script
      // the land runs.
      final cargo = File('tool/cargo_turn.sh')
          .readAsStringSync()
          .replaceAll('\r\n', '\n')
          .split('\n');
      final waits = cargo.indexWhere(
        (l) => l.startsWith('until ') && l.contains(r'mkdir "$TURN"'),
      );
      final kept = cargo.indexWhere(
        (l) => l.contains(r'[ -z "$LANE_LAND_TURN" ] || touch -c'),
      );
      final sleeps = cargo.indexWhere((l) => l.trim() == 'sleep 5');
      expect(waits, isNot(-1));
      expect(kept, greaterThan(waits));
      expect(sleeps, greaterThan(kept));
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
      // 🚨관제 2026-11-14 (a-land-takes-its-turn-before-one-that-waited): a
      // land that came later took the turn before one that had waited for
      // sixteen minutes — only the oldest ticket in the line tries it.
      final taken = taking.indexWhere(
        (l) =>
            l.trimLeft().startsWith('until ') &&
            l.contains(r'first_in_line "$line"') &&
            l.contains(r'mkdir "$turn"'),
      );
      // The ticket's own trap comes first; the turn's replaces it.
      final handedBack = taking.lastIndexWhere((l) => l.contains('trap '));
      expect(taken, isNot(-1));
      expect(handedBack, greaterThan(taken));
      expect(taking[handedBack], contains('EXIT'));
      // ↩️관제 2026-11-12 (브러시/렌더링's reading, then seen at 21:13): it
      // was `rm -rf` whoever held it — a land that had lost its turn,
      // ending, removed the turn of the land that held it then.
      expect(taking[handedBack], contains('give_turn_back'));
      final giving = codeOf('give_turn_back');
      final asked = at(
        giving,
        r'if [ "$(cat "$1/pid" 2>/dev/null)" = "$$" ]; then',
      );
      expect(asked, isNot(-1), reason: 'only while it is still this land\'s');
      expect(at(giving, r'rm -rf "$1"'), greaterThan(asked));
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
      // ↩️It was the turn's own age (`-maxdepth 0 -mmin +45`); a test run
      // under the land beats inside it, so its age is its newest sign of life
      // (관제 2026-11-12).
      expect(
        all,
        contains(r'[ -z "$(find "$turn" -mmin -45 2>/dev/null)" ]'),
        reason: 'and so is a hung one\'s: nothing in it moved for 45 minutes',
      );
      expect(
        all,
        contains(r'if [ -d "$turn" ] && '),
        reason: 'a turn nobody holds has no age — a land behind another in '
            'the line waits for it, and does not spin',
      );
    });

    test('⚠️keeps the same line as the shared target\'s turn — two places, '
        'not three', () {
      final cargo = LaneScript(File('tool/cargo_turn.sh').readAsStringSync());
      expect(codeOf('first_in_line'), cargo.codeOf('first_in_line'));
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

  // 관제 2026-11-14, a-land-runs-the-crate-tests-the-lane-already-passed-here:
  // a profile green here with the same input is not run again, so the input
  // has to be all the crate's tests read — they read a movie, the fonts and
  // two Dart files from outside the crate's tree — and a lane that changed
  // one pays refusal 8: one list for both.
  test('⛔what the crate\'s tests read outside its tree is all in what they '
      'answer to, and nothing else is', () {
    final kept = RegExp(r'^CRATE_INPUTS=\(([^)]*)\)', multiLine: true)
        .firstMatch(File('tool/lane.sh').readAsStringSync())![1]!
        .split(RegExp(r'\s+'))
        .where((word) => word.isNotEmpty)
        .toList();
    final read = <String>{};
    for (final file in _rustSources('packages/gpu_engine/rust')) {
      final crate = _crateOf(file.parent);
      for (final line in file.readAsLinesSync()) {
        if (line.trimLeft().startsWith('//')) continue;
        for (final literal in _climbingLiteral.allMatches(line)) {
          final placeholder = RegExp(r'^\{([^}]*)\}/').firstMatch(literal[2]!);
          // `{checkout}` is .cargo/config.toml's QA_CHECKOUT: the workspace's
          // folder, which the ledger reads from at any crate's depth.
          final base = literal[1] != null
              ? file.parent.path
              : placeholder?[1] == 'checkout'
              ? 'packages/gpu_engine/rust'
              : crate.path;
          final path = _resolved(
            base,
            literal[2]!.substring(placeholder?.end ?? 0),
          );
          if (!path.startsWith('packages/gpu_engine/rust/')) read.add(path);
        }
      }
    }
    expect(read, contains('lib/src/native/qa_tablet_bridge.dart'));
    expect(
      [
        for (final path in read)
          if (!kept.any((k) => path == k || path.startsWith('$k/'))) path,
      ],
      isEmpty,
      reason: 'a green would answer for a file it was not measured on',
    );
    expect(
      [
        for (final k in kept)
          if (k != 'packages/gpu_engine/rust' &&
              !read.any((path) => path == k || path.startsWith('$k/')))
            k,
      ],
      isEmpty,
      reason: 'a file no test reads any more is no input',
    );
  });
}

/// A string literal that climbs a folder — an `include!`'s or a module's
/// `#[path]` (group 1) from the source file's own folder, any other from its
/// crate's.
final _climbingLiteral = RegExp(
  r'(include(?:_str|_bytes)?!\(\s*|#\[path\s*=\s*)?"([^"\n]*\.\./[^"\n]*)"',
);

/// The Rust sources and manifests of the workspace at [root], past the
/// build folders at its top (`target`, `target-hook`) — millions of files
/// no source is among.
Iterable<File> _rustSources(String root) => [
  for (final entity in Directory(root).listSync())
    if (entity is File)
      entity
    else if (!entity.uri.pathSegments
        .lastWhere((s) => s.isNotEmpty)
        .startsWith('target'))
      ...filesUnder(entity.path),
].where((file) => file.path.endsWith('.rs') || file.path.endsWith('Cargo.toml'));

/// The folder of the crate [folder] is in: the nearest with a manifest.
Directory _crateOf(Directory folder) =>
    File('${folder.path}/Cargo.toml').existsSync()
    ? folder
    : _crateOf(folder.parent);

/// [relative] from [base], as a path from the repository's root.
String _resolved(String base, String relative) {
  final parts = <String>[];
  for (final part in '$base/$relative'.replaceAll(r'\', '/').split('/')) {
    if (part == '..') {
      parts.removeLast();
    } else if (part.isNotEmpty && part != '.') {
      parts.add(part);
    }
  }
  return parts.join('/');
}
