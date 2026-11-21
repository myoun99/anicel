@TestOn('vm')
library;

import 'package:flutter_test/flutter_test.dart';

import '../helpers/dart_sources.dart';

/// 🚨A test keeps a pool to the OS's budget only by a name that says so
/// (🗣️관제 2026-11-16, pool-tests-ride-the-os-vram-budget: 「OS 예산 자체를
/// 재는 시험이 아니면 시험이 쓰는 풀은 예산을 스스로 정한다 … 예산 자체를 보는
/// 시험만 OS 의 것을 쓴다고 이름으로 드러낼 것」). Every test's pool keeps to
/// none of the OS's (GpuPool.debugBudgetTillOneIsSet, set by the run —
/// a_test_pool_keeps_to_no_budget_but_its_own_test.dart reads it); a test
/// that sets the OS's back is seen here, by `OS` in its name. The crate's
/// own tests keep the same law by a scan of their own
/// (rust/src/kernels/shared/every_test_pool.rs).
void main() {
  test("a test keeps a pool to the OS's budget only by a name that says OS",
      () {
    final riders = [
      for (final file in dartFilesUnder('test'))
        ...testsKeepingToTheOsBudget(file.readAsStringSync()),
    ];

    expect(riders, isEmpty, reason: 'none does — one that does is named here');
    expect(namedWithoutOs(riders), isEmpty);
  });

  test('the scan sees a plant', () {
    final planted = [
      "test('a cel is stored', () => pool.$_instead(null));",
      "test('the OS line moves', () => ledger.$_osBudget(null));",
      "test('a page is made', () => pool.$_instead(0));",
      "test('the run is set', () => $_tillOneIsSet = null);",
    ].join('\n');

    expect(testsKeepingToTheOsBudget(planted), [
      "'a cel is stored'",
      "'the OS line moves'",
      "'the run is set'",
    ]);
    expect(namedWithoutOs(testsKeepingToTheOsBudget(planted)), [
      "'a cel is stored'",
      "'the run is set'",
    ]);
  });
}

/// The calls that set a pool, a ledger's or every one back to the OS's
/// budget — spelled apart, so the scan's own words are no test's.
const _instead = 'keepToInsteadOf' 'TheOs';
const _osBudget = 'debugKeepTo' 'OsBudget';
const _tillOneIsSet = 'GpuPool.debugBudget' 'TillOneIsSet';

/// The names of the tests in [text] that keep a pool to the OS's budget —
/// each test read to the next.
List<String> testsKeepingToTheOsBudget(String text) {
  bool rides(String body) =>
      body.contains('$_instead(null)') ||
      body.contains('$_osBudget(null)') ||
      body.contains('$_tillOneIsSet = null');
  return [
    for (final body in text.split(RegExp(r'\btest(?:Widgets)?\(')).skip(1))
      if (rides(body)) body.split(RegExp(r',\s*\(')).first.trim(),
  ];
}

/// Of [riders], those whose name does not say `OS`.
Iterable<String> namedWithoutOs(List<String> riders) =>
    riders.where((name) => !name.contains('OS'));
