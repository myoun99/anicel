// 「기울기 못 재는 기기에서는 傾き 소스를 건너뛴다」 — 유저 2026-09-09,
// `brush-tilt-no-device-Q1` 답 1 (「1번이 구조적으로 맞아보여서」).
//
// A mouse and a pen held perfectly upright used to arrive as the SAME number,
// altitude 1.0, because the pen door invented that value for every device
// that reported nothing. An imported Clip Studio brush whose 傾き minimum is
// 0% therefore drew NOTHING on a mouse, and nothing on screen could say why.
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/brush_dab.dart';
import 'package:anicel/src/models/brush_input_source.dart';
import 'package:anicel/src/models/brush_pressure_curve.dart';
import 'package:anicel/src/models/brush_shape.dart';
import 'package:anicel/src/models/brush_tip_shape.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/services/brush_pressure_dynamics.dart';

void main() {
  BrushDab dab({double? tiltAltitude}) => BrushDab(
    center: CanvasPoint(x: 1, y: 1),
    color: 0xFF000000,
    size: 10,
    opacity: 1,
    flow: 1,
    hardness: 1,
    tipShape: BrushTipShape.round,
    pressure: 1,
    tiltAltitude: tiltAltitude,
    sequence: 0,
  );

  // The shape a real import produces: 傾き drives size from a 0% floor.
  final leanDrivesSize = const BrushShape().withCurve(
    BrushPressureTarget.size,
    BrushInputSource.tilt,
    BrushPressureCurve.linearFrom(0.0),
  );

  test('🚨a device that reported NO tilt draws at the base size', () {
    // The whole answer: the source is SKIPPED, so it contributes exactly 1.0.
    expect(
      applyBrushInputDynamics(dab(), shape: leanDrivesSize).size,
      10.0,
    );
    expect(brushInputValue(dab(), BrushInputSource.tilt), isNull);
  });

  test('an UPRIGHT pen is still the curve floor — the two are not the same', () {
    // ⛔This is the half that must not be lost while fixing the other: a pen
    // the device DID measure, standing straight up, leans 0.0 and lands on the
    // floor. If this went green at 10.0 too, the fix would have thrown the
    // tilt response away instead of separating the two cases.
    expect(
      applyBrushInputDynamics(
        dab(tiltAltitude: 1.0),
        shape: leanDrivesSize,
      ).size,
      0.0,
    );
    expect(brushInputValue(dab(tiltAltitude: 1.0), BrushInputSource.tilt), 0.0);
  });

  test('a pen laid flat is still full lean', () {
    expect(
      brushInputValue(dab(tiltAltitude: 0.0), BrushInputSource.tilt),
      1.0,
    );
  });

  test('⛔a lean with no altitude cannot be built at all', () {
    // One reading of two numbers has ONE way to be absent. Azimuth without
    // altitude would be a direction nothing reported — a second spelling of
    // "no tilt", which is exactly how a mutation walked out of the speed
    // round untouched.
    expect(
      () => BrushDab(
        center: CanvasPoint(x: 1, y: 1),
        color: 0xFF000000,
        size: 10,
        opacity: 1,
        flow: 1,
        hardness: 1,
        tipShape: BrushTipShape.round,
        pressure: 1,
        tiltAzimuthDegrees: 45,
        sequence: 0,
      ),
      throwsArgumentError,
    );
  });

  test('absence round-trips through json as an ABSENT key', () {
    final json = dab().toJson();
    expect(json.containsKey('tiltAltitude'), isFalse);
    expect(BrushDab.fromJson(json).tiltAltitude, isNull);

    // ...and a measured upright pen keeps its number.
    final measured = dab(tiltAltitude: 1.0).toJson();
    expect(measured['tiltAltitude'], 1.0);
    expect(BrushDab.fromJson(measured).tiltAltitude, 1.0);
  });
}
