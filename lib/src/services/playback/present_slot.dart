import 'dart:math' as math;

/// 🚨THE COMPOSITOR'S LATCH, MEASURED (Windows, DWM, a 144Hz screen,
/// 2026-10-11 — the desktop's own frames read back through Desktop
/// Duplication, ~900 film changes over six runs, joined to the app's frame
/// times): a picture whose raster ENDS between
/// `vblank + presentLatchEarlyMicros` and
/// `next vblank − presentLatchLateMicros` is shown
/// [presentShownAfterVblanks] vblanks on, every time. One that ends in the
/// last 0.7ms before a vblank is sometimes shown a vblank later; one that
/// ends in the first 1.75ms after one is now and then caught early, when
/// the compositor wakes late.
///
/// Between those edges the vblank a picture lands on depends on nothing but
/// WHEN its raster ends — not on how long the frame took, and not on the
/// engine's own vsync, which on Windows is a grid of its own that never
/// meets the real one ([PresentClaims]).
const int presentLatchEarlyMicros = 1750;
const int presentLatchLateMicros = 700;

/// How many vblanks after the one its raster ends past a picture is shown:
/// the compositor takes what is ready at its latch and shows it on the
/// vblank after next.
const int presentShownAfterVblanks = 2;

/// A look's claim on a vblank: the hand-off — any moment from
/// [handOffFromMicros] to [handOffByMicros] puts a raster of the measured
/// spread between the latch's edges — and the moment its picture is shown.
typedef PresentClaim = ({
  int handOffFromMicros,
  int handOffByMicros,
  int shownAtMicros,
});

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
/// hands its scene to the GPU inside that vblank's hand-off window, and the
/// clock is read at the moment that vblank's picture is SHOWN. One look,
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
  /// to come taking at most [budgetMicros] and its raster running
  /// [rasterLowMicros] to [rasterHighMicros] past the hand-off.
  ///
  /// [vblankMicros] is any real vblank and [periodMicros] the real refresh
  /// period, both on the frame clock.
  PresentClaim claim({
    required int nowMicros,
    required int vblankMicros,
    required double periodMicros,
    required int budgetMicros,
    required int rasterLowMicros,
    required int rasterHighMicros,
  }) {
    // The hand-off's window against the vblank its raster ends past — or,
    // where the spread is wider than the latch leaves, its middle.
    var from = presentLatchEarlyMicros - rasterLowMicros.toDouble();
    var by = periodMicros - presentLatchLateMicros - rasterHighMicros;
    if (by < from) {
      from = by = (from + by) / 2;
    }
    int indexOf(double micros) =>
        ((micros - vblankMicros) / periodMicros).round();
    final natural =
        ((nowMicros + budgetMicros - by - vblankMicros) / periodMicros).ceil();
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
      handOffFromMicros: (vblank + from).round(),
      handOffByMicros: (vblank + by).round(),
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

/// How long a paced frame's raster runs past its hand-off — the spread a
/// claim's window is placed for — followed over the last [capacity] paced
/// frames.
///
/// ⚠️QUANTILES, NOT THE EXTREMES: a raster that an upload lands in (a
/// texture made on the raster thread, 8–13ms) would drag the window's
/// whole placement after it, and every ordinary frame would then end hard
/// by the early edge. The spikes are taken out where they come from.
final class RasterSpread {
  RasterSpread({this.capacity = 64});

  final int capacity;
  final List<int> _recent = [];
  int _next = 0;

  /// Before any paced frame has said: what a whole-window raster of this
  /// app took after its hand-off on the machine the latch was measured on.
  static const int unmeasuredLowMicros = 3500;
  static const int unmeasuredHighMicros = 7500;

  void add(int micros) {
    if (_recent.length < capacity) {
      _recent.add(micros);
    } else {
      _recent[_next] = micros;
      _next = (_next + 1) % capacity;
    }
  }

  int get lowMicros => _quantile(0.1, unmeasuredLowMicros);

  int get highMicros => _quantile(0.9, unmeasuredHighMicros);

  int _quantile(double fraction, int unmeasured) {
    if (_recent.length < 8) {
      return unmeasured;
    }
    final sorted = [..._recent]..sort();
    final index = math.min(
      sorted.length - 1,
      (fraction * sorted.length).floor(),
    );
    return sorted[index];
  }
}
