part of '../interactive_brush_edit_canvas_view.dart';

/// PRESSURE AND THE STAMP — a pointer's pressure normalised for the
/// device and applied to the dab's dynamics, and the masked stamp the
/// brush paints with — as their own object.
///
/// 🚨A collaborator carved out of `_InteractiveBrushEditCanvasViewState`
/// (the audit's SRP cut, 2026-09-02). It reaches the State through
/// `_state`.
class _BrushEditPressure {
  _BrushEditPressure(this._state);

  final _InteractiveBrushEditCanvasViewState _state;

  /// Where and when the previous reading landed, in CANVAS space — the two
  /// halves of a speed measurement. Null before a stroke's first sample, and
  /// again after [restInput], so the next stroke never measures its opening
  /// speed against where the last one stopped.
  CanvasPoint? _travelledFrom;
  Duration? _travelledAt;

  List<BrushDab> withPressureDynamics(List<BrushDab> dabs) {
    final settings =
        _state._activeStrokeInputSettings ?? _state.widget.inputSettings;
    if (!settings.hasPressureDynamics) {
      return dabs;
    }
    return <BrushDab>[
      for (final dab in dabs)
        applyBrushInputDynamics(dab, shape: settings.shape),
    ];
  }

  /// Normalizes a pointer's pressure into 0..1.
  ///
  /// Only stylus devices report meaningful pressure. A mouse claims a 0..1
  /// pressure range on some platforms while always reporting 0.0 — trusting
  /// it made pressure-sized strokes invisible — and touch pressure is
  /// unreliable across devices, so both paint at full pressure.
  ///
  /// Wintab sidecar (PEN-2): while the user has picked the Wintab tablet
  /// service and the driver stream is LIVE, the driver's pressure wins for
  /// EVERY kind — that is the point of the switch: a pen the OS pipeline
  /// misreports (touch, or mouse with Ink unchecked) paints with real
  /// pressure anyway. Stale/absent stream falls through unchanged.
  double normalizedPressure(PointerEvent event) {
    // The response curve (PEN-3) shapes REAL pressure from either source
    // — the full-pressure fallbacks stay 1.0 through any gamma.
    final wintab = PenSidecars.freshContactPressure();
    if (wintab != null) {
      return AppInput.applyPressureCurve(wintab);
    }
    if (event.kind != PointerDeviceKind.stylus &&
        event.kind != PointerDeviceKind.invertedStylus) {
      return 1.0;
    }
    final range = event.pressureMax - event.pressureMin;
    if (!range.isFinite || range <= 0.0) {
      return 1.0;
    }
    return AppInput.applyPressureCurve(
      ((event.pressure - event.pressureMin) / range).clamp(0.0, 1.0),
    );
  }

  /// Reads every input the next dab will carry off one pointer sample.
  ///
  /// 🚨ONE CALL, because pressure and tilt come off the SAME event and a
  /// dab that mixed one sample's pressure with another's lean would be a
  /// reading that never happened. Three call sites set pressure today; they
  /// all go through here so a fourth input cannot be added to two of them.
  void noteSample(PointerEvent event) {
    _state._currentPressure = normalizedPressure(event);
    final tilt = penTilt(event);
    _state._currentTiltAzimuthDegrees = tilt.azimuthDegrees;
    _state._currentTiltAltitude = tilt.altitude;
    _noteSpeed(event);
  }

  /// 速度 off the same event — the one input that needs TWO readings, so it
  /// is the one input this object has to remember anything for.
  ///
  /// ⚠️Canvas space, not screen space: the viewport transform is applied
  /// before the distance is taken, which is what makes the setting mean
  /// canvas px/s at every zoom.
  ///
  /// ⛔Raw, unsmoothed. Pro tools do smooth this, and nobody asked us to —
  /// a filter here would be a second tuning knob invented beside the one the
  /// user actually chose. If the reference speed turns out to feel noisy on
  /// device, that is the evidence a smoothing round would start from.
  void _noteSpeed(PointerEvent event) {
    final at = event.timeStamp;
    final position = _state._canvasPositionFromLocal(event.localPosition);
    final from = _travelledFrom;
    final since = _travelledAt;
    _travelledFrom = position;
    _travelledAt = at;
    if (from == null || since == null) {
      // A pen that has just landed has no move behind it.
      _state._currentSpeed = 0.0;
      return;
    }
    final measured = AppInput.normalizedSpeed(
      canvasPixels: from.distanceTo(position),
      elapsed: at - since,
    );
    // Null is "these two readings share a clock tick", not "stopped" — the
    // last real measurement stands rather than the stroke dropping to zero.
    if (measured != null) {
      _state._currentSpeed = measured;
    }
  }

  /// Returns every input to its resting value — an upright pen at full
  /// pressure, which is what a device that reports none draws with, standing
  /// still, with no earlier reading to measure the next move against.
  void restInput() {
    _state._currentPressure = 1.0;
    _state._currentTiltAzimuthDegrees = 0.0;
    _state._currentTiltAltitude = 1.0;
    _state._currentSpeed = 0.0;
    _travelledFrom = null;
    _travelledAt = null;
  }

  /// How the pen leans, as the pair a dab carries: degrees of azimuth and a
  /// 0..1 altitude (1 = upright).
  ///
  /// 🚨READ FROM THE POINTER, NOT THE SIDECAR — deliberately, and unlike
  /// pressure. `PenSidecars` exists because the OS pipeline MISREPORTS
  /// pressure for some pens (PEN-2); no such defect is known for tilt, and
  /// the sidecar does not surface it today (`qa_tablet_bridge` carries
  /// azimuth and altitude, but `PenSidecars` publishes only pressure,
  /// buttons and inverted). Routing tilt through the sidecar as well is a
  /// separate round with its own evidence.
  ///
  /// ⚠️Flutter reports tilt as radians FROM VERTICAL and orientation as
  /// radians around the pen's axis; the app speaks the tablet bridge's
  /// azimuth/altitude instead, so the conversion happens once, here.
  ({double azimuthDegrees, double altitude}) penTilt(PointerEvent event) {
    if (event.kind != PointerDeviceKind.stylus &&
        event.kind != PointerDeviceKind.invertedStylus) {
      return (azimuthDegrees: 0.0, altitude: 1.0);
    }
    final tilt = event.tilt;
    if (!tilt.isFinite) {
      return (azimuthDegrees: 0.0, altitude: 1.0);
    }
    final altitude = (1.0 - tilt.abs() / (math.pi / 2.0)).clamp(0.0, 1.0);
    final orientation = event.orientation;
    final degrees = orientation.isFinite
        ? ((orientation * 180.0 / math.pi) % 360.0 + 360.0) % 360.0
        : 0.0;
    return (azimuthDegrees: degrees, altitude: altitude.toDouble());
  }

  /// [rgba] with the live selection applied, or [rgba] itself when there
  /// is no selection (no copy, no scan).
  Uint8List _maskedStampRgba({
    required Uint8List rgba,
    required int left,
    required int top,
    required int width,
    required int height,
    double opacity = 1.0,
  }) {
    final region = _state.widget.selectionRegion;
    if (region == null && opacity >= 1.0) {
      return rgba;
    }
    final masked = Uint8List.fromList(rgba);
    // TP1: the fill has an opacity now, and this preview does NOT go
    // through the pre-blend kernel (see the caller) — so the multiply the
    // commit will do has to be done here too, or a 50% fill previews at
    // 100% and lands at 50%. The commit's own expression is
    // `(stampA / 255) * dabOpacity`; scaling the alpha byte is that, in the
    // one place this path has to say it.
    if (opacity < 1.0) {
      for (var offset = 3; offset < masked.length; offset += 4) {
        masked[offset] = (masked[offset] * opacity).round().clamp(0, 255);
      }
    }
    if (region == null) {
      return masked;
    }
    // The same rule the pre-blend kernel and the commit's clip run — a
    // fill only reaches a different function, never a different rule.
    applySelectionMaskToStrokeAlpha(
      pixels: masked,
      mask: region.maskFor(left: left, top: top, width: width, height: height),
      pixelCount: width * height,
    );
    return masked;
  }
}
