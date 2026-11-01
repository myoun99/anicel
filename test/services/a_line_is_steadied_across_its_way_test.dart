import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/brush_correction.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/services/input/pen_readings.dart';
import 'package:anicel/src/services/stroke_stabilizer.dart';

const _floor = BrushCorrection.lagAtClipStudioZero;
const _sample = Duration(microseconds: 4167);

const PenReadings _rest = (pressure: 0.5, lean: null, twist: null, speed: 0.0);

StrokeStabilizer _line({
  Duration lag = _floor,
  Duration acrossOnly = _floor,
  PenReadings readings = _rest,
}) => StrokeStabilizer(
  lagAt: (_) => lag,
  acrossOnly: acrossOnly,
  start: (position: CanvasPoint(x: 0, y: 0), readings: readings),
  at: Duration.zero,
);

/// A 240 Hz pen going right at [speed] px/s, [samples] of it, its wobble
/// across given by [across]: answers how far along the line runs behind it,
/// and where it stands across it.
({double behind, double y}) _go(
  StrokeStabilizer line,
  double speed, {
  int samples = 60,
  double Function(int sample)? across,
}) {
  var x = 0.0;
  var y = 0.0;
  for (var i = 1; i <= samples; i += 1) {
    x = speed * (_sample * i).inMicroseconds / 1e6;
    final brush = line
        .follow(
          CanvasPoint(x: x, y: across?.call(i) ?? 0),
          _rest,
          at: _sample * i,
        )
        .last;
    y = brush.position.y;
  }
  return (behind: x - line.brush.position.x, y: y);
}

/// The pen [distance] px along a run of 600 px, half a circle of [radius],
/// and the same way back.
CanvasPoint _uTurn(double distance, double radius) {
  const run = 600.0;
  final arc = math.pi * radius;
  if (distance <= run) {
    return CanvasPoint(x: distance, y: 0);
  }
  if (distance <= run + arc) {
    final turned = (distance - run) / radius;
    return CanvasPoint(
      x: run + radius * math.sin(turned),
      y: radius - radius * math.cos(turned),
    );
  }
  return CanvasPoint(x: run - (distance - run - arc), y: 2 * radius);
}

/// How a line turned on the way round a U-turn taken at [speed] px/s: through
/// how many degrees all told, and how often it changed side.
({double degrees, int changes}) _roundTheTurn(
  StrokeStabilizer line,
  double speed, {
  required double radius,
}) {
  final seconds = _sample.inMicroseconds / 1e6;
  final way = [
    for (var i = 1; i * speed * seconds < 1200 + math.pi * radius; i += 1)
      ...line
          .follow(_uTurn(i * speed * seconds, radius), _rest, at: _sample * i)
          .map((point) => point.position),
  ].where((point) => point.x > 480).toList();
  var degrees = 0.0;
  var changes = 0;
  var side = 0.0;
  for (var i = 1; i + 1 < way.length; i += 1) {
    final (a, b, c) = (way[i - 1], way[i], way[i + 1]);
    final (ux, uy) = (b.x - a.x, b.y - a.y);
    final (vx, vy) = (c.x - b.x, c.y - b.y);
    final turn = math.atan2(ux * vy - uy * vx, ux * vx + uy * vy) * 180 / math.pi;
    degrees += turn.abs();
    if (turn.abs() > 2) {
      changes += side * turn < 0 ? 1 : 0;
      side = turn;
    }
  }
  return (degrees: degrees, changes: changes);
}

void main() {
  test('🚨along the way it goes the line is level with the pen', () {
    expect(_go(_line(), 1200).behind, closeTo(0, 0.01));
    expect(_go(_line(), 300).behind, closeTo(0, 0.01));
  });

  test('none of the lag across only, it runs behind as it ever did', () {
    final plain = _go(_line(acrossOnly: Duration.zero), 1200).behind;

    expect(plain, closeTo(1200 * 0.00227, 0.05));
  });

  test('🚨across it the line is steadied as much as it ever was', () {
    double wobble(int sample) => sample.isEven ? 0.2 : -0.2;

    final plain = _go(
      _line(acrossOnly: Duration.zero),
      1200,
      across: wobble,
    ).y;
    final across = _go(_line(), 1200, across: wobble).y;

    expect(plain.abs(), lessThan(0.11));
    expect(across, closeTo(plain, 0.02));
  });

  test('a lag past what is across only stays behind by what is left', () {
    const lag = Duration(milliseconds: 100);

    final across = _go(_line(lag: lag), 1200, samples: 600).behind;
    final rest = _go(
      _line(lag: lag - _floor, acrossOnly: Duration.zero),
      1200,
      samples: 600,
    ).behind;

    expect(across, closeTo(rest, rest / 100));
  });

  test('🚨a pen too slow to tell its way goes as far as it does', () {
    final plain = _go(_line(acrossOnly: Duration.zero), 30).behind;
    final slow = _go(_line(), 30).behind;

    expect(slow, closeTo(plain * 0.85, plain / 50));
  });

  test('a pen that stops leaves the line to close all round', () {
    final line = _line();
    _go(line, 1200);
    final pen = line.brush.position;
    final moved = line.follow(
      CanvasPoint(x: pen.x, y: 1),
      _rest,
      at: _sample * 61,
    );

    expect(moved.last.position.y, closeTo(0.647, 0.02));
  });

  test('🚨the way is told over time: the sample after a corner is across', () {
    final line = _line();
    final before = _go(line, 1200);
    final at = line.brush.position;
    final turned = line
        .follow(
          CanvasPoint(x: at.x + before.behind, y: 5),
          _rest,
          at: _sample * 61,
        )
        .last
        .position;

    expect(turned.y, closeTo(5 * 0.647, 0.3));
  });

  group('🚨a quick turn is turned once (F-536)', () {
    for (final (speed, radius) in [
      (1500.0, 6.0),
      (3000.0, 6.0),
      (3000.0, 15.0),
      (5000.0, 6.0),
      (5000.0, 15.0),
    ]) {
      test('$speed px/s round $radius px', () {
        final turn = _roundTheTurn(_line(), speed, radius: radius);

        expect(turn.changes, 0, reason: '⛔it swings out and back');
        expect(turn.degrees, closeTo(180, 5));
      });
    }

    test('🚨and a brush past 0 alike', () {
      final turn = _roundTheTurn(
        _line(lag: const Duration(microseconds: 5610)),
        1500,
        radius: 6,
      );

      expect(turn.changes, 0);
      expect(turn.degrees, closeTo(180, 5));
    });

    test('🚨CONTROL: steadied all round, it always was', () {
      final turn = _roundTheTurn(
        _line(acrossOnly: Duration.zero),
        5000,
        radius: 6,
      );

      expect(turn.changes, 0);
      expect(turn.degrees, closeTo(180, 1));
    });
  });

  test('🚨a wobble does not bring the lag back: it is no turn', () {
    final dice = math.Random(7);
    final line = _line();
    var behind = 0.0;
    for (var i = 1; i <= 60; i += 1) {
      final x = 1200 * (_sample * i).inMicroseconds / 1e6;
      final y = (dice.nextDouble() - 0.5) * 0.8;
      final at = _sample * i;
      behind += x - line.follow(CanvasPoint(x: x, y: y), _rest, at: at).last.position.x;
    }

    expect(behind / 60, closeTo(0, 1200 * 0.0002));
  });

  test('🚨a pen that turns back goes nowhere along its old way', () {
    final line = _line();
    final before = _go(line, 1200);
    final at = line.brush.position;
    final back = line
        .follow(
          CanvasPoint(x: at.x + before.behind - 4, y: 0),
          _rest,
          at: _sample * 61,
        )
        .last
        .position;

    expect(back.x, closeTo(at.x - 4 * 0.647, 0.3));
  });

  test('🚨whichever way it goes', () {
    final line = _line();
    late CanvasPoint pen;
    for (var i = 1; i <= 60; i += 1) {
      pen = CanvasPoint(x: -720.0 * i / 240, y: 960.0 * i / 240);
      line.follow(pen, _rest, at: _sample * i);
    }

    expect(line.brush.position.x, closeTo(pen.x, 0.02));
    expect(line.brush.position.y, closeTo(pen.y, 0.02));
  });

  test('🚨a pen standing on the line reads what it read', () {
    final line = _line();
    _go(line, 1200);
    final pen = line.brush.position;
    line.follow(pen, _rest, at: _sample * 61);
    final stood = line.follow(pen, _rest, at: _sample * 62).last;

    expect(stood.position, pen);
    expect(stood.readings.pressure, _rest.pressure);
  });

  test('🚨a corner kept is gone through, whatever is level with the pen', () {
    final line = StrokeStabilizer(
      lagAt: (_) => const Duration(milliseconds: 60),
      acrossOnly: _floor,
      keepsCorners: true,
      start: (position: CanvasPoint(x: 0, y: 0), readings: _rest),
      at: Duration.zero,
    );
    final way = <CanvasPoint>[];
    for (var i = 1; i <= 40; i += 1) {
      way.addAll(
        line
            .follow(CanvasPoint(x: i * 5.0, y: 0), _rest, at: _sample * i)
            .map((point) => point.position),
      );
    }
    for (var i = 1; i <= 40; i += 1) {
      way.addAll(
        line
            .follow(CanvasPoint(x: 200, y: i * 5.0), _rest, at: _sample * (40 + i))
            .map((point) => point.position),
      );
    }

    expect(
      way.map((point) => point.distanceTo(CanvasPoint(x: 200, y: 0))),
      contains(closeTo(0, 0.5)),
    );
  });

  test('samples that share a clock tell no way', () {
    final line = _line();
    final moved = line.follow(
      CanvasPoint(x: 100, y: 0),
      _rest,
      at: Duration.zero,
    );

    expect(moved.last.position.x, 0);

    final after = line.follow(CanvasPoint(x: 100, y: 0), _rest, at: _sample);
    expect(after.last.position.x, greaterThan(0));
  });

  test('🚨with no way told yet a frame still closes on the pen', () {
    final line = _line();
    line.follow(CanvasPoint(x: 100, y: 0), _rest, at: Duration.zero);

    line.lookAtFrame(Duration.zero);
    line.lookAtFrame(_sample);

    expect(line.brush.position.x, closeTo(100 * 0.647, 1));
  });

  test('🚨the readings come level with the line', () {
    final line = _line();
    _go(line, 1200);

    final pen = line.brush.position;
    final brush = line
        .follow(
          CanvasPoint(x: pen.x + 5, y: 0),
          (pressure: 0.9, lean: null, twist: null, speed: 0.0),
          at: _sample * 61,
        )
        .last;

    expect(brush.position.x, closeTo(pen.x + 5, 0.01));
    expect(brush.readings.pressure, closeTo(0.9, 0.01));
  });

  test('🚨they go as far as the line went, across it too', () {
    final line = _line();
    _go(line, 1200);

    final pen = line.brush.position;
    final brush = line
        .follow(
          CanvasPoint(x: pen.x + 5, y: 1),
          (pressure: 0.9, lean: null, twist: null, speed: 0.0),
          at: _sample * 61,
        )
        .last;

    expect(brush.position.y, inInclusiveRange(0.6, 0.8));
    expect(brush.readings.pressure, greaterThan(0.85));
  });
}
