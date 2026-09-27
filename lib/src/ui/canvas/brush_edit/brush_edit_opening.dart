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
  /// ⛔NOT 「paint the stand-in and repaint when the reading comes」 — what
  /// is shown once is seen ([[no-optimistic-commit-then-revert]]).
  ///
  /// Only an input the brush's curves READ is waited for: any other changes
  /// nothing it draws.
  ({Duration since, List<_WaitingSample> samples})? _waiting;

  /// How long a stroke waits for its first reading before it takes the
  /// device's word.
  ///
  /// The longest wait on record is UIKit's: seven coalesced samples at
  /// 240 Hz, 29 ms (Apple Developer Forums 96700) — and on the user's iPad
  /// the stand-in held for the press and three moves (2026-09-27), which is
  /// 25 ms of events at 120 Hz but up to 67 ms if they arrive at 60 Hz.
  /// A pen that never measures — one without a force sensor may repeat its
  /// stand-in for good — would otherwise hold its whole stroke off screen
  /// until it lifted; past this bound it paints what it reports, as it
  /// always did. Only such a pen ever pays it.
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
        samples: [_waitingSample(paintPress, at, position)],
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
    if (_awaitsAReading && at - waiting.since <= _patience) {
      waiting.samples.add(_waitingSample(paint, at, penPosition));
      return true;
    }
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
  /// sample's lean is read now ([_BrushEditPressure.tiltOf]), so a contact
  /// has read it from its press and there is nothing to wait for.
  bool get _awaitsAReading =>
      (_pressureUnread && _reads(BrushInputSource.pressure)) ||
      (!_speedMeasured && _reads(BrushInputSource.speed)) ||
      (_pressDirection == null &&
          (_state._strokeDynamics?.readsDirection ?? false));

  /// Whether this stroke's brush reads [source] at all.
  bool _reads(BrushInputSource source) =>
      (_state._activeStrokeInputSettings ?? _state.widget.inputSettings())
          .shape
          .reads(source);

  /// The FIRST reading of an input stands for every sample that waited
  /// without one — the sample just noted brought it, so it is what the
  /// stroke holds now.
  void _fillWaiting({required bool pressure, required bool speed}) {
    for (final sample in _waiting!.samples) {
      if (pressure) {
        sample.pressure = _state._currentPressure;
      }
      if (speed) {
        sample.speed = _state._currentSpeed;
      }
    }
  }

  /// Paints every sample that waited, each with its own lean and the
  /// pressure and speed it waited for ([_WaitingSample]), and leaves the
  /// current readings as they were.
  ///
  /// ★A sample the platform has since MEASURED is painted with that — its
  /// own force, the one UIKit sends after the fact — not the first reading
  /// that stood in for it ([_BrushEditPressure.recordedPressure]).
  void _paintWaiting() {
    final samples = _waiting!.samples;
    _waiting = null;
    final pressure = _state._currentPressure;
    final tilt = _state._currentTilt;
    final speed = _state._currentSpeed;
    for (final sample in samples) {
      final tilt = sample.tilt;
      _state._currentPressure =
          _state._pressure.recordedPressure(sample.at) ?? sample.pressure;
      _state._currentTilt = tilt == null
          ? null
          : _state._pressure.recordedTilt(sample.at, tilt.azimuthDegrees) ??
                tilt;
      _state._currentSpeed = sample.speed;
      sample.paint();
    }
    _state._currentPressure = pressure;
    _state._currentTilt = tilt;
    _state._currentSpeed = speed;
  }

  /// The sample just noted, stamped [at] at [position], as it waits.
  _WaitingSample _waitingSample(
    void Function() paint,
    Duration at,
    CanvasPoint position,
  ) => _WaitingSample(
    at: at,
    position: position,
    pressure: _state._currentPressure,
    speed: _state._currentSpeed,
    tilt: _state._currentTilt,
    paint: paint,
  );
}

/// One sample a stroke holds while it waits for its first readings
/// ([_BrushEditOpening._waiting]): its own lean and what it paints, and the
/// pressure and speed it will be painted with — its own, the first reading
/// that came after it ([_BrushEditOpening._fillWaiting]), or, when none
/// came, what the device reported in the reading's place.
class _WaitingSample {
  _WaitingSample({
    required this.at,
    required this.position,
    required this.pressure,
    required this.speed,
    required this.tilt,
    required this.paint,
  });

  /// When the sample was taken — the key its platform record is under.
  final Duration at;

  /// Where the pen was, before any smoothing: the press's is where the
  /// stroke's direction is measured from.
  final CanvasPoint position;
  double pressure;
  double speed;
  final PenLean? tilt;
  final void Function() paint;
}
