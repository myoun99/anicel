import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../helpers/dart_sources.dart';

/// Each job of a workflow's [lines], by its id: the lines from its
/// `  <id>:` under `jobs:` to the next job's.
Map<String, String> _jobsOf(List<String> lines) {
  final jobs = <String, String>{};
  final start = lines.indexOf('jobs:');
  if (start == -1) return jobs;
  String? id;
  final body = StringBuffer();
  for (final line in [...lines.skip(start + 1), '  end-of-jobs:']) {
    final head = RegExp(r'^  ([\w-]+):\s*$').firstMatch(line);
    if (head == null) {
      body.writeln(line);
      continue;
    }
    if (id != null) jobs[id] = body.toString();
    body.clear();
    id = head[1];
  }
  return jobs;
}

/// 🚨A JOB THAT RUNS THE ENGINE ON LAVAPIPE LENDS IT /dev/udmabuf.
///
/// The engine's shown surface is exported as a dma-buf, and lavapipe — what
/// `mesa-vulkan-drivers` installs — offers the export only when llvmpipe
/// can open /dev/udmabuf. gpu-engine.yml's Linux job was lent it on
/// 2026-11-07; ci.yml's Linux shards were not, and every test that opened a
/// screen was refused there: 150 red files on shard 1 of the bundle PR's
/// run 43591634086, whose second run passed the 45 minutes (관제
/// 2026-11-15, board ci-linux-shards-cannot-make-a-shown-surface).
void main() {
  test('every job that installs lavapipe lends it /dev/udmabuf', () {
    final lavapipe = <String>[];
    final unlent = <String>[];
    for (final file in filesUnder('.github/workflows')) {
      if (!file.path.endsWith('.yml')) continue;
      final workflow = file.path.replaceAll(r'\', '/');
      final jobs = _jobsOf(file.readAsLinesSync());
      for (final MapEntry(key: id, value: job) in jobs.entries) {
        if (!job.contains('install -y mesa-vulkan-drivers')) continue;
        lavapipe.add('$workflow:$id');
        if (!job.contains(r'sudo chown "$USER" /dev/udmabuf')) {
          unlent.add('$workflow:$id');
        }
      }
    }
    // LIVENESS — the scan reaches both jobs that run the engine there.
    expect(
      lavapipe,
      containsAll([
        '.github/workflows/ci.yml:analyze-and-test',
        '.github/workflows/gpu-engine.yml:linux',
      ]),
    );
    expect(
      unlent,
      isEmpty,
      reason: "lend it as gpu-engine.yml's Linux job does",
    );
  });
}
