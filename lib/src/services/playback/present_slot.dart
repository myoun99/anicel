import 'dart:math' as math;

/// 🚨THE COMPOSITOR'S LATCH, ON THE GLASS (Windows, DWM kept composing on
/// every vblank while a clock runs — `PresentPacing` — a 144Hz screen,
/// 2026-10-13: the compositor's own statistics of when each of its frames
/// reached the glass, joined to the app's frame times; 2,886 film changes
/// over eight runs): a picture whose raster ENDS after the vblank it claimed
/// is taken by the composition frame that starts on the next vblank, and
/// shown [presentShownAfterVblanks] vblanks after the claimed one — unless
/// the GPU is still at its work when that frame starts, which the raster's
/// end does not wait for. Ends 0–2ms past the vblank: 1.2 in a hundred off,
/// none of 84 in its first quarter of a millisecond. Later ends are taken
/// late more and more often (4% at 2–2.5ms, 9% at 2.5–4.5ms, 35% past
/// that); ends before the vblank are taken by the frame that starts ON it
/// and shown a refresh early, at once (4% in the quarter of a millisecond
/// before it, 20% in the quarter before that). So the edges are not alike:
/// the early one is sharp and the late one soft, and a hand-off puts the
/// shortest of the recent scenes on the early one and leaves the GPU the
/// rest of the refresh ([RasterSpread.handOffFor]).
///
/// [presentLatchLateMicros] is the compositor's own lead: a picture with
/// nothing left for the GPU to do (a test window's, handed over at a moment
/// of its choosing) was taken by the frame starting on the next vblank
/// 97.7–100 in a hundred times up to 1.44ms before it, and mostly not at
/// 0.44ms.
///
/// ↩️Read 10-11 and 10-12 through Desktop Duplication, which says when the
/// compositor PRESENTED a frame — a vblank before it reaches the glass — and
/// off a compositor left to compose on demand, which takes a picture at
/// once when it idles and at the next vblank when it is busy: a window
/// 1.75ms past a vblank to 0.95ms before the next, shown two vblanks on.
/// Both were the instrument's.
///
/// Between those edges the vblank a picture lands on depends on nothing but
/// WHEN its raster ends — not on how long the frame took, and not on the
/// engine's own vsync, which on Windows is a grid of its own that never
/// meets the real one ([PresentClaims]).
const int presentLatchEarlyMicros = 0;
const int presentLatchLateMicros = 1500;

/// How many vblanks after the one it claimed a picture is shown: the
/// composition frame that takes it starts on the next vblank, and a
/// composition frame reaches the glass on the second vblank after it starts.
const int presentShownAfterVblanks = 3;

/// A look's claim on a vblank: [handOffMicros], the moment its frame's
/// scene is handed over — the one that ends the shortest of the recent
/// scenes on the latch's early edge ([RasterSpread.handOffFor]) — and
/// [shownAtMicros], the moment its picture is shown.
///
/// ↩️It had a latest hand-off too, the last moment that ended the longest
/// scene on the latch's late edge, and a look claimed a vblank its frame
/// could reach by then. With the late edge soft every moment past the
/// hand-off ends the scenes later, and a frame let go late in that room
/// lands late more often (10-13: 1 in 20 held frames reached its seam past
/// its hand-off) — a look claims a vblank its frame can WAIT for.
typedef PresentClaim = ({int handOffMicros, int shownAtMicros});

/// 🚨WHICH VBLANK EACH LOOK OF A CLOCK FILLS (유저 2026-10-11: 「144hz든
/// 몇이든 확실하게 근본/구조적으로 해결하도록」).
///
/// Flutter on Windows begins its frames on a grid of its own — multiples
/// of the refresh period from the machine's boot — and that grid JUMPS:
/// the engine reads the compositor's period afresh for every vsync, and a
/// change of a tenth of a microsecond in it moves the multiples of hours
/// of uptime by a random part of a refresh. 🔬Measured on the screen
/// (144Hz, 10-11): the engine's vsync stood at two or three places against
/// the real vblank within each six seconds of a run, eight to ten changes a
/// run. Its frames are also presented without waiting for a vblank, so a
/// picture is shown on whichever vblank its raster happens to end before:
/// film frames of five and seven refreshes where six were due, 12–17 in a
/// hundred of them.
///
/// So a look does not take its vblank from the engine's vsync. Each look
/// claims a REAL vblank — the one after the last look's — and its frame
/// hands its scene to the GPU at that vblank's hand-off, and the clock is
/// read at the moment that vblank's picture is SHOWN. One look,
/// one vblank, one after another: a jump of the engine's grid moves when a
/// look happens, never which vblank it fills.
///
/// A run's first look claims [lead] vblank past the earliest it can make,
/// so a later look that comes a little late — a jittered tick, the grid
/// jumping forward — still finds the vblank after the last one in reach.
/// A frame that waits for its hand-off holds up the looks after it, which
/// spends that lead; the look after a CHANGE takes it back by passing over
/// one vblank, the one right after the change, which carries none while a
/// film frame lasts two refreshes or more ([changed]). A look that comes
/// early claims no further than [reserve] vblanks past the earliest it can
/// make: past that it claims the last one again, which shows the same
/// picture twice and nothing else.
///
/// 🔬Simulated against the engine's habits (its grid jumping between two
/// phases, ticks 0.2–2ms late, a 3.5–7.5ms raster, the latch as measured):
/// film frames shown a refresh off — 4.9% claimed from the engine's vsync,
/// 1.1% chained, 0.00% chained with the lead taken back, at 60, 120 and
/// 144Hz, 12, 24 and 30 frames a second.
final class PresentClaims {
  /// Vblanks of lead a run's first look takes past the earliest it can make.
  static const int lead = 1;

  /// The most vblanks a claim may stand past the earliest its look can make.
  static const int reserve = 2;

  /// The last claimed vblank, on the frame clock.
  double? _last;
  bool _lastChanged = false;

  /// The vblank the look made at [nowMicros] fills, its frame's work still
  /// to come taking at most [budgetMicros] and its scene handed over
  /// [handOffMicros] past that vblank.
  ///
  /// [vblankMicros] is any real vblank and [periodMicros] the real refresh
  /// period, both on the frame clock.
  PresentClaim claim({
    required int nowMicros,
    required int vblankMicros,
    required double periodMicros,
    required int budgetMicros,
    required double handOffMicros,
  }) {
    int indexOf(double micros) =>
        ((micros - vblankMicros) / periodMicros).round();
    final natural =
        ((nowMicros + budgetMicros - handOffMicros - vblankMicros) /
                periodMicros)
            .ceil();
    final last = _last == null ? null : indexOf(_last!);
    final int index;
    // Nowhere near the last claim — a run started again, or a clock that
    // is not the one the last claim was made on — starts the chain afresh.
    if (last == null || (natural - last).abs() > lead + reserve + 1) {
      index = natural + lead;
    } else if (_lastChanged) {
      index = math.min(
        math.max(natural + lead, last + 1),
        math.max(last + 2, natural),
      );
    } else {
      index = math.min(
        math.max(last + 1, natural),
        math.max(last, natural + reserve),
      );
    }
    final vblank = vblankMicros + index * periodMicros;
    _last = vblank;
    _lastChanged = false;
    return (
      handOffMicros: (vblank + handOffMicros).round(),
      shownAtMicros: (vblank + presentShownAfterVblanks * periodMicros)
          .round(),
    );
  }

  /// The last claim's look changed what the clock shows.
  void changed() => _lastChanged = true;

  /// No claim was made before: the next starts a chain.
  void forget() {
    _last = null;
    _lastChanged = false;
  }
}

/// How long a paced scene runs from its hand-off to its raster's end,
/// followed over the last [capacity] paced frames — and where to hand a
/// scene over for those lengths to end inside the latch's window.
///
/// 🚨THE WINDOW GOES WHERE THE MOST SCENES LAND (10-12, after the screen
/// said otherwise): a percentile follows a stretch of slow scenes wherever
/// it goes — the scenes of a run still making its pictures (20–60ms) moved
/// the first steady seconds' window 29ms early — while the most-covered
/// window moves only once slow scenes outnumber the steady ones within any
/// one window's width.
///
/// 🚨AND THE SHORTEST OF THOSE SCENES ENDS ON THE EARLY EDGE (10-13, on the
/// glass): the early edge is sharp and the late one soft — a scene that ends
/// later is taken late more often, the longer the GPU is left to finish it
/// in ([presentLatchEarlyMicros] has the measurement) — so every scene is
/// handed over as early as the early edge lets the shortest of them be.
/// ↩️The window's middle, which 10-12 chose over a tenth percentile on the
/// early edge, was chosen on Desktop Duplication's word, where the early
/// edge had come out soft and 1.75ms late (the instrument's): on the glass,
/// with the compositor kept composing, that middle put 9–13 film changes in
/// a hundred a refresh late, and a hand-off 2ms earlier 1.4–5.8.
///
/// 🔬A scene's length is not its film frame's: the same frame a loop later
/// took a different length (correlation −0.3 to 0.1 over eight runs) — it
/// is the machine's, so only how the lengths spread can be followed.
final class RasterSpread {
  RasterSpread({this.capacity = 32});

  final int capacity;
  final List<int> _recent = [];
  int _next = 0;

  /// Before eight paced scenes have said: the shortest a whole-window scene
  /// of this app took after its hand-off on the machine the latch was
  /// measured on (10-13: a tenth of 2,524 held frames were shorter).
  static const int unmeasuredMicros = 2000;

  void add(int micros) {
    if (_recent.length < capacity) {
      _recent.add(micros);
    } else {
      _recent[_next] = micros;
      _next = (_next + 1) % capacity;
    }
  }

  /// What a length weighs against the one after it.
  ///
  /// 🚨THE LAST FEW SCENES SAY WHERE THE WINDOW GOES (10-12): a run changes
  /// as it goes — its pictures all made, a load come or gone — and with
  /// every length weighing alike, the steady scenes after a run had made
  /// its pictures took the window back only once they were half the ring:
  /// 🔬on the screen, film frames shown a refresh early for 0.7s after the
  /// making ended. Replayed over seven runs' own lengths, a length weighing
  /// this much less for each newer one after it put 14.3 film changes in a
  /// hundred off against 15.6 even. One odd scene still weighs less than
  /// the steady ones around it.
  static const double ageDecay = 0.85;

  /// Where to hand a scene over, against the vblank its raster is to end
  /// past, on a display of [periodMicros]: the window of the latch's width
  /// that holds the most of the recent lengths, each weighing [ageDecay]
  /// for every newer one, handed over so that the shortest of them ends on
  /// the latch's early edge.
  double handOffFor(double periodMicros) {
    final width = math.max(
      0.0,
      periodMicros - presentLatchEarlyMicros - presentLatchLateMicros,
    );
    final lengths = _byLength();
    // Each candidate holds lengths[i..j], all within one width of the
    // shortest.
    var most = -1.0;
    var covered = 0.0;
    var shortest = 0;
    var j = -1;
    for (var i = 0; i < lengths.length; i += 1) {
      if (j < i) {
        j = i;
        covered = lengths[i].weight;
      }
      while (j + 1 < lengths.length &&
          lengths[j + 1].micros - lengths[i].micros <= width) {
        j += 1;
        covered += lengths[j].weight;
      }
      if (covered > most) {
        most = covered;
        shortest = lengths[i].micros;
      }
      covered -= lengths[i].weight;
    }
    return (presentLatchEarlyMicros - shortest).toDouble();
  }

  /// The recent lengths, shortest first, each with its weight — the newest
  /// weighing 1 — or, before eight have said, the unmeasured one.
  List<({int micros, double weight})> _byLength() {
    if (_recent.length < 8) {
      return const [(micros: unmeasuredMicros, weight: 1)];
    }
    // The ring's oldest is at [_next] once it is full, at 0 before.
    final oldest = _recent.length < capacity ? 0 : _next;
    return [
      for (var age = 0; age < _recent.length; age += 1)
        (
          micros:
              _recent[(oldest + _recent.length - 1 - age) % _recent.length],
          weight: math.pow(ageDecay, age).toDouble(),
        ),
    ]..sort((a, b) => a.micros.compareTo(b.micros));
  }
}

/// How late the raster thread is seen past a paced scene, from what one
/// batch of the frames' timings says of each of its scenes ([lates], at
/// least one): the median — one fence held up behind a busy thread says
/// nothing of the rest (🔬2026-10-15, the glass: a median of 0.54ms, the
/// p99 2.9–6ms, the longest 9–12ms).
int seenLateOf(List<int> lates) {
  final sorted = [...lates]..sort();
  return sorted[sorted.length ~/ 2];
}

/// 🚨BACKGROUND GPU WORK RUNS IN THE QUIET BETWEEN TWO HELD FRAMES (10-12,
/// read off the screen's own first loop): a texture uploaded on the io
/// thread while a held frame rasters slows that raster down — the two
/// threads' GL calls take turns on one device. 🔬Four of a first loop's
/// five change rasters over 7ms had 12–19ms of io-thread uploads beside
/// them (the next page's tiles, warming), their scene encoding 5.7ms
/// against 3.3ms in the others — and those were the film frames shown a
/// refresh late.
///
/// The quiet a held frame leaves runs from where the compositor has taken
/// its picture — where the latch's window for the vblank it claimed closes,
/// its raster and the GPU's work after it done or too late to matter — to
/// the next held frame's hand-off, less [marginMicros] for the work that
/// frame still does before it. Held frames claim VBLANKS, so the next
/// stands a whole number of refreshes past this one — at least the [held]
/// gap — and is handed over no sooner than its claim's hand-off: the quiet
/// ends on the vblank grid, not on when a frame happened to be let go.
///
/// ↩️It was read off the moments the held frames were let go: their
/// interval after the last, less two refreshes for where the next release
/// falls and the build before it. 🧮At 60Hz a 24fps film is held two
/// refreshes and three by turns, and two refreshes and a millisecond are
/// more than the shorter — every quiet was EMPTY and nothing warmed while
/// a cut played there (10-12); at 144Hz that margin took 15ms of 42.
///
/// Where the scenes leave no room it is EMPTY — it ends before it begins —
/// and the work waits for a held frame that leaves some: a quiet with no
/// room is not leave to run beside the frames. Once over it stays over:
/// when the held frame after next comes is known once the next has.
({int fromMicros, int untilMicros}) quietBetweenHeldFrames({
  required HeldFrames held,
  required int marginMicros,
}) {
  final (:vblankMicros, :periodMicros, :gap, :handOffMicros) = held;
  return (
    fromMicros: (vblankMicros + periodMicros - presentLatchLateMicros)
        .round(),
    untilMicros:
        (vblankMicros + gap * periodMicros + handOffMicros).round() -
        marginMicros,
  );
}

/// What a run's held frames say of the quiet they leave: the vblank the
/// last claimed and the refresh period, the fewest refreshes the next can
/// stand past it, and where against its vblank a frame is handed over
/// ([quietBetweenHeldFrames]).
typedef HeldFrames = ({
  double vblankMicros,
  double periodMicros,
  int gap,
  double handOffMicros,
});
