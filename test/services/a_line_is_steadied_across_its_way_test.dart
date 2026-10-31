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

  test('samples that share a clock tell no way', () {
    final line = _line();
    final moved = line.follow(
      CanvasPoint(x: 100, y: 0),
      _rest,
      at: Duration.zero,
    );

    expect(moved.last.position.x, 0);
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
}
