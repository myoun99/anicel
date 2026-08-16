import 'package:flutter/foundation.dart';

/// The app's MEASUREMENT switches — the diagnosis overlays, in one place.
///
/// This is the second of them. The first is the pen program's
/// `InputInspector` (Settings ▸ Input Inspector), and they answer different
/// questions about the same session: the inspector says what the platform
/// DELIVERED, this says what the app did with the frame it had. Both are
/// static [ValueNotifier]s toggled from the top strip's SETTINGS popover,
/// both inert until asked for.
///
/// ⚠️These used to say "Edit ▸", and the Edit menu has not existed since
/// the seven-menu bar was replaced by the top strip — every command it
/// carried moved to the surface that shows its result. A stale path in a
/// doc comment is worse than none: it sent a reader looking for a menu
/// that is not there, which has already cost one round.
abstract final class MeasurementMode {
  /// Flutter's frame-timing overlay (Settings ▸ Frame Timing Overlay): two
  /// graphs over the app. Each bar is a frame; the line across them is the
  /// frame budget, so bars crossing it are the jank.
  ///
  /// 🚨WHICH GRAPH IS WHICH — this comment had it BACKWARDS, and getting it
  /// backwards means reading GPU jank as Dart jank and fixing the wrong
  /// thread:
  ///
  ///  * TOP    = the RASTER thread. Replaying the recorded picture into
  ///             pixels: uploads, shaders, `saveLayer` offscreens.
  ///  * BOTTOM = the UI thread. Dart — build, layout and paint, where
  ///             "paint" RECORDS commands and touches no pixel at all.
  ///
  /// ⚠️Each graph is LABELLED on screen. Read the label, not the position —
  /// this file has already been wrong about the position once.
  ///
  /// Read it while DOING the thing — Flutter renders on demand, so an
  /// idle app sitting at 0fps is not a finding. What it is for: the three
  /// canvas workloads want opposite things from the frame clock and only
  /// measurement separates them — a stroke wants the lowest latency at
  /// the display's full rate (120Hz on ProMotion, which
  /// `CADisableMinimumFrameDurationOnPhone` in ios/Runner/Info.plist
  /// unlocks), playback wants exactly the cel rate and nothing more, and
  /// a scrub wants no re-raster of cels it already holds.
  ///
  /// A TOGGLE and not just a build flag because flipping a `--dart-define`
  /// on a tablet costs a full rebuild and reinstall — useless for "watch
  /// this one stroke". The define below only seeds the starting value, so
  /// a run can still start with it on.
  ///
  /// Orthogonal to `--profile`: this decides what is DRAWN, the build mode
  /// decides what is MEASURED. In a debug build these are debug-build
  /// frame times, which is this project's performance bar; `flutter run
  /// --profile` gives near-release numbers and the DevTools timeline to
  /// take a bottleneck apart once the overlay says which thread lost.
  static final ValueNotifier<bool> frameTimingOverlay = ValueNotifier<bool>(
    startWithFrameTimingOverlay,
  );

  /// Paints MAGENTA wherever the canvas painter had no picture for a
  /// coordinate it was asked to draw (Settings ▸ Show Unpainted Tiles).
  ///
  /// The third switch, and the one this app should have had first. Every
  /// artifact in the stale-tile family — a stroke's last tiles missing at
  /// pen-up, a commit arriving tile by tile, a transform's landing half
  /// absent — is the same event underneath: a tile whose bytes exist and
  /// whose image does not. It is invisible by construction, because the
  /// painter's answer to "I have nothing here" is to draw nothing, so
  /// each one had to be found by hand and reported from a real session.
  /// Turned on, they announce themselves in the frame they happen.
  ///
  /// Borrowed from MyPaint's `visualize_rendering`, whose own comment
  /// says it exists to make it apparent if something is not being
  /// painted.
  ///
  /// ⚠️ Magenta means "no picture", not "no artwork". A coordinate that
  /// is genuinely empty is never drawn at all and never flashes; what
  /// flashes is a coordinate with content the painter could not show.
  static final ValueNotifier<bool> showUnpaintedTiles = ValueNotifier<bool>(
    startWithUnpaintedTiles,
  );

  /// The frame clock in NUMBERS (Settings ▸ Frame Stats): raster, UI and
  /// end-to-end latency as p50/p95, plus the engine's raster-cache
  /// counts. See [FrameStats].
  ///
  /// The fourth switch, and the one that answers what the graphs above
  /// cannot. Three reasons it exists next to them rather than instead of
  /// them:
  ///
  ///  * **Percentiles.** The overlay reports max and avg. An average
  ///    over a rolling window reads the same for a flat cost and a
  ///    RISING one, which is the exact shape of "it gets worse as I
  ///    keep working"; a max is a single frame.
  ///  * **Latency.** `FrameTiming.totalSpan` is the whole pipeline for
  ///    one frame, and Flutter pipelines — build and raster can both sit
  ///    inside budget while the end-to-end span runs long, which is what
  ///    "smooth but the pen feels behind" is made of. The overlay has no
  ///    line for it.
  ///  * **Retained raster.** `layerCacheCount`/`pictureCacheCount` are
  ///    the only way from Dart to see whether a repaint boundary bought
  ///    anything on the GPU. A boundary stops re-RECORDING; only the
  ///    cache stops re-RASTERIZING.
  ///
  /// ⚠️Prefer this one when the two disagree. The overlay is two
  /// full-width bar graphs redrawn every frame INSIDE the scene whose
  /// raster time it reports — it is part of its own measurement. This
  /// is six lines of text at 4 Hz behind a repaint boundary.
  static final ValueNotifier<bool> frameStats = ValueNotifier<bool>(
    startWithFrameStats,
  );

  /// Tints a surface every time it is BAKED (Settings ▸ Show Repaints).
  ///
  /// The fifth switch, and the one two mature apps decided they could not
  /// ship without: Krita carries `KisRepaintDebugger` in production and
  /// paints it at the end of `paintGL`; Blender tints every drawn region
  /// a random colour under `G.debug_value == 888`, commented "for
  /// debugging unneeded area redraws and partial redraw".
  ///
  /// The reason is the one this program keeps rediscovering: **a panel
  /// paying full price looks exactly like a free one.** The standing
  /// report says which panels bake; this says WHEN, while you work. A
  /// surface that flickers as you move the pen is re-baking on your
  /// pointer, and no amount of reading finds that as fast as seeing it.
  ///
  /// The tint cycles per bake, so a surface baking every frame strobes
  /// and one that baked once sits still.
  static final ValueNotifier<bool> showRepaints = ValueNotifier<bool>(
    startWithShowRepaints,
  );

  /// ⓔ 6단계 A/B — the compose KNEE at 1 (Settings ▸ Screen-Res Buffer).
  ///
  /// OFF (default, today): the screen-scale buffer runs only past the
  /// 8192 cap, where the alternative was the direct walk. ON: it runs
  /// whenever the artwork has more pixels than the screen (`zoom·dpr
  /// < 1`), which is stage 6's whole content — one constant's worth of
  /// change, behind a switch so a tablet can A/B it in the SAME build
  /// without a rebuild and reinstall.
  ///
  /// What the device A/B is looking at, per the plan's four check-points
  /// (유저 질문 「e6단계 확인은 어떻게하지?」, 2026-08-16):
  ///
  ///  1. BELOW 100%: overall lightness/weight of the picture — the
  ///     buffer resamples ONCE uniformly where the walk resampled per
  ///     layer.
  ///  2. The T21 feel: active layer and neighbours under one filter —
  ///     the active layer must stop reading crisper/rougher than the
  ///     layers beside it while zoomed out.
  ///  3. The ACCEPTED cost (결정 ①): semi-transparent overlaps may tint
  ///     slightly differently below 100%. Expected, not a bug.
  ///  4. AT/ABOVE 100%: nothing may change, byte for byte — the gate
  ///     never fires at `s >= 1`, so any difference seen there is a
  ///     defect.
  ///
  /// Flipping the default to ON later IS stage 6's landing; this switch
  /// is how that decision gets its device evidence first.
  static final ValueNotifier<bool> kneeAtOne = ValueNotifier<bool>(
    startWithKneeAtOne,
  );

  /// Diagnosis A/B for the transition pixel jump (Settings ▸ Bypass
  /// Raster Cache): hints the engine not to raster-cache the canvas
  /// stack's picture.
  ///
  /// The jump under investigation (2026-08-16 실기, Windows): at
  /// fractional pan phase, axis-aligned edges hop 1px for a frame at
  /// pen-down/pen-up/layer-switch. The compose path was exonerated
  /// byte-for-byte (transition_pixel_jump_probe_test); the remaining
  /// suspect is Skia's raster cache, which snaps a stable picture to
  /// integral device translation while live repaints render fractional
  /// — and those transitions are exactly its engage/disengage moments.
  /// ON removes the cache from the equation: jump gone = confirmed.
  ///
  /// ⚠️A/B switch, not a fix — ON makes the idle canvas re-rasterize
  /// every composited frame. The durable fix on confirmation is
  /// snapping OUR canvas translation to device pixels so the cached and
  /// live renders agree. Impeller (iPad/Android) has no picture raster
  /// cache, so this switch should change nothing there.
  static final ValueNotifier<bool> bypassCanvasRasterCache =
      ValueNotifier<bool>(startWithBypassCanvasRasterCache);

  /// Seeds [bypassCanvasRasterCache]:
  ///
  /// ```
  /// flutter run --dart-define=QA_BYPASS_RASTER_CACHE=true
  /// ```
  static const bool startWithBypassCanvasRasterCache = bool.fromEnvironment(
    'QA_BYPASS_RASTER_CACHE',
  );

  /// Seeds [kneeAtOne]:
  ///
  /// ```
  /// flutter run --dart-define=QA_KNEE_AT_ONE=true
  /// ```
  static const bool startWithKneeAtOne = bool.fromEnvironment(
    'QA_KNEE_AT_ONE',
  );

  /// Seeds [showRepaints]:
  ///
  /// ```
  /// flutter run --dart-define=QA_SHOW_REPAINTS=true
  /// ```
  static const bool startWithShowRepaints = bool.fromEnvironment(
    'QA_SHOW_REPAINTS',
  );

  /// Seeds [frameStats]:
  ///
  /// ```
  /// flutter run --dart-define=QA_FRAME_STATS=true
  /// ```
  static const bool startWithFrameStats = bool.fromEnvironment(
    'QA_FRAME_STATS',
  );

  /// Seeds [showUnpaintedTiles], same shape as the overlay's define:
  ///
  /// ```
  /// flutter run --dart-define=QA_SHOW_UNPAINTED=true
  /// ```
  static const bool startWithUnpaintedTiles = bool.fromEnvironment(
    'QA_SHOW_UNPAINTED',
  );

  /// Seeds [frameTimingOverlay] so a measurement run can start with the
  /// graphs already up:
  ///
  /// ```
  /// flutter run --profile --dart-define=QA_PERF_OVERLAY=true
  /// ```
  ///
  /// False in every ordinary build, pinned by a test — an overlay left on
  /// ships two graphs across the user's canvas.
  static const bool startWithFrameTimingOverlay = bool.fromEnvironment(
    'QA_PERF_OVERLAY',
  );

  /// Test hygiene: back to the build's own defaults.
  @visibleForTesting
  static void reset() {
    frameTimingOverlay.value = startWithFrameTimingOverlay;
    showUnpaintedTiles.value = startWithUnpaintedTiles;
    frameStats.value = startWithFrameStats;
    showRepaints.value = startWithShowRepaints;
    kneeAtOne.value = startWithKneeAtOne;
    bypassCanvasRasterCache.value = startWithBypassCanvasRasterCache;
  }
}
