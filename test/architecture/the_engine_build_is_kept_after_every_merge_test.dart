import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 🚨THE ENGINE BUILD IS KEPT ON EVERY MASTER PUSH, `again` OR NOT.
///
/// The Linux shards start from the engine build ci.yml's engine-target job
/// keeps (card ci-shards-build-the-engine-cold, 2026-11-17), and only a
/// master push can keep one every later run reads — a pull request's cache
/// is its own. A master push whose tree a pull request already tested sets
/// the scope's `again` and stands the test jobs down; were engine-target to
/// stand down with them, a bundle merge — the master push there is — would
/// keep nothing, and the shards would build cold for ever (관제 asked
/// for this pin that day).
void main() {
  test('engine-target runs on a master push whatever `again` says', () {
    final lines = File('.github/workflows/ci.yml').readAsLinesSync();
    final start = lines.indexOf('  engine-target:');
    expect(start, isNot(-1), reason: 'LIVENESS — the job is in ci.yml');
    final job = lines
        .skip(start + 1)
        .takeWhile((line) => !RegExp(r'^  [\w-]+:\s*$').hasMatch(line))
        .toList();
    final condition = job.firstWhere(
      (line) => line.startsWith('    if:'),
      orElse: () => '',
    );
    expect(condition, contains("github.event_name == 'push'"));
    expect(condition, isNot(contains('again')));
    expect(job.join('\n'), contains('target: keep'));
    expect(
      RegExp('target: keep').allMatches(lines.join('\n')),
      hasLength(1),
      reason: 'one writer — it is the one job that keeps the folder',
    );
  });
}
