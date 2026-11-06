import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../helpers/dart_sources.dart';

/// 🚨EVERY CARGO A TOOL OF THIS REPOSITORY BUILDS WITH GOES THROUGH
/// `tool/cargo_turn.sh`.
///
/// 관제 2026-11-06 (native-memory-safety): two cargos in the trunk's shared
/// target folder replace each other's builds — a land's doc-tests failed
/// twice with `E0463 can't find crate for media`. The turn keeps them
/// apart, and a session's Bash call is held to it by a guard
/// (session_hooks/guard_shared_target.sh); a script of this repository
/// that called cargo itself would walk past both, so one that does is named
/// here.
void main() {
  final building = RegExp(
    r'(^|[\s;&|(])cargo\s+(\+\S+\s+)?'
    r'(build|check|test|run|bench|clippy|doc|rustc|rustdoc|fix)\b',
  );
  const turn = 'tool/cargo_turn.sh';

  test('no script but the turn runs a cargo that builds', () {
    final own = <String>[];
    for (final file in filesUnder('tool')) {
      final path = file.path.replaceAll(r'\', '/');
      if (!path.endsWith('.sh') ||
          path.endsWith(turn) ||
          path.endsWith('_test.sh')) {
        continue;
      }
      final lines = file.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        if (lines[i].trimLeft().startsWith('#')) continue;
        if (building.hasMatch(lines[i])) own.add('$path:${i + 1}');
      }
    }
    expect(own, isEmpty, reason: 'bash "\$ROOT/$turn" <cargo arguments>');
  });

  test('and the land\'s crate gate builds through it', () {
    final lane = File('tool/lane.sh').readAsStringSync();
    expect(lane, contains('bash "\$ROOT/$turn" test --locked --workspace'));
  });
}
