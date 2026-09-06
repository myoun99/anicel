import 'package:flutter/material.dart';

import 'stylus_glide_stop.dart';
import 'timeline_beat_lines.dart';

/// The chrome both timeline grids wrap their whole tree in — the grid law,
/// the stylus glide stop and the no-overscroll scroll configuration, in
/// that order. The rail grid and the x-sheet each spelled the three (the
/// audit's clone scan, 2026-09-06); the storyboard publishes the law alone
/// because it has no glide to stop.
///
/// PEN-9: a stylus approach stops a coasting fling — mid-glide the
/// viewports ignore-pointer their children, so without the stop a pen
/// landing right after a touch fling scrolls instead of selecting.
///
/// 🚨D43-2 재개: the grid's ground is stated ONCE, here, above both the
/// beat-line overlay and every row that covers it — see [TimelineGridLaw].
/// A row that paints over the overlay owes the grid a redraw, and it
/// cannot do that correctly without knowing what it is painting on.
class TimelineGridShell extends StatelessWidget {
  const TimelineGridShell({
    super.key,
    required this.ground,
    required this.framesPerSecond,
    required this.controllers,
    required this.child,
  });

  /// The host's own Material colour under the overlay ([TimelineGridLaw]).
  final Color ground;

  /// The counting fps — which boundaries are SECOND boundaries.
  final int framesPerSecond;

  /// The grid's own scroll controllers ([StylusGlideStop.controllers]).
  final List<ScrollController> controllers;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return TimelineGridLaw(
      ground: ground,
      framesPerSecond: framesPerSecond,
      child: StylusGlideStop(
        controllers: controllers,
        // PEN-12 #7: no overscroll stretch/glow — the painterized ruler
        // and rails mirror the offset and cannot stretch with the cells,
        // so Android's stretch tore the two apart at the edges. A hard
        // clamp matches the desktop feel everywhere.
        child: ScrollConfiguration(
          behavior: ScrollConfiguration.of(context).copyWith(overscroll: false),
          child: child,
        ),
      ),
    );
  }
}
