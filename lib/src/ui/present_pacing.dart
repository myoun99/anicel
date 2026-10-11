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
/// lets the look after it take back the lead its wait spent
/// ([PresentClaims.changed]). Said anywhere else, it is nobody's news.
void lookChangedWhatItShows() {
  final binding = SchedulerBinding.instance;
  if (binding is PresentPacing) {
    binding._changedInALook();
  }
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
/// with the rest, and only the raster's own spread is left for the window
/// to hold ([RasterSpread], learned from the frames it paced). Any moment
/// in the window lands the picture on the same vblank, so the wait is the
/// shortest that reaches it.
///
/// A frame no clock looked in is handed over the moment it is built — an
/// edit is never held for a vblank. A frame a clock looked in is handed
/// over in its claim's window whatever else asked for it to be drawn: a
/// page turn or a tile landing in the same frame shows on the same vblank
/// as the film it carries.
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
  final RasterSpread _spread = RasterSpread();

  /// Whether the frame under way has been asked for its claim, and the
  /// claim — null for a frame no clock looked in, or no display that says.
  bool _claimAsked = false;
  PresentClaim? _claim;

  /// Each paced frame by its number, with the moment its seam let it go —
  /// waiting for the frame's timings to say when its raster ended.
  final Map<int, int> _paced = <int, int>{};

  TimingsCallback? _learning;

  /// A test's own run starts where a run starts — every test replays the
  /// same frame times, and a chain left by the test before would go on.
  @visibleForTesting
  void debugForgetClaims() => _claims.forget();

  @override
  void handleBeginFrame(Duration? rawTimeStamp) {
    _claimAsked = false;
    _claim = null;
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
    return _claims.claim(
      nowMicros: timing.nowMicros,
      vblankMicros: grid.vblankMicros,
      periodMicros: grid.periodMicros,
      budgetMicros: budgetMicros,
      rasterLowMicros: _spread.lowMicros,
      rasterHighMicros: _spread.highMicros,
    );
  }

  void _changedInALook() {
    if (_claim != null) {
      _claims.changed();
    }
  }

  @override
  ui.SceneBuilder createSceneBuilder() {
    final claim = _claim;
    final timing = displayTiming;
    if (claim != null && timing != null) {
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
