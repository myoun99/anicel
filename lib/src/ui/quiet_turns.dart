import 'dart:async';
import 'dart:developer' show Timeline;
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../services/playback/present_slot.dart' show quietBetweenHeldFrames;
import 'present_pacing.dart' show quietForBackgroundGpuWork, quietMayHaveMoved;

/// What background GPU work reads the quiet between held frames through:
/// the quiet itself, the clock it is on, the wait for it to begin, and the
/// wait for it to move — the display's, on the frame clock
/// ([quietForBackgroundGpuWork], [quietMayHaveMoved]); a test hands its
/// own.
@immutable
class QuietClock {
  const QuietClock({
    this.quiet = quietForBackgroundGpuWork,
    this.now = _frameClockNow,
    this.wait = _sleep,
    this.moved = quietMayHaveMoved,
  });

  final ({int fromMicros, int untilMicros})? Function() quiet;
  final int Function() now;
  final Future<void> Function(Duration) wait;
  final Future<void> Function() moved;

  static int _frameClockNow() => Timeline.now;

  static Future<void> _sleep(Duration duration) =>
      Future<void>.delayed(duration);
}

/// Work no held frame is waiting to show ([QuietTurns.inAQuiet]): it waits
/// for a quiet whenever one is kept.
bool notDue() => false;

/// How long one kind of background GPU work has taken from its turn to its
/// landing, at the most of late ([QuietTurn.landed]) — what one more has to
/// fit in before the quiet ends. Each kind keeps its own: a timeline span,
/// a playback row and a baked word are not one length.
final class QuietSpan {
  int micros = 0;
}

/// 🚨BACKGROUND GPU WORK TAKES ITS TURN IN THE QUIET BETWEEN HELD FRAMES,
/// ONE JOB AT A TIME (유저 2026-10-11: 「144hz든 몇이든 확실하게
/// 근본/구조적으로 해결하도록」) — every kind of it, not only the timeline's
/// warm-up ([quietBetweenHeldFrames] has the law and its first
/// measurement).
///
/// 🔬Until 2026-10-15 only the timeline's warm-up kept it. Measured that day
/// in a release build on the glass (144Hz, a cut played from nothing made):
/// the film frames shown a refresh off came at the start of a run — scenes
/// waiting 34–74 ms for the raster thread while playback's own making
/// posted 4–12 compose snapshots every 80 ms — and at the first pass's page
/// turns, where 6–18 baked words queued scenes 12–19 ms. Every row of the
/// making held to the quiet (a rough patch): frames over a film frame long
/// 9 · 8 · 14 → 4 · 7 · 0.
///
/// One job at a time, so a quiet's room is counted once for every kind: two
/// that each fit alone, posted side by side, end past it together.
///
/// ⛔Where no quiet is kept — no clock running, a display that does not say
/// — a turn is given at once and nobody queues: warming at rest keeps its
/// makings side by side (10-10: a whole cut made 7–30% sooner for them).
final class QuietTurns {
  QuietTurns({this.clock = const QuietClock()});

  /// The app's: every kind of background GPU work takes its turns here.
  static final QuietTurns instance = QuietTurns();

  final QuietClock clock;

  /// The turn taken last — what the next waits for.
  Future<void> _taken = Future<void>.value();

  /// A turn in the quiet that is now — waited for to begin — for a job
  /// [span] long: null when that quiet has no room for one, is over, or
  /// ends before one would land, or when [gone] after its wait. The job
  /// goes on after the next held frame, asked again by whoever asks then.
  Future<QuietTurn?> inThisQuiet(
    QuietSpan span, {
    required bool Function() gone,
  }) async {
    if (clock.quiet() == null) {
      return QuietTurn._(this, span);
    }
    final release = await _queue();
    final quiet = clock.quiet();
    if (quiet == null || await _into(quiet, span, gone)) {
      return QuietTurn._(this, span, release: release);
    }
    release();
    return null;
  }

  /// A turn in the first quiet with room for a job [span] long — this one
  /// or one after it; null only when [gone].
  ///
  /// 🚨WHAT THE NEXT HELD FRAME SHOWS IS NOT BACKGROUND WORK: while [due],
  /// the turn is given at once and nobody is queued behind — the quiet
  /// that frame leaves comes after it, too late for what it shows. Asked
  /// again each time the quiet moves.
  Future<QuietTurn?> inAQuiet(
    QuietSpan span, {
    required bool Function() gone,
    bool Function() due = notDue,
  }) async {
    while (!gone()) {
      if (due() || clock.quiet() == null) {
        return QuietTurn._(this, span);
      }
      final release = await _queue();
      if (gone()) {
        release();
        return null;
      }
      final quiet = clock.quiet();
      if (due() || quiet == null || await _into(quiet, span, gone)) {
        return QuietTurn._(this, span, release: release);
      }
      release();
      if (!gone()) {
        await clock.moved();
      }
    }
    return null;
  }

  /// Takes the next turn: answers once the one before it is given back,
  /// with what gives this one back.
  Future<void Function()> _queue() async {
    final before = _taken;
    final mine = Completer<void>();
    _taken = mine.future;
    await before;
    return mine.complete;
  }

  /// Waits for [quiet] to begin; false when it has no room at all, when it
  /// is over, when it ends before one more job of [span] would land, or
  /// when [gone] after the wait. A job longer than the quiet once does not
  /// shut the kind out: each look turned away by a quiet too short shortens
  /// what is asked.
  Future<bool> _into(
    ({int fromMicros, int untilMicros}) quiet,
    QuietSpan span,
    bool Function() gone,
  ) async {
    final now = clock.now();
    if (quiet.untilMicros <= quiet.fromMicros || now >= quiet.untilMicros) {
      return false;
    }
    if (now < quiet.fromMicros) {
      await clock.wait(Duration(microseconds: quiet.fromMicros - now));
      if (gone()) {
        return false;
      }
    }
    if (clock.now() + span.micros > quiet.untilMicros) {
      span.micros = span.micros * 3 ~/ 4;
      return false;
    }
    return true;
  }
}

/// A job's turn ([QuietTurns]): given back when the job [landed] — what it
/// took is learned — or [gaveUp].
final class QuietTurn {
  QuietTurn._(this._turns, this._span, {void Function()? release})
    : _release = release,
      _started = _turns.clock.now();

  final QuietTurns _turns;
  final QuietSpan _span;
  final int _started;
  void Function()? _release;

  /// The job landed: what it took is what its kind is next asked to fit
  /// ([QuietSpan]), and the next job takes its turn.
  void landed() {
    _span.micros = math.max(
      _span.micros * 3 ~/ 4,
      _turns.clock.now() - _started,
    );
    gaveUp();
  }

  /// The job came to nothing: the next takes its turn, and nothing is
  /// learned.
  void gaveUp() {
    final release = _release;
    _release = null;
    release?.call();
  }
}
