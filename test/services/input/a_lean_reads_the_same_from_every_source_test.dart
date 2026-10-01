import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/services/input/pen_lean.dart';

/// desktop-pen-tilt: four sources say how a pen leans in three conventions,
/// and `pen_lean.dart` is where each becomes the pair a dab carries.
///
/// 🚨THE SAME PEN, THE SAME ANSWER. Every source is handed the one pen —
/// its top leaning right, then toward the user, 30° from vertical — in its
/// own words, and all of them must read it back alike. A converter that
/// only agreed with itself would pass a test of its own formula.
void main() {
  Matcher lean(double azimuthDegrees, double altitude) => isA<PenLean>()
      .having(
        (lean) => lean.azimuthDegrees,
        'azimuthDegrees',
        closeTo(azimuthDegrees, 1e-9),
      )
      .having((lean) => lean.altitude, 'altitude', closeTo(altitude, 1e-9));

  double radians(double degrees) => degrees * math.pi / 180.0;

  // 30° from vertical is 60° up: two thirds of a right angle.
  const upright = 2.0 / 3.0;

  test('🚨a pen whose top leans RIGHT reads the same from every source', () {
    final right = lean(0, upright);
    // Flutter: the TIP points left — a quarter turn back from up.
    expect(
      penLeanFromPointer(tilt: radians(30), orientation: radians(-90)),
      right,
    );
    expect(penLeanFromPlaneTilt(x: 30, y: 0), right);
    expect(penLeanFromAppKitTilt(x: 30 / 90, y: 0), right);
    // Wintab: the top's bearing is east.
    expect(penLeanFromWintab(bearing: 90, altitude: upright), right);
  });

  test('🚨a pen whose top leans TOWARD THE USER reads the same from every '
      'source', () {
    final towardTheUser = lean(90, upright);
    // Flutter: the tip points up, away from the user.
    expect(
      penLeanFromPointer(tilt: radians(30), orientation: 0),
      towardTheUser,
    );
    expect(penLeanFromPlaneTilt(x: 0, y: 30), towardTheUser);
    // AppKit counts +y toward the top of the tablet.
    expect(penLeanFromAppKitTilt(x: 0, y: -30 / 90), towardTheUser);
    // Wintab: the top's bearing is south.
    expect(penLeanFromWintab(bearing: 180, altitude: upright), towardTheUser);
  });

  test('the other two ways round, from the spec\'s own tilts', () {
    expect(penLeanFromPlaneTilt(x: -30, y: 0), lean(180, upright));
    expect(penLeanFromPlaneTilt(x: 0, y: -30), lean(270, upright));
  });

  test('a pen held upright stands at 1', () {
    expect(penLeanFromPlaneTilt(x: 0, y: 0), lean(0, 1));
    expect(penLeanFromPointer(tilt: 0, orientation: 0).altitude, 1.0);
    expect(penLeanFromAppKitTilt(x: 0, y: 0), lean(0, 1));
  });

  test('⚠️plane tilts are not a vector: 45° both ways stands the pen 35.3° '
      'up, not 26.4°', () {
    final both = penLeanFromPlaneTilt(x: 45, y: 45);
    expect(both.azimuthDegrees, closeTo(45, 1e-9));
    expect(
      both.altitude * 90.0,
      closeTo(math.atan(1 / math.sqrt(2)) * 180 / math.pi, 1e-9),
    );
    expect(both.altitude * 90.0, closeTo(35.26, 0.01));
  });

  test('a plane tilt of 90 lies flat, with the direction lost along with '
      'the lean', () {
    expect(penLeanFromPlaneTilt(x: 90, y: 20), lean(0, 0));
    expect(penLeanFromPlaneTilt(x: 10, y: -90), lean(0, 0));
    expect(penLeanFromAppKitTilt(x: -1, y: 0), lean(0, 0));
  });

  test('Wintab\'s eraser end reports its altitude negative — the lean is '
      'the same', () {
    expect(
      penLeanFromWintab(bearing: 90, altitude: -upright),
      lean(0, upright),
    );
  });

  test('an azimuth is always read inside one turn', () {
    expect(
      penLeanFromPointer(tilt: 0.5, orientation: radians(-170)).azimuthDegrees,
      closeTo(280, 1e-9),
    );
    expect(penLeanFromWintab(bearing: 0, altitude: 1).azimuthDegrees, 270);
    expect(
      penLeanFromPlaneTilt(x: -10, y: -10).azimuthDegrees,
      closeTo(225, 1e-9),
    );
  });

  test('a pointer with no orientation leans nowhere in particular', () {
    expect(
      penLeanFromPointer(tilt: 0.3, orientation: double.nan).azimuthDegrees,
      0.0,
    );
  });
}
