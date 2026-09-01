@TestOn('vm')
library;

import 'package:flutter_test/flutter_test.dart';

import '../../tool/code_map.dart';
import 'complexity_baseline.dart';

/// 🚨★★★A FUNCTION FORKS SIX WAYS AT MOST.
///
/// 유저 (2026-09-02): 「내가 이상적으로 생각하는건 **사람은 3이고 AI는 6**이야.
/// 그래서 6으로 하고싶은거고」. The earlier line in CLAUDE.md — 「복잡도 상한
/// 숫자를 미리 정하지 않는다」 — was negotiated with an AI and was never the
/// user's; it is reversed, and `reversed-decisions.md` says so.
///
/// ## Why a ratchet and not a wall
///
/// 🧪Measured the day this was written: 10,515 functions, **1,222 of them
/// above 6** (11.6%). A wall would turn every PR red for reasons the PR did
/// not cause, and a gate nobody can pass is a gate somebody switches off —
/// CLAUDE.md: 「넷을 한 번에 켜려 하면 마지막 하나가 나머지를 영영 막는다」.
///
/// So the debt is on a list, and three things are true of it from today:
///   1. A function NOT on the list may not exceed 6. New code obeys the rule.
///   2. A listed function that comes down to 6 (or goes away) must leave the
///      list — a stale entry FAILS. The list cannot keep paid debt.
///   3. The count is written down, so a PR that adds three and excuses three
///      still shows a number moving the wrong way.
/// That is exactly the shape `layer_dependency_direction_test` graduated
/// with, and `app_shapes_coverage_test` before it (84 → 74 → 51 → 32 → 0).
///
/// ## ⛔What this must not become
///
/// A score to chase. CLAUDE.md keeps the warning that a number invites
/// 「점수만 낮추고 이해도는 떨어지는 분할」, and the audit met it on day one:
/// extracting the timeline rail bare needed ELEVEN parameters. The answer was
/// not a smaller cut — it was that seven of them were one unnamed idea
/// (`_RowWindow`). **If the parameter list explodes, something has no name.**
/// A split that takes a function from 9 to 6 by handing its locals to a
/// helper has lowered the number and raised nothing.
///
/// ## Complexity, as this file counts it
///
/// McCabe over the AST: 1 + every `if`, loop, `case`, `catch`, `?:`, and
/// every `&&` `||` `??` — `tool/code_map.dart` is the one place it is
/// computed, and this reads that so the gate and the map cannot disagree.
/// A widget tree's `?:` count as forks, and that is right: each one is a
/// branch the reader has to hold.
///
/// ⚠️`test/architecture/` and not `test/tool/`: the pre-push hook treats
/// `test/tool/` as board-only.
void main() {
  const ceiling = 6;

  late CodeMap map;
  late Map<String, int> overCeiling;

  setUpAll(() {
    map = CodeMap.walk('lib');
    overCeiling = {
      for (final f in map.functions)
        if (f.complexity > ceiling) '${f.file}::${f.qualified}': f.complexity,
    };
  });

  test('the premise: the tree was read, and the ceiling bites something', () {
    // ⛔An empty walk passes every 「nothing exceeds」 assertion below. And a
    // ceiling nothing exceeds would mean the number, not the code, is wrong.
    expect(map.unreadable, isEmpty, reason: map.unreadable.toString());
    expect(map.functions.length, greaterThan(9000));
    expect(overCeiling, isNotEmpty);
  });

  test('no function outside the baseline forks more than six ways', () {
    final fresh = [
      for (final e in overCeiling.entries)
        if (!complexityBaseline.contains(e.key)) '${e.key}  (cx ${e.value})',
    ]..sort();
    expect(
      fresh,
      isEmpty,
      reason:
          'These functions exceed the ceiling of $ceiling and are not on the '
          'baseline. Split them along a seam that has a NAME — if the helper '
          'would need a long parameter list, the missing name is the finding, '
          'not the cut. Adding to `complexity_baseline.dart` is adding debt '
          'and needs an argument in the commit.\n  ${fresh.join('\n  ')}',
    );
  });

  test('the baseline holds no debt that was already paid', () {
    final paid = [
      for (final key in complexityBaseline)
        if (!overCeiling.containsKey(key)) key,
    ]..sort();
    expect(
      paid,
      isEmpty,
      reason:
          'These baseline entries no longer exceed the ceiling (or the '
          'function is gone). Delete the lines — a list that keeps paid debt '
          'stops being read. Going DOWN is the whole point; say so in the '
          'commit:\n  ${paid.join('\n  ')}',
    );
  });

  test('the baseline is the whole debt, counted', () {
    // The number lives here so the diff shows it moving. 1,222 on
    // 2026-09-02, the day the ratchet was switched on.
    expect(
      complexityBaseline.length,
      1220,
      reason:
          'The baseline count changed. Going DOWN is the point — update this '
          'number and say so in the commit. Going UP needs an argument.',
    );
  });

  test('the parity kernel is on the list and is not expected to leave', () {
    // ⚠️NOT an exemption from the rule — an expectation about the debt.
    // `resample_kernel.dart` carries a decision comment: the C kernel's
    // parity with this reference is 「expression identity, not value
    // identity」. Splitting its expressions changes what the parity pins
    // compare. It is the one entry on this list whose reason to stay is
    // written down, so nobody 「pays」 it by breaking the thing it guards.
    const kernel =
        'lib/src/services/resample/resample_kernel.dart::resampleRgbaReferenceInto';
    expect(complexityBaseline, contains(kernel));
    expect(overCeiling[kernel], greaterThan(100));
  });
}
