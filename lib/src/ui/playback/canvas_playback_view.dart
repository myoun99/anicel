import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../models/camera_pose.dart';
import '../../models/canvas_point.dart';
import '../../models/canvas_size.dart';
import '../../models/canvas_viewport.dart';
import '../../models/cut.dart';
import '../../models/cut_id.dart';
import '../../models/layer_effect.dart' show LayerEffect;
import '../../models/playback_quality.dart';
import '../../models/project.dart' show defaultProjectPasteboardArgb;
import '../../models/project_background.dart';
import '../../models/transform_track.dart';
import '../../services/se_name_tag_plan.dart';
import '../canvas/composite_effect_paint.dart' show CompositeEffectPaint;
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
    this.seNameTagsOf,
    this.cutFxEnabledOf,
    this.trackStaticOpacityOf,
    this.cutPictureVisibleOf,
    this.viewport,
    this.background = ProjectBackground.defaultBackground,
    this.pasteboardArgb = defaultProjectPasteboardArgb,
    this.transformTrackOf,
    this.trackEffectsOf,
    this.trackGlobalFrameOf,
    this.trackStack,
  });

  final CanvasPlaybackController controller;
  final CutFrameCompositeCache compositeCache;
  final PlaybackQuality Function() qualityOf;
  final ValueListenable<PrerenderProgress> prerenderProgress;
  final bool cameraViewEnabled;
  final CanvasSize cameraFrameSize;
  final CameraPose Function(Cut cut, int frameIndex) cameraPoseOf;

  /// The SE rows' on-canvas name tags at this cut frame (R5b) — resolved
  /// by the session, drawn over the composite in canvas space.
  final List<ResolvedSeNameTag> Function(Cut cut, int frameIndex)? seNameTagsOf;

  /// The storyboard V-row display gates (session view state, R9). FX off
  /// bypasses the cut-level Transform group — pose AND fade — in this
  /// display; the eye off hides the cut's PICTURE (the paper stays). Null
  /// = always on. Display aids only: the MP4 bake and thumbnails never
  /// consult these.
  final bool Function(CutId cutId)? cutFxEnabledOf;

  /// The owning V track's STATIC opacity (R9 #21) — the live drag value
  /// while the V row's slider is in flight. Null keeps every track opaque.
  final double Function(CutId cutId)? trackStaticOpacityOf;
  final bool Function(CutId cutId)? cutPictureVisibleOf;

  /// The panel's live pan/zoom (canvas mode); identity when null.
  final CanvasViewport? viewport;

  /// The project background (R10-⑥): the paper AND what playlist gaps
  /// show (a gap frame is background-only — no picture, no fade).
  final ProjectBackground background;

  /// The project pasteboard (R3b): the stage apron the camera view shows
  /// past the paper's edge, fading with the cut unit.
  final int pasteboardArgb;

  /// The owning TRACK's transform lanes per cut (R4: pose + fade on the
  /// global axis). Null = no effects (tests, plain fixtures).
  final TransformTrack Function(CutId cutId)? transformTrackOf;

  /// The owning TRACK's EFFECT chain per cut — the V row's fx over the whole
  /// composited cut. Null = none (tests, plain fixtures).
  final List<LayerEffect> Function(CutId cutId)? trackEffectsOf;

  /// The GLOBAL frame of a cut-local index on the cut's track — what the
  /// track lanes are keyed in. Null falls back to the local index (a
  /// single-track fixture whose cut starts at 0).
  final int Function(CutId cutId, int localFrame)? trackGlobalFrameOf;

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

    // The TRACK-level transform (R4: the V effects on the global axis),
    // display-time only — never baked into the composite cache. Camera
    // mode resolves the pose over the camera frame (the space the lanes
    // author in); CANVAS mode remaps that same camera-space pose onto the
    // canvas — resolving over the canvas instead read every key in the
    // wrong space and snapped the picture top-left (R8-③).
    final transformTrack = cut == null
        ? TransformTrack.empty()
        : widget.transformTrackOf?.call(cut.id) ?? TransformTrack.empty();
    final trackFrame = cut != null && position != null
        ? widget.trackGlobalFrameOf?.call(cut.id, position.localFrameIndex) ??
              position.localFrameIndex
        : 0;
    TransformPose? cutPose;
    CanvasPoint? cutAnchorPoint;
    if (cut != null &&
        position != null &&
        cutFxEnabled &&
        trackPoseIsActive(transformTrack)) {
      if (widget.cameraViewEnabled) {
        cutPose = trackPoseAt(
          transformTrack,
          trackFrame,
          widget.cameraFrameSize,
        );
        cutAnchorPoint = trackAnchorPointAt(transformTrack, trackFrame);
      } else {
        final preview = trackPoseForCanvasPreview(
          transformTrack,
          trackFrame,
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
              // The cut-picture eye hides the tags too — the stack view's
              // answer, and the defensible one: with the picture withheld
              // the annotation names nothing.
              seNameTags:
                  inGap || cut == null || position == null || !cutPictureVisible
                  ? const []
                  : widget.seNameTagsOf?.call(cut, position.localFrameIndex) ??
                        const [],
              cameraFrameSize: widget.cameraViewEnabled
                  ? widget.cameraFrameSize
                  : null,
              cutPose: cutPose,
              cutAnchorPoint: cutAnchorPoint,
              // The V row's fx chain over the cut's picture, sampled on the
              // GLOBAL axis its keys live on and bypassed by the same fx
              // master as the pose and the fade.
              cutEffects: inGap || cut == null || position == null
                  ? CompositeEffectPaint.none
                  : trackEffectPaintAt(
                      widget.trackEffectsOf?.call(cut.id) ?? const [],
                      trackFrame,
                      enabled: cutFxEnabled,
                    ),
              paperBackground: widget.background,
              paintPaper: !inGap,
              // The stage's apron rides the camera view (R3b): the camera
              // sees the pasteboard wherever it reaches past the paper,
              // and the fade thins the whole unit (transparency, no wash).
              pasteboardColor: widget.cameraViewEnabled && !inGap
                  ? Color(widget.pasteboardArgb)
                  : null,
              // R9 #21: the track's STATIC opacity carries the animated
              // fade (a layer's static opacity carries its own) and stays
              // on through an fx bypass, because it is not an fx.
              fadeOpacity: inGap || cut == null || position == null
                  ? 1
                  : (widget.trackStaticOpacityOf?.call(cut.id) ?? 1.0) *
                        (cutFxEnabled
                            ? trackFadeOpacityAt(transformTrack, trackFrame)
                            : 1.0),
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
