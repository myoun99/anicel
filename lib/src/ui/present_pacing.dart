import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui
    show
        Canvas,
        FramePhase,
        FrameTiming,
        Paint,
        PictureRecorder,
        Rect,
        SceneBuilder;

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
/// holds the frame for its claim's hand-off ([PresentPacing]), and lets the
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

/// Completes when the quiet between held frames may have moved
/// ([quietForBackgroundGpuWork]): a frame was held — the quiet it leaves
/// is the next — the last clock stopped, or no clock has looked for long
/// enough that nothing will be held. At once where no quiet is kept.
Future<void> quietMayHaveMoved() {
  final binding = SchedulerBinding.instance;
  return binding is PresentPacing
      ? binding._quietMoves()
      : Future<void>.value();
}

/// 🚨A CLOCK'S LOOK CLAIMS A REAL VBLANK, AND ITS FRAME HANDS ITS SCENE TO
/// THE GPU AT THAT VBLANK'S HAND-OFF (유저 2026-10-11: 「144hz든 몇이든
/// 확실하게 근본/구조적으로 해결하도록」) — [PresentClaims] has why, and
/// which vblank; [frameShownAt] is when it is seen.
///
/// The hand-off is the framework's own seam between painting and the scene
/// ([createSceneBuilder] — called once a frame, by
/// `RenderView.compositeFrame`, and nowhere else): by then the frame is
/// built, laid out and painted, so however long that took is waited out
/// with the rest, and only the scene's own length is left for the hand-off
/// to place ([RasterSpread], learned from the frames it paced): the frame
/// is handed over then, or at once if it comes later.
///
/// 🚨ONLY A LOOK THAT CHANGED WHAT ITS CLOCK SHOWS IS HELD (10-12): a look
/// that changed nothing shows the same picture whichever vblank its frame
/// lands on, so a page turn or a tile landing drawn between two film
/// frames is handed over the moment it is built, and the lengths learned
/// are those of the changing frames — the ones whose landing IS the
/// cadence. A frame that carries a change is handed over at its claim's
/// hand-off whatever else asked for it to be drawn: a page turn in the same
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
  /// the only frame that is held for its claim's hand-off.
  bool _changed = false;

  /// Each paced frame by its number: the moment its seam let it go, and the
  /// moment the raster thread was seen past its scene ([rasterBehind]) —
  /// waiting for the frame's timings to say when its raster really ended
  /// ([_seenLate]).
  final Map<int, ({int released, int? seen})> _paced =
      <int, ({int released, int? seen})>{};

  TimingsCallback? _learning;

  /// How long after a scene's raster ends the raster thread is seen past it
  /// ([rasterBehind]) — the fence's own raster and its way back to this
  /// thread — as the frames' timings last said: the median of a batch.
  int _seenLate = seenLateUnmeasuredMicros;

  /// Before the frames' timings have said: the median on the glass
  /// (2026-10-15, release, 144Hz, 742 held frames — p10 0.39 · p90 0.81ms).
  static const int seenLateUnmeasuredMicros = 540;

  /// When a clock last looked, the vblank the last held frame claimed, and
  /// how many refreshes apart the last held frames claimed theirs: what the
  /// quiet between held frames is read off ([quietForBackgroundGpuWork]).
  int? _lookedAt;
  double? _heldVblank;
  final List<int> _heldGaps = <int>[];

  /// No look for this long: a clock that is running but no longer looks —
  /// its ticker silenced, the route it is on not shown — holds nothing
  /// either. (A clock that stopped holds nothing from that moment
  /// ([clockStopped]).)
  static const int _runGoneMicros = 100000;

  /// What waits for the quiet to move ([quietMayHaveMoved]), and what tells
  /// it once no clock has looked for [_runGoneMicros].
  Completer<void>? _quietMove;
  Timer? _quietMoving;

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
      if (_clocks.isEmpty) {
        // Nothing will be held: what waits for a quiet need not.
        _quietMoved();
      }
    }
  }

  /// A test's own run starts where a run starts — every test replays the
  /// same frame times, and a chain left by the test before would go on, and
  /// the lengths it taught would place the hand-off.
  @visibleForTesting
  void debugForgetClaims() {
    _claims.forget();
    _spread = RasterSpread();
    _paced.clear();
    _seenLate = seenLateUnmeasuredMicros;
    _lookedAt = null;
    _heldVblank = null;
    _heldGaps.clear();
    _quietMoved();
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
      handOffMicros: _spread.handOffFor(grid.periodMicros),
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
    if (timing.nowMicros < claim.handOffMicros) {
      timing.waitUntil(claim.handOffMicros);
    }
    if (_paced.length > 256) {
      _paced.clear();
    }
    final frame = platformDispatcher.frameData.frameNumber;
    final released = timing.nowMicros;
    _paced[frame] = (released: released, seen: null);
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
    // Laid from a microtask: those run once the frame has handed its scene
    // to the raster thread, and this one before what the quiet's waiters
    // post behind it (🔬10-15: 1 of 742 came back before the raster's end;
    // laid from a timer, the median came back 0.16ms later).
    scheduleMicrotask(() => _seeTheRasterEnd(frame, released));
    // Told now, before the scene this frame hands over is built: what it
    // wakes runs once the frame is done, behind that scene.
    _quietMoved();
  }

  /// 🚨A HELD FRAME'S LENGTH IS READ AS ITS RASTER ENDS (2026-10-15, the
  /// glass): the moment the raster thread is seen past the frame's scene
  /// ([rasterBehind]), less how late it is seen ([_seenLate]).
  ///
  /// The frames' own timings say it exactly, but a release build hands them
  /// over about once a second (debug and profile every 100ms — the latch was
  /// measured in profile), and a run's first second taught the next: the
  /// held frames of a cut played from nothing took 3–11ms the first time a
  /// film frame was shown and 2–3ms every time after, and a hand-off placed
  /// for the long ones put 20 film frames in a row a refresh early (cut 302,
  /// 1.04–1.96s). Replayed over two runs' own lengths (742 held frames),
  /// reading each as it ends put 11.5 film changes a refresh off where the
  /// second's batches put 19.1.
  void _seeTheRasterEnd(int frame, int released) {
    unawaited(
      rasterBehind().then((_) {
        final timing = displayTiming;
        if (timing == null) {
          return;
        }
        final seen = timing.nowMicros;
        if (_paced.containsKey(frame)) {
          _paced[frame] = (released: released, seen: seen);
        }
        _spread.add(seen - _seenLate - released);
      }, onError: (Object _) {}),
    );
  }

  /// Completes once the raster thread is past everything handed to it before
  /// the call: an image of next to nothing, rastered behind it. A test hands
  /// its own.
  @protected
  Future<void> rasterBehind() async {
    final recorder = ui.PictureRecorder();
    ui.Canvas(
      recorder,
    ).drawRect(const ui.Rect.fromLTWH(0, 0, 1, 1), ui.Paint());
    final picture = recorder.endRecording();
    try {
      (await picture.toImage(1, 1)).dispose();
    } finally {
      picture.dispose();
    }
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
        _heldGaps.isEmpty ||
        _clocks.isEmpty) {
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
        handOffMicros: _spread.handOffFor(period),
      ),
      // What the next held frame's own work may still take before its
      // hand-off ([budgetMicros]), and a millisecond.
      marginMicros: budgetMicros + 1000,
    );
  }

  Future<void> _quietMoves() {
    if (_quiet() == null) {
      return Future<void>.value();
    }
    _quietMoving ??= Timer(
      const Duration(microseconds: _runGoneMicros),
      _quietMoved,
    );
    return (_quietMove ??= Completer<void>()).future;
  }

  void _quietMoved() {
    _quietMoving?.cancel();
    _quietMoving = null;
    final move = _quietMove;
    _quietMove = null;
    move?.complete();
  }

  /// The frames' timings say how late the raster thread was seen past each
  /// paced scene ([_seeTheRasterEnd]) — what every length read after them
  /// is read less.
  void _learn(List<ui.FrameTiming> timings) {
    final late = <int>[];
    for (final frame in timings) {
      final seen = _paced.remove(frame.frameNumber)?.seen;
      if (seen != null) {
        late.add(
          seen - frame.timestampInMicroseconds(ui.FramePhase.rasterFinish),
        );
      }
    }
    if (late.isNotEmpty) {
      late.sort();
      _seenLate = late[late.length ~/ 2];
    }
  }
}
