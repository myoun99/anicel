import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/services/input/pen_readings.dart';
import 'package:anicel/src/services/stroke_stabilizer.dart';

const _lag = Duration(milliseconds: 10);
final _oneLag = 1 - math.exp(-1);

const PenReadings _rest = (pressure: 0.5, lean: null, twist: null, speed: 0.0);

StrokeStabilizer _from(
  CanvasPoint start, {
  Duration at = Duration.zero,
  PenReadings readings = _rest,
  Duration lag = _lag,
  bool keepsCorners = false,
}) => StrokeStabilizer(
  lagAt: (_) => lag,
  start: (position: start, readings: readings),
  at: at,
  keepsCorners: keepsCorners,
);

Duration _ms(int ms) => Duration(milliseconds: ms);

/// A point on y = 0.
CanvasPoint _p(num x) => CanvasPoint(x: x.toDouble(), y: 0);

void main() {
  test('a sample one lag later closes 1 - 1/e of the distance to the pen', () {
    final stabilizer = _from(CanvasPoint(x: 0, y: 0));
    final brush = stabilizer.follow(
      CanvasPoint(x: 100, y: 0),
      _rest,
      at: _ms(10),
    ).last;
    expect(brush.position.x, closeTo(100 * _oneLag, 1e-9));
    expect(brush.position.y, 0);
    expect(stabilizer.settled, isFalse);
  });

  test('the brush goes straight for the pen, cutting across the corner the '
      'pen turned (F-418-Q4)', () {
    final stabilizer = _from(CanvasPoint(x: 0, y: 0));
    final before = stabilizer
        .follow(CanvasPoint(x: 100, y: 0), _rest, at: _ms(10))
        .last
        .position;
    final pen = CanvasPoint(x: 100, y: 100);
    final after = stabilizer.follow(pen, _rest, at: _ms(20)).last.position;
    // On the straight line from where it was to the pen, a share of the way.
    expect(after.x, closeTo(before.x + (pen.x - before.x) * _oneLag, 1e-9));
    expect(after.y, closeTo(before.y + (pen.y - before.y) * _oneLag, 1e-9));
  });

  test('the readings come behind the pen with the line, by the same share', () {
    final stabilizer = _from(
      CanvasPoint(x: 0, y: 0),
      readings: (
        pressure: 0.2,
        lean: (azimuthDegrees: 90.0, altitude: 0.5),
        twist: 90.0,
        speed: 0.0,
      ),
    );
    final brush = stabilizer.follow(CanvasPoint(x: 100, y: 0), (
      pressure: 1.0,
      lean: (azimuthDegrees: 180.0, altitude: 1.0),
      twist: 180.0,
      speed: 0.6,
    ), at: _ms(10)).last;
    final readings = brush.readings;
    expect(readings.pressure, closeTo(0.2 + 0.8 * _oneLag, 1e-9));
    expect(readings.speed, closeTo(0.6 * _oneLag, 1e-9));
    expect(readings.lean!.azimuthDegrees, closeTo(90 + 90 * _oneLag, 1e-9));
    expect(readings.lean!.altitude, closeTo(0.5 + 0.5 * _oneLag, 1e-9));
    expect(readings.twist, closeTo(90 + 90 * _oneLag, 1e-9));
  });

  test('a lean turns the shorter way round, across 0°', () {
    final stabilizer = _from(
      CanvasPoint(x: 0, y: 0),
      readings: (
        pressure: 1.0,
        lean: (azimuthDegrees: 350.0, altitude: 0.5),
        twist: null,
        speed: 0.0,
      ),
    );
    final lean = stabilizer
        .follow(CanvasPoint(x: 100, y: 0), (
          pressure: 1.0,
          lean: (azimuthDegrees: 10.0, altitude: 0.5),
          twist: null,
          speed: 0.0,
        ), at: _ms(10))
        .last
        .readings
        .lean!;
    expect(lean.azimuthDegrees, closeTo((350 + 20 * _oneLag) % 360, 1e-9));
  });

  test('a lean only one side measured is taken as the pen reads it', () {
    final stabilizer = _from(CanvasPoint(x: 0, y: 0));
    const measured = (azimuthDegrees: 45.0, altitude: 0.8);
    final brush = stabilizer.follow(CanvasPoint(x: 100, y: 0), (
      pressure: 0.5,
      lean: measured,
      twist: null,
      speed: 0.0,
    ), at: _ms(10)).last;
    expect(brush.readings.lean, measured);
    final lost = stabilizer.follow(
      CanvasPoint(x: 100, y: 0),
      _rest,
      at: _ms(20),
    ).last;
    expect(lost.readings.lean, isNull);
  });

  test('a sample at no later time moves nothing', () {
    final stabilizer = _from(CanvasPoint(x: 0, y: 0), at: _ms(50));
    final way = stabilizer.follow(
      CanvasPoint(x: 100, y: 0),
      _rest,
      at: _ms(40),
    );
    expect(way.single.position, CanvasPoint(x: 0, y: 0));
  });

  test('while the pen rests, frames keep closing on it — the first frame '
      'after a sample only marks where the pen time stands', () {
    final stabilizer = _from(CanvasPoint(x: 0, y: 0));
    stabilizer.follow(CanvasPoint(x: 100, y: 0), _rest, at: Duration.zero);
    // The frame clock starts wherever it likes; only its steps count.
    expect(stabilizer.lookAtFrame(_ms(7000)), isEmpty);
    final moved = stabilizer.lookAtFrame(_ms(7010));
    expect(moved.single.position.x, closeTo(100 * _oneLag, 1e-9));
    expect(stabilizer.lookAtFrame(_ms(7010)), isEmpty, reason: 'no time');
  });

  test('a sample after frames starts the frame count over from it', () {
    final stabilizer = _from(CanvasPoint(x: 0, y: 0));
    stabilizer.follow(CanvasPoint(x: 100, y: 0), _rest, at: Duration.zero);
    stabilizer.lookAtFrame(_ms(500));
    stabilizer.lookAtFrame(_ms(510));
    final atSample = stabilizer.follow(
      CanvasPoint(x: 100, y: 0),
      _rest,
      at: _ms(10),
    );
    // The frames already brought the brush to the sample's time.
    expect(atSample.single.position.x, closeTo(100 * _oneLag, 1e-9));
    expect(stabilizer.lookAtFrame(_ms(520)), isEmpty, reason: 'marks only');
  });

  test('the line settles exactly on a resting pen, readings and all, and '
      'then nothing moves it', () {
    final stabilizer = _from(CanvasPoint(x: 0, y: 0));
    final pen = CanvasPoint(x: 100, y: 0);
    const pressed = (pressure: 0.9, lean: null, twist: null, speed: 0.3);
    stabilizer.follow(pen, pressed, at: Duration.zero);
    stabilizer.lookAtFrame(Duration.zero);
    var frame = 0;
    while (!stabilizer.settled && frame < 1000) {
      frame += 1;
      stabilizer.lookAtFrame(_ms(frame));
    }
    expect(stabilizer.settled, isTrue);
    expect(stabilizer.brush, (position: pen, readings: pressed));
    expect(frame, lessThan(200), reason: 'ln(100 / 0.01) lags is ~92 ms');
    expect(stabilizer.lookAtFrame(_ms(frame + 16)), isEmpty);
  });

  test('the pen lifts and the line goes straight to where it was, reading '
      'what it read there (F-418-Q2)', () {
    final stabilizer = _from(CanvasPoint(x: 0, y: 0));
    final pen = CanvasPoint(x: 100, y: 40);
    const lifting = (pressure: 0.1, lean: null, twist: null, speed: 0.8);
    stabilizer.follow(pen, lifting, at: _ms(10));
    expect(stabilizer.finish(), [(position: pen, readings: lifting)]);
    expect(stabilizer.brush.position, pen);
    expect(stabilizer.finish(), isEmpty, reason: 'already there');
  });

  test('a pen that never left the start finishes with nothing to draw', () {
    final stabilizer = _from(CanvasPoint(x: 5, y: 5));
    expect(stabilizer.settled, isTrue);
    expect(stabilizer.finish(), isEmpty);
    expect(stabilizer.lookAtFrame(_ms(16)), isEmpty);
  });

  test('how far behind the line runs is asked at the speed the pen moves '
      'now (速度による手ブレ補正)', () {
    final asked = <double>[];
    final stabilizer = StrokeStabilizer(
      lagAt: (speed) {
        asked.add(speed);
        return speed > 0.5 ? _ms(100) : _lag;
      },
      start: (position: CanvasPoint(x: 0, y: 0), readings: _rest),
      at: Duration.zero,
    );
    const quick = (pressure: 0.5, lean: null, twist: null, speed: 0.9);
    final brush = stabilizer.follow(
      CanvasPoint(x: 100, y: 0),
      quick,
      at: _ms(10),
    ).last;
    expect(asked, [0.9]);
    expect(brush.position.x, closeTo(100 * (1 - math.exp(-0.1)), 1e-9));
  });

  group('角をとがらせる (F-418-Q11)', () {
    final corner = CanvasPoint(x: 100, y: 0);

    test('a brush that keeps its corners goes through the corner the pen '
        'turned, reading what the pen read there', () {
      final way = _right(_from(CanvasPoint(x: 0, y: 0), keepsCorners: true));
      final there = way.where((point) => point.position == corner);
      expect(there, isNotEmpty);
      expect(there.first.readings, _pressing(0.3));
    });

    test('one that does not cuts across it', () {
      final way = _right(_from(CanvasPoint(x: 0, y: 0)));
      expect(
        way.map((point) => point.position.distanceTo(corner)).reduce(math.min),
        greaterThan(3),
      );
    });

    test('a corner the line has already cut past is not gone back for', () {
      final way = _right(
        _from(CanvasPoint(x: 0, y: 0), lag: _ms(1), keepsCorners: true),
      );
      for (var i = 1; i < way.length; i += 1) {
        expect(
          way[i].position.y,
          greaterThanOrEqualTo(way[i - 1].position.y),
          reason: 'step $i',
        );
      }
    });

    test('a step closes the same share of the way through the corner as of '
        'a straight way, reading what the pen read along the leg it is on '
        '— and what it has left past the corner, it goes on with', () {
      final stabilizer = _from(
        CanvasPoint(x: 0, y: 0),
        readings: _pressing(0.3),
        keepsCorners: true,
      );
      // At no later time than the start: the pen turns, the line stays.
      _right(stabilizer, downTo: 40, lift: false, still: true);
      final pen = CanvasPoint(x: 100, y: 40);
      const way = 100.0 + 40;

      final first = stabilizer.follow(pen, _pressing(0.9), at: _ms(10));
      expect(first.single.position.x, closeTo(way * _oneLag, 1e-9));
      expect(first.single.position.y, 0);
      expect(first.single.readings.pressure, closeTo(0.3, 1e-9));

      final second = stabilizer.follow(pen, _pressing(0.9), at: _ms(20));
      final past = way * _oneLag + (way - way * _oneLag) * _oneLag - 100;
      expect(second.map((point) => point.position.x), [100, 100]);
      expect(second.first.position.y, 0);
      expect(second.last.position.y, closeTo(past, 1e-9));
      expect(
        second.last.readings.pressure,
        closeTo(0.3 + 0.6 * past / 40, 1e-9),
      );
    });

    test('a frame that takes the line through a corner answers the corner '
        'too', () {
      final stabilizer = _from(CanvasPoint(x: 0, y: 0), keepsCorners: true);
      _right(stabilizer, downTo: 40, lift: false, still: true);
      expect(stabilizer.lookAtFrame(_ms(1000)), isEmpty);
      expect(
        stabilizer.lookAtFrame(_ms(1020)).map((point) => point.position),
        [corner, isA<CanvasPoint>()],
      );
    });

    test('a line come within a hair of the pen with a corner still to go '
        'through has not settled: the lift draws the fold', () {
      final stabilizer = _from(CanvasPoint(x: 0, y: 0), keepsCorners: true);
      final pen = CanvasPoint(x: 24, y: 0);
      // Out along y = 0 to x = 40 and straight back to the pen, at no
      // later time than the start.
      for (var x = 2; x <= 40; x += 2) {
        stabilizer.follow(_p(x), _rest, at: Duration.zero);
      }
      for (var x = 38; x >= 24; x -= 2) {
        stabilizer.follow(_p(x), _rest, at: Duration.zero);
      }
      // 40 out and 16 back: a share of 24/56 brings the line to the pen's
      // side on its way out.
      final step = stabilizer.follow(
        pen,
        _rest,
        at: const Duration(microseconds: 5596),
      );
      expect(step.last.position.distanceTo(pen), lessThan(0.01));
      expect(stabilizer.settled, isFalse);
      expect(stabilizer.finish().map((point) => point.position), [
        _p(40),
        pen,
      ]);
    });

    test('the lift goes through the corners the line had yet to reach — '
        'and the one the pen was still turning', () {
      final stabilizer = _from(CanvasPoint(x: 0, y: 0), keepsCorners: true);
      _right(stabilizer, downTo: 12, lift: false);
      expect(
        stabilizer.finish().map((point) => point.position),
        [corner, CanvasPoint(x: 100, y: 12)],
      );

      final turning = _from(CanvasPoint(x: 0, y: 0), keepsCorners: true);
      _right(turning, downTo: 8, lift: false);
      expect(
        turning.finish().map((point) => point.position),
        [corner, CanvasPoint(x: 100, y: 8)],
      );
    });
  });
}

PenReadings _pressing(double pressure) =>
    (pressure: pressure, lean: null, twist: null, speed: 0.0);

/// A pen that goes right along y = 0 to x = 100, pressing 0.3, and turns
/// down to y = [downTo], pressing 0.9 — a sample every millisecond, 4 px
/// apart, or all at the start when [still]: the way the line went, to the
/// lift when it [lift]s.
List<PenPoint> _right(
  StrokeStabilizer stabilizer, {
  int downTo = 100,
  bool lift = true,
  bool still = false,
}) {
  final way = <PenPoint>[];
  var ms = 0;
  void sample(double x, double y, double pressure) {
    ms += 1;
    way.addAll(
      stabilizer.follow(
        CanvasPoint(x: x, y: y),
        _pressing(pressure),
        at: still ? Duration.zero : _ms(ms),
      ),
    );
  }

  for (var x = 4; x <= 100; x += 4) {
    sample(x.toDouble(), 0, 0.3);
  }
  for (var y = 4; y <= downTo; y += 4) {
    sample(100, y.toDouble(), 0.9);
  }
  if (lift) {
    way.addAll(stabilizer.finish());
  }
  return way;
}
