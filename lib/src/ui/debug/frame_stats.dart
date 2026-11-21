import 'dart:ui' show FramePhase, FrameTiming, PlatformDispatcher, Size;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

import '../../native/screen_texture.dart';
import '../widgets/static_raster.dart';
import '../widgets/still_raster.dart';
import 'measurement_mode.dart';
import 'pointer_clock.dart';

/// One publication of the frame clock: percentiles over a rolling window,
/// plus the two numbers nobody in this app had ever read.
///
/// Why percentiles and not the max/avg the built-in overlay shows: an
/// average over a rolling window cannot tell a flat cost from a rising
/// one — a series climbing through the window produces the same
/// max/avg ratio as a steady one — and a max is one frame, so it moves
/// for reasons that have nothing to do with the change under test. p50
/// says what the session FEELS like and p95 says how bad the bad frames
/// are; a fix that halves the work moves both, and a fix that only
/// hides a spike moves p95 alone.
///
/// And why a saturating counter is deliberately absent: this program has
/// already been misled once by a metric that could only say "not zero
/// yet" (a jank counter with a 45 ms floor is pinned, so halving the
/// cost reads as no change at all).
@immutable
class FrameStatsSnapshot {
  const FrameStatsSnapshot({
    required this.frames,
    required this.windowSeconds,
    required this.rasterP50,
    required this.rasterP95,
    required this.rasterWorst,
    required this.uiP50,
    required this.uiP95,
    required this.uiWorst,
    required this.latencyP50,
    required this.latencyP95,
    required this.buildWaitP50,
    required this.buildWaitP95,
    required this.rasterWaitP50,
    required this.rasterWaitP95,
    required this.screenUpP50,
    required this.screenUpP95,
    required this.screensUpPerSecond,
    required this.screensBehindPerSecond,
    required this.screenDrawP50,
    required this.screenDrawP95,
    required this.screenFinishP50,
    required this.screenFinishP95,
    required this.screenShowP50,
    required this.screenShowP95,
    required this.windowsAreCopied,
    required this.pointsPerSecond,
    required this.packetsPerSecond,
    required this.pointerP50,
    required this.pointerP95,
    required this.pointerMillisPerSecond,
    required this.layerCacheCount,
    required this.layerCacheMegabytes,
    required this.pictureCacheCount,
    required this.pictureCacheMegabytes,
    required this.windowMegabytes,
    required this.devicePixelRatio,
    required this.windowPhysicalWidth,
    required this.windowPhysicalHeight,
    required this.bakedSurfaces,
    required this.bakedMegabytes,
    required this.bakesPerSecond,
    required this.blockedSurfaces,
    required this.blockedArea,
  });

  /// How many frames the window holds. Zero means the app produced none
  /// — Flutter renders on demand, so an idle app reporting nothing is
  /// not a finding.
  final int frames;

  /// Wall span the window covers, from the first frame's vsync to the
  /// last's. [framesPerSecond] divides by it.
  final double windowSeconds;

  final double rasterP50;
  final double rasterP95;
  final double rasterWorst;

  final double uiP50;
  final double uiP95;
  final double uiWorst;

  /// `FrameTiming.totalSpan` — vsync to raster-finish, i.e. the whole
  /// pipeline for one frame. THE latency number, and the one this
  /// codebase had no reader for at all.
  ///
  /// It answers a question the other two structurally cannot: Flutter
  /// pipelines, so build and raster can both sit inside budget while the
  /// end-to-end span runs several frames long. That is the shape of
  /// "animation is smooth but the pen feels behind", which is exactly
  /// how the ink-lag report reads.
  final double latencyP50;
  final double latencyP95;

  /// What of [latencyP50] is neither build nor raster: how long a frame
  /// stood before its build began (`FrameTiming.vsyncOverhead`) — the
  /// thread that builds the app's frames busy with something else: pointer
  /// packets ([pointerMillisPerSecond]), a screen's draw told finished and
  /// shown ([screenShowP50]) —, and how long it stood built before its
  /// raster began — the raster thread still on the frame before.
  ///
  /// 🔬Build 1095 on the Galaxy Tab, panning (유저 2026-11-21, card
  /// the-galaxy-tab-canvas-went-slow-on-build-1095): latency p50 30.3 ms
  /// against raster 9.5 and build 2.6 — some 18 ms a frame in neither,
  /// and no line said which of these two it was.
  final double buildWaitP50;
  final double buildWaitP95;
  final double rasterWaitP50;
  final double rasterWaitP95;

  /// The engine's screens — the canvas, the frame grids: how long their
  /// newest frames took from their draw to being put up
  /// (`ScreenTexture.upMicros`), and how many were put up a second.
  ///
  /// None of it is in the three durations above. A screen's frame is
  /// drawn by the engine, on no thread of Flutter's, and put up when the
  /// GPU has finished it: a canvas can stand three frames behind the pen
  /// while build, raster and latency all read inside budget. 🗣️유저
  /// 2026-11-21, a Galaxy Tab out of reach (card
  /// the-galaxy-tab-canvas-went-slow-on-build-1095): 「팬이나 줌이나
  /// 스트로크가 너무 느려졋어」, and no line here said whose frames were
  /// slow.
  ///
  /// ⚠️The percentiles are over the screens' own newest frames, not over
  /// this window's: with no screen drawing they are what the last ones
  /// took. The rate is a slope over the interval since the last
  /// publication, as [bakesPerSecond] is.
  final double screenUpP50;
  final double screenUpP95;
  final double screensUpPerSecond;

  /// How many of the frames put up a second went up with a newer one asked
  /// for meanwhile (`ScreenTexture.upsBehindCounted`): near
  /// [screensUpPerSecond], the screens are what holds the picture back;
  /// near none, they put up all that was asked of them.
  final double screensBehindPerSecond;

  /// [screenUpP50] part by part (`ScreenUp`): the draw — on Android the
  /// wait for the window's next image is in it —, the GPU finishing the
  /// frame and this isolate hearing so, and the show — on Android the
  /// present, with a copy of the whole screen where [windowsAreCopied].
  /// The draw and the show are on the thread that builds the app's frames.
  final double screenDrawP50;
  final double screenDrawP95;
  final double screenFinishP50;
  final double screenFinishP95;
  final double screenShowP50;
  final double screenShowP95;

  /// `ScreenTexture.windowsAreCopied`: null where no window was opened —
  /// every platform but Android.
  final bool? windowsAreCopied;

  /// The pointer packets the platform handed over (`PointerClock`): the
  /// points and the packets a second, how long a packet took to be dealt
  /// with, and how many milliseconds of each second went to them — on the
  /// thread that builds the app's frames, between its frames.
  final double pointsPerSecond;
  final double packetsPerSecond;
  final double pointerP50;
  final double pointerP95;
  final double pointerMillisPerSecond;

  /// The engine's retained-raster accounting, and the reason this class
  /// exists.
  ///
  /// A `RepaintBoundary` stops a subtree from being re-RECORDED on the
  /// UI thread. It does NOT stop the raster thread from re-executing
  /// that subtree's display list every frame — the pixels survive
  /// between frames only if the engine's raster cache is holding them.
  /// Nothing in Dart can observe that except these four numbers, so
  /// "did the boundary buy us anything" was until now unanswerable, and
  /// the whole retained-UI program turns on the answer.
  ///
  /// Read them like this: counts climbing to a small stable number while
  /// the megabytes sit at roughly (surface area x 4 bytes) means the
  /// engine IS holding pictures across frames. Counts pinned at zero
  /// while raster time stays high means every frame is being redrawn
  /// from scratch and caching has to be done by hand.
  final int layerCacheCount;
  final double layerCacheMegabytes;

  /// ⚠️These two used to report the app's cacheable population MINUS the
  /// four artwork pictures, which carried `willChange: true` and so never
  /// entered the cache at all. R11 retired those hints (R12 put two back
  /// for a few hours, R13 retired them again the same day with the cause
  /// measured — see `canvas_layer_stack_view.dart`), so the artwork can
  /// enter: **a RISE here is the expected reading, not a leak.**
  ///
  /// It is also the only route from Dart to observe whether the artwork
  /// actually did enter, which makes a Windows before/after reading the
  /// cheap positive confirmation that the retirement did what it claims
  /// (the history is in `canvas_layer_stack_view.dart`). ⛔Impeller holds
  /// no picture cache, so on mobile these do not move.
  final int pictureCacheCount;
  final double pictureCacheMegabytes;

  /// What one window-sized RGBA surface costs, so a cache total has
  /// something to be divided by. Without it, "495 MB" is unreadable.
  final double windowMegabytes;

  /// The view's scale factor and its size in DEVICE pixels.
  ///
  /// 🚨 The missing denominator behind the missing denominator. Every
  /// estimate this program has made about a cache entry is of the form
  /// `bounds × dpr²` — and the dpr was never measured once. A whole round
  /// of arithmetic ran parameterised by a number nobody had read, and the
  /// one time it was back-solved out of a byte total it came to 1.38,
  /// which is not a scale factor Windows offers.
  ///
  /// Printed as the raw triple rather than the derived logical size so it
  /// stays legible when the two disagree: a display list recorded at
  /// LOGICAL size and an entry allocated at DEVICE size differ by exactly
  /// this factor, and telling those two apart is the whole job.
  final double devicePixelRatio;
  final double windowPhysicalWidth;
  final double windowPhysicalHeight;

  /// What OUR baked panels cost, which the engine's counters above will
  /// never show — a `StaticRaster` bake and a `StillRaster` region's still
  /// image are ordinary `ui.Image`s the app holds, not cache entries.
  ///
  /// Qt warns about exactly our usage for the identical mechanism
  /// (`layer.enabled`: `w × h × 4` per layer, batching lost, "a scene
  /// with many layered items may have performance problems"), and we
  /// install bakes on blanket funnels so a new panel gets one for free.
  /// A default whose price is invisible is a default that gets abused.
  final int bakedSurfaces;
  final double bakedMegabytes;

  /// Bakes per second across every surface.
  ///
  /// This is the number that says the fix is not working: a baked panel
  /// should re-bake when it CHANGES, so a few per second is a person
  /// editing and sixty is a panel re-baking on the pointer. Blender gets
  /// this for free — its `do_draw` tag is set by named notifiers, so
  /// "who dirtied this region and why" is auditable. Ours is implicit in
  /// whether Flutter ran `paint()`, so the rate is the most we can say.
  final double bakesPerSecond;

  /// Surfaces painting through for a reason that could be fixed, and the
  /// screen area they cover in logical px².
  ///
  /// 🚨 A blocked panel is pixel-identical to a free one, so this is the
  /// only thing that reports it without turning a debug mode on. It was
  /// missing, and three panels went a whole round paying full price.
  final int blockedSurfaces;
  final double blockedArea;

  double get framesPerSecond => windowSeconds <= 0 ? 0 : frames / windowSeconds;

  @override
  String toString() =>
      'FrameStatsSnapshot(frames: $frames, raster p50 $rasterP50 '
      'p95 $rasterP95, ui p50 $uiP50 p95 $uiP95, latency p50 $latencyP50 '
      'p95 $latencyP95, layerCache $layerCacheCount, '
      'pictureCache $pictureCacheCount)';
}

/// The app's frame-clock recorder (Settings ▸ Frame Stats).
///
/// The fourth measurement switch, and the one that reads the numbers the
/// built-in overlay does not have. The overlay is the engine's own and
/// shows max/avg of two durations; this shows percentiles of three —
/// raster, UI, and END-TO-END LATENCY — plus the raster cache counts.
///
/// It is also the honest instrument in a way the overlay cannot be: the
/// overlay is two full-width bar graphs that change every single frame,
/// composited into the very scene whose raster time it reports, so it is
/// inside its own number. This draws a column of text at 4 Hz behind a
/// repaint boundary. When the two disagree, believe this one.
///
/// Registration lives in `main()` and NOT in the merged
/// `ListenableBuilder` around `MaterialApp` — that builder re-runs
/// whenever the accent colour changes, and registering there would add a
/// duplicate callback each time.
abstract final class FrameStats {
  /// How many frames the rolling window keeps. 240 is about four seconds
  /// at 60 Hz and two at 120 — long enough that p95 means something,
  /// short enough that the window still tracks what the hand is doing
  /// rather than averaging over a whole session.
  @visibleForTesting
  static const int windowFrames = 240;

  /// How often the readout republishes. Deliberately slow: the point of
  /// this instrument is to not be part of what it measures, and a
  /// readout that rebuilds every frame is the mistake the built-in
  /// overlay makes. Four times a second is faster than anyone can read
  /// and slower than anything it could perturb.
  ///
  /// The clock for it is the FRAME timestamps, not a `Timer` — an
  /// instrument that wakes on its own schedule manufactures frames when
  /// the app would otherwise be asleep, and manufacturing frames is the
  /// exact thing under investigation. Driving off the frames means the
  /// readout moves only while something is already moving, and an idle
  /// app leaves the last window on screen to be read.
  @visibleForTesting
  static const Duration publishInterval = Duration(milliseconds: 250);

  /// The published window. Null until enough frames have arrived.
  static final ValueNotifier<FrameStatsSnapshot?> latest =
      ValueNotifier<FrameStatsSnapshot?>(null);

  /// The bake counter at the previous publication, so the rate is a
  /// slope. −1 means "no previous reading", which reports 0 rather than
  /// a spike made of the whole session's history.
  ///
  /// 🚨 Paired with the frame timestamp it was read at, because a slope
  /// needs BOTH ends of the same interval. The first version of this
  /// divided a delta accumulated since the last publish (250 ms) by the
  /// whole window's wall span (240 frames — seconds), which under-reports
  /// by the ratio between them: more than 20x once the window is full.
  /// An instrument that answers "0.0/s" whatever is happening is worse
  /// than no instrument, because it gets believed.
  static int _lastCaptureTotal = -1;
  static int? _lastCaptureVsync;

  /// What the screens and the pointer clock had counted at the previous
  /// publication — read at [_lastCaptureVsync], as the bakes' total is —,
  /// and null where there is none before.
  static ({int ups, int upsBehind, int packets, int points, int pointerMicros})?
  _lastCounted;

  static final List<FrameTiming> _window = <FrameTiming>[];
  static bool _installed = false;
  static int? _lastPublishedVsync;

  /// How many times [install] actually registered. The guard it proves
  /// is the one this app has been bitten by before: a callback added
  /// from a widget `build` stacks a fresh copy on every rebuild, and a
  /// duplicated timings callback would count every frame twice.
  @visibleForTesting
  static int debugRegistrations = 0;

  /// Registers the timings callback exactly once. Call from `main()`
  /// before `runApp`.
  ///
  /// The callback stays registered for the process lifetime even while
  /// the switch is off — `addTimingsCallback` costs one list append per
  /// frame batch on the engine side, and the alternative (adding and
  /// removing it on toggle) risks the classic double-register. The
  /// gating is on ACCUMULATION instead, one bool per batch.
  static void install() {
    if (_installed) {
      return;
    }
    _installed = true;
    debugRegistrations += 1;
    SchedulerBinding.instance.addTimingsCallback(_record);
    MeasurementMode.frameStats.addListener(_onEnabledChanged);
    _onEnabledChanged();
  }

  static void _onEnabledChanged() {
    if (!MeasurementMode.frameStats.value) {
      reset();
    }
  }

  static void _record(List<FrameTiming> timings) {
    if (!MeasurementMode.frameStats.value || timings.isEmpty) {
      return;
    }
    debugFeed(timings);
    final now = _window.last.timestampInMicroseconds(FramePhase.vsyncStart);
    final since = _lastPublishedVsync;
    if (since == null || now - since >= publishInterval.inMicroseconds) {
      _lastPublishedVsync = now;
      publish();
    }
  }

  /// Recomputes [latest] from the current window. The publish timer
  /// calls this; tests call it directly.
  @visibleForTesting
  static void publish() {
    latest.value = _window.isEmpty ? null : _summarize(_window);
  }

  /// Drives the real callback body, for tests: window, throttle and
  /// publish together. [debugFeed] fills the window without publishing;
  /// this is the whole path the engine takes.
  @visibleForTesting
  static void debugRecord(List<FrameTiming> timings) => _record(timings);

  /// Feeds synthetic frames, for tests. Bypasses the enable switch so a
  /// test does not have to flip global state to exercise the maths.
  @visibleForTesting
  static void debugFeed(List<FrameTiming> timings) {
    _window.addAll(timings);
    if (_window.length > windowFrames) {
      _window.removeRange(0, _window.length - windowFrames);
    }
  }

  /// Test hygiene: empties the window and unpublishes. Does NOT
  /// unregister the callback — installation is once per process by
  /// contract, and a test that could undo it would let the next test
  /// double-register.
  @visibleForTesting
  static void reset() {
    _window.clear();
    _lastPublishedVsync = null;
    // The slope's previous reading has to go too. Leaving it behind
    // makes the next publish subtract a total from another session (or
    // another test) and report a rate that never happened.
    _lastCaptureTotal = -1;
    _lastCaptureVsync = null;
    _lastCounted = null;
    PointerClock.forget();
    latest.value = null;
  }

  /// One window-sized RGBA surface, in megabytes.
  ///
  /// 🚨 The yardstick the cache line was missing. `picture cache 16 /
  /// 495.3 MB` read as an alarm for a while; it is ~31 MB an entry, and a
  /// maximised window on a 4K display at 150% has a client area of about
  /// 8.0 Mpx = 30.6 MB. One entry per viewport, which is the least
  /// surprising thing a picture cache could be doing. The panic came from
  /// dividing by a number nobody had.
  static double _windowMegabytes() {
    final size = _viewPhysicalSize();
    return size.width * size.height * 4 / 1024 / 1024;
  }

  /// The view's device-pixel size, or zero when there is no implicit view
  /// (headless tests). Zero reads as "not measured" everywhere it lands.
  static Size _viewPhysicalSize() =>
      PlatformDispatcher.instance.implicitView?.physicalSize ?? Size.zero;

  /// RAW on purpose: this readout is labelled "view dpr" and reports the
  /// display itself. Geometry reads the EFFECTIVE ratio instead (view ×
  /// UI scale — see `EffectiveDevicePixelRatio`), and this static
  /// recorder has no context to reach that from anyway.
  static double _devicePixelRatio() =>
      PlatformDispatcher.instance.implicitView?.devicePixelRatio ?? 0;

  static FrameStatsSnapshot _summarize(List<FrameTiming> window) {
    final raster = <int>[];
    final ui = <int>[];
    final latency = <int>[];
    final buildWait = <int>[];
    final rasterWait = <int>[];
    for (final timing in window) {
      raster.add(timing.rasterDuration.inMicroseconds);
      ui.add(timing.buildDuration.inMicroseconds);
      latency.add(timing.totalSpan.inMicroseconds);
      buildWait.add(timing.vsyncOverhead.inMicroseconds);
      rasterWait.add(
        timing.timestampInMicroseconds(FramePhase.rasterStart) -
            timing.timestampInMicroseconds(FramePhase.buildFinish),
      );
    }
    raster.sort();
    ui.sort();
    latency.sort();
    buildWait.sort();
    rasterWait.sort();

    // The window's wall span, taken from the frame timestamps rather
    // than a clock read: they share one epoch, and using them keeps the
    // fps figure honest when frames arrive in a batch.
    final firstVsync = window.first.timestampInMicroseconds(
      FramePhase.vsyncStart,
    );
    final lastVsync = window.last.timestampInMicroseconds(
      FramePhase.vsyncStart,
    );
    final spanSeconds = window.length < 2
        ? 0.0
        : (lastVsync - firstVsync) / Duration.microsecondsPerSecond;

    // The cache figures are a level, not a duration: the last frame's
    // reading is the current state of the cache, so averaging them
    // would blur a cache that is filling into one that is half full.
    final last = window.last;

    // Bakes are a COUNTER, so the useful reading is its slope — the
    // delta between two readings over the time between those same two
    // readings. Both ends come from frame timestamps, the same epoch the
    // fps figure uses, so bakes/s approaching fps still means a surface
    // is re-baking on the pointer instead of on a change.
    //
    // A dock region's still image is a bake too (2026-09-25): on Impeller
    // it is the only kind there is, so leaving it out would read 0/s on
    // exactly the engine the regions work on.
    final captures = StaticRaster.censusCaptures + StillRaster.censusCaptures;
    final bakedBytes = StaticRaster.censusBytes + StillRaster.censusBytes;
    final previousTotal = _lastCaptureTotal;
    final previousVsync = _lastCaptureVsync;
    _lastCaptureTotal = captures;
    _lastCaptureVsync = lastVsync;
    final rateSeconds = previousVsync == null
        ? 0.0
        : (lastVsync - previousVsync) / Duration.microsecondsPerSecond;
    final bakesPerSecond = previousTotal < 0 || rateSeconds <= 0
        ? 0.0
        : (captures - previousTotal) / rateSeconds;

    final ups = ScreenTexture.upMicros;
    final upWholes = [for (final up in ups) up.draw + up.finish + up.show]
      ..sort();
    final upDraws = [for (final up in ups) up.draw]..sort();
    final upFinishes = [for (final up in ups) up.finish]..sort();
    final upShows = [for (final up in ups) up.show]..sort();
    final packets = [...PointerClock.packetMicros]..sort();

    // Counters all, read as the bakes' total is: each one's slope over the
    // interval since the last publication.
    final counted = (
      ups: ScreenTexture.upsCounted,
      upsBehind: ScreenTexture.upsBehindCounted,
      packets: PointerClock.packetsCounted,
      points: PointerClock.pointsCounted,
      pointerMicros: PointerClock.microsCounted,
    );
    final before = _lastCounted;
    _lastCounted = counted;
    double aSecond(int now, int? then) =>
        then == null || rateSeconds <= 0 ? 0.0 : (now - then) / rateSeconds;

    return FrameStatsSnapshot(
      frames: window.length,
      windowSeconds: spanSeconds,
      rasterP50: _percentileMillis(raster, 0.50),
      rasterP95: _percentileMillis(raster, 0.95),
      rasterWorst: _percentileMillis(raster, 1.0),
      uiP50: _percentileMillis(ui, 0.50),
      uiP95: _percentileMillis(ui, 0.95),
      uiWorst: _percentileMillis(ui, 1.0),
      latencyP50: _percentileMillis(latency, 0.50),
      latencyP95: _percentileMillis(latency, 0.95),
      buildWaitP50: _percentileMillis(buildWait, 0.50),
      buildWaitP95: _percentileMillis(buildWait, 0.95),
      rasterWaitP50: _percentileMillis(rasterWait, 0.50),
      rasterWaitP95: _percentileMillis(rasterWait, 0.95),
      screenUpP50: _percentileMillis(upWholes, 0.50),
      screenUpP95: _percentileMillis(upWholes, 0.95),
      screensUpPerSecond: aSecond(counted.ups, before?.ups),
      screensBehindPerSecond: aSecond(counted.upsBehind, before?.upsBehind),
      screenDrawP50: _percentileMillis(upDraws, 0.50),
      screenDrawP95: _percentileMillis(upDraws, 0.95),
      screenFinishP50: _percentileMillis(upFinishes, 0.50),
      screenFinishP95: _percentileMillis(upFinishes, 0.95),
      screenShowP50: _percentileMillis(upShows, 0.50),
      screenShowP95: _percentileMillis(upShows, 0.95),
      windowsAreCopied: ScreenTexture.windowsAreCopied,
      pointsPerSecond: aSecond(counted.points, before?.points),
      packetsPerSecond: aSecond(counted.packets, before?.packets),
      pointerP50: _percentileMillis(packets, 0.50),
      pointerP95: _percentileMillis(packets, 0.95),
      pointerMillisPerSecond:
          aSecond(counted.pointerMicros, before?.pointerMicros) / 1000,
      layerCacheCount: last.layerCacheCount,
      layerCacheMegabytes: last.layerCacheMegabytes,
      pictureCacheCount: last.pictureCacheCount,
      pictureCacheMegabytes: last.pictureCacheMegabytes,
      windowMegabytes: _windowMegabytes(),
      devicePixelRatio: _devicePixelRatio(),
      windowPhysicalWidth: _viewPhysicalSize().width,
      windowPhysicalHeight: _viewPhysicalSize().height,
      bakedSurfaces: StaticRaster.census.length + StillRaster.census.length,
      bakedMegabytes: bakedBytes / 1024.0 / 1024.0,
      bakesPerSecond: bakesPerSecond,
      blockedSurfaces: StaticRaster.censusAvoidableCost.$1,
      blockedArea: StaticRaster.censusAvoidableCost.$2,
    );
  }

  /// Nearest-rank percentile over a SORTED list of microseconds, in
  /// milliseconds. Same index arithmetic the brush lab already uses, so
  /// numbers from the two instruments can be compared directly.
  static double _percentileMillis(List<int> sortedMicros, double p) {
    if (sortedMicros.isEmpty) {
      return 0;
    }
    final index = ((sortedMicros.length - 1) * p).round();
    return sortedMicros[index] / 1000.0;
  }
}
