@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../helpers/lane_script.dart';

/// 관제 2026-11-20 (card folders-still-appear-at-the-top-of-temp-on-the-main-
/// pc): 공통 dropped lane-measure-grid-on-the-engine, whose worktree held
/// work/measure-grid-box, and `drop` deleted the branch of the NAME —
/// work/measure-grid-on-the-engine, 31 commits on neither master nor a
/// keep/ branch.
///
/// 🧪Run by hand in a scratch clone (11-20): a worktree `lane-a` holding
/// `work/b`, beside a branch `work/a` — the old script deleted `work/a` and
/// left `work/b` with nobody's worktree; this one deletes `work/b` and
/// leaves `work/a`. `lane-c` holding `keep/x` was refused, worktree and
/// all; a detached `lane-d` took `work/d` as before.
void main() {
  // Late, so the LIVENESS expect in `codeOf` runs inside a test.
  late final drop = LaneScript(
    File('tool/lane.sh').readAsStringSync(),
  ).codeOf('cmd_drop');
  int at(String text) => drop.indexWhere((line) => line.contains(text));

  test('🚨the branch that goes is the one its worktree holds — not the '
      "name's", () {
    final asked = at(
      r'held="$(git -C "$p" symbolic-ref --quiet --short HEAD',
    );
    final taken = at(r'work/*) branch="$held" ;;');
    final deleted = at(r'branch -D "$branch"');
    expect([asked, taken, deleted], everyElement(isNot(-1)));
    expect(asked, lessThan(taken));
    expect(taken, lessThan(deleted));
    expect(at(r'branch -D "work/$name"'), -1);
  });

  test("a worktree that holds a branch no lane's is refused before anything "
      'goes', () {
    final refused = at("which is no lane's branch — nothing dropped");
    expect(refused, isNot(-1));
    expect(drop[refused], contains('*) die '));
    expect(refused, lessThan(at(r'rm -rf "$p"')));
  });

  test("one that holds no branch — a check's, moved by commit — leaves the "
      "name's", () {
    expect(at(r'local branch="work/$name" held='), isNot(-1));
    expect(at("    '') ;;"), isNot(-1));
  });
}
