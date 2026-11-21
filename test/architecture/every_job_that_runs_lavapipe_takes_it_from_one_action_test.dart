import 'package:flutter_test/flutter_test.dart';

import '../helpers/dart_sources.dart';
import '../helpers/workflow_jobs.dart';

const _action = '.github/actions/lavapipe/action.yml';

/// 🚨A JOB THAT RUNS THE ENGINE ON LAVAPIPE TAKES IT FROM ONE ACTION.
///
/// The engine's shown surface is exported as a dma-buf, and lavapipe — what
/// `mesa-vulkan-drivers` installs — offers the export only when llvmpipe
/// can open /dev/udmabuf, and makes none past udmabuf's limit on one
/// buffer. gpu-engine.yml's Linux job was lent the device on 2026-11-07;
/// ci.yml's Linux shards were not, and every test that opened a screen was
/// refused there: 150 red files on shard 1 of the bundle PR's run
/// 43591634086 (관제 2026-11-15, board
/// ci-linux-shards-cannot-make-a-shown-surface). Lent, the screens past
/// 64 MiB were still refused (run 43724112264, 2026-11-16).
/// ↩️Two copies of one step were held in step by this scan till a third job
/// needed them — linux-release.yml's engine tests, every one `no adapter`
/// (round 1091) — and the rule of three moved them into [_action]. So the
/// law is now that nothing else installs lavapipe: a job that wants it can
/// only have it lent and its limit raised.
void main() {
  test('only the lavapipe action installs mesa-vulkan-drivers', () {
    final byHand = <String>[];
    final taking = <String>[];
    for (final dir in ['.github/workflows', '.github/actions']) {
      for (final file in filesUnder(dir)) {
        if (!file.path.endsWith('.yml')) continue;
        final path = file.path.replaceAll(r'\', '/');
        if (path == _action) continue;
        final text = file.readAsStringSync();
        if (text.contains('mesa-vulkan-drivers')) byHand.add(path);
        for (final MapEntry(key: id, value: job)
            in jobsOf(file.readAsLinesSync()).entries) {
          if (job.contains('uses: ./.github/actions/lavapipe')) {
            taking.add('$path:$id');
          }
        }
      }
    }
    // LIVENESS — the scan reaches every job that runs the engine there.
    expect(
      taking,
      containsAll([
        '.github/workflows/ci.yml:analyze-and-test',
        '.github/workflows/gpu-engine.yml:linux',
        '.github/workflows/linux-release.yml:engine',
      ]),
    );
    expect(
      byHand,
      isEmpty,
      reason: 'take lavapipe from $_action, which lends it /dev/udmabuf',
    );
  });

  test('the action lends lavapipe /dev/udmabuf, past 64 MiB a buffer', () {
    final action = filesUnder('.github/actions/lavapipe')
        .singleWhere((f) => f.path.endsWith('action.yml'))
        .readAsStringSync();
    expect(action, contains('install -y mesa-vulkan-drivers'));
    expect(action, contains(r'sudo chown "$USER" /dev/udmabuf'));
    final limit = RegExp(
      r'echo (\d+) \| sudo tee /sys/module/udmabuf/parameters/size_limit_mb',
    ).firstMatch(action);
    expect(limit, isNotNull, reason: 'the limit on one buffer is raised');
    // A test at 1600 × 1000 opens its screen at 5120 × 3584, 70 MiB.
    expect(int.parse(limit![1]!), greaterThanOrEqualTo(70));
  });
}
