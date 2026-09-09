import 'dart:math' as math;

import '../models/brush_dab.dart';
import '../models/canvas_point.dart';

/// Lightweight Brush T2 dab spacing/interpolation.
///
/// This keeps input sampling independent from Flutter pointer types. The spacing
/// interval is based on the materialized brush size and editor-session spacing
/// ratio, clamped to at least one canvas unit to prevent excessive dab counts.
class BrushDabInterpolator {
  const BrushDabInterpolator();

  double spacingForBrushSize(double brushSize, double spacingRatio) {
    if (!brushSize.isFinite || brushSize <= 0 || !spacingRatio.isFinite) {
      return 1.0;
    }
    return math.max(1.0, brushSize * spacingRatio);
  }

  List<BrushDab> interpolate({
    required BrushDab? previous,
    required BrushDab nextRaw,
    required int firstSequence,
    double spacingRatio = 0.25,
  }) {
    if (previous == null) {
      return [nextRaw.copyWith(sequence: firstSequence)];
    }

    final spacing = spacingForBrushSize(nextRaw.size, spacingRatio);
    final distance = previous.center.distanceTo(nextRaw.center);
    if (distance < spacing) {
      return const <BrushDab>[];
    }

    final stepCount = math.max(1, (distance / spacing).ceil());
    final previousPressure = previous.pressure;
    final pressureDelta = nextRaw.pressure - previousPressure;
    // ⚠️Both ends have to have REPORTED a tilt for the ramp to mean anything.
    // Within one stroke they always agree — the device does not change
    // mid-stroke — so the null arm is the whole no-tilt-device case, and it
    // carries absence forward rather than inventing an upright pen.
    final previousAltitude = previous.tiltAltitude;
    final nextAltitude = nextRaw.tiltAltitude;
    final altitudeDelta = (previousAltitude == null || nextAltitude == null)
        ? null
        : nextAltitude - previousAltitude;
    return List<BrushDab>.generate(stepCount, (index) {
      final fraction = (index + 1) / stepCount;
      return nextRaw.copyWith(
        center: CanvasPoint.lerp(previous.center, nextRaw.center, fraction),
        // Interpolate pressure along the segment so pressure-driven size or
        // opacity ramps smoothly between input samples instead of snapping
        // to the endpoint value on every inserted dab.
        pressure: previousPressure + pressureDelta * fraction,
        // 🚨AND THE LEAN, for exactly the same reason. This was pressure-only
        // until 速度 sent someone through both interpolators: the tilt round
        // made 傾き drive the curves but never reached the LIVE one, so every
        // dab between two pointer readings wore the endpoint's lean and a
        // tilt brush stepped instead of ramping. The pin that would have said
        // so was watching `brushInputSamplesToBrushDabs`, which nothing in
        // `lib/` calls.
        //
        // ⛔Azimuth is deliberately left riding along from `nextRaw`: nothing
        // reads it yet, and its lerp has to go the SHORT way round the circle
        // (350° to 10° is twenty degrees forward, not 340 back). The round
        // that gives it a reader is the one that shares that helper.
        tiltAltitude: altitudeDelta == null
            ? nextAltitude
            : previousAltitude! + altitudeDelta * fraction,
        // ⛔SPEED IS DELIBERATELY NOT INTERPOLATED, and it is not an
        // oversight to fix: it rides along from `nextRaw` because it is a
        // property of the MOVE this call is subdividing. Every dab here was
        // laid during the one hand movement that carried the pen from
        // `previous` to `nextRaw`, so they all travelled at its speed.
        sequence: firstSequence + index,
      );
    });
  }
}
