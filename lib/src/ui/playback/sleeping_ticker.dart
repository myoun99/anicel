import 'dart:async';

import 'package:flutter/scheduler.dart';

/// A ticker that SLEEPS between the frames it has to show.
///
/// 🚨THE SCREEN IS REDRAWN AS OFTEN AS THE FRAME CHANGES (유저 2026-10-08:
/// 「3 화면을 프레임만큼만 다시그리도록」).
///
/// A ticker that runs asks the engine for a frame at every vsync, and the
/// engine composites one whether or not anything changed. At 24 frames a
/// second that is three screen frames in five drawn for nothing at 60Hz and
/// five in six at 144. 🔬Measured 2026-10-08 on Windows, the same eight
/// seconds of playback with a ticker that never sleeps and with this one,
/// turn about: 752~805 app frames against 202~233, and 4.9~5.3 seconds of
/// rasterising against 1.3~1.7 — with the same 190 frames shown, none
/// dropped, either way.
///
/// So between frames the ticker is MUTED — time goes on running in a muted
/// ticker — and woken when the frame is about to change. The tick that
/// changes the frame is still the ticker's, on a vsync, read off the clock
/// it always read. How it is woken is its owner's to say, by what its clock
/// can tell:
///
/// - a clock that knows when its next frame is due sleeps [untilDue], and a
///   timer wakes it [wakeAhead] before that;
/// - a clock that does not is ASKED ([untilItSays]) — off the ticker, which
///   costs no screen frame — and the ticker is woken when it says so.
///
/// ⚠️`Ticker.muted` is by convention its provider's to write — a route
/// that is not shown silences its tickers through it. The two writers do
/// not fight: a ticker the provider un-silences ticks once, is put to sleep
/// again by the tick, and what woke it before is replaced; one the provider
/// silenced is woken by its waker a tick a frame, which is less than it
/// ticked before.
class SleepingTicker {
  SleepingTicker(this._onTick);

  final TickerCallback _onTick;
  Ticker? _ticker;
  Timer? _waker;

  /// How long before a frame is due the ticker is woken for it.
  ///
  /// The wake is a timer, and a timer comes late where a vsync does not —
  /// 🔬measured on Windows under load: 1.8ms at the median, 4.5 at the
  /// worst. Woken too late for the vsync that would have changed the frame,
  /// the frame changes on the next one: one screen frame late, and only
  /// when that vsync fell within the lateness of the frame's boundary —
  /// where which of the two shows it is a toss already. Woken early, one
  /// tick finds the frame unchanged and it is drawn again.
  static const Duration wakeAhead = Duration(milliseconds: 4);

  /// How often a sleeping ticker's clock is asked: twice within a screen
  /// frame of the fastest screens, so a frame changes on the vsync it would
  /// have, or the one after.
  static const Duration askEvery = Duration(milliseconds: 3);

  bool get isRunning => _ticker != null;

  /// Starts afresh on [vsync]: the elapsed time its ticks carry counts from
  /// the first of them.
  void start(TickerProvider vsync) {
    stop();
    final ticker = _ticker = vsync.createTicker(_onTick);
    unawaited(ticker.start());
  }

  /// 🚨No waker outlives its ticker: every way a clock ends comes through
  /// here, and what would have woken it goes with it.
  void stop() {
    _waker?.cancel();
    _waker = null;
    _ticker?.dispose();
    _ticker = null;
  }

  /// Sleeps until just before a frame that is due in [due]. Asked by a
  /// tick, of the tick's own clock.
  void untilDue(Duration due) {
    final sleep = due - wakeAhead;
    if (sleep > Duration.zero) {
      _sleep(() => Timer(sleep, _wake));
    }
  }

  /// Sleeps until [itIsTime] says so, asked every [askEvery].
  void untilItSays(bool Function() itIsTime) {
    _sleep(
      () => Timer.periodic(askEvery, (_) {
        if (itIsTime()) {
          _wake();
        }
      }),
    );
  }

  /// Silences the ticker — if there still is one: the tick that asks may
  /// have ended the clock — and keeps what [wakes] it.
  void _sleep(Timer Function() wakes) {
    final ticker = _ticker;
    if (ticker == null) {
      return;
    }
    _waker?.cancel();
    ticker.muted = true;
    _waker = wakes();
  }

  void _wake() {
    _waker?.cancel();
    _waker = null;
    _ticker?.muted = false;
  }
}
