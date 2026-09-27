import 'dart:math' as math;

/// HOW A PEN LEANS, as a dab carries it — and the one place where each
/// source's own words become it (desktop-pen-tilt, 2026-09-28).
///
/// `azimuthDegrees` is which way the pen's TOP leans, clockwise from +x: 0
/// is 3 o'clock and 90 is 6 o'clock — the Pointer Events `azimuthAngle`,
/// in degrees. `altitude` is how upright the pen stands as 0..1 of a right
/// angle: 1 vertical, 0 flat on the surface — `altitudeAngle ÷ π/2`.
///
/// 🚨FOUR SOURCES SPEAK THREE CONVENTIONS, and each converter below is the
/// whole of what its source means: the same pen held the same way reads the
/// same pair from all of them (`a_lean_reads_the_same_from_every_source_
/// test`). ↩️Before this file the pointer's orientation went into the dab
/// unconverted — a quarter turn off the convention the dab documents,
/// unseen because nothing reads azimuth yet.
typedef PenLean = ({double azimuthDegrees, double altitude});

/// Flutter's own pointer (iOS · Android): [tilt] in radians FROM VERTICAL,
/// and [orientation] the bearing the pen's TIP points, in radians clockwise
/// from up. iOS's engine hands `UITouch.azimuthAngle − π/2` (the top's
/// angle from +x, turned back a quarter), Android its `AXIS_ORIENTATION`
/// (`atan2(−sin tiltX, sin tiltY)`: up when the top leans toward the user).
/// The top leans a half turn round from the tip, and +x is a quarter turn
/// on from up.
PenLean penLeanFromPointer({
  required double tilt,
  required double orientation,
}) {
  final altitude = (1.0 - tilt.abs() / (math.pi / 2.0)).clamp(0.0, 1.0);
  final azimuth = orientation.isFinite
      ? orientation * 180.0 / math.pi + 90.0
      : 0.0;
  return (azimuthDegrees: azimuth % 360.0, altitude: altitude.toDouble());
}

/// The Pointer Events plane tilts, [x] and [y] in degrees from vertical
/// (−90..90: +x leans right, +y toward the user) — what a Windows pen's HID
/// report declares (X Tilt 0x3D, Y Tilt 0x3E: 「positive to the right of the
/// user」, 「towards the user」 in Microsoft's pen requirements) — through
/// the spec's own `tilt2spherical`.
///
/// ⚠️A PLANE TILT IS NOT A COMPONENT OF THE LEAN. Each is the pen's angle
/// inside its own vertical plane, so the two do not add as a vector: 45°
/// both ways stands the pen 35.3° up, where adding them would lay it at
/// 26.4° (WinPenKit #127 is that confusion, written down).
PenLean penLeanFromPlaneTilt({required double x, required double y}) {
  if (x.abs() >= 90.0 || y.abs() >= 90.0) {
    // Flat on the surface: the spec's altitude 0, and — the direction lost
    // with the lean — its azimuth 0.
    return (azimuthDegrees: 0.0, altitude: 0.0);
  }
  final tanX = math.tan(x * math.pi / 180.0);
  final tanY = math.tan(y * math.pi / 180.0);
  // Upright, the root is 0 and the quotient infinite: atan gives π/2.
  final altitude = math.atan(1.0 / math.sqrt(tanX * tanX + tanY * tanY));
  return (
    azimuthDegrees: (math.atan2(tanY, tanX) * 180.0 / math.pi) % 360.0,
    altitude: altitude / (math.pi / 2.0),
  );
}

/// AppKit's scaled tilt — `NSEvent.tilt`, −1..1 each way, what the macOS pen
/// ledger records.
///
/// ★±1 IS ±90°, AND +y IS THE TOP OF THE TABLET. Apple names no angle, and
/// its words for the sign read the other way round from what a Wacom sends.
/// The spec's implementations agree on both: Chromium scales by 90
/// (`lround(tilt.x * 90)`), and Firefox negated y to match Chromium, Qt and
/// Wacom's own diagnostic (Mozilla bug 1822714). ⚠️Qt scales by 60 instead
/// — the ±60° its own API promises — and would read a pen at its full lean
/// as a third of the way up where the browsers read it flat.
PenLean penLeanFromAppKitTilt({required double x, required double y}) =>
    penLeanFromPlaneTilt(x: x * 90.0, y: -y * 90.0);

/// Wintab's orientation: the pen top's compass [bearing] in degrees — 0
/// toward the top of the tablet, clockwise; GTK's port puts it as
/// 「Wintab's reference angle leads gdk's by 90 degrees」 — and [altitude] as
/// 0..1 of a right angle. The eraser end down reports the altitude
/// NEGATIVE; the pen leans no less for it, so its size is what is kept.
PenLean penLeanFromWintab({
  required double bearing,
  required double altitude,
}) => (
  azimuthDegrees: (bearing - 90.0) % 360.0,
  altitude: altitude.abs().clamp(0.0, 1.0).toDouble(),
);
