part of '../interactive_brush_edit_canvas_view.dart';

/// THE OPENING of a stroke — what its contact has read so far, and the
/// samples it holds until it has read what its brush draws with — as its
/// own object.
///
/// 🚨A collaborator carved out of [_BrushEditStroke] (2026-09-27): the wait
/// (H43) took that class past the six hundred lines the clean-code ratchet
/// holds, and it is one job the stroke only asks two things of — whether
/// to hold a sample, and which way the stroke set off. It reaches the
/// State through `_state`, as the stroke does.
class _BrushEditOpening {
  _BrushEditOpening(this._state);

  final _InteractiveBrushEditCanvasViewState _state;

  /// Whether this contact has not read a pressure yet — what
  /// [_BrushEditPressure.noteSample] is told as `opening`.
  bool _pressureUnread = false;

  /// Whether this contact has measured a speed yet. A press never has:
  /// speed takes two readings.
  bool _speedMeasured = false;

  /// The direction the stroke set off in, once a move has left the press —
  /// what the press is drawn with when its brush turns on direction
  /// ([BrushStrokeDynamics.readsDirection]). Like speed, a press has none of
  /// its own.
  double? _pressDirection;

  /// The samples a stroke took before its first READINGS, in the order
  /// they came, each with what it will paint — null while nothing waits.
  ///
  /// 🚨★★★H43 (유저 2026-09-26, iPad: 「필압있는 브러시 쓸때 첫 펜다운한
  /// 부분? 만 입력한 필압보다 센게나와. 최대치가 나오는거같기도하고」). The
  /// first samples of a contact can carry a value the device has not
  /// measured yet ([_BrushEditPressure.pressureOf]), and the stroke painted
  /// it: UIKit's estimate on an iPad, a hovering packet under Wintab.
  ///
  /// ★THE STROKE WAITS FOR THE FIRST READING OF EVERY INPUT ITS BRUSH
  /// READS, and each sample that waited without one is painted with it —
  /// the nearest measurement there is, exactly as a sample that cannot
  /// measure speed keeps the last one that could. The wait is the few
  /// samples it takes the device to catch up; nothing is on screen until
  /// then. 🗣️Speed is the same law (유저 2026-09-27, `opening-dab-speed-Q1`:
  /// 「첫 이동의 속도로 — 필압과 같은 법」): a press has no move behind it,
  /// so a brush that reads speed paints its press at the first move's.
  ///
  /// ⚠️That pairs one sample's lean with another sample's pressure — what
  /// [_BrushEditPressure.noteSample] is one call to prevent — and it does
  /// so knowingly: those samples carry no pressure of their own, and the
  /// nearest measurement is closer to the hand than the stand-in the
  /// device put there.
  ///
  /// 🚨★AND THE OPENING WAITS FOR ITS OWN FORCE (유저 2026-11-01,
  /// a-light-press-opens-with-heavy-dabs: 「엄청나게 약하게 스트로크 시작해도
  /// 필압강하게 3개dab정도가 찍힘」). 🔬Build 1086, a second of a weak stroke:
  /// `ledger meas=1 est=75 fin=0 upd=73 rep=3` — UIKit does correct its
  /// estimates. The first force past the stand-in is one of them, on its way
  /// down from it, and the press and its repeats took it. So the opening waits
  /// for the correction of its last sample ([_awaitsACorrection]), and each of
  /// the samples up to that one ([_WaitingSample.opens]) is painted with its
  /// own — one that has none, as the press, with the nearest after it.
  /// ⚠️The price is the first dab that much later: the inspector's `opened`
  /// line says how much. A pen with no corrections to send pays nothing.
  ///
  /// ⛔NOT 「paint the stand-in and repaint when the reading comes」 — what
  /// is shown once is seen ([[no-optimistic-commit-then-revert]]).
  ///
  /// Only an input the brush's curves READ is waited for: any other changes
  /// nothing it draws.
  ({Duration since, List<_WaitingSample> samples})? _waiting;

  /// How long a stroke waits for its first reading, and for the corrections
  /// of its opening, before it takes the device's word.
  ///
  /// The longest wait on record is UIKit's: seven coalesced samples at
  /// 240 Hz, 29 ms (Apple Developer Forums 96700) — and on the user's iPad
  /// the stand-in held for the press and three moves (2026-09-27), which is
  /// 25 ms of events at 120 Hz but up to 67 ms if they arrive at 60 Hz.
  /// A pen that never measures — one without a force sensor may repeat its
  /// stand-in for good — would otherwise hold its whole stroke off screen
  /// until it lifted; past this bound it paints what it reports, as it
  /// always did. Only such a pen ever pays all of it. 🔬How late UIKit's
  /// corrections come: build 1087's one weak stroke had samples up to about
  /// 69 ms corrected when the wait ended near 103 ms, so about 30 ms behind
  /// the sample then; one report says ~50 ms. ⚠️Whether the first of a stroke
  /// comes that soon is not measured.
  static const Duration _patience = Duration(milliseconds: 100);

  /// Whether this contact has not read a pressure yet.
  bool get pressureUnread => _pressureUnread;

  /// Which way the stroke set off, or null until a move has said so.
  double? get pressDirection => _pressDirection;

  /// A contact begins with what its press [read].
  void startContact(({bool pressure, bool speed}) read) {
    _pressureUnread = !read.pressure;
    _speedMeasured = read.speed;
    _pressDirection = null;
  }

  /// The press, taken [at] at [position]: [paintPress] now — or held, when
  /// the stroke's brush reads an input the press has not read.
  void press(
    void Function() paintPress, {
    required Duration at,
    required CanvasPoint position,
  }) {
    if (_awaitsAReading) {
      _waiting = (
        since: at,
        samples: [_waitingSample(paintPress, at, position, opens: true)],
      );
      return;
    }
    paintPress();
  }

  /// Whether the sample taken [at] at [penPosition] — which [read] what
  /// [_BrushEditPressure.noteSample] answered — is HELD with the others
  /// until the readings come. When the stroke stops waiting, what waited is
  /// painted first, and the caller paints this one ([paint]).
  bool holds(
    void Function() paint, {
    required CanvasPoint penPosition,
    required Duration at,
    required ({bool pressure, bool speed}) read,
  }) {
    final waiting = _waiting;
    final opens = _pressureUnread;
    if (waiting != null) {
      // Only what the brush reads is filled: what it does not read stays as
      // the device reported it, exactly as in a stroke that never waited.
      _fillWaiting(
        pressure:
            read.pressure &&
            _pressureUnread &&
            _reads(BrushInputSource.pressure),
        speed:
            read.speed && !_speedMeasured && _reads(BrushInputSource.speed),
      );
      // The first move that leaves the press says which way the stroke set
      // off — the direction its opening segment is drawn along.
      _pressDirection ??= strokeDirectionDegrees(
        from: waiting.samples.first.position,
        to: penPosition,
      );
    }
    if (read.pressure) {
      _pressureUnread = false;
    }
    if (read.speed) {
      _speedMeasured = true;
    }
    if (waiting == null) {
      return false;
    }
    // In the list first: the sample that brought the reading is owed a
    // correction like the ones it fills.
    waiting.samples.add(_waitingSample(paint, at, penPosition, opens: opens));
    if ((_awaitsAReading || _awaitsACorrection) &&
        at - waiting.since <= _patience) {
      return true;
    }
    waiting.samples.removeLast();
    _paintWaiting();
    return false;
  }

  /// The contact ended before its first readings: what waited lands with
  /// what the device reported — a tap too short for the device to measure
  /// still leaves its dot.
  void stopWaiting() {
    if (_waiting != null) {
      _paintWaiting();
    }
  }

  /// Drops whatever waits, unpainted — the stroke's teardown.
  void clear() {
    _waiting = null;
  }

  /// Whether an input this stroke's brush reads has not been read yet in
  /// this contact — its pressure or speed, or, for a brush that turns on
  /// the stroke's direction, which way it set off.
  ///
  /// ↩️The lean waited here too, while UIKit's estimate of it counted as no
  /// reading. Build 1065 showed nearly every Pencil sample estimated: every
  /// sample's lean is read now ([penLeanOf]), so a contact
  /// has read it from its press and there is nothing to wait for.
  bool get _awaitsAReading =>
      (_pressureUnread && _reads(BrushInputSource.pressure)) ||
      (!_speedMeasured && _reads(BrushInputSource.speed)) ||
      (_pressDirection == null &&
          ((_state._strokeDynamics?.readsDirection ?? false) ||
              (_state._secondStroke?.readsDirection ?? false)));

  /// Whether the opening's last sample is still owed the force UIKit will
  /// send after the fact — by a brush that draws with it.
  ///
  /// 🚨THE LAST ONE, NOT EVERY ONE (유저 2026-11-02: 「시작지연은
  /// 줄일수있으면 줄이고싶어」). ↩️It asked of every sample of the opening,
  /// and the press is one. 🔬Build 1087, a weak stroke: `opened 95ms held=12
  /// own=8` · `state e e e` · `fixed - .00 .01` · `est=100 upd=99`: UIKit
  /// calls the press an estimate it will correct and never does, so every
  /// opening ran to the patience, and the fixture had the press measured.
  /// ⚠️Build 1086 lost a second one (`est=75 upd=73`), so naming the press is
  /// not enough: past the last sample's correction nothing is worth waiting
  /// for. One that came late or never takes the nearest after it
  /// ([_takeRecordedPressures]).
  bool get _awaitsACorrection =>
      _reads(BrushInputSource.pressure) &&
      _state._pressure.awaitsCorrection(
        _waiting!.samples.lastWhere((sample) => sample.opens).at,
      );

  /// Whether this stroke's brush reads [source] at all.
  bool _reads(BrushInputSource source) =>
      (_state._activeStrokeInputSettings ?? _state.widget.inputSettings())
          .shape
          .reads(source);

  /// The FIRST reading of an input stands for every sample that waited
  /// without one — the sample just noted brought it, so it is what the
  /// stroke holds now.
  void _fillWaiting({required bool pressure, required bool speed}) {
    final now = _state._readings;
    for (final sample in _waiting!.samples) {
      if (pressure) {
        sample.readings = sample.readings.withPressure(now.pressure);
      }
      if (speed) {
        sample.readings = sample.readings.withSpeed(now.speed);
      }
    }
  }

  /// Paints every sample that waited, each with its own lean and twist and the
  /// pressure and speed it waited for ([_WaitingSample]), and leaves the
  /// current readings as they were.
  ///
  /// ★A sample the platform has since MEASURED is painted with that — its
  /// own force, the one UIKit sends after the fact — not the first reading
  /// that stood in for it ([_BrushEditPressure.recordedPressure]).
  void _paintWaiting() {
    final samples = _waiting!.samples;
    _waiting = null;
    final fixed = _takeRecordedPressures(samples);
    _state._pressure.noteOpened(
      waited: samples.last.at - samples.first.at,
      held: samples.length,
      fixed: fixed,
    );
    for (final sample in samples) {
      final own = sample.readings;
      final lean = own.lean;
      _state._stroke.paintReading(
        own.withLean(
          lean == null
              ? null
              : recordedPenLean(sample.at, lean.azimuthDegrees) ?? lean,
        ),
        sample.paint,
      );
    }
  }

  /// Each of [samples] takes the force the platform has recorded for it, and
  /// one of the opening with none takes the nearest recorded after it —
  /// the press, whose own record is the stand-in. Answers how many had their
  /// own.
  int _takeRecordedPressures(List<_WaitingSample> samples) {
    var fixed = 0;
    double? nearest;
    for (final sample in samples.reversed) {
      final recorded = _state._pressure.recordedPressure(sample.at);
      if (recorded != null) {
        fixed += 1;
        nearest = recorded;
      }
      if (recorded != null || sample.opens) {
        sample.readings = sample.readings.withPressure(
          nearest ?? sample.readings.pressure,
        );
      }
    }
    return fixed;
  }

  /// The sample just noted, stamped [at] at [position], as it waits.
  _WaitingSample _waitingSample(
    void Function() paint,
    Duration at,
    CanvasPoint position, {
    required bool opens,
  }) => _WaitingSample(
    at: at,
    position: position,
    opens: opens,
    readings: _state._readings,
    paint: paint,
  );
}

/// One sample a stroke holds while it waits for its first readings
/// ([_BrushEditOpening._waiting]): its own lean and twist and what it paints,
/// and the pressure and speed it will be painted with — its own, the first
/// reading that came after it ([_BrushEditOpening._fillWaiting]), or, when
/// none came, what the device reported in the reading's place.
class _WaitingSample {
  _WaitingSample({
    required this.at,
    required this.position,
    required this.opens,
    required this.readings,
    required this.paint,
  });

  /// When the sample was taken — the key its platform record is under.
  final Duration at;

  /// Where the pen was, before any smoothing: the press's is where the
  /// stroke's direction is measured from.
  final CanvasPoint position;

  /// Whether it is of the contact's OPENING: taken before it read a pressure,
  /// or the sample that first did. What such a sample reported is the
  /// stand-in or the estimate coming down from it, so it takes its own
  /// correction, or the nearest after it, and the opening waits for the last
  /// of them ([_BrushEditOpening._awaitsACorrection]). A sample after those
  /// keeps its own estimate if none has come.
  final bool opens;

  /// What the sample read, whole — its pressure and speed filled in as the
  /// first readings come ([_BrushEditOpening._fillWaiting]).
  PenReadings readings;
  final void Function() paint;
}
