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

  /// Where and when the previous reading landed, in CANVAS space — the far
  /// end of the next speed measurement. Null before a stroke's first sample,
  /// and again after [restInput], so the next stroke never measures its
  /// opening speed against where the last one stopped.
  ///
  /// 🚨ONE FIELD, NOT A POINT AND A TIME SIDE BY SIDE. As two nullable
  /// fields, clearing either one already answered "no previous reading", so
  /// deleting one of the two resets changed nothing and a mutation walked
  /// through the pin that guards it. There is one fact here; it gets one
  /// place to be absent.
  ({CanvasPoint at, Duration when})? _travelled;

  List<BrushDab> withPressureDynamics(List<BrushDab> dabs) {
    final settings =
        _state._activeStrokeInputSettings ?? _state.widget.inputSettings();
    if (!settings.hasPressureDynamics) {
      return dabs;
    }
    return <BrushDab>[
      for (final dab in dabs)
        applyBrushInputDynamics(dab, shape: settings.shape),
    ];
  }

  /// A pointer's pressure normalized into 0..1 — and whether it READ this
  /// contact, or is only what the device put in the reading's place.
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
  ///
  /// 🚨NOT A READING (H43, 유저 2026-09-26: 「필압있는 브러시 쓸때 첫
  /// 펜다운한 부분? 만 입력한 필압보다 센게나와」) — what the device hands
  /// over in place of a pressure it has not measured yet:
  ///
  /// * UIKit's force ESTIMATE ([_isUIKitForceEstimate]);
  /// * a driver packet taken while the pen was still HOVERING, asked for
  ///   the [opening] of a contact. Once the contact has read, the same
  ///   packet means the pen has lifted, and 0 is the reading. Until then
  ///   the pointer's own word stands in: a stylus's is itself a reading of
  ///   this contact, and a mouse's or a finger's full pressure is only a
  ///   reading when no sidecar is left to read the pen it might be.
  ///
  /// The stroke waits for a reading instead of painting a stand-in (see
  /// `_BrushEditStroke.takeSample`).
  ({double pressure, bool read}) pressureOf(
    PointerEvent event, {
    required bool opening,
  }) {
    // The response curve (PEN-3) shapes REAL pressure from either source
    // — the full-pressure fallbacks stay 1.0 through any gamma.
    final sidecar = PenSidecars.freshReading();
    if (sidecar != null && (sidecar.touching || !opening)) {
      return (
        pressure: AppInput.applyPressureCurve(sidecar.pressure),
        read: true,
      );
    }
    final range = event.pressureMax - event.pressureMin;
    final measures =
        (event.kind == PointerDeviceKind.stylus ||
            event.kind == PointerDeviceKind.invertedStylus) &&
        range.isFinite &&
        range > 0.0;
    if (!measures) {
      return (pressure: 1.0, read: sidecar == null);
    }
    return (
      pressure: AppInput.applyPressureCurve(
        ((event.pressure - event.pressureMin) / range).clamp(0.0, 1.0),
      ),
      read: !_isUIKitForceEstimate(event),
    );
  }

  /// 🚨UIKIT'S STAND-IN FORCE. Apple Pencil's force travels over Bluetooth
  /// and lands after the touch does, so UIKit reports an ESTIMATE for the
  /// first samples of a contact and sends the measured value later through
  /// `touchesEstimatedPropertiesUpdated` — which Flutter's engine does not
  /// implement (its iOS view controller, checked 2026-09-26 on 3.47). The
  /// estimate is therefore all this app ever sees for those samples.
  ///
  /// Developers who logged it found exactly 1/3, whatever the pressure and
  /// whatever the device: Apple Developer Forums thread 96700 (2018, a CSV
  /// of five strokes, the first 2–7 coalesced points of each) and 734203
  /// (2023, iPad Pro M2 + Apple Pencil 2, the first 2–6 touches). A sensor
  /// reading does not land within a millionth of 1/3 by chance.
  static bool _isUIKitForceEstimate(PointerEvent event) =>
      defaultTargetPlatform == TargetPlatform.iOS &&
      (event.pressure - 1.0 / 3.0).abs() < 1e-6;

  /// Reads every input the next dab will carry off one pointer sample, and
  /// answers whether the sample READ this contact's pressure ([pressureOf]).
  ///
  /// 🚨ONE CALL, because pressure and tilt come off the SAME event and a
  /// dab that mixed one sample's pressure with another's lean would be a
  /// reading that never happened. Three call sites set pressure today; they
  /// all go through here so a fourth input cannot be added to two of them.
  ///
  /// A sample that did not read keeps the stroke's LAST reading once there
  /// is one — the rule speed already has for a sample it cannot measure.
  /// Before the first, the device's stand-in is kept as the value the
  /// sample lands with if no reading ever comes.
  bool noteSample(PointerEvent event, {required bool opening}) {
    final pressure = pressureOf(event, opening: opening);
    if (pressure.read || opening) {
      _state._currentPressure = pressure.pressure;
    }
    // ⚠️ONE FIELD for the tilt READING, because azimuth without altitude is a
    // lean in a direction nothing reported — and `BrushDab` refuses that pair
    // outright. The same shape as `_travelled` below, and for the same reason.
    _state._currentTilt = penTilt(event);
    _noteSpeed(event);
    return pressure.read;
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
    final previous = _travelled;
    _travelled = (at: position, when: at);
    if (previous == null) {
      // A pen that has just landed has no move behind it.
      _state._currentSpeed = 0.0;
      return;
    }
    final measured = AppInput.normalizedSpeed(
      canvasPixels: previous.at.distanceTo(position),
      elapsed: at - previous.when,
    );
    // Null is "these two readings share a clock tick", not "stopped" — the
    // last real measurement stands rather than the stroke dropping to zero.
    if (measured != null) {
      _state._currentSpeed = measured;
    }
  }

  /// Returns every input to its resting value — full pressure, NO tilt
  /// reported (which is what a mouse says, and is not the same as an upright
  /// pen), standing still, with no earlier reading to measure against.
  void restInput() {
    _state._currentPressure = 1.0;
    _state._currentSpeed = 0.0;
    _travelled = null;
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
  /// 🚨NULL WHEN THE DEVICE REPORTED NONE — it used to answer "upright pen"
  /// (altitude 1.0), which is a reading a mouse never made. 유저 2026-09-09,
  /// `brush-tilt-no-device-Q1` 답 1: 「기울기 못 재는 기기에서는 傾き 소스를
  /// 건너뛴다」 (「1번이 구조적으로 맞아보여서」). With the invented value, an
  /// imported brush whose tilt minimum is 0% drew nothing at all on a mouse
  /// and nothing on screen could say why.
  ({double azimuthDegrees, double altitude})? penTilt(PointerEvent event) {
    if (event.kind != PointerDeviceKind.stylus &&
        event.kind != PointerDeviceKind.invertedStylus) {
      return null;
    }
    final tilt = event.tilt;
    if (!tilt.isFinite) {
      return null;
    }
    final altitude = (1.0 - tilt.abs() / (math.pi / 2.0)).clamp(0.0, 1.0);
    final orientation = event.orientation;
    final degrees = orientation.isFinite
        ? ((orientation * 180.0 / math.pi) % 360.0 + 360.0) % 360.0
        : 0.0;
    return (azimuthDegrees: degrees, altitude: altitude.toDouble());
  }
}
