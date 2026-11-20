import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/test_shard.dart';

/// 🚨THE FILES A SHARD WEIGHS BY ARE THERE.
///
/// A test file no CI run timed is weighed by its size, three times over if
/// it opens the app (ci-takes-an-hour-on-lavapipe, 2026-11-17) — found as
/// the tests that reach [kOpensTheApp] (tool/test_shard.dart). A rename of
/// one stops every shard at its deal on CI — a round of the bundle PR lost
/// — so the landing's architecture run says it first. ↩️Till 2026-11-17
/// the action named them to tool/tests_reaching_files.dart, and this read
/// the action (card ci-shards-dealt-by-measured-seconds).
void main() {
  test('every file the shard deal weighs by is in the tree', () {
    expect(kOpensTheApp, isNotEmpty, reason: 'the scan reads the list');
    expect(
      [
        for (final path in kOpensTheApp)
          if (!File(path).existsSync()) path,
      ],
      isEmpty,
      reason: 'a renamed file leaves the deal on nothing',
    );
  });

  // The engine build the Linux shards start from is made by ci.yml's
  // engine-target job running one test file (ci-shards-build-the-engine-
  // cold, 2026-11-17): a rename of that file would turn master's run red
  // and leave the shards building cold. 🆕The Windows ARM64 release names
  // the device test it runs first (windows-arm64-runner-engine-tests-stall-
  // on-a-software-gpu, 2026-11-18) — a rename there turns a release round
  // red, so every workflow is read, not ci.yml alone.
  test('every test file a workflow runs by name is in the tree', () {
    final named = [
      for (final file in Directory('.github/workflows').listSync())
        if (file is File && file.path.endsWith('.yml'))
          for (final line in file.readAsLinesSync())
            if (!line.trimLeft().startsWith('#'))
              for (final m
                  in RegExp(r'test/[\w/]+_test\.dart').allMatches(line))
                m[0]!,
    ];
    expect(named, isNotEmpty, reason: 'LIVENESS — the engine-target job');
    expect(
      [
        for (final path in named)
          if (!File(path).existsSync()) path,
      ],
      isEmpty,
    );
  });
}
