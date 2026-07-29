import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../models/camera_pose.dart';
import '../../models/canvas_point.dart';
import '../../models/canvas_size.dart';
import '../../models/canvas_viewport.dart';
import '../../models/cut.dart';
import '../../models/cut_id.dart';
import '../../models/playback_quality.dart';
import '../../models/project_background.dart';
import '../../models/transform_track.dart';
import '../storyboard_cut_fade_policy.dart';
import 'canvas_playback_controller.dart';
import 'cut_frame_composite_cache.dart';
import 'playback_frame_painter.dart';
import 'playback_prerender_scheduler.dart';

/// The canvas panel's playback content: cached composite frames advancing
/// with the controller's ticker, rendered INSIDE the panel viewport so the
/// panel chrome (zoom buttons, panbars) keeps working during playback.
///
/// Tapping anywhere cancels playback. Cache misses keep the last displayed
/// frame on screen (the stale-frame policy the tile cache also uses) while a
/// thin strip reports warming progress. With the camera view enabled the
/// frame is projected through the cut's camera pose instead of shown in
/// canvas space.
class CanvasPlaybackView extends StatefulWidget {
  const CanvasPlaybackView({
    super.key,
    required this.controller,
    required this.compositeCache,
    required this.qualityOf,
    required this.prerenderProgress,
    required this.cameraViewEnabled,
    required this.cameraFrameSize,
    required this.cameraPoseOf,
    this.cutFxEnabledOf,
    this.cutPictureVisibleOf,
    this.viewport,
    this.background = ProjectBackground.defaultBackground,
    this.trackStack,
  });

  final CanvasPlaybackController controller;
  final CutFrameCompositeCache compositeCache;
  final PlaybackQuality Function() qualityOf;
  final ValueListenable<PrerenderProgress> prerenderProgress;
  final bool cameraViewEnabled;
  final CanvasSize cameraFrameSize;
  final CameraPose Function(Cut cut, int frameIndex) cameraPoseOf;

  /// The storyboard V-row display gates (session view state, R9). FX off
  /// bypasses the cut-level Transform group — pose AND fade — in this
  /// display; the eye off hides the cut's PICTURE (the paper stays). Null
  /// = always on. Display aids only: the MP4 bake and thumbnails never
  /// consult these.
  final bool Function(CutId cutId)? cutFxEnabledOf;
  final bool Function(CutId cutId)? cutPictureVisibleOf;

  /// The panel's live pan/zoom (canvas mode); identity when null.
  final CanvasViewport? viewport;

  /// The project background (R10-⑥): the paper AND what playlist gaps
  /// show (a gap frame is background-only — no picture, no fade).
  final ProjectBackground background;

  /// The multitrack display path for ALL-CUTS playback (R3a): when set,
  /// the FRAME is this widget — the parked canvas's track stack, following
  /// the clock's global frame — and this view keeps everything else it
  /// owns: the ticker it vends the controller, the tap-to-stop surface and
  /// the warm-progress bar. Null = the single-cut painter (the activeCut
  /// scope, where the editing context IS one cut).
  final Widget? trackStack;

  @override
  State<CanvasPlaybackView> createState() => _CanvasPlaybackViewState();
}

// TickerProviderStateMixin (multi), NOT the single variant: the controller
// disposes and recreates its ticker on every pause/resume/seek, and a single
// ticker provider asserts after the first creation (pause → play was dead).
class _CanvasPlaybackViewState extends State<CanvasPlaybackView>
    with TickerProviderStateMixin {
  /// Our own clone of the last displayed composite: the cache may evict and
  /// dispose its image at any time, a clone shares the pixels but has an
  /// independent lifetime.
  ui.Image? _heldFrame;

  /// The cache image the clone came from (identity only, may be disposed);
  /// cloning happens only when this changes, not on every tick.
  ui.Image? _heldSource;
  CanvasSize? _heldCanvasSize;

  @override
  void initState() {
    super.initState();
    widget.controller.attachTicker(this);
    widget.controller.addListener(_onPlaybackChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onPlaybackChanged);
    widget.controller.detachTicker();
    _heldFrame?.dispose();
    super.dispose();
  }

  void _onPlaybackChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.trackStack case final stack?) {
      // The stack paints the frame; no composite is read or held here —
      // the stack view runs its own hold/clone lifecycle per covered cut.
      return GestureDetector(
        key: const ValueKey<String>('canvas-playback-view'),
        behavior: HitTestBehavior.opaque,
        onTap: widget.controller.stop,
        child: Stack(
          fit: StackFit.expand,
          children: [stack, _prerenderProgressBar(context)],
        ),
      );
    }
    final position = widget.controller.position;
    if (position != null) {
      final composite = widget.compositeCache.validCompositeOrNull(
        cut: position.cut,
        frameIndex: position.localFrameIndex,
        quality: widget.qualityOf(),
      );
      if (composite != null && !identical(composite, _heldSource)) {
        _heldFrame?.dispose();
        _heldSource = composite;
        _heldFrame = composite.clone();
        _heldCanvasSize = position.cut.canvasSize;
      }
    }

    final cut = position?.cut;
    final canvasSize =
        cut?.canvasSize ?? _heldCanvasSize ?? widget.cameraFrameSize;

    // A playlist GAP (empty frames between cuts): a VOID — no held frame,
    // no fade wash, and NO paper (UI-R9 #2, superseding R10-⑥'s
    // background-only gaps): there is no cut in a gap, so the panel's own
    // background shows through, exactly like the gap-parked scrub preview.
    final inGap =
        widget.controller.isActive &&
        widget.controller.globalFrameIndexListenable.value != null &&
        position == null;

    // The storyboard V-row display gates (R9): fx off bypasses the whole
    // cut-level Transform group (pose + fade) in this display; the eye off
    // drops the picture (paper only).
    final cutFxEnabled =
        cut == null || (widget.cutFxEnabledOf?.call(cut.id) ?? true);
    final cutPictureVisible =
        cut == null || (widget.cutPictureVisibleOf?.call(cut.id) ?? true);

    // The cut-level transform (V track, AE precomp semantics), display-time
    // only — never baked into the composite cache. Camera mode resolves the
    // pose over the camera frame (the space the lanes author in); CANVAS
    // mode remaps that same camera-space pose onto the canvas
    // (cutPoseForCanvasPreview) — resolving over the canvas instead read
    // every key in the wrong space and snapped the picture top-left (R8-③).
    TransformPose? cutPose;
    CanvasPoint? cutAnchorPoint;
    if (cut != null &&
        position != null &&
        cutFxEnabled &&
        cutPoseIsActive(cut)) {
      if (widget.cameraViewEnabled) {
        cutPose = cutPoseAt(
          cut,
          position.localFrameIndex,
          widget.cameraFrameSize,
        );
        cutAnchorPoint = cutAnchorPointAt(cut, position.localFrameIndex);
      } else {
        final preview = cutPoseForCanvasPreview(
          cut,
          position.localFrameIndex,
          cameraFrameSize: widget.cameraFrameSize,
          canvasSize: canvasSize,
        );
        cutPose = preview.pose;
        cutAnchorPoint = preview.anchorPoint;
      }
    }

    return GestureDetector(
      key: const ValueKey<String>('canvas-playback-view'),
      behavior: HitTestBehavior.opaque,
      // One tap anywhere on the canvas cancels playback.
      onTap: widget.controller.stop,
      child: Stack(
        fit: StackFit.expand,
        children: [
          CustomPaint(
            painter: PlaybackFramePainter(
              image:
                  !inGap && cutPictureVisible && _heldCanvasSize == canvasSize
                  ? _heldFrame
                  : null,
              canvasSize: canvasSize,
              viewport: widget.viewport,
              cameraPose:
                  widget.cameraViewEnabled && cut != null && position != null
                  ? widget.cameraPoseOf(cut, position.localFrameIndex)
                  : null,
              cameraFrameSize: widget.cameraViewEnabled
                  ? widget.cameraFrameSize
                  : null,
              cutPose: cutPose,
              cutAnchorPoint: cutAnchorPoint,
              paperBackground: widget.background,
              paintPaper: !inGap,
              fadeOpacity:
                  !inGap && cut != null && position != null && cutFxEnabled
                  ? cut.fadeOpacityAt(position.localFrameIndex)
                  : 1,
              fadeColor: cut != null
                  ? cutFadeTargetColor(cut)
                  : const Color(0xFF000000),
            ),
          ),
          _prerenderProgressBar(context),
        ],
      ),
    );
  }

  Widget _prerenderProgressBar(BuildContext context) {
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: ValueListenableBuilder<PrerenderProgress>(
        valueListenable: widget.prerenderProgress,
        builder: (context, progress, _) {
          if (progress.total == 0 || progress.isComplete) {
            return const SizedBox.shrink();
          }
          return Column(
            key: const ValueKey<String>('canvas-playback-progress'),
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'caching ${progress.cached}/${progress.total}',
                textAlign: TextAlign.right,
                style: Theme.of(context).textTheme.labelSmall,
              ),
              LinearProgressIndicator(
                value: progress.cached / progress.total,
                minHeight: 2,
              ),
            ],
          );
        },
      ),
    );
  }
}
