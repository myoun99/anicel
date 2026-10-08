import 'dart:async';

import 'package:flutter/scheduler.dart';

import '../look_only_frames.dart';

/// The ticker of a clock that follows time: it LOOKS at every vsync, and
/// asks for nothing to be drawn.
///
/// 🚨THE CLOCK IS READ ON EVERY VSYNC, AND THE SCREEN IS REDRAWN AS OFTEN AS
/// THE FRAME CHANGES (유저 2026-10-08: 「3 화면을 프레임만큼만 다시그리도록」 ·
/// 「소리 싱크나 영상이나 뭐 그런거 정확하기만하면되. 그게 제일 최우선.」).
/// Its frame changes on the first vsync it is due on — nothing is read
/// between vsyncs, and nothing has to wake in time — and what the tick
/// changes is drawn in that same frame, by whatever it made dirty. A tick
/// that changes nothing is a frame that is not drawn ([LookOnlyFrames],
/// where the law, its reasons and what it replaced are).
///
/// It is the framework's own `Ticker`, from the view's own provider: a
/// route that is not shown still silences it, and a test still drives it
/// with a pump.
class LookingTicker {
  LookingTicker(this._onTick);

  final TickerCallback _onTick;
  Ticker? _ticker;

  bool get isRunning => _ticker != null;

  /// Starts afresh on [vsync]: the elapsed time its ticks carry counts from
  /// the first of them.
  void start(TickerProvider vsync) {
    stop();
    final ticker = _ticker = vsync.createTicker(_tick);
    _onlyToLook(() => unawaited(ticker.start()));
  }

  void stop() {
    _ticker?.dispose();
    _ticker = null;
  }

  void _tick(Duration elapsed) {
    _onTick(elapsed);
    // The tick may have ended this clock: then there is nothing to look
    // again with. (It may have started it afresh, too; the ticker it then
    // has looks again like any other.)
    final ticker = _ticker;
    if (ticker != null) {
      _lookAgain(ticker);
    }
  }

  /// Asks for the next vsync — to look.
  ///
  /// 🚨A `Ticker` asks for its next tick BY ITSELF, once its callback has
  /// returned, and nothing can be said about a request made in there: the
  /// scheduler would take it for one made to draw, and every frame would be
  /// drawn. So the request is made here instead, inside the look — the one
  /// way a ticker's own request can be made from outside it: muted, it lets
  /// go of the tick it has scheduled; unmuted, it schedules one. A ticker
  /// that has a tick scheduled does not ask again.
  void _lookAgain(Ticker ticker) {
    _onlyToLook(() {
      ticker
        ..muted = true
        ..muted = false;
    });
  }

  static void _onlyToLook(VoidCallback asks) {
    final binding = SchedulerBinding.instance;
    if (binding is LookOnlyFrames) {
      binding.askingOnlyToLook(asks);
    } else {
      // A binding that draws every frame it begins (a test's own): asked
      // the way any ticker asks.
      asks();
    }
  }
}
