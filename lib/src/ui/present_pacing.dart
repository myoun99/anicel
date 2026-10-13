import 'dart:math' as math;
import 'dart:ui' as ui show FramePhase, FrameTiming, SceneBuilder;

import 'package:flutter/foundation.dart' show protected, visibleForTesting;
import 'package:flutter/scheduler.dart' show SchedulerBinding, TimingsCallback;
import 'package:flutter/widgets.dart' show WidgetsBinding;

import '../native/qa_display_timing.dart';
import '../services/playback/present_slot.dart';

/// 🚨THE MOMENT THE FRAME UNDER WAY IS SHOWN, ON THE FRAME CLOCK — the time
/// a clock that looks in it is read at (유저 2026-10-08: 「소리 싱크나
/// 영상이나 뭐 그런거 정확하기만하면되. 그게 제일 최우선.」).
///
/// Where the display says where its vblanks are, the vblank this look
/// claimed is shown at a known moment ([PresentPacing]); everywhere else the
/// frame's own time is the moment the engine means it to be shown — the
/// vsync it is due on.
Duration frameShownAt() {
  final binding = SchedulerBinding.instance;
  final claimed = binding is PresentPacing ? binding._shownAtOfALook() : null;
  return claimed ?? binding.currentSystemFrameTimeStamp;
}

/// A clock's look changed what it shows in the frame under way — what
/// holds the frame for its claim's window ([PresentPacing]), and lets the
/// look after it take back the lead that wait spent
/// ([PresentClaims.changed]). Said anywhere else, it is nobody's news.
void lookChangedWhatItShows() {
  final binding = SchedulerBinding.instance;
  if (binding is PresentPacing) {
    binding._changedInALook();
  }
}

/// [clock] follows time from now on, until it says [clockStopped]: while
/// any clock does, the compositor is kept composing on every vblank
/// ([PresentPacing]). Said anywhere else, it is nobody's news.
void clockStarted(Object clock) {
  final binding = SchedulerBinding.instance;
  if (binding is PresentPacing) {
    binding._clockRuns(clock, running: true);
  }
}

/// [clock] no longer follows time ([clockStarted]).
void clockStopped(Object clock) {
  final binding = SchedulerBinding.instance;
  if (binding is PresentPacing) {
    binding._clockRuns(clock, running: false);
  }
}

/// When background GPU work — an upload, a bake — can run without running
/// beside a held frame's raster, on the frame clock
/// ([quietBetweenHeldFrames] has why): EMPTY where a run leaves no room,
/// and null only where nothing is held — no display that says, or no clock
/// running.
({int fromMicros, int untilMicros})? quietForBackgroundGpuWork() {
  final binding = SchedulerBinding.instance;
  return binding is PresentPacing ? binding._quiet() : null;
}

/// 🚨A CLOCK'S LOOK CLAIMS A REAL VBLANK, AND ITS FRAME HANDS ITS SCENE TO
/// THE GPU IN THAT VBLANK'S WINDOW (유저 2026-10-11: 「144hz든 몇이든
/// 확실하게 근본/구조적으로 해결하도록」) — [PresentClaims] has why, and
/// which vblank; [frameShownAt] is when it is seen.
///
/// The hand-off is the framework's own seam between painting and the scene
/// ([createSceneBuilder] — called once a frame, by
/// `RenderView.compositeFrame`, and nowhere else): by then the frame is
/// built, laid out and painted, so however long that took is waited out
/// with the rest, and only the scene's own length is left for the window
/// to place ([RasterSpread], learned from the frames it paced): the frame
/// is handed over at the window's start, or at once anywhere up to its end.
///
/// 🚨ONLY A LOOK THAT CHANGED WHAT ITS CLOCK SHOWS IS HELD (10-12): a look
/// that changed nothing shows the same picture whichever vblank its frame
/// lands on, so a page turn or a tile landing drawn between two film
/// frames is handed over the moment it is built, and the lengths learned
/// are those of the changing frames — the ones whose landing IS the
/// cadence. A frame that carries a change is handed over in its claim's
/// window whatever else asked for it to be drawn: a page turn in the same
/// frame shows on the same vblank as the film it carries. A frame no clock
/// looked in is never held — an edit waits for no vblank.
///
/// 🚨WHILE A CLOCK RUNS THE COMPOSITOR COMPOSES ON EVERY VBLANK (10-13,
/// the compositor's own per-frame statistics against the vblank each film
/// frame claimed): Windows' compositor composes on demand, and a frame of
/// its reaches the glass on the second vblank after it starts — an idle one
/// starts the moment a picture is handed to it, a busy one at the next
/// vblank. The same hand-off reached the glass two vblanks after its claim
/// or three as the rest of the desktop kept the compositor idle or busy, and
/// 39–47 film frames in a hundred were a refresh off their neighbours. Kept
/// composing ([DisplayTiming.composeEveryVblank]), it takes every picture at
/// the vblank after its claim and shows it [presentShownAfterVblanks] on.
/// From [clockStarted] to the last [clockStopped], so a desktop no clock is
/// running on rests as it did.
///
/// ⛔Where the engine's vsync IS the display's — every platform but Windows
/// — there is no [displayTiming], nothing is claimed and nothing waits:
/// there a frame is shown on the vsync after its raster, which the build
/// already starts on.
mixin PresentPacing on WidgetsBinding {
  /// The display's timing: the engine's own ([QaDisplayTiming]), or
  /// null where the engine's vsync is the display's. A test hands its own.
  @protected
  DisplayTiming? get displayTiming => QaDisplayTiming.instance;

  /// How long a look's frame may still take, from the look to the seam,
  /// for the vblank it claims to be within reach. 🔬Measured 1.5–3ms from
  /// the tick to the hand-off on the frames a film frame changes in
  /// (profile, 144Hz); a claim stands a vblank of lead past this besides.
  static const int budgetMicros = 3000;

  final PresentClaims _claims = PresentClaims();
  RasterSpread _spread = RasterSpread();

  /// Whether the frame under way has been asked for its claim, and the
  /// claim — null for a frame no clock looked in, or no display that says.
  bool _claimAsked = false;
  PresentClaim? _claim;

  /// Whether a look in the frame under way changed what its clock shows —
  /// the only frame that is held for its claim's window.
  bool _changed = false;

  /// Each paced frame by its number, with the moment its seam let it go —
  /// waiting for the frame's timings to say when its raster ended.
  final Map<int, int> _paced = <int, int>{};

  TimingsCallback? _learning;

  /// When a clock last looked, the vblank the last held frame claimed, and
  /// how many refreshes apart the last held frames claimed theirs: what the
  /// quiet between held frames is read off ([quietForBackgroundGpuWork]).
  int? _lookedAt;
  double? _heldVblank;
  final List<int> _heldGaps = <int>[];

  /// No look for this long and no clock is running: nothing is held.
  static const int _runGoneMicros = 100000;

  /// The clocks running now ([clockStarted]): while there are any, the
  /// compositor composes on every vblank.
  final Set<Object> _clocks = <Object>{};

  void _clockRuns(Object clock, {required bool running}) {
    final composing = _clocks.isNotEmpty;
    if (running) {
      _clocks.add(clock);
    } else {
      _clocks.remove(clock);
    }
    if (_clocks.isNotEmpty != composing) {
      displayTiming?.composeEveryVblank(on: _clocks.isNotEmpty);
    }
  }

  /// A test's own run starts where a run starts — every test replays the
  /// same frame times, and a chain left by the test before would go on, and
  /// the lengths it taught would place the window.
  @visibleForTesting
  void debugForgetClaims() {
    _claims.forget();
    _spread = RasterSpread();
    _paced.clear();
    _lookedAt = null;
    _heldVblank = null;
    _heldGaps.clear();
    _clocks.clear();
  }

  @override
  void handleBeginFrame(Duration? rawTimeStamp) {
    _claimAsked = false;
    _claim = null;
    _changed = false;
    super.handleBeginFrame(rawTimeStamp);
  }

  Duration? _shownAtOfALook() {
    if (!_claimAsked) {
      _claimAsked = true;
      _claim = _claimFor();
    }
    final claim = _claim;
    return claim == null ? null : Duration(microseconds: claim.shownAtMicros);
  }

  PresentClaim? _claimFor() {
    final timing = displayTiming;
    final grid = timing?.vblankGrid();
    if (timing == null || grid == null) {
      return null;
    }
    final now = _lookedAt = timing.nowMicros;
    return _claims.claim(
      nowMicros: now,
      vblankMicros: grid.vblankMicros,
      periodMicros: grid.periodMicros,
      budgetMicros: budgetMicros,
      handOff: _spread.handOffFor(grid.periodMicros),
    );
  }

  void _changedInALook() {
    if (_claim != null) {
      _changed = true;
      _claims.changed();
    }
  }

  @override
  ui.SceneBuilder createSceneBuilder() {
    final claim = _claim;
    final timing = displayTiming;
    if (claim != null && timing != null && _changed) {
      _handOver(claim, timing);
    }
    return super.createSceneBuilder();
  }

  void _handOver(PresentClaim claim, DisplayTiming timing) {
    if (_learning == null) {
      addTimingsCallback(_learning = _learn);
    }
    if (timing.nowMicros < claim.handOffFromMicros) {
      timing.waitUntil(claim.handOffFromMicros);
    }
    if (_paced.length > 256) {
      _paced.clear();
    }
    _paced[platformDispatcher.frameData.frameNumber] = timing.nowMicros;
    final period = _periodOf(timing);
    final vblank = claim.shownAtMicros - presentShownAfterVblanks * period;
    final before = _heldVblank;
    if (before != null) {
      if (_heldGaps.length == 8) {
        _heldGaps.removeAt(0);
      }
      _heldGaps.add(((vblank - before) / period).round());
    }
    _heldVblank = vblank;
  }

  double _periodOf(DisplayTiming timing) =>
      timing.vblankGrid()?.periodMicros ?? 1e6 / 60;

  ({int fromMicros, int untilMicros})? _quiet() {
    final timing = displayTiming;
    final lookedAt = _lookedAt;
    final vblank = _heldVblank;
    if (timing == null ||
        lookedAt == null ||
        vblank == null ||
        _heldGaps.isEmpty) {
      return null;
    }
    if (timing.nowMicros - lookedAt > _runGoneMicros) {
      return null;
    }
    // The second fewest of the last gaps: one odd one — the loop's wrap, a
    // run's first frames — does not shut every quiet after it.
    final gaps = [..._heldGaps]..sort();
    final period = _periodOf(timing);
    return quietBetweenHeldFrames(
      held: (
        vblankMicros: vblank,
        periodMicros: period,
        gap: gaps[math.min(1, gaps.length - 1)],
        handOffFromMicros: _spread.handOffFor(period).fromMicros,
      ),
      // What the next held frame's own work may still take before its
      // hand-off ([budgetMicros]), and a millisecond.
      marginMicros: budgetMicros + 1000,
    );
  }

  void _learn(List<ui.FrameTiming> timings) {
    for (final frame in timings) {
      final released = _paced.remove(frame.frameNumber);
      if (released != null) {
        _spread.add(
          frame.timestampInMicroseconds(ui.FramePhase.rasterFinish) - released,
        );
      }
    }
  }
}
