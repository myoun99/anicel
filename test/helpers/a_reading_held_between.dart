import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';

/// Holds what [read] says of a number that moves on all the time to the
/// engine's answers around it: asked of [engine], [read] and [engine]
/// again, until the reading lies between the two answers — or is null
/// where both are. ↩️The memory crate's Rust tests held the Rust to the C
/// so (`between`) until the connection round deleted the C (2026-11-08).
void expectReadingHeldBetween(
  int? Function() engine,
  int? Function() read,
) {
  for (var attempt = 0; attempt < 1000; attempt += 1) {
    final before = engine();
    final reading = read();
    final after = engine();
    if (before == null || after == null || reading == null) {
      if (before == null && after == null && reading == null) {
        return;
      }
      continue;
    }
    if (math.min(before, after) <= reading &&
        reading <= math.max(before, after)) {
      return;
    }
  }
  fail('LIVENESS — the reading never lay between two of the engine\'s '
      'answers');
}
