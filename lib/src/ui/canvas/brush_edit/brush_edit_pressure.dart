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

  /// The raw force this contact's FIRST sample reported — what an iPad's
  /// stand-in repeats until the Pencil measures ([_isUIKitForceEstimate]).
  /// Taken afresh at every contact's first sample, which is what
  /// [_travelled] being null marks.
  double? _pressedForce;

  /// Whether a driver-side stream has said the pen is TOUCHING in this
  /// contact — what makes its later untouching reading the pen LIFTING,
  /// rather than a stream that never reached the contact (see
  /// [pressureOf]). Forgotten at every contact's first sample, as
  /// [_pressedForce] is taken.
  bool _sidecarTouched = false;

  List<BrushDab> withPressureDynamics(List<BrushDab> dabs) {
    final settings =
        _state._activeStrokeInputSettings ?? _state.widget.inputSettings();
    if (!settings.hasPressureDynamics) {
      return dabs;
    }
    return <BrushDab>[
      for (final dab in dabs)
        applyBrushInputDynamics(
          dab,
          shape: settings.shape,
          random: _state._inputRandom,
        ),
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
  /// * the STAND-IN a Pencil's first samples carry — the force the contact
  ///   pressed with, repeated until the Pencil measures, and wherever it
  ///   comes back ([_isUIKitForceEstimate]);
  /// * a driver packet that says the pen is HOVERING before the stream has
  ///   said it touched in this contact. Once it has ([_sidecarTouched]),
  ///   the same packet means the pen has lifted, and 0 is the reading.
  ///   Until then the pointer's own word stands in: a stylus's is itself a
  ///   reading of this contact, and a mouse's or a finger's full pressure
  ///   is only a reading when no sidecar is left to read the pen it might
  ///   be.
  ///
  /// 🚨A STREAM THAT NEVER TOUCHED IS NOT THE PEN LIFTING (F-331, 유저
  /// 2026-10-10: 「필압이 인식이 안된다면 마우스랑 동일하게 필압1인채로
  /// 그리거나 하는데 그게 안되있음」). ↩️It was 「once the CONTACT has
  /// read」: a stylus that opened with its own reading took a stream that
  /// had not reached the contact for the pen lifting, and laid the rest of
  /// its stroke at 0 — however long the stream never reached it.
  ///
  /// The stroke waits for a reading instead of painting a stand-in (see
  /// `_BrushEditStroke.takeSample`).
  ///
  /// ★THE SAMPLE'S OWN RECORD COMES FIRST (유저 2026-09-27: 「근본
  /// 구조적으로 해결해줘」). Where the platform keeps one ([QaPenLedger] —
  /// UIKit's word on iOS, the NSEvent on macOS), it holds the value for
  /// THIS event with no race between a sidecar's queue and the pointer's,
  /// and a correction UIKit sends later reaches a sample that waited
  /// ([recordedPressure]).
  ///
  /// 🚨UIKIT'S ESTIMATE IS NOT THE STAND-IN (유저 2026-09-28, build 1065:
  /// 「전혀 안고쳐져있어」 — inspector 「measured 1 고정 · estimated 9 ·
  /// none 0」). UIKit calls nearly every Pencil sample's force an estimate.
  /// The second round waited for one it called measured, found one per
  /// stroke, and after the patience painted the stand-ins as before. An
  /// estimate is UIKit's best value and is READ; the stand-in is the press's
  /// force repeated, whatever UIKit calls it.
  ({double pressure, bool read}) pressureOf(PointerEvent event) {
    final recorded = QaPenLedger.forceAt(event.timeStamp);
    if (QaPenLedger.start()) {
      _ledgerAnswers[event.timeStamp] = recorded?.state;
    }
    final repeat = _isUIKitForceEstimate(event);
    if (repeat) {
      _heldRepeats[event.timeStamp] = recorded?.state;
    }
    if (recorded != null) {
      return switch (recorded.state) {
        PenLedgerState.measured => (
          pressure: AppInput.applyPressureCurve(
            _platformPressure(recorded.value),
          ),
          read: !repeat,
        ),
        PenLedgerState.estimated || PenLedgerState.estimatedFinal => (
          pressure: AppInput.applyPressureCurve(_uikitForce(event.pressure)),
          read: !repeat,
        ),
        PenLedgerState.noPressure => (pressure: 1.0, read: true),
      };
    }
    // The response curve (PEN-3) shapes REAL pressure from either source
    // — the full-pressure fallbacks stay 1.0 through any gamma.
    final sidecar = PenSidecars.freshReading();
    if (sidecar != null && sidecar.touching) {
      _sidecarTouched = true;
    }
    if (sidecar != null && _sidecarTouched) {
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
      pressure: AppInput.applyPressureCurve(_normalized(event, range)),
      read: !repeat,
    );
  }

  /// A measuring stylus's pressure as 0..1.
  ///
  /// 🗣️iPad — UIKit's force in APPLE'S OWN UNIT, halved (유저 2026-09-27,
  /// `ipad-pencil-pressure-scale-Q1`: 「Apple 기준으로 — 평균 터치(1.0)를
  /// 절반으로」). `UITouch.force` 1.0 is the force of an average touch, so
  /// the average hand lands mid-curve and twice that is the top of it.
  /// Divided by `maximumPossibleForce` (≈4.17) as every other platform's
  /// range is, ordinary writing sat near 0.24 and the top of a curve was
  /// out of reach. Everywhere else the range the device reports IS the
  /// pen's travel.
  static double _normalized(PointerEvent event, double range) =>
      defaultTargetPlatform == TargetPlatform.iOS
          ? _uikitForce(event.pressure)
          : ((event.pressure - event.pressureMin) / range).clamp(0.0, 1.0);

  /// A UIKit force as 0..1 — the unit [_normalized] explains.
  static double _uikitForce(double force) =>
      (force / _fullPressureForce).clamp(0.0, 1.0);

  /// The UIKit force that is full pressure: twice the average touch.
  static const double _fullPressureForce = 2.0;

  /// A value the pen ledger recorded as 0..1: UIKit force on iOS, and the
  /// NSEvent's own 0..1 pressure on macOS.
  static double _platformPressure(double value) =>
      defaultTargetPlatform == TargetPlatform.iOS
          ? _uikitForce(value)
          : value.clamp(0.0, 1.0);

  /// The pressure the platform has by now MEASURED for the sample stamped
  /// [at] — on iOS the force UIKit sent after the fact — or null when the
  /// ledger holds no measurement of it. What a sample that waited is
  /// painted with when it has one of its own.
  double? recordedPressure(Duration at) {
    if (_heldRepeats[at] == PenLedgerState.measured) {
      return null;
    }
    final recorded = QaPenLedger.forceAt(at);
    if (recorded == null || recorded.state != PenLedgerState.measured) {
      return null;
    }
    return AppInput.applyPressureCurve(_platformPressure(recorded.value));
  }

  /// What the pen ledger answered for each of this contact's samples when
  /// it was asked — null for one it held nothing for.
  final Map<Duration, PenLedgerState?> _ledgerAnswers = {};

  /// This contact's samples held as the press repeated, each with what the
  /// ledger called it then (null where none answered) — the inspector's
  /// `rep`. One the ledger called MEASURED has the stand-in for its record,
  /// so it is painted with the first reading after it, never with its
  /// record ([recordedPressure]). Emptied when a contact begins.
  final Map<Duration, PenLedgerState?> _heldRepeats = {};

  /// How this contact's samples leaned: how many there were, how many read
  /// a lean, and the lowest and highest altitude among those.
  var _leanTally = _noLean;

  static const _noLean = (samples: 0, leaned: 0, low: 1.0, high: 0.0);

  /// Puts the contact that just ended on the input inspector — the `ledger`
  /// line where the platform keeps one, and the `lean` line — the one
  /// place a device shows whether the platform's word reached the brush —
  /// and starts counting afresh.
  ///
  /// ⚠️Called on the pointer event's own path (the stroke's end), never
  /// from teardown: a probe that notifies during build kills its own
  /// display (H21).
  void reportReadings() {
    final tally = _leanTally;
    if (tally.samples > 0) {
      InputInspector.note(
        tally.leaned == 0
            ? 'lean 0/${tally.samples}'
            : 'lean ${tally.leaned}/${tally.samples} '
                  'alt ${tally.low.toStringAsFixed(2)}'
                  '–${tally.high.toStringAsFixed(2)}',
      );
      _leanTally = _noLean;
    }
    if (_ledgerAnswers.isEmpty) {
      return;
    }
    int count(PenLedgerState? state) =>
        _ledgerAnswers.values.where((answer) => answer == state).length;
    // The estimates the ledger holds MEASURED by now: whether UIKit's
    // corrections reach it at all.
    final corrected = _ledgerAnswers.entries
        .where(
          (answer) =>
              (answer.value == PenLedgerState.estimated ||
                  answer.value == PenLedgerState.estimatedFinal) &&
              QaPenLedger.forceAt(answer.key)?.state ==
                  PenLedgerState.measured,
        )
        .length;
    // Short names: a note row is one line, and the card is narrow.
    InputInspector.note(
      'ledger meas=${count(PenLedgerState.measured)} '
      'est=${count(PenLedgerState.estimated)} '
      'fin=${count(PenLedgerState.estimatedFinal)} '
      'upd=$corrected '
      'rep=${_heldRepeats.length} '
      'none=${count(PenLedgerState.noPressure) + count(null)}',
    );
    _ledgerAnswers.clear();
  }

  /// 🚨UIKIT'S STAND-IN FORCE. Apple Pencil's force travels over Bluetooth
  /// and lands after the touch does, so UIKit reports an ESTIMATE for the
  /// first samples of a contact and sends the measured value later through
  /// `touchesEstimatedPropertiesUpdated` — which Flutter's engine does not
  /// implement (its iOS view controller, checked 2026-09-26 on 3.47). The
  /// estimate is therefore all this app ever sees for those samples.
  ///
  /// ★IT IS KNOWN BY WHAT IT DOES, NOT BY WHAT IT IS: the estimate is a
  /// CONSTANT — Apple Developer Forums 26830, 「constant placeholder
  /// pressure value (moderately large value, 0.33)」, the source of the
  /// high-pressure blobs at the start of strokes in Procreate, OneNote and
  /// Notability — so it is the force the contact PRESSED with, repeated,
  /// and the first force that differs is the first the Pencil measured.
  ///
  /// 🔬The value alone did not hold: a test for exactly 1/3 (the figure
  /// logged in threads 96700 and 734203) shipped in build 1064 and did not
  /// catch it. 유저 2026-09-27 on that build, inspector rows for one light
  /// stroke: 「펜 다운 0.33이 1개, 펜 무브 0.33이 3개, 무브 0.16 1개, 무브
  /// 0.0 1개, 업 0.0 1개」 — the press and three moves repeated one force,
  /// then the Pencil measured.
  ///
  /// ↩️It was the FALLBACK — asked only where no ledger answered — until
  /// build 1065 showed UIKit's word missing the stand-in (see [pressureOf]).
  /// It is asked of every sample now, whatever the ledger says.
  bool _isUIKitForceEstimate(PointerEvent event) =>
      defaultTargetPlatform == TargetPlatform.iOS &&
      event.pressure == _pressedForce;

  /// Reads every input the next dab will carry off one pointer sample, and
  /// answers which of them the sample READ: its pressure ([pressureOf]) and
  /// its speed ([_noteSpeed]). Its lean ([tiltOf]) is always read. [opening]
  /// says the contact has not read a pressure yet.
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
  ({bool pressure, bool speed}) noteSample(
    PointerEvent event, {
    required bool opening,
  }) {
    if (_travelled == null) {
      _pressedForce = event.pressure;
      _sidecarTouched = false;
      _heldRepeats.clear();
    }
    final pressure = pressureOf(event);
    if (pressure.read || opening) {
      _state._currentPressure = pressure.pressure;
    }
    // ⚠️ONE FIELD for the tilt READING, because azimuth without altitude is a
    // lean in a direction nothing reported — and `BrushDab` refuses that pair
    // outright. The same shape as `_travelled` below, and for the same reason.
    final lean = tiltOf(event);
    _state._currentTilt = lean;
    _state._currentTwist = penTwist();
    final tally = _leanTally;
    _leanTally = lean == null
        ? (
            samples: tally.samples + 1,
            leaned: tally.leaned,
            low: tally.low,
            high: tally.high,
          )
        : (
            samples: tally.samples + 1,
            leaned: tally.leaned + 1,
            low: math.min(tally.low, lean.altitude),
            high: math.max(tally.high, lean.altitude),
          );
    return (pressure: pressure.read, speed: _noteSpeed(event));
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
  ///
  /// Answers whether this sample MEASURED a speed.
  bool _noteSpeed(PointerEvent event) {
    final at = event.timeStamp;
    final position = _state._canvasPositionFromLocal(event.localPosition);
    final previous = _travelled;
    _travelled = (at: position, when: at);
    if (previous == null) {
      // A pen that has just landed has no move behind it: standing still is
      // only what stands in until the first move measures (유저 2026-09-27,
      // `opening-dab-speed-Q1`: 「첫 이동의 속도로 — 필압과 같은 법」).
      _state._currentSpeed = 0.0;
      return false;
    }
    final measured = AppInput.normalizedSpeed(
      canvasPixels: previous.at.distanceTo(position),
      elapsed: at - previous.when,
    );
    // Null is "these two readings share a clock tick", not "stopped" — the
    // last real measurement stands rather than the stroke dropping to zero.
    if (measured == null) {
      return false;
    }
    _state._currentSpeed = measured;
    return true;
  }

  /// Returns every input to its resting value — full pressure, NO tilt
  /// reported (which is what a mouse says, and is not the same as an upright
  /// pen), standing still, with no earlier reading to measure against.
  void restInput() {
    _state._currentPressure = 1.0;
    _state._currentSpeed = 0.0;
    _travelled = null;
  }

  /// How the pen leans, as the pair a dab carries ([PenLean]) — or null
  /// where nothing measured one.
  ///
  /// ★FROM WHOEVER CARRIES THE LEAN FOR THIS EVENT (desktop-pen-tilt,
  /// 2026-09-28): the pointer on iOS and Android; on a desktop, whose
  /// pointer carries none ([_pointerCarriesTilt]), the platform's own
  /// record — the NSEvent's, through the pen ledger, on macOS, and the
  /// driver's, through the sidecars, on Windows. Each speaks its own
  /// convention, and `pen_lean.dart` is the one place they become one.
  /// ↩️This used to read the pointer alone, 「deliberately, and unlike
  /// pressure」, because no defect in tilt was known: the defect was that a
  /// desktop pointer has no tilt to read.
  ///
  /// 🚨NULL WHEN THE DEVICE REPORTED NONE — it used to answer "upright pen"
  /// (altitude 1.0), which is a reading a mouse never made. 유저 2026-09-09,
  /// `brush-tilt-no-device-Q1` 답 1: 「기울기 못 재는 기기에서는 傾き 소스를
  /// 건너뛴다」 (「1번이 구조적으로 맞아보여서」). With the invented value, an
  /// imported brush whose tilt minimum is 0% drew nothing at all on a mouse
  /// and nothing on screen could say why.
  PenLean? penTilt(PointerEvent event) {
    if (!_pointerCarriesTilt) {
      final appKit = QaPenLedger.tiltAt(event.timeStamp);
      if (appKit != null) {
        return penLeanFromAppKitTilt(x: appKit.x, y: appKit.y);
      }
      return PenSidecars.freshLean();
    }
    if (event.kind != PointerDeviceKind.stylus &&
        event.kind != PointerDeviceKind.invertedStylus) {
      return null;
    }
    final tilt = event.tilt;
    if (!tilt.isFinite) {
      return null;
    }
    return penLeanFromPointer(tilt: tilt, orientation: event.orientation);
  }

  /// 🚨WHERE THE POINTER CARRIES NO LEAN AT ALL (checked 2026-09-27 on
  /// 3.47). Flutter's desktop embedder API has no tilt field: Windows reads
  /// POINTER_PEN_INFO's pressure and rotation and drops tiltX/tiltY, and
  /// macOS and Linux never see a pen. There a 0 is the field's default, not
  /// a pen held upright — the invented reading `brush-tilt-no-device-Q1`
  /// ruled out. Only iOS (UITouch's altitude) and Android (AXIS_TILT) carry
  /// the lean; everywhere else [penTilt] asks the platform's own record.
  /// How far the pen is turned about its own barrel, in degrees 0..360
  /// clockwise — null where nothing measured one (F-176-Q9, Clip Studio's
  /// ペン軸の回転).
  ///
  /// Only Windows' driver-side streams carry it ([PenSidecars.freshTwist]).
  /// Flutter's pointer has no field for it on any platform — the Windows
  /// embedder reads POINTER_PEN_INFO's rotation into a pan-zoom field that
  /// a pen's event never shows — and the macOS pen ledger records no
  /// rotation yet, so everywhere else this is null: the twist base turns
  /// nothing there, as 없음 does.
  double? penTwist() =>
      _pointerCarriesTilt ? null : PenSidecars.freshTwist();

  static bool get _pointerCarriesTilt =>
      defaultTargetPlatform == TargetPlatform.iOS ||
      defaultTargetPlatform == TargetPlatform.android;

  /// How the pen leans for this sample ([penTilt]) — every sample's lean is
  /// a reading. Where the ledger holds UIKit's measurement of the Pencil's
  /// altitude, that is the altitude.
  ///
  /// ↩️An altitude UIKit called an estimate used to WAIT, as its force did
  /// (H43 round two). Build 1065 showed UIKit calling nearly every sample's
  /// force an estimate, and the lean crosses the same Bluetooth link: a tilt
  /// brush would have waited the whole patience on every stroke. The
  /// estimate is UIKit's best value, so it is read — pressure's law, which
  /// holds only the press repeated (see [pressureOf]).
  PenLean? tiltOf(PointerEvent event) {
    final own = penTilt(event);
    final recorded = own == null
        ? null
        : QaPenLedger.altitudeAt(event.timeStamp);
    if (own == null || recorded?.state != PenLedgerState.measured) {
      return own;
    }
    return (
      azimuthDegrees: own.azimuthDegrees,
      altitude: _altitudeFrom(recorded!.value),
    );
  }

  /// The lean the platform has by now MEASURED for the sample stamped [at]
  /// — UIKit's altitude sent after the fact, with the sample's own
  /// [azimuthDegrees] — or null when the ledger holds no measurement of it.
  PenLean? recordedTilt(Duration at, double azimuthDegrees) {
    final recorded = QaPenLedger.altitudeAt(at);
    if (recorded == null || recorded.state != PenLedgerState.measured) {
      return null;
    }
    return (
      azimuthDegrees: azimuthDegrees,
      altitude: _altitudeFrom(recorded.value),
    );
  }

  /// UIKit's altitude (radians up from the surface) as the dab's 0..1.
  static double _altitudeFrom(double radians) =>
      (radians / (math.pi / 2.0)).clamp(0.0, 1.0);
}
