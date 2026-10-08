import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../models/camera_pose.dart';
import '../../models/canvas_size.dart';
import '../../models/canvas_viewport.dart';
import '../../models/cut.dart';
import '../../models/cut_id.dart';
import '../../models/layer_effect.dart' show LayerEffect, ResolvedLayerEffect;
import '../../models/project.dart' show defaultProjectPasteboardArgb;
import '../../models/project_background.dart';
import '../../models/transform_track.dart';
import '../../services/se_name_tag_plan.dart';
import '../track_effect_paint_policy.dart';
import 'canvas_playback_controller.dart';
import 'cut_frame_composite_cache.dart';
import 'playback_frame_painter.dart';
import 'playback_prerender_scheduler.dart';
import '../effective_device_pixel_ratio.dart';
import '../input/control_press_claim.dart';
import '../listenable_rebind.dart';

/// The canvas panel's playback content: cached composite frames advancing
/// with the controller's ticker, rendered INSIDE the panel viewport so the
/// panel chrome (zoom buttons, panbars) keeps working during playback.
///
/// Tapping anywhere cancels playback. Cache misses keep the last displayed
/// frame on screen (the stale-frame policy the tile cache also uses) while
/// the bar at its foot says how much of what the run wants is made. With
/// the camera view enabled the frame is projected through the cut's camera
/// pose instead of shown in canvas space.
class CanvasPlaybackView extends StatefulWidget {
  const CanvasPlaybackView({
    super.key,
    required this.controller,
    required this.compositeCache,
    required this.prerenderProgress,
    this.picturesLanded,
    required this.cameraViewEnabled,
    required this.cameraFrameSize,
    required this.cameraPoseOf,
    this.seNameTagsOf,
    this.cutFxEnabledOf,
    this.viewport,
    this.background = ProjectBackground.defaultBackground,
    this.pasteboardArgb = defaultProjectPasteboardArgb,
    this.pasteboardNone = false,
    this.transformTrackOf,
    this.trackEffectsOf,
    this.trackGlobalFrameOf,
    this.trackStack,
  });

  final CanvasPlaybackController controller;
  final CutFrameCompositeCache compositeCache;
  final ValueListenable<PrerenderProgress> prerenderProgress;

  /// Ticks when a picture of the run has landed
  /// ([PlaybackPrerenderScheduler.landings]). The one under the playhead
  /// may be among them, and while the playhead stands on it nothing else
  /// says so: the controller speaks only when the frame changes.
  final Listenable? picturesLanded;
  final bool cameraViewEnabled;
  final CanvasSize cameraFrameSize;
  final CameraPose Function(Cut cut, int frameIndex) cameraPoseOf;

  /// The SE rows' on-canvas name tags at this cut frame (R5b) — resolved
  /// by the session, drawn over the composite in canvas space.
  final List<ResolvedSeNameTag> Function(Cut cut, int frameIndex)? seNameTagsOf;

  /// The storyboard V row's display gate (R9): FX off bypasses the
  /// cut-level fx work in this display. Null = always on. A display aid
  /// only: the MP4 bake and thumbnails never consult it.
  ///
  /// ↩️The V row had two more — an eye that hid a cut's PICTURE here (the
  /// paper stayed) and the track's static opacity. Both left its head on
  /// 2026-10-08 (I-73, 유저: 「V행의 불투명도랑 비지블 필요없어보여서
  /// 삭제하고싶은데 어때」 · 「5. 값도지움」).
  final bool Function(CutId cutId)? cutFxEnabledOf;

  /// The panel's live pan/zoom (canvas mode); identity when null.
  final CanvasViewport? viewport;

  /// The project background (R10-⑥): the paper AND what playlist gaps
  /// show (a gap frame is background-only — no picture, no fade).
  final ProjectBackground background;

  /// The project pasteboard (R3b): the stage apron the camera view shows
  /// past the paper's edge, fading with the cut unit.
  final int pasteboardArgb;

  /// Whether the pasteboard is ABSENT (F-114) — the checkerboard on screen.
  final bool pasteboardNone;

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

  /// A6: the slot the held clone came from, pinned in the composite cache
  /// for as long as the hold lasts — held pixels are declared pixels, so
  /// the budget stops evicting the very frame on screen and
  /// [CutFrameCompositeCache.pinnedBytes] can report it.
  (CutId, int)? _heldPin;

  void _swapHeldPin((CutId, int)? next) {
    final previous = _heldPin;
    if (previous != null) {
      widget.compositeCache.releasePin(previous);
    }
    if (next != null) {
      widget.compositeCache.retainPin(next);
    }
    _heldPin = next;
  }

  @override
  void initState() {
    super.initState();
    widget.controller.attachTicker(this);
    widget.controller.addListener(_onPlaybackChanged);
    widget.picturesLanded?.addListener(_onPlaybackChanged);
  }

  @override
  void didUpdateWidget(covariant CanvasPlaybackView oldWidget) {
    super.didUpdateWidget(oldWidget);
    rebindListener(
      oldWidget.picturesLanded,
      widget.picturesLanded,
      _onPlaybackChanged,
    );
  }

  @override
  void dispose() {
    widget.picturesLanded?.removeListener(_onPlaybackChanged);
    widget.controller.removeListener(_onPlaybackChanged);
    widget.controller.detachTicker();
    _swapHeldPin(null);
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
      //
      // The tap is the CANVAS's half of the stop law (D13): the actuation
      // gate's navigation hole lets pointers reach the panel so pan/zoom
      // keep working during playback, and a plain tap — a press that
      // navigates nothing — still means stop, as it did before T28-c.
      return _stopsOnPress(
        Stack(
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
      );
      if (composite != null && !identical(composite, _heldSource)) {
        _heldFrame?.dispose();
        _heldSource = composite;
        _heldFrame = composite.clone();
        _heldCanvasSize = position.cut.canvasSize;
        _swapHeldPin((position.cut.id, position.localFrameIndex));
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

    // The storyboard V row's display gate (R9): fx off bypasses the whole
    // cut-level fx work in this display.
    final cutFxEnabled =
        cut == null || (widget.cutFxEnabledOf?.call(cut.id) ?? true);

    // No TRACK-level pose any more: the V row has no transform, so the camera
    // is the only thing that moves the picture on the stage.
    final trackFrame = cut != null && position != null
        ? widget.trackGlobalFrameOf?.call(cut.id, position.localFrameIndex) ??
              position.localFrameIndex
        : 0;

    // One press anywhere on the canvas cancels playback.
    return _stopsOnPress(
      Stack(
        fit: StackFit.expand,
        children: [
          CustomPaint(
            // ⛔The `willChange: true` hint this picture carried is GONE
            // with the editing stack's (see `canvas_layer_stack_view.dart`
            // for the #1100→R11 history and the two symptoms to watch for).
            // It was here so the desktop raster cache could not snap this
            // layer to integral device translation on engage — a 1px hop
            // against the fractional offset panel layout used to produce.
            // Layout no longer produces a fractional one.
            //
            // ⚠️The old text said "a PAUSED frame goes stable". There is no
            // paused state: `isActive` and `isPlaying` are the same
            // question and this view is mounted only while playback is
            // active. The one window in which this picture goes still is a
            // HOLD — the same composite shown for several ticks.
            //
            // ⚠️And this is the one retiring site where removal can COST
            // rather than save: a hold past the cache's engage threshold
            // now bakes an entry, and the next drawing evicts it. On a 24fps
            // sheet full of 6–8 frame holds that is a repeated bake/evict
            // cycle, so the thing to watch here is a raster hitch right
            // after a drawing lands — not a hop.
            painter: PlaybackFramePainter(
              image: !inGap && _heldCanvasSize == canvasSize
                  ? _heldFrame
                  : null,
              canvasSize: canvasSize,
              viewport: widget.viewport,
              // The pan-phase snap's device grid — the editing stack snaps
              // to the same one, so entering playback cannot hop the
              // picture by a sub-pixel.
              devicePixelRatio:
                  EffectiveDevicePixelRatio.of(context),
              cameraPose:
                  widget.cameraViewEnabled && cut != null && position != null
                  ? widget.cameraPoseOf(cut, position.localFrameIndex)
                  : null,
              seNameTags: inGap || cut == null || position == null
                  ? const []
                  : widget.seNameTagsOf?.call(cut, position.localFrameIndex) ??
                        const [],
              cameraFrameSize: widget.cameraViewEnabled
                  ? widget.cameraFrameSize
                  : null,
              // No cutPose/cutAnchorPoint: the V row has no transform.
              // The V row's fx chain over the cut's picture, sampled on the
              // GLOBAL axis its keys live on and bypassed by the row's fx
              // master.
              cutEffects: inGap || cut == null || position == null
                  ? const <ResolvedLayerEffect>[]
                  : trackEffectsAt(
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
              // F-114: an absent pasteboard or paper shows the checkerboard
              // here as on the editing canvas — on screen only.
              pasteboardNone: widget.pasteboardNone,
              checkersAbsentPlanes: true,
              // No fade here: single-cut playback shows one cut and so
              // cannot show a cross-boundary ramp — the all-cuts track
              // stack is where a transition plays. ↩️The track's STATIC
              // opacity thinned this unit (R9 #21) until I-73 took it off
              // the V row.
            ),
          ),
          _prerenderProgressBar(context),
        ],
      ),
    );
  }

  /// The whole view as one press that stops playback.
  ///
  /// 🚨A CLAIMED PRESS, not a tap recogniser (H24, 2026-09-15). The canvas
  /// surface this sits on takes the arena on the first movement, and a tap
  /// recogniser loses its tap to whatever wins it — so a finger that wobbled
  /// would no longer have stopped playback. The claim fires on the release,
  /// and not for a press the canvas turned into a gesture: D13's 「a press
  /// that navigates nothing」, kept exactly.
  Widget _stopsOnPress(Widget picture) => ControlPressClaim(
    onPressed: widget.controller.stop,
    child: GestureDetector(
      key: const ValueKey<String>('canvas-playback-view'),
      behavior: HitTestBehavior.opaque,
      onTap: silentPress(widget.controller.stop),
      child: picture,
    ),
  );

  /// How much of what the run wants ahead of its playhead is made: a bar
  /// whose seat is always there (유저 답 F-296-Q5: 「자리를 늘 두는 막대로
  /// 바꾼다」). While a run waits for its picture it is the one thing on the
  /// canvas that moves. ↩️It was a strip that came with the English words
  /// 「caching N/M」 while pictures were being made and went when they were
  /// — 없다가 생기는 UI, and what it said the ruler's green bar said too.
  Widget _prerenderProgressBar(BuildContext context) {
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
