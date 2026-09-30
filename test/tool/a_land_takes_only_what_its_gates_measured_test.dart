import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 🚨lane-land-edited-under-its-gates (2026-09-30): while a land sat in
/// `flutter analyze`, its author fixed the red architecture test in the
/// lane, uncommitted. The gates read the working tree and passed; the merge
/// takes commits only, so master got them without the fix, and the forced
/// worktree removal destroyed it (66e598ba4, repaired by 6ab4facd1).
/// Refusal 7 asks again after the last gate: is HEAD still the commit the
/// rebase made, and does the tree hold exactly that.
///
/// ⚠️These pin WHERE the land asks, not what it does next — the suite spawns
/// no process (tests_do_not_race_the_code_test). What it does was run by
/// hand in a scratch repo, with a `flutter` that edited, committed or added
/// a file during analyze: all three refused, and the script before this
/// change landed all three. A `flutter` that rewrote a registrant, as the
/// build hooks do, landed.
void main() {
  final script = File('tool/lane.sh').readAsStringSync().replaceAll(
    '\r\n',
    '\n',
  );

  // The second copy of a_land_never_waits_for_a_login_test's `body`, kept
  // apart by the rule of three: the third test that cuts a function out of
  // lane.sh merges them.
  List<String> codeOf(String function) {
    final start = script.indexOf('\n$function() {');
    expect(start, isNot(-1), reason: 'LIVENESS — $function is in the script');
    return [
      for (final line in script
          .substring(start, script.indexOf('\n}\n', start))
          .split('\n'))
        line.trimLeft().startsWith('#') ? '' : line,
    ];
  }

  // Late, so the LIVENESS expect in `codeOf` runs inside a test.
  late final land = codeOf('cmd_land');
  int first(String text) => land.indexWhere((line) => line.contains(text));
  int last(String text) => land.lastIndexWhere((line) => line.contains(text));
  late final rebase = first(r'rebase "$TRUNK"');
  late final merge = first('merge --ff-only');
  // A gate is whatever runs in the lane: flutter from inside it, and the
  // native build and tests.
  late final gates = [
    for (var i = 0; i < land.length; i++)
      if (land[i].contains(r'(cd "$p" &&') || land[i].contains('cmd_native'))
        i,
  ];

  test('LIVENESS — the land rebases, runs its gates, then merges', () {
    expect(rebase, isNot(-1));
    expect(gates, isNotEmpty);
    expect(merge, isNot(-1));
  });

  test('the commit the gates measure is read after the rebase, before '
      'the first gate', () {
    expect(
      first(r'measured="$(git -C "$p" rev-parse HEAD)"'),
      inExclusiveRange(rebase, gates.first),
    );
  });

  test('after the last gate and before the merge, HEAD is read again and '
      'must still be that commit', () {
    final read = first(r'now="$(git -C "$p" rev-parse HEAD)"');
    final compared = first(r'[ "$now" = "$measured" ] || die');
    expect(read, inExclusiveRange(gates.last, merge));
    expect(compared, inExclusiveRange(read, merge));
  });

  test('after the last gate and before the merge, the tree must be clean — '
      'through the same check that ran before the rebase', () {
    final asked = [
      for (var i = 0; i < land.length; i++)
        if (land[i].contains(r'lane_is_clean "$p" || die')) i,
    ];
    expect(asked, isNotEmpty);
    expect(asked.first, lessThan(rebase), reason: 'before the rebase');
    expect(asked.last, inExclusiveRange(gates.last, merge));
    expect(
      last('status --short'),
      -1,
      reason: 'a second, inline clean check is a copy that can drift from '
          'lane_is_clean',
    );
  });

  test('the check puts the platform folders back and refreshes the stat '
      'cache before it reads the status', () {
    final check = codeOf('lane_is_clean');
    int at(String text) => check.indexWhere((line) => line.contains(text));
    final status = at('status --short');
    expect(status, isNot(-1));
    final before = inExclusiveRange(-1, status);
    expect(at('checkout -- linux macos windows'), before);
    expect(at('update-index -q --really-refresh'), before);
  });
}
