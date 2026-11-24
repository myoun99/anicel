import 'package:gpu_engine/gpu_engine.dart' show GpuCompiles;

import 'frame_stats.dart';
import 'screen_asked.dart' show screenAskWords;
import 'screen_check.dart';
import 'stroke_steps.dart' show FirstStep, FrameDid, Landing;

/// The frame statistics' lines, in the groups the debug window shows them
/// in (`DebugWindow`): the frame clock, the engine's screens, the pointer
/// and the strokes, the GPU and its compiler, the caches.
///
/// ↩️Till 2026-11-24 these were one column of text over the app of their
/// own (`FrameStatsReadout`, under `MeasurementReadoutHost`), with a
/// MEMORY line that counted apart from the census — against the census's
/// law (`collectMemoryCensus`, ⛔ONE CENSUS) — gone with it: the window's
/// memory is the census's.
abstract final class FrameStatsLines {

  static String _ms(double value) => value.toStringAsFixed(1).padLeft(6);

  static String _px(double value) => value.round().toString();

  /// What is not said — no engine open, no answer of the OS's — as no
  /// figure, not a zero.
  static String _orNone(Object? value) => value?.toString() ?? '—';

  /// A finish's parts as the readout says them: queue, GPU, heard,
  /// together, each `p50/p95` in milliseconds — `—` where no frame said
  /// them.
  static String _wentWords(FinishWentMillis? went) {
    if (went == null) {
      return '—';
    }
    String part(double p50, double p95) =>
        '${p50.toStringAsFixed(1)}/${p95.toStringAsFixed(1)}';
    return 'queue ${part(went.queuedP50, went.queuedP95)}  '
        'gpu ${part(went.polledP50, went.polledP95)}  '
        'heard ${part(went.heardP50, went.heardP95)}  '
        'together ${part(went.togetherP50, went.togetherP95)}';
  }

  /// What the engine's compiler made as the readout says it: how many,
  /// what they took in all and the longest, how many are under way, the
  /// composite's passes that ran on the full one while their own was still
  /// to come, and how many the folder it keeps them in answered — `—`
  /// where the OS keeps them and says nothing, and where no engine is open.
  static String _compileWords(GpuCompiles? compiles) {
    if (compiles == null) {
      return '—';
    }
    return 'made ${compiles.made}  '
        'in ${(compiles.micros / 1e6).toStringAsFixed(1)} s  '
        'longest ${(compiles.longestMicros / 1000).toStringAsFixed(0)} ms  '
        'now ${compiles.underWay}  '
        'full pass ${compiles.stoodIn}  '
        'disk ${_orNone(compiles.found)}';
  }

  /// [micros] in milliseconds to a tenth, unpadded — none where null.
  static String _msOf(int? micros) =>
      micros == null ? '—' : (micros / 1000).toStringAsFixed(1);

  /// The newest stroke's steps along it as its line says them
  /// ([FrameStatsSnapshot.strokeAlong]).
  static String _alongWords(
    ({double first, double last, int steps})? along,
  ) => switch (along) {
    null => '—',
    (:final first, :final last, :final steps) =>
      'first ⅓ p50${_ms(first)}  last ⅓ p50${_ms(last)}  of $steps',
  };

  /// The newest stroke's first step as its line says it, from the press
  /// ([FrameStatsSnapshot.firstStep]).
  static String _firstWords(FirstStep? step) => switch (step) {
    null => '—',
    (:final armed, :final dab, :final held, :final up, :final behind, did: _) =>
      'arm ${_msOf(armed)}  dab ${_msOf(dab)}  held ${_msOf(held)}  '
          'up ${_msOf(up)}  behind ${_orNone(behind)}',
  };

  /// The newest landing as its line says it, from the lift
  /// ([FrameStatsSnapshot.landing]).
  static String _landingWords(Landing? landing) => switch (landing) {
    null => '—',
    (:final commit, :final up, :final behind, did: _) =>
      'commit ${_msOf(commit)}  up ${_msOf(up)}  '
          'behind ${_orNone(behind)}',
  };

  /// What the frame that showed it did ([FrameDid]): how its pictures took
  /// the change, and what its screen drew.
  static String _didWords(FrameDid? did) => switch (did) {
    null => '—',
    (:final wrote, :final asked) =>
      'in place ${wrote.inPlace}  copied ${wrote.copied}  '
          'whole ${wrote.whole}  '
          '${asked == null ? 'drew none' : screenAskWords(asked)}',
  };

  /// Guards the logical-size division only. A zero dpr means there is no
  /// implicit view (headless), and the sizes are zero too — dividing by 1
  /// keeps the line reading `0x0` instead of `NaNxNaN`.
  static double _safeDpr(double dpr) => dpr <= 0 ? 1 : dpr;

  /// What is said before any frame: Flutter renders on demand, so no
  /// frames is the normal state of an app nobody is touching — say so,
  /// rather than showing zeroes that read as "measured, and it is free".
  static const List<String> none = <String>[
    'FRAME STATS',
    'no frames yet — do the thing while this is up',
  ];

  /// The frame clock: the window, the view, the raster, the build, the
  /// latency and what of it is neither.
  static List<String> frame(FrameStatsSnapshot stats) => <String>[
    'FRAME STATS  ${stats.frames}f  '
        '${stats.windowSeconds.toStringAsFixed(1)}s  '
        '${stats.framesPerSecond.toStringAsFixed(1)}fps  '
        'display ${stats.displayHertz.toStringAsFixed(0)}Hz',
    // 🚨 The denominator every MiB estimate in this program was
    // parameterised by and nobody had ever read. A cache entry is
    // `bounds × dpr²`, so without the dpr a byte total can be divided into
    // a viewport-sized entry or a content-sized one at will — which is how
    // a round went by back-solving it out of a total and landing on 1.38,
    // a scale factor Windows does not offer.
    'view    dpr ${stats.devicePixelRatio.toStringAsFixed(2)}  '
        '${_px(stats.windowPhysicalWidth)}x'
        '${_px(stats.windowPhysicalHeight)} px  '
        '${_px(stats.windowPhysicalWidth / _safeDpr(stats.devicePixelRatio))}x'
        '${_px(stats.windowPhysicalHeight / _safeDpr(stats.devicePixelRatio))} logical',
    'RASTER  p50${_ms(stats.rasterP50)}  '
        'p95${_ms(stats.rasterP95)}  '
        'max${_ms(stats.rasterWorst)}',
    'UI      p50${_ms(stats.uiP50)}  '
        'p95${_ms(stats.uiP95)}  '
        'max${_ms(stats.uiWorst)}',
    'LATENCY p50${_ms(stats.latencyP50)}  '
        'p95${_ms(stats.latencyP95)}',
    // What of the latency is neither build nor raster
    // ([FrameStatsSnapshot.buildWaitP50]).
    ' waits  build p50${_ms(stats.buildWaitP50)}  '
        'p95${_ms(stats.buildWaitP95)}  '
        'raster p50${_ms(stats.rasterWaitP50)}  '
        'p95${_ms(stats.rasterWaitP95)}',
  ];

  /// The engine's screens, which the frame clock does not see
  /// ([FrameStatsSnapshot.screenUpP50]), then a frame of theirs part by
  /// part, the buffers Flutter could not read yet, the way the screen
  /// reaches Flutter's and whether it shows the bytes the engine wrote.
  static List<String> screen(FrameStatsSnapshot stats) => <String>[
    'SCREEN  p50${_ms(stats.screenUpP50)}  '
        'p95${_ms(stats.screenUpP95)}  '
        '${stats.screensUpPerSecond.toStringAsFixed(1)}/s  '
        'behind '
        '${stats.screensBehindPerSecond.toStringAsFixed(1)}/s',
    // What the newest frame was drawn as beside it
    // ([FrameStatsSnapshot.screenAsked]): its texels, the display's scale
    // and the mode by it.
    ' draw   p50${_ms(stats.screenDrawP50)}  '
        'p95${_ms(stats.screenDrawP95)}'
        '${switch (stats.screenAsked) {
          null => '',
          final asked => '  ${screenAskWords(asked)}',
        }}',
    ' finish p50${_ms(stats.screenFinishP50)}  '
        'p95${_ms(stats.screenFinishP95)}',
    // What the finish went to, part by part (`ScreenFinish`), each its
    // p50/p95 — its row always there.
    '  went  ${_wentWords(stats.screenFinishWent)}',
    ' show   p50${_ms(stats.screenShowP50)}  '
        'p95${_ms(stats.screenShowP95)}',
    // The waits for a buffer Flutter can no longer read
    // ([FrameStatsSnapshot.surfaceWaits]): none where nothing tells the
    // reads, as on Windows.
    ' wait   ${stats.surfaceWaits.waits}  '
        '${(stats.surfaceWaits.waitMicros / 1000).toStringAsFixed(1)} ms  '
        'past bound ${stats.surfaceWaits.pastTheBound}  '
        'cut ${stats.surfaceWaits.cuts}  '
        '${stats.surfaceWaits.word}',
    // The way the screen reaches Flutter's, and why not where it was
    // refused ([FrameStatsSnapshot.screenPath]) — its row always there,
    // its words read off the device.
    ' path   ${stats.screenPath.isEmpty ? '—' : stats.screenPath}',
    // Whether Flutter shows the bytes the engine wrote, that way
    // ([ScreenCheck], its probe in the window).
    ' check  ${ScreenCheck.said.value}',
  ];

  /// The pointer packets, dealt with between the frames
  /// ([FrameStatsSnapshot.pointsPerSecond]), and the strokes: their steps,
  /// how far behind the pen they stand, the first step and the landing
  /// apart, and what the frame that showed each did.
  static List<String> stroke(FrameStatsSnapshot stats) => <String>[
    'POINTER ${stats.pointsPerSecond.toStringAsFixed(0)} pts/s  '
        '${stats.packetsPerSecond.toStringAsFixed(0)} pkts/s  '
        'p50${_ms(stats.pointerP50)}  '
        'p95${_ms(stats.pointerP95)}  '
        '${stats.pointerMillisPerSecond.toStringAsFixed(1)} ms/s',
    'STROKE  ${stats.stepsPerSecond.toStringAsFixed(1)} steps/s  '
        'dabs/step p50 ${stats.dabsPerStepP50}  '
        'max ${stats.dabsPerStepWorst}',
    ' held   p50${_ms(stats.strokeHeldP50)}  '
        'p95${_ms(stats.strokeHeldP95)}',
    ' pen→up p50${_ms(stats.strokeUpP50)}  '
        'p95${_ms(stats.strokeUpP95)}',
    ' along  ${_alongWords(stats.strokeAlong)}',
    ' first  ${_firstWords(stats.firstStep)}',
    '  wrote ${_didWords(stats.firstStep?.did)}',
    ' press→up p50${_ms(stats.firstUpP50)}  '
        'max${_ms(stats.firstUpWorst)}',
    ' landed ${_landingWords(stats.landing)}',
    '  wrote ${_didWords(stats.landing?.did)}',
  ];

  /// The submits piled on the GPU ([FrameStatsSnapshot.gpuBehind]) and
  /// what the engine's compiler made ([GpuCompiles]).
  static List<String> gpu(FrameStatsSnapshot stats) => <String>[
    'GPU     behind ${_orNone(stats.gpuBehind)}  '
        'max ${_orNone(stats.gpuBehindWorst)}  '
        'timestamps ${switch (stats.gpuClocked) {
          true => 'yes',
          false => 'none',
          null => '—',
        }}',
    'COMPILE ${_compileWords(stats.compiles)}',
  ];

  /// The playback warmer's pace (H74, [FrameStatsSnapshot.warmsPerSecond]):
  /// the frame pictures it lands a second, and how long the newest took to
  /// make — beside a frame's time, whether it can keep up with a run.
  static List<String> warm(FrameStatsSnapshot stats) => <String>[
    'WARM    ${stats.warmsPerSecond.toStringAsFixed(1)} pics/s  '
        'p50${_ms(stats.warmP50)}  p95${_ms(stats.warmP95)}',
  ];

  /// The retained raster: the layer and picture caches and the bakes.
  static List<String> caches(FrameStatsSnapshot stats) => <String>[
    'layer   cache ${stats.layerCacheCount}  '
        '${stats.layerCacheMegabytes.toStringAsFixed(1)} MB',
    // 🚨 Per-entry, against a window's worth of pixels — the yardstick this
    // line was missing. `495 MB` read as an alarm until someone worked out
    // it was ~31 MB an entry against a maximised 4K-at-150% client area of
    // ~8.0 Mpx, which is one entry PER VIEWPORT and entirely ordinary. A
    // total with nothing to divide it by is a number people either ignore
    // or panic at.
    'picture cache ${stats.pictureCacheCount}  '
        '${stats.pictureCacheMegabytes.toStringAsFixed(1)} MB  '
        '${stats.pictureCacheCount == 0 ? '—' : (stats.pictureCacheMegabytes / stats.pictureCacheCount).toStringAsFixed(1)}/entry  '
        'window ${stats.windowMegabytes.toStringAsFixed(1)}',
    'baked   ${stats.bakedSurfaces} surfaces  '
        '${stats.bakedMegabytes.toStringAsFixed(1)} MB  '
        '${stats.bakesPerSecond.toStringAsFixed(1)}/s',
    // Its row always there (no UI that pops into existence): none blocked
    // reads as a zero.
    'blocked ${stats.blockedSurfaces} surfaces  '
        '${(stats.blockedArea / 1000).toStringAsFixed(0)}k px²',
  ];
}
