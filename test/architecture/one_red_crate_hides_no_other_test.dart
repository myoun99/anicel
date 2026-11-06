import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 🚨ONE RED CRATE HIDES NO OTHER (관제 2026-11-07, gpu-engine-skeleton).
///
/// The first run of the GPU engine's hand-dispatched CI (42274856506)
/// stopped the macOS and Linux jobs at a pin of the first crate, `audio`,
/// and not one GPU kernel test ran: cargo stops at the first test binary
/// that fails, and a step that fails skips every step after it. So every
/// crate test runs --no-fail-fast, the GPU kernels (the root crate) and the
/// native crates are a step each, in each profile, and each such step runs
/// once the toolchain is in place, whatever the step before it said.
void main() {
  const workflow = '.github/workflows/gpu-engine.yml';
  final lines = File(workflow).readAsLinesSync();
  final runs = [
    for (var i = 0; i < lines.length; i++)
      if (!lines[i].trim().startsWith('#') &&
          lines[i].contains('cargo test'))
        i,
  ];

  test('every crate test runs past a red one', () {
    expect(runs, isNotEmpty, reason: workflow);
    for (final at in runs) {
      expect(lines[at], contains('--no-fail-fast'), reason: lines[at]);
    }
  });

  test('the GPU kernels and the native crates are a step each, in debug and '
      'in release, in every job', () {
    final jobs = lines
        .skip(lines.indexOf('jobs:'))
        .where(RegExp(r'^  [\w-]+:$').hasMatch)
        .length;
    expect(jobs, greaterThan(0), reason: workflow);
    final steps = [
      for (final at in runs)
        lines[at].replaceFirst(RegExp(r'^\s*run: cargo test --locked '), ''),
    ];
    const kernels = '--no-fail-fast -p gpu_engine';
    const native = '--no-fail-fast --workspace --exclude gpu_engine';
    for (final step in [
      kernels,
      native,
      '$kernels --release',
      '$native --release',
    ]) {
      expect(steps.where((s) => s == step), hasLength(jobs), reason: step);
    }
    expect(steps, hasLength(4 * jobs));
  });

  test('each runs whatever the step before it said, once the toolchain is '
      'in place', () {
    for (final at in runs) {
      expect(
        lines[at - 1].trim(),
        "if: \${{ !cancelled() && steps.toolchain.outcome == 'success' }}",
        reason: lines[at],
      );
    }
    expect(
      lines.where((line) => line.trim() == '- id: toolchain'),
      isNotEmpty,
    );
  });

  test('and the root crate is the GPU kernels: the native crates are the '
      'rest of the workspace', () {
    final manifest =
        File('packages/gpu_engine/rust/Cargo.toml').readAsStringSync();
    expect(manifest, contains('name = "gpu_engine"'));
    expect(manifest, contains('members = ["native/*"]'));
  });
}
