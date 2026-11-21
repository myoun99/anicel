import 'package:flutter_test/flutter_test.dart';

import '../helpers/dart_sources.dart';
import '../helpers/workflow_jobs.dart';

/// 🗣️A WINDOWS RUNNER RUNS NO LIST OF TESTS THAT REACH THE GPU ENGINE
/// (유저 gpu-engine-skeleton-Q16, 2026-11-07 「윈도 샤드는 엔진에 닿는 시험을
/// 리눅스에 맡긴다」 · Q9 「ARM 은 빌드와 CPU 크레이트 시험만 — 다른 잡
/// 급으로」): a Windows runner has no GPU, and WARP, the device the engine
/// opens on one, never finishes the engine's optimised shaders.
///
/// The law was one job's input till the C engine went (2026-11-13). Then
/// the ARM64 release's parity list became the tests that name
/// `src/native/`, which open the GPU engine, and no round got past it: in
/// round 1095 its 290 files waited past 30 s 129 times on `Microsoft Basic
/// Render Driver`, and the 28 red files all reached package:gpu_engine
/// (card the-windows-arm64-build-stops-at-its-engine-tests, 2026-11-21).
/// So every list a Windows job runs is held here, each by the one answer
/// to which tests reach the package (tool/tests_reaching_package.dart):
/// the shards' deal by the action's input, the parity list by that tool.
void main() {
  test('every list of tests a Windows job runs leaves out what reaches '
      'package:gpu_engine', () {
    final held = <String>[];
    for (final file in filesUnder('.github/workflows')) {
      if (!file.path.endsWith('.yml')) continue;
      final path = file.path.replaceAll(r'\', '/');
      for (final MapEntry(key: id, value: job)
          in jobsOf(file.readAsLinesSync()).entries) {
        if (!job.contains('runs-on: windows')) continue;
        if (job.contains('uses: ./.github/actions/test-shard')) {
          held.add('$path:$id');
          expect(
            job,
            contains('leave-out-package: gpu_engine'),
            reason: '$path:$id deals the suite to a Windows runner',
          );
        }
        if (job.contains('bash tool/native_parity_tests.sh')) {
          held.add('$path:$id');
          expect(
            job,
            contains('dart tool/tests_reaching_package.dart gpu_engine'),
            reason: '$path:$id runs the parity list on a Windows runner',
          );
          expect(
            job,
            contains(
              r'grep -vxFf "$RUNNER_TEMP/left_out.txt" '
              r'"$RUNNER_TEMP/engine.txt"',
            ),
            reason: '$path:$id leaves them out of the list it runs',
          );
        }
      }
    }
    // LIVENESS — the scan reaches every Windows job that runs a list.
    expect(held..sort(), [
      '.github/workflows/ci.yml:windows',
      '.github/workflows/windows-arm64-release.yml:bundle',
    ]);
  });
}
