@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/affected_tests.dart' show beatTheLandsTurn;

/// 관제 2026-11-12, card a-long-land-loses-its-turn-at-45-minutes: a land's
/// turn is taken over once nothing in it has moved for 45 minutes
/// (`tool/lane.sh`, `land_turn`), and `tile-blocks-on-rust`'s native gate —
/// whose parity run is affected_tests — went 61 without a sign of life.
/// Each batch it starts under a land's gates beats the turn.
///
/// ⚠️What the turn makes of a beat — its age read through what is inside
/// it, the land that stops once its turn is someone else's — is in
/// `tool/lane_test.sh`, section Y: no test here may start a process
/// (`tests_do_not_race_the_code_test`).
void main() {
  late Directory scratch;
  setUp(() => scratch = Directory.systemTemp.createTempSync('land-turn'));
  tearDown(() => scratch.deleteSync(recursive: true));

  test('under a land, a batch writes a beat inside its turn', () {
    final turn = Directory('${scratch.path}/lane-land.turn')..createSync();
    final beat = File('${turn.path}/beat');
    expect(beat.existsSync(), isFalse, reason: 'LIVENESS — none before');

    expect(beatTheLandsTurn({'LANE_LAND_TURN': turn.path}), isTrue);
    expect(beat.existsSync(), isTrue);

    final old = DateTime.now().subtract(const Duration(hours: 2));
    beat.setLastModifiedSync(old);
    expect(beatTheLandsTurn({'LANE_LAND_TURN': turn.path}), isTrue);
    expect(
      beat.lastModifiedSync().isAfter(old.add(const Duration(hours: 1))),
      isTrue,
      reason: 'the next batch beats it anew',
    );
  });

  test('a turn that is gone stays gone — nothing is made where it was', () {
    final turn = '${scratch.path}/lane-land.turn';
    expect(beatTheLandsTurn({'LANE_LAND_TURN': turn}), isFalse);
    expect(Directory(turn).existsSync(), isFalse);
    expect(File('$turn/beat').existsSync(), isFalse);
  });

  test('outside a land it beats nothing', () {
    expect(beatTheLandsTurn(const {}), isFalse);
    expect(beatTheLandsTurn(const {'LANE_LAND_TURN': ''}), isFalse);
    expect(scratch.listSync(), isEmpty);
  });
}
