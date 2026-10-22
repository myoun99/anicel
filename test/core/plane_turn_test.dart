import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/core/turn_trig.dart';

/// [PlaneTurn] — the one turn of a point, by the one table (board
/// `a-point-turned-by-an-angle-is-spelled-in-many-places`).
void main() {
  test('it turns clockwise where y runs down: +x goes onto +y', () {
    final turned = PlaneTurn(90).apply(1, 0);
    expect(turned.x, 0.0, reason: 'the table, not the library\'s 6e-17');
    expect(turned.y, 1.0);
  });

  test('every quarter turn is exact, either way round and past a turn', () {
    for (final (degrees, x, y) in [
      (180.0, -1.0, 0.0),
      (270.0, 0.0, -1.0),
      (-90.0, 0.0, -1.0),
      (450.0, 0.0, 1.0),
      (360.0, 1.0, 0.0),
    ]) {
      final turned = PlaneTurn(degrees).apply(1, 0);
      expect((turned.x, turned.y), (x, y), reason: '$degrees');
    }
  });

  test('a turn in between is the library\'s', () {
    final turned = PlaneTurn(30).apply(2, 0);
    expect(turned.x, closeTo(math.sqrt(3), 1e-12));
    expect(turned.y, closeTo(1, 1e-12));
  });

  test('its way back takes a turned point home', () {
    final random = math.Random(20261018);
    for (var i = 0; i < 100; i += 1) {
      final turn = PlaneTurn(random.nextDouble() * 720 - 360);
      final x = random.nextDouble() * 200 - 100;
      final y = random.nextDouble() * 200 - 100;
      final there = turn.apply(x, y);
      final home = turn.back.apply(there.x, there.y);
      expect(home.x, closeTo(x, 1e-9));
      expect(home.y, closeTo(y, 1e-9));
    }
  });

  test('the way back is the turn the other way', () {
    final back = PlaneTurn(90).back.apply(0, 1);
    expect((back.x, back.y), (1.0, 0.0));
  });
}
