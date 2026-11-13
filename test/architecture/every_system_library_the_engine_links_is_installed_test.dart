import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// What each `-sys` crate of the engine's lock needs on a Linux runner —
/// null for none: the ones that bind another OS's API, or the kernel's
/// calls, or load their library only if it is there when the app runs.
const _linuxPackageOf = <String, String?>{
  'alsa-sys': 'libasound2-dev',
  'jni-sys': null,
  'js-sys': null,
  'linux-raw-sys': null,
  'ndk-sys': null,
  'renderdoc-sys': null,
  'web-sys': null,
  'windows-sys': null,
};

/// 🚨A LINUX BUILD OF THE ENGINE HAS EVERY SYSTEM LIBRARY IT LINKS.
///
/// Card the-linux-ci-shards-cannot-build-the-engine-without-alsa (관제
/// 2026-11-13): the sound device brought cpal, whose Linux backend's
/// alsa-sys asks pkg-config for ALSA, and the bundle PR's three Linux
/// shards could not build the engine — ci.yml's package list was the one
/// of three without it. The packages now come from the action every job
/// that builds the engine goes through, and a crate that binds a system
/// library cannot join the lock without saying what a runner installs.
void main() {
  const lock = 'packages/gpu_engine/rust/Cargo.lock';
  const action = '.github/actions/rust-engine/action.yml';

  test('every -sys crate of the engine says what a Linux runner needs', () {
    final crates = {
      for (final match in RegExp(
        r'^name = "([\w-]+-sys)"\r?$',
        multiLine: true,
      ).allMatches(File(lock).readAsStringSync()))
        match.group(1)!,
    };
    expect(crates, contains('alsa-sys'), reason: lock);
    expect(
      crates.difference(_linuxPackageOf.keys.toSet()),
      isEmpty,
      reason:
          'name it in _linuxPackageOf with what a Linux runner installs '
          'for it, and install that in $action',
    );
  });

  test('and the action installs each one on Linux', () {
    final lines = File(action).readAsLinesSync();
    final start = lines.indexWhere(
      (line) => line.trim() == "- if: runner.os == 'Linux'",
    );
    expect(start, isNot(-1), reason: action);
    final step = lines
        .skip(start + 1)
        .takeWhile((line) => !line.trimLeft().startsWith('- '))
        .join('\n');
    final install = RegExp(r'apt-get install -y ([^\n&]+)').firstMatch(step);
    expect(install, isNotNull, reason: action);
    final installed = install![1]!.trim().split(RegExp(r'\s+'));
    for (final package in _linuxPackageOf.values.nonNulls) {
      expect(installed, contains(package), reason: action);
    }
  });
}
