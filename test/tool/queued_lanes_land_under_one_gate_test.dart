import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../helpers/lane_script.dart';

/// 🧺A BUNDLE (card queued-lanes-land-under-one-gate, 관제 2026-11-17 for
/// 유저 「할수있는거 최대한하자」): `lane.sh land <a> <b> …` stacks the lanes
/// queued together and runs the gates once, on the top; red, it halves the
/// stack down to the first red lane, lands the lanes before it and bundles
/// the rest again without it. What it DOES is run by hand in scratch
/// repositories (tool/lane_test.sh, 「1 A BUNDLE」); this holds each step in
/// its place, as the single land's are held.
void main() {
  final script = LaneScript(File('tool/lane.sh').readAsStringSync());
  int at(List<String> code, String text) =>
      code.indexWhere((line) => line.contains(text));

  test('more than one name goes to the bundle — after the turn and every '
      'lane\'s clean tree, before anything is rebased', () {
    final land = script.codeOf('cmd_land');
    final bundled = at(land, r'land_bundle "${names[@]}"');
    expect(bundled, isNot(-1));
    expect(bundled, greaterThan(at(land, 'land_turn')));
    expect(bundled, greaterThan(at(land, r'lane_is_clean "$p" || die')));
    expect(bundled, lessThan(at(land, r'rebase "$TRUNK"')));
  });

  test('🚨a lane is stacked by its own commits alone — and one that does '
      'not rebase is put back as it was before it leaves the bundle', () {
    // Its own: a lane after a refused one sits on that one's commits, and a
    // plain rebase would carry them along into master.
    final stack = script.codeOf('stack_bundle');
    final rebased = at(stack, r'rebase --onto "$base" "${BELOW[$i]}"');
    final aborted = at(stack, 'rebase --abort');
    final putBack = at(stack, r'reset -q --hard "${ORIG[$i]}"');
    final out = at(stack, r'LEFT_OUT+=("$name")');
    expect([rebased, aborted, putBack, out], everyElement(isNot(-1)));
    expect(aborted, greaterThan(rebased));
    expect(putBack, greaterThan(aborted));
    expect(out, greaterThan(putBack));
    expect(at(stack, r'require_worktree "$p"'), lessThan(rebased));
  });

  // 🐞관제 2026-11-18 03:35: the pan keys were sent stacked on the name tag
  // fold, and measured from the fork they laid the fold's commits again on
  // its copies — left out of the bundle, and in conflict alone after it.
  test('🚨a lone land and a bundle ask one place where a lane\'s own commits '
      'start — past a lane it was sent stacked on', () {
    final land = script.codeOf('cmd_land');
    final asked = at(land, r'below="$(own_base "work/$name")"');
    expect(asked, isNot(-1));
    expect(asked, lessThan(at(land, r'rebase --onto "$TRUNK" "$below"')));
    final bundle = script.codeOf('land_bundle');
    expect(at(bundle, r'own_base "work/$name" ${ORIG[@]+"${ORIG[@]}"}'),
        isNot(-1),
        reason: 'the lanes before it in the bundle, as they were sent');
    expect(at(bundle, r'merge-base "$TRUNK"'), -1,
        reason: 'the fork is own_base\'s first answer, not a second copy');
    final base = script.codeOf('own_base');
    final stacked = at(base, r'merge-base --is-ancestor "$c" "$lane"');
    final copies = at(base, "--format='%at %ae %s'");
    expect([stacked, copies], everyElement(isNot(-1)));
    expect(copies, greaterThan(stacked),
        reason: 'copies are looked for past the nearest lane it holds');
  });

  test('a stack is measured by the land\'s own gates, and only a gate\'s own '
      'refusal reads as red — one that could not run stops the land', () {
    final green = script.codeOf('stack_is_green');
    final gated = at(green, r'( gates "$name" "$p" land )');
    final alive = green.indexWhere((line) => line.trim() == 'still_landing');
    final stops = at(green, 'die "the gates could not run');
    expect([gated, alive, stops], everyElement(isNot(-1)));
    expect(alive, greaterThan(gated), reason: 'a turn taken over stops it');
    expect(stops, greaterThan(alive));
  });

  test('the first red lane is found by halving, past the last green', () {
    final halving = script.codeOf('first_red');
    expect(
      at(halving, r'if stack_is_green "$mid"; then lo=$(( mid + 1 )); '
          r'else hi=$mid; fi'),
      isNot(-1),
    );
  });

  test('🚨what lands was measured: refusal 7 for every lane of the stack, '
      'then master, then each leaves as a land\'s lane does', () {
    final landing = script.codeOf('land_stack');
    final asked = at(landing, r'unmoved_since "$(lane_path "${BUNDLE[$i]}")"');
    final merged = at(landing, r'merge --ff-only "work/${BUNDLE[$1]}"');
    final left = at(landing, 'lanes_landed "\${BUNDLE[@]:0:');
    expect([asked, merged, left], everyElement(isNot(-1)));
    expect(merged, greaterThan(asked));
    expect(left, greaterThan(merged));
  });
}
