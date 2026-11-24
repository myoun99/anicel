import 'package:flutter/material.dart';

import '../../native/app_gpu_engine.dart' show appGpuEngineOpen;
import 'engine_stages.dart';
import 'frame_stats.dart';
import 'measurement_mode.dart';
import 'screen_asked.dart' show screenAskWords;
import 'screen_check.dart';
import 'stroke_steps.dart' show FirstStep, FrameDid, Landing;

/// Hosts the measurement readouts above the whole app.
///
/// Installed from `MaterialApp.builder`, which is the only level that is
/// above every route AND below the `Navigator` — dialogs, popovers and
/// dropdown routes live in the Navigator's overlay, so a wrapper under
/// [HomePage] would be covered by exactly the surfaces a measurement run
/// wants to see past.
///
/// The app itself is passed through as a captured child, so this widget
/// rebuilding never rebuilds the app under it: `Element.updateChild`
/// short-circuits on an identical child widget instance. The readout's
/// own 4 Hz republish therefore costs a rebuild of the readout's handful
/// of `Text`s and nothing else.
class MeasurementReadoutHost extends StatelessWidget {
  const MeasurementReadoutHost({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      textDirection: TextDirection.ltr,
      children: <Widget>[
        child,
        // Below the top strip on purpose: an instrument that covers the
        // SETTINGS button is one the user cannot switch off. Pointer
        // events pass through regardless, so it never steals a click
        // from the panel it happens to sit over.
        Positioned(
          left: 8,
          top: 44,
          child: IgnorePointer(
            child: RepaintBoundary(
              child: ValueListenableBuilder<bool>(
                valueListenable: MeasurementMode.frameStats,
                builder: (context, visible, _) => visible
                    ? const FrameStatsReadout()
                    : const SizedBox.shrink(),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// A handful of lines of text that say what the frame clock is doing.
///
/// Deliberately theme-independent: white on near-black, because this has
/// to stay legible over the canvas, over a panel, and in a screenshot
/// that someone will read numbers off. Tabular figures so the columns
/// do not dance between republishes.
class FrameStatsReadout extends StatelessWidget {
  const FrameStatsReadout({super.key});

  static const TextStyle _style = TextStyle(
    color: Color(0xFFFFFFFF),
    fontSize: 11,
    height: 1.45,
    fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
  );

  static String _ms(double value) => value.toStringAsFixed(1).padLeft(6);

  static String _px(double value) => value.round().toString();

  static String _mb(double value) => '${value.toStringAsFixed(1)} MB';

  /// What is not said — no engine open, no answer of the OS's — as no
  /// figure, not a zero.
  static String _orNone(Object? value) => value?.toString() ?? '—';

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

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<FrameStatsSnapshot?>(
      valueListenable: FrameStats.latest,
      builder: (context, stats, _) {
        final lines = stats == null
            // Flutter renders on demand, so no frames is the normal
            // state of an app nobody is touching — say so, rather than
            // showing zeroes that read as "measured, and it is free".
            ? const <String>[
                'FRAME STATS',
                'no frames yet — do the thing while this is up',
              ]
            : <String>[
                'FRAME STATS  ${stats.frames}f  '
                    '${stats.windowSeconds.toStringAsFixed(1)}s  '
                    '${stats.framesPerSecond.toStringAsFixed(1)}fps  '
                    'display ${stats.displayHertz.toStringAsFixed(0)}Hz',
                // 🚨 The denominator every MiB estimate in this program was
                // parameterised by and nobody had ever read. A cache entry
                // is `bounds × dpr²`, so without the dpr a byte total can
                // be divided into a viewport-sized entry or a
                // content-sized one at will — which is how a round went by
                // back-solving it out of a total and landing on 1.38, a
                // scale factor Windows does not offer.
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
                // The engine's screens, which the lines above do not see
                // ([FrameStatsSnapshot.screenUpP50]), then a frame of
                // theirs part by part.
                'SCREEN  p50${_ms(stats.screenUpP50)}  '
                    'p95${_ms(stats.screenUpP95)}  '
                    '${stats.screensUpPerSecond.toStringAsFixed(1)}/s  '
                    'behind '
                    '${stats.screensBehindPerSecond.toStringAsFixed(1)}/s',
                // What the newest frame was drawn as beside it
                // ([FrameStatsSnapshot.screenAsked]): its texels, the
                // display's scale and the mode by it.
                ' draw   p50${_ms(stats.screenDrawP50)}  '
                    'p95${_ms(stats.screenDrawP95)}'
                    '${switch (stats.screenAsked) {
                      null => '',
                      final asked => '  ${screenAskWords(asked)}',
                    }}',
                ' finish p50${_ms(stats.screenFinishP50)}  '
                    'p95${_ms(stats.screenFinishP95)}',
                ' show   p50${_ms(stats.screenShowP50)}  '
                    'p95${_ms(stats.screenShowP95)}',
                // The waits for a buffer Flutter can no longer read
                // ([FrameStatsSnapshot.surfaceWaits]): none where nothing
                // tells the reads, as on Windows.
                ' wait   ${stats.surfaceWaits.waits}  '
                    '${(stats.surfaceWaits.waitMicros / 1000).toStringAsFixed(1)} ms  '
                    'past bound ${stats.surfaceWaits.pastTheBound}  '
                    'cut ${stats.surfaceWaits.cuts}  '
                    '${stats.surfaceWaits.word}',
                // The way the screen reaches Flutter's, and why not where
                // it was refused ([FrameStatsSnapshot.screenPath]) — its
                // row always there, its words read off the device.
                ' path   ${stats.screenPath.isEmpty ? '—' : stats.screenPath}',
                // Whether Flutter shows the bytes the engine wrote, that
                // way ([ScreenCheck], its probe under the lines).
                ' check  ${ScreenCheck.said.value}',
                // The pointer packets, dealt with between the frames
                // ([FrameStatsSnapshot.pointsPerSecond]).
                'POINTER ${stats.pointsPerSecond.toStringAsFixed(0)} pts/s  '
                    '${stats.packetsPerSecond.toStringAsFixed(0)} pkts/s  '
                    'p50${_ms(stats.pointerP50)}  '
                    'p95${_ms(stats.pointerP95)}  '
                    '${stats.pointerMillisPerSecond.toStringAsFixed(1)} ms/s',
                // A stroke's steps, how far behind the pen it stands
                // ([FrameStatsSnapshot.stepsPerSecond]), and the submits
                // piled on the GPU ([FrameStatsSnapshot.gpuBehind]).
                'STROKE  ${stats.stepsPerSecond.toStringAsFixed(1)} steps/s  '
                    'dabs/step p50 ${stats.dabsPerStepP50}  '
                    'max ${stats.dabsPerStepWorst}',
                ' held   p50${_ms(stats.strokeHeldP50)}  '
                    'p95${_ms(stats.strokeHeldP95)}',
                ' pen→up p50${_ms(stats.strokeUpP50)}  '
                    'p95${_ms(stats.strokeUpP95)}',
                ' along  ${_alongWords(stats.strokeAlong)}',
                // A stroke's first step and its landing, apart, and what
                // the frame that showed each did
                // ([FrameStatsSnapshot.firstStep]).
                ' first  ${_firstWords(stats.firstStep)}',
                '  wrote ${_didWords(stats.firstStep?.did)}',
                ' press→up p50${_ms(stats.firstUpP50)}  '
                    'max${_ms(stats.firstUpWorst)}',
                ' landed ${_landingWords(stats.landing)}',
                '  wrote ${_didWords(stats.landing?.did)}',
                'GPU     behind ${_orNone(stats.gpuBehind)}  '
                    'max ${_orNone(stats.gpuBehindWorst)}  '
                    'timestamps ${switch (stats.gpuClocked) {
                      true => 'yes',
                      false => 'none',
                      null => '—',
                    }}',
                'MEMORY  app ${_mb(stats.footprintMegabytes)}  '
                    'screens ${_mb(stats.screensMegabytes)}  '
                    'vram ${switch (stats.videoMegabytes) {
                      null => '—',
                      (:final used, budget: null) => _mb(used),
                      (:final used, budget: final budget?) =>
                        '${used.toStringAsFixed(1)} / ${_mb(budget)}',
                    }}',
                'layer   cache ${stats.layerCacheCount}  '
                    '${stats.layerCacheMegabytes.toStringAsFixed(1)} MB',
                // 🚨 Per-entry, against a window's worth of pixels — the
                // yardstick this line was missing. `495 MB` read as an
                // alarm until someone worked out it was ~31 MB an entry
                // against a maximised 4K-at-150% client area of ~8.0
                // Mpx, which is one entry PER VIEWPORT and entirely
                // ordinary. A total with nothing to divide it by is a
                // number people either ignore or panic at.
                'picture cache ${stats.pictureCacheCount}  '
                    '${stats.pictureCacheMegabytes.toStringAsFixed(1)} MB  '
                    '${stats.pictureCacheCount == 0 ? '—' : (stats.pictureCacheMegabytes / stats.pictureCacheCount).toStringAsFixed(1)}/entry  '
                    'window ${stats.windowMegabytes.toStringAsFixed(1)}',
                'baked   ${stats.bakedSurfaces} surfaces  '
                    '${stats.bakedMegabytes.toStringAsFixed(1)} MB  '
                    '${stats.bakesPerSecond.toStringAsFixed(1)}/s'
                    '${stats.blockedSurfaces == 0 ? '' : '\nblocked ${stats.blockedSurfaces} surfaces  '
                              '${(stats.blockedArea / 1000).toStringAsFixed(0)}k px²'}',
                // The engine's work place by place, while it is timed
                // ([EngineStages]) — read as this window is published,
                // of the frames it keeps itself.
                if (MeasurementMode.engineStages.value)
                  ...EngineStages.lines(
                    EngineStages.summary,
                    clocked: appGpuEngineOpen.value?.clocked ?? false,
                  ),
              ];
        return DecoratedBox(
          decoration: const BoxDecoration(color: Color(0xE6101112)),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                for (final line in lines)
                  Text(line, style: _style, textDirection: TextDirection.ltr),
                const ScreenCheck(),
              ],
            ),
          ),
        );
      },
    );
  }
}
