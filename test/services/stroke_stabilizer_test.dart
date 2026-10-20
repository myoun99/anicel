import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/services/stroke_stabilizer.dart';

const _lag = Duration(milliseconds: 10);
final _oneLag = 1 - math.exp(-1);

StrokeStabilizer _from(CanvasPoint start, {Duration at = Duration.zero}) =>
    StrokeStabilizer(lag: _lag, start: start, at: at);

Duration _ms(int ms) => Duration(milliseconds: ms);

void main() {
  test('a sample one lag later closes 1 - 1/e of the distance to the pen', () {
    final stabilizer = _from(CanvasPoint(x: 0, y: 0));
    final brush = stabilizer.follow(CanvasPoint(x: 100, y: 0), at: _ms(10));
    expect(brush.x, closeTo(100 * _oneLag, 1e-9));
    expect(brush.y, 0);
    expect(stabilizer.settled, isFalse);
  });

  test('the brush goes straight for the pen, cutting across the corner the '
      'pen turned (F-418-Q4)', () {
    final stabilizer = _from(CanvasPoint(x: 0, y: 0));
    final before = stabilizer.follow(CanvasPoint(x: 100, y: 0), at: _ms(10));
    final pen = CanvasPoint(x: 100, y: 100);
    final after = stabilizer.follow(pen, at: _ms(20));
    // On the straight line from where it was to the pen, a share of the way.
    expect(after.x, closeTo(before.x + (pen.x - before.x) * _oneLag, 1e-9));
    expect(after.y, closeTo(before.y + (pen.y - before.y) * _oneLag, 1e-9));
  });

  test('a sample at no later time moves nothing', () {
    final stabilizer = _from(CanvasPoint(x: 0, y: 0), at: _ms(50));
    final brush = stabilizer.follow(CanvasPoint(x: 100, y: 0), at: _ms(40));
    expect(brush, CanvasPoint(x: 0, y: 0));
  });

  test('while the pen rests, frames keep closing on it — the first frame '
      'after a sample only marks where the pen time stands', () {
    final stabilizer = _from(CanvasPoint(x: 0, y: 0));
    stabilizer.follow(CanvasPoint(x: 100, y: 0), at: Duration.zero);
    // The frame clock starts wherever it likes; only its steps count.
    expect(stabilizer.lookAtFrame(_ms(7000)), isNull);
    final moved = stabilizer.lookAtFrame(_ms(7010));
    expect(moved!.x, closeTo(100 * _oneLag, 1e-9));
    expect(stabilizer.lookAtFrame(_ms(7010)), isNull, reason: 'no time');
  });

  test('a sample after frames starts the frame count over from it', () {
    final stabilizer = _from(CanvasPoint(x: 0, y: 0));
    stabilizer.follow(CanvasPoint(x: 100, y: 0), at: Duration.zero);
    stabilizer.lookAtFrame(_ms(500));
    stabilizer.lookAtFrame(_ms(510));
    final atSample = stabilizer.follow(CanvasPoint(x: 100, y: 0), at: _ms(10));
    // The frames already brought the brush to the sample's time.
    expect(atSample.x, closeTo(100 * _oneLag, 1e-9));
    expect(stabilizer.lookAtFrame(_ms(520)), isNull, reason: 'marks only');
  });

  test('the line settles exactly on a resting pen, and then nothing moves '
      'it', () {
    final stabilizer = _from(CanvasPoint(x: 0, y: 0));
    final pen = CanvasPoint(x: 100, y: 0);
    stabilizer.follow(pen, at: Duration.zero);
    stabilizer.lookAtFrame(Duration.zero);
    var frame = 0;
    while (!stabilizer.settled && frame < 1000) {
      frame += 1;
      stabilizer.lookAtFrame(_ms(frame));
    }
    expect(stabilizer.settled, isTrue);
    expect(stabilizer.position, pen);
    expect(frame, lessThan(200), reason: 'ln(100 / 0.01) lags is ~92 ms');
    expect(stabilizer.lookAtFrame(_ms(frame + 16)), isNull);
  });

  test('the pen lifts and the line goes straight to where it was '
      '(F-418-Q2)', () {
    final stabilizer = _from(CanvasPoint(x: 0, y: 0));
    final pen = CanvasPoint(x: 100, y: 40);
    stabilizer.follow(pen, at: _ms(10));
    expect(stabilizer.finish(), pen);
    expect(stabilizer.position, pen);
    expect(stabilizer.finish(), isNull, reason: 'already there');
  });

  test('a pen that never left the start finishes with nothing to draw', () {
    final stabilizer = _from(CanvasPoint(x: 5, y: 5));
    expect(stabilizer.settled, isTrue);
    expect(stabilizer.finish(), isNull);
    expect(stabilizer.lookAtFrame(_ms(16)), isNull);
  });
}
