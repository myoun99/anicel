import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../tool/crate_notices.dart';
import '../tool/crates_for_host.dart';

/// Every registry crate the GPU engine's library carries is SHOWN with the
/// app, under its licence text — the one list tool/crate_notices.dart writes
/// (관제 2026-11-07, connection-round-checklist A 📜: four rows did it crate
/// by crate, and wgpu's crates had none). A lane that adds or moves a crate
/// in the lock turns this red until the list is written again.
///
/// Offline and by name and version alone: which crates ship is the tool's
/// walk (tested beside it), so here every crate of the lock has to be
/// accounted for — noticed, or found shipped on no target — once.
void main() {
  final file = noticedCrates(
    jsonDecode(File('assets/licenses/rust_crates.json').readAsStringSync())
        as Map<String, dynamic>,
  );

  test('the list was made for every target the engine is built for', () {
    final toolchain = File(
      'packages/gpu_engine/rust/rust-toolchain.toml',
    ).readAsStringSync();
    expect(file.targets.toSet(), toolchainTargets(toolchain).toSet());
  });

  test('every crate of the lock is noticed or ships nowhere, once', () {
    final lock = lockPackages(
      File('packages/gpu_engine/rust/Cargo.lock').readAsStringSync(),
    );
    final registry = [
      for (final package in lock)
        if (package.fromRegistry) '${package.name} ${package.version}',
    ]..sort();
    expect([...file.noticed, ...file.unshipped]..sort(), registry);
  });
}
