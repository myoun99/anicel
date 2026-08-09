import 'package:flutter/material.dart';

import 'frame_stats.dart';
import 'measurement_mode.dart';

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
/// own 4 Hz republish therefore costs a rebuild of six `Text`s and
/// nothing else.
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

/// Six lines of text that say what the frame clock is doing.
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
                    '${stats.framesPerSecond.toStringAsFixed(1)}fps',
                'RASTER  p50${_ms(stats.rasterP50)}  '
                    'p95${_ms(stats.rasterP95)}  '
                    'max${_ms(stats.rasterWorst)}',
                'UI      p50${_ms(stats.uiP50)}  '
                    'p95${_ms(stats.uiP95)}  '
                    'max${_ms(stats.uiWorst)}',
                'LATENCY p50${_ms(stats.latencyP50)}  '
                    'p95${_ms(stats.latencyP95)}',
                'layer   cache ${stats.layerCacheCount}  '
                    '${stats.layerCacheMegabytes.toStringAsFixed(1)} MB',
                'picture cache ${stats.pictureCacheCount}  '
                    '${stats.pictureCacheMegabytes.toStringAsFixed(1)} MB',
                'baked   ${stats.bakedSurfaces} surfaces  '
                    '${stats.bakedMegabytes.toStringAsFixed(1)} MB  '
                    '${stats.bakesPerSecond.toStringAsFixed(1)}/s'
                    '${stats.blockedSurfaces == 0 ? '' : '\nblocked ${stats.blockedSurfaces} surfaces  '
                          '${(stats.blockedArea / 1000).toStringAsFixed(0)}k px²'}',
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
              ],
            ),
          ),
        );
      },
    );
  }
}
