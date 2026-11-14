import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// THE ENGINE'S BUILD HOOK BUILDS THE LOCK IT WAS GIVEN
/// (the-engine-hook-builds-without-locked-and-rewrites-the-lock,
/// 2026-11-13).
///
/// A plain `cargo build` mends a lock that is out of step with the
/// manifests and builds what it chose, so every Flutter run of a checkout
/// whose lock was off rewrote it — a mutant of its names was undone before
/// the test that read it ran. With `--locked` that build fails instead,
/// which was measured once by hand with the lock's names changed (cargo is
/// a process no test here starts).
void main() {
  test('the builder is asked for --locked', () {
    final hook = File(
      'packages/gpu_engine/hook/build.dart',
    ).readAsStringSync();
    expect(hook, contains("extraCargoBuildArgs: const ['--locked']"));
  });
}
