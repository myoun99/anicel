import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../input/control_press_claim.dart';
import 'canvas_playback_controller.dart';
import 'playback_prerender_scheduler.dart';

/// What a RUN puts over whatever draws it — everything of playback that is
/// not a picture: the ticker the controller's clock runs on, the one press
/// that stops it, and the bar that says how much of what the run wants is
/// made. [child] rides over the picture with them (the ADR streamer).
///
/// 🚨★★★THE CLOCK'S TICKER LIVES HERE, and so a run has ONE of these
/// mounted, in one place, for as long as it is active — whatever draws the
/// picture: the canvas or the track stack
/// (playback-plays-the-screen-material). It used to be the composite
/// view's, which tied the clock to the one way of drawing a frame that the
/// overhaul retires.
class PlaybackRunLayer extends StatefulWidget {
  const PlaybackRunLayer({
    super.key,
    required this.controller,
    required this.prerenderProgress,
    this.child,
  });

  final CanvasPlaybackController controller;
  final ValueListenable<PrerenderProgress> prerenderProgress;

  /// What rides over the picture with the layer — the ADR streamer.
  final Widget? child;

  @override
  State<PlaybackRunLayer> createState() => _PlaybackRunLayerState();
}

// TickerProviderStateMixin (multi), NOT the single variant: the controller
// disposes and recreates its ticker on every pause/resume/seek, and a single
// ticker provider asserts after the first creation (pause → play was dead).
class _PlaybackRunLayerState extends State<PlaybackRunLayer>
    with TickerProviderStateMixin {
  @override
  void initState() {
    super.initState();
    widget.controller.attachTicker(this);
  }

  @override
  void dispose() {
    widget.controller.detachTicker(this);
    super.dispose();
  }

  /// The whole layer as one press that stops playback.
  ///
  /// 🚨A CLAIMED PRESS, not a tap recogniser (H24, 2026-09-15). The canvas
  /// surface this sits on takes the arena on the first movement, and a tap
  /// recogniser loses its tap to whatever wins it — so a finger that wobbled
  /// would no longer have stopped playback. The claim fires on the release,
  /// and not for a press the canvas turned into a gesture: D13's 「a press
  /// that navigates nothing」, kept exactly.
  @override
  Widget build(BuildContext context) => ControlPressClaim(
    onPressed: widget.controller.stop,
    child: GestureDetector(
      key: const ValueKey<String>('canvas-playback-view'),
      behavior: HitTestBehavior.opaque,
      onTap: silentPress(widget.controller.stop),
      child: Stack(
        fit: StackFit.expand,
        children: [?widget.child, _prerenderProgressBar()],
      ),
    ),
  );

  /// How much of what the run wants ahead of its playhead is made: a bar
  /// whose seat is always there (유저 답 F-296-Q5: 「자리를 늘 두는 막대로
  /// 바꾼다」). While a run waits for its picture it is the one thing on the
  /// canvas that moves. ↩️It was a strip that came with the English words
  /// 「caching N/M」 while pictures were being made and went when they were
  /// — 없다가 생기는 UI, and what it said the ruler's green bar said too.
  Widget _prerenderProgressBar() {
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: ValueListenableBuilder<PrerenderProgress>(
        valueListenable: widget.prerenderProgress,
        builder: (context, progress, _) => LinearProgressIndicator(
          key: const ValueKey<String>('canvas-playback-progress'),
          // Nothing asked for is nothing left to make.
          value: progress.total == 0
              ? 1.0
              : (progress.cached / progress.total).clamp(0.0, 1.0),
          minHeight: 2,
        ),
      ),
    );
  }
}
