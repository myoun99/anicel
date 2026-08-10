import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../models/camera_pose.dart';
import '../../models/canvas_size.dart';
import '../../models/canvas_viewport.dart';
import '../../models/cut.dart';
import '../../models/cut_id.dart';
import '../../models/layer_effect.dart' show LayerEffect;
import '../../models/playback_quality.dart';
import '../../models/project.dart'
    show defaultProjectBackdropArgb, defaultProjectPasteboardArgb;
import '../../models/project_background.dart';
import '../../models/transform_track.dart';
import '../../services/playback/playback_frame_mapping.dart';
import '../../services/se_name_tag_plan.dart';
import '../canvas/paper_background.dart'
    show AlphaCheckerboardPainter;
import '../storyboard_cut_fade_policy.dart';
import 'cut_frame_composite_cache.dart';
import 'playback_frame_painter.dart';

/// The parked-state canvas content — the multitrack display path.
///
/// With NO active cut (a gap parking, UI-R9 #3) the canvas used to show a
/// paperless void even when the parked frame sits ON a cut (an SE-row
/// press parks in place, feedback #7). Now every track answers "which of
/// my cuts covers this global frame?" and the covered cuts' cached
/// composites stack in CAMERA-FRAME space, each projected through its own
/// cut's camera pose — playback's camera view, one layer per track.
/// Editing stays single-active-cut; this path only displays ("draw on the
/// canvas, watch through the camera" — with nothing active, everything
/// here is watched).
///
/// The first covered track paints the letterbox, its cut's paper, and the
/// full-frame fade wash (playback parity in the single-track case); the
/// tracks above composite transparently, their fades applied to their own
/// contribution only — a full-frame wash there would blank the stage
/// below instead of revealing it.
///
/// No covered track at all keeps the void (the panel background shows
/// through) — the same gap semantics playback and the scrub preview
/// already have.
class CanvasTrackStackView extends StatefulWidget {
  const CanvasTrackStackView({
    super.key = const ValueKey<String>('canvas-track-stack-view'),
    required this.globalFrame,
    required this.positionsOf,
    required this.compositeCache,
    required this.qualityOf,
    required this.cameraFrameSize,
    required this.cameraPoseOf,
    this.cameraViewEnabled = true,
    this.seNameTagsOf,
    this.cutFxEnabledOf,
    this.trackStaticOpacityOf,
    this.cutPictureVisibleOf,
    this.onFrameCached,
    this.viewport,
    this.background = ProjectBackground.defaultBackground,
    this.backdropArgb = defaultProjectBackdropArgb,
    this.pasteboardArgb = defaultProjectPasteboardArgb,
    this.showAlphaCheckerboard = false,
    this.transformTrackOf,
    this.trackEffectsOf,
  });

  /// The parked global frame (the session's gap parking): moves per
  /// gesture move, null = no parking (the degenerate no-cut state) —
  /// nothing shows.
  final ValueListenable<int?> globalFrame;

  /// Live per-track resolution (resolveTrackStackContributions over the
  /// CURRENT project layout — never playlist snapshots, so edits made
  /// while parked show up on the next build). An O.L answers with BOTH
  /// cuts, the leaving one first.
  final List<TrackStackContribution> Function(int globalFrame) positionsOf;

  /// Whether the CAMERA VIEW is on — the same view-mode flag the playback
  /// view takes, and the reason this stack no longer crops unconditionally.
  ///
  /// ★A ruler scrub across cut boundaries parks per move (UI-R7 #9), so the
  /// parked stack is what the storyboard shows while you drag. It used to
  /// be the one display path that ignored the toggle, which meant dragging
  /// the ruler reframed the canvas into the camera crop even with camera
  /// view off. The law is one line now: camera view decides the framing,
  /// wherever the picture comes from.
  final bool cameraViewEnabled;

  final CutFrameCompositeCache compositeCache;
  final PlaybackQuality Function() qualityOf;
  final CanvasSize cameraFrameSize;
  final CameraPose Function(Cut cut, int frameIndex) cameraPoseOf;

  /// The SE rows' on-canvas name tags (R5b): resolved PER CUT, so each
  /// covered track shows its own speakers rather than the selected
  /// track's.
  final List<ResolvedSeNameTag> Function(Cut cut, int frameIndex)?
  seNameTagsOf;

  /// The storyboard V-row display gates (R9), exactly as playback applies
  /// them: fx off bypasses the cut-level pose AND fade, the eye off hides
  /// the cut's picture. Null = always on.
  final bool Function(CutId cutId)? cutFxEnabledOf;

  /// The owning V track's STATIC opacity (R9 #21) — the live drag value
  /// while the V row's slider is in flight. Null keeps every track opaque.
  final double Function(CutId cutId)? trackStaticOpacityOf;
  final bool Function(CutId cutId)? cutPictureVisibleOf;

  /// Called after each on-demand composite lands in the cache (the
  /// session's budget trim): the parked state has no warmer running its
  /// afterFrameCached hook, so without this nothing would trim what a
  /// long parked scrub piles up.
  final void Function()? onFrameCached;

  /// The panel's live pan/zoom; identity when null.
  final CanvasViewport? viewport;

  /// The project background: the paper of the bottom covered track.
  final ProjectBackground background;

  /// The BACKDROP (R3b): the panel-wide floor this stack sits on — what
  /// an uncovered frame shows (the old void) and what every fade reveals.
  final int backdropArgb;

  /// The bottom covered track's stage apron (R3b): fills its camera frame
  /// under the paper, and fades with the cut unit.
  final int pasteboardArgb;

  /// Alpha preview (display-only): the backdrop renders as the alpha
  /// checkerboard, showing what an alpha export leaves open.
  final bool showAlphaCheckerboard;

  /// The owning TRACK's transform lanes per cut (R4: pose + fade on the
  /// global axis). Null = no effects (tests, plain fixtures).
  final TransformTrack Function(CutId cutId)? transformTrackOf;

  /// The owning TRACK's EFFECT chain per cut — the V row's fx, filtering the
  /// whole composited cut. Null = none (tests, plain fixtures).
  final List<LayerEffect> Function(CutId cutId)? trackEffectsOf;

  @override
  State<CanvasTrackStackView> createState() => _CanvasTrackStackViewState();
}

class _CanvasTrackStackViewState extends State<CanvasTrackStackView> {
  /// Our own clones of the displayed composites, one per covered cut: the
  /// cache may evict and dispose its image at any time; a clone shares the
  /// pixels but has an independent lifetime.
  final Map<CutId, ui.Image> _heldFrames = <CutId, ui.Image>{};

  /// The cache images the clones came from (identity only, may be
  /// disposed) — cloning happens only when the source changes.
  final Map<CutId, ui.Image> _heldSources = <CutId, ui.Image>{};

  /// The canvas size each held clone was composed at: a stale clone must
  /// not stretch into a RESIZED cut's rect (the playback view's guard).
  final Map<CutId, CanvasSize> _heldCanvasSizes = <CutId, CanvasSize>{};

  /// ONE in-flight compose per track (per cut), latest-frame-wins: a fast
  /// gap scrub crosses many cold frames, and unbounded fire-and-forget
  /// composes would contend with the live drag long after the parking
  /// moved on. The abort hook stands a stale compose down mid-build; the
  /// completion repaint re-requests whatever frame is current then.
  final Map<CutId, int> _inFlightFrame = <CutId, int>{};

  /// What each covered cut should show right now — the abort hook's
  /// comparison target, refreshed every build.
  final Map<CutId, int> _wantedFrame = <CutId, int>{};

  @override
  void initState() {
    super.initState();
    widget.globalFrame.addListener(_onFrameMoved);
  }

  @override
  void didUpdateWidget(covariant CanvasTrackStackView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.globalFrame, widget.globalFrame)) {
      oldWidget.globalFrame.removeListener(_onFrameMoved);
      widget.globalFrame.addListener(_onFrameMoved);
    }
  }

  @override
  void dispose() {
    widget.globalFrame.removeListener(_onFrameMoved);
    for (final image in _heldFrames.values) {
      image.dispose();
    }
    super.dispose();
  }

  void _onFrameMoved() {
    if (mounted) {
      setState(() {});
    }
  }

  void _prepare(Cut cut, int frameIndex, PlaybackQuality quality) {
    if (_inFlightFrame.containsKey(cut.id)) {
      return;
    }
    _inFlightFrame[cut.id] = frameIndex;
    widget.compositeCache
        .prepareCompositeInterruptible(
          cut: cut,
          frameIndex: frameIndex,
          quality: quality,
          shouldAbort: () =>
              !mounted || _wantedFrame[cut.id] != frameIndex,
        )
        .then(
          (image) {
            _inFlightFrame.remove(cut.id);
            if (image != null) {
              widget.onFrameCached?.call();
            }
            // Repaint either way (when still mounted): a landed image
            // shows, an aborted one lets the build re-request the frame
            // that is wanted NOW.
            if (mounted) {
              setState(() {});
            }
          },
          // No repaint on failure: a repaint would re-request and a
          // persistently failing composite (store torn down) would spin.
          onError: (Object _) => _inFlightFrame.remove(cut.id),
        );
  }

  /// Drops held state for cuts no longer covered, so a long parked
  /// session does not accumulate one clone per cut ever displayed.
  void _pruneStale(Iterable<CutId> covered) {
    final keep = covered.toSet();
    _heldFrames.removeWhere((cutId, image) {
      if (keep.contains(cutId)) {
        return false;
      }
      image.dispose();
      _heldSources.remove(cutId);
      _heldCanvasSizes.remove(cutId);
      return true;
    });
    _wantedFrame.removeWhere((cutId, _) => !keep.contains(cutId));
  }

  @override
  Widget build(BuildContext context) {
    final frame = widget.globalFrame.value;
    final positions = frame == null
        ? const <TrackStackContribution>[]
        : widget.positionsOf(frame);
    _pruneStale([for (final position in positions) position.cutId]);
    // The BACKDROP floor (R3b): the void is retired — an uncovered frame
    // shows the stage's floor (or the alpha checkerboard under the
    // preview toggle), exactly what an opaque export bakes there.
    final floor = widget.showAlphaCheckerboard
        ? const CustomPaint(
            key: ValueKey<String>('canvas-track-stack-floor'),
            painter: AlphaCheckerboardPainter(),
            child: SizedBox.expand(),
          )
        : ColoredBox(
            key: const ValueKey<String>('canvas-track-stack-floor'),
            color: Color(widget.backdropArgb),
          );
    if (positions.isEmpty) {
      return SizedBox.expand(
        key: const ValueKey<String>('canvas-track-stack-void'),
        child: floor,
      );
    }

    final quality = widget.qualityOf();
    final layers = <Widget>[floor];
    // The unit alpha of each contribution: its transition share times the
    // track's own opacity and fade. The weights that follow turn those into
    // source-over alphas — see [sourceOverWeights] for why they are not the
    // same number.
    final unitAlphas = <double>[];
    for (final position in positions) {
      final cut = position.cut;
      final cutFxEnabled = widget.cutFxEnabledOf?.call(cut.id) ?? true;
      final transformTrack =
          widget.transformTrackOf?.call(cut.id) ?? TransformTrack.empty();
      unitAlphas.add(
        position.opacity *
            (widget.trackStaticOpacityOf?.call(cut.id) ?? 1.0) *
            (cutFxEnabled
                ? trackFadeOpacityAt(transformTrack, position.globalFrameIndex)
                : 1.0),
      );
    }
    final weights = trackGroupSourceOverWeights(positions, unitAlphas);
    for (var i = 0; i < positions.length; i++) {
      final position = positions[i];
      final cut = position.cut;
      final localFrame = position.localFrameIndex;
      _wantedFrame[cut.id] = localFrame;

      final composite = widget.compositeCache.validCompositeOrNull(
        cut: cut,
        frameIndex: localFrame,
        quality: quality,
      );
      if (composite == null) {
        _prepare(cut, localFrame, quality);
      } else if (!identical(composite, _heldSources[cut.id])) {
        _heldFrames[cut.id]?.dispose();
        _heldSources[cut.id] = composite;
        _heldFrames[cut.id] = composite.clone();
        _heldCanvasSizes[cut.id] = cut.canvasSize;
      }

      final cutFxEnabled = widget.cutFxEnabledOf?.call(cut.id) ?? true;
      final cutPictureVisible =
          widget.cutPictureVisibleOf?.call(cut.id) ?? true;

      // The TRACK-level pose (R4: the V effects live on the track's
      // global axis), display-time only — resolved over the CAMERA frame,
      // the space its lanes author in (R8-③), at the frame's GLOBAL
      // position (this stack's own axis).
      final transformTrack =
          widget.transformTrackOf?.call(cut.id) ?? TransformTrack.empty();
      final globalFrame = position.globalFrameIndex;
      final poseActive = cutFxEnabled && trackPoseIsActive(transformTrack);
      final weight = weights[i];
      // The stage — paper, letterbox, apron — belongs to the bottom covered
      // TRACK, and to EVERY contribution of it: a 場面転換 cross-fades the
      // whole screen, so the arriving cut brings its own paper and the
      // weights mix the two. Tracks above composite transparently over it.
      final isStage = position.isBottomTrack;
      final cameraView = widget.cameraViewEnabled;
      layers.add(
        CustomPaint(
          painter: PlaybackFramePainter(
            image:
                cutPictureVisible &&
                    _heldCanvasSizes[cut.id] == cut.canvasSize
                ? _heldFrames[cut.id]
                : null,
            canvasSize: cut.canvasSize,
            viewport: widget.viewport,
            // Camera view off: the cut sits in its own canvas space, uncropped
            // and unprojected — the editing framing, which is what a ruler
            // scrub should keep showing.
            cameraPose: cameraView
                ? widget.cameraPoseOf(cut, localFrame)
                : null,
            seNameTags: cutPictureVisible
                ? widget.seNameTagsOf?.call(cut, localFrame) ?? const []
                : const [],
            cameraFrameSize: cameraView ? widget.cameraFrameSize : null,
            cutPose: !poseActive
                ? null
                : cameraView
                ? trackPoseAt(transformTrack, globalFrame, widget.cameraFrameSize)
                : trackPoseForCanvasPreview(
                    transformTrack,
                    globalFrame,
                    cameraFrameSize: widget.cameraFrameSize,
                    canvasSize: cut.canvasSize,
                  ).pose,
            cutAnchorPoint: poseActive
                ? trackAnchorPointAt(transformTrack, globalFrame)
                : null,
            // The V row's chain, on the cut's picture. rasterScale stays 1:
            // the composite is drawn up to CANVAS space here, whatever
            // quality it was cached at, and a blur radius is canvas pixels.
            cutEffects: trackEffectPaintAt(
              widget.trackEffectsOf?.call(cut.id) ?? const [],
              globalFrame,
              enabled: cutFxEnabled,
            ),
            paperBackground: widget.background,
            paintPaper: isStage,
            // Nothing to letterbox against without a camera frame.
            paintLetterbox: isStage && cameraView,
            // The apron rides the camera view, as the playback view's does:
            // it is what the camera sees past the paper.
            pasteboardColor: isStage && cameraView
                ? Color(widget.pasteboardArgb)
                : null,
            fadeOpacity: isStage ? weight : 1,
            imageOpacity: isStage ? 1 : weight,
          ),
        ),
      );
    }

    return Stack(
      key: const ValueKey<String>('canvas-track-stack-frames'),
      fit: StackFit.expand,
      children: layers,
    );
  }
}
