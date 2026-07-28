import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../models/camera_pose.dart';
import '../../models/canvas_size.dart';
import '../../models/canvas_viewport.dart';
import '../../models/cut.dart';
import '../../models/cut_id.dart';
import '../../models/playback_quality.dart';
import '../../models/project_background.dart';
import '../../services/playback/playback_frame_mapping.dart';
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
    this.cutFxEnabledOf,
    this.cutPictureVisibleOf,
    this.onFrameCached,
    this.viewport,
    this.background = ProjectBackground.defaultBackground,
  });

  /// The parked global frame (the session's gap parking): moves per
  /// gesture move, null = no parking (the degenerate no-cut state) —
  /// nothing shows.
  final ValueListenable<int?> globalFrame;

  /// Live per-track resolution (resolveTrackStackPositions over the
  /// CURRENT project layout — never playlist snapshots, so edits made
  /// while parked show up on the next build).
  final List<PlaybackPosition> Function(int globalFrame) positionsOf;

  final CutFrameCompositeCache compositeCache;
  final PlaybackQuality Function() qualityOf;
  final CanvasSize cameraFrameSize;
  final CameraPose Function(Cut cut, int frameIndex) cameraPoseOf;

  /// The storyboard V-row display gates (R9), exactly as playback applies
  /// them: fx off bypasses the cut-level pose AND fade, the eye off hides
  /// the cut's picture. Null = always on.
  final bool Function(CutId cutId)? cutFxEnabledOf;
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
        ? const <PlaybackPosition>[]
        : widget.positionsOf(frame);
    _pruneStale([for (final position in positions) position.cutId]);
    if (positions.isEmpty) {
      // A frame no track covers (or no parking at all): the void — the
      // panel's own background shows through, like playback gaps.
      return const SizedBox.expand(
        key: ValueKey<String>('canvas-track-stack-void'),
      );
    }

    final quality = widget.qualityOf();
    final layers = <Widget>[];
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

      // The cut-level pose (V track, AE precomp semantics), display-time
      // only — resolved over the CAMERA frame, the space its lanes author
      // in (R8-③).
      final poseActive = cutFxEnabled && cutPoseIsActive(cut);
      final fade = cutFxEnabled ? cut.fadeOpacityAt(localFrame) : 1.0;
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
            cameraPose: widget.cameraPoseOf(cut, localFrame),
            cameraFrameSize: widget.cameraFrameSize,
            cutPose: poseActive
                ? cutPoseAt(cut, localFrame, widget.cameraFrameSize)
                : null,
            cutAnchorPoint: poseActive
                ? cutAnchorPointAt(cut, localFrame)
                : null,
            paperBackground: widget.background,
            // The bottom covered track is the stage: letterbox, paper,
            // and the full-frame fade wash (single-track = playback
            // parity). The tracks above composite transparently, and
            // their fades thin THEIR contribution only — a full-frame
            // wash would blank the stage below instead of revealing it.
            paintPaper: i == 0,
            paintLetterbox: i == 0,
            fadeOpacity: i == 0 ? fade : 1,
            imageOpacity: i == 0 ? 1 : fade,
            fadeColor: cutFadeTargetColor(cut),
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
