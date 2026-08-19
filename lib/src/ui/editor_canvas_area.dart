import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../models/canvas_size.dart';
import '../models/canvas_viewport.dart';
import '../models/cut.dart' show Cut;
import '../models/layer_id.dart';
import '../models/project_background.dart';
import '../services/canvas_color_sampler.dart';
import '../services/canvas_flood_fill.dart';
import '../services/canvas_selection.dart' show SelectionMaskOptions;
import '../services/cut_piece_slot.dart';
import '../services/se_name_tag_plan.dart';
import 'brush/brush_tool_state.dart';
import 'dev_profile.dart';
import 'input/app_input_settings.dart' show AppInput;
import 'brush/canvas_selection_commands.dart';
import 'brush/transform_tool_options.dart';
import 'brush/canvas_view_commands.dart';
import 'canvas/viewport_canvas_transform.dart';
import 'brush/brush_canvas_panel.dart' show CanvasAutoFrameRequest;
import 'brush/main_canvas_brush_host.dart';
import 'camera/camera_frame_overlay.dart';
import 'canvas/active_stroke_overlay.dart';
import 'canvas/flip_hud_controller.dart';
import '../models/drawing_guide.dart';
import 'canvas/guide_overlay.dart';
import 'canvas/canvas_layer_stack_view.dart';
import 'canvas/layer_position_gizmo.dart';
import 'canvas/layer_transform_box.dart';
import 'editor_session_manager.dart';
import 'canvas/paper_background.dart' show alphaPreviewEnabled;
import 'playback/canvas_playback_controller.dart' show PlaybackScope;
import 'playback/canvas_playback_view.dart';
import 'playback/canvas_track_stack_view.dart';
import 'playback/recording_streamer_overlay.dart';
import 'debug/input_inspector.dart';
import 'text/app_strings.dart';
import 'text/se_name_tag_paint.dart';
import 'timeline/layer_label_controls.dart';
import '../models/layer.dart' show layerAcceptsBrushInput;
import '../models/layer_kind.dart' show layerKindHasLayerTransform;
import '../models/timeline_row_address.dart'
    show LaneRowAddress, TimelineRowAddress;
import 'widgets/cursor_notice.dart';
import 'timeline/transform_lane_editing.dart';
import 'effective_device_pixel_ratio.dart';
import 'timeline/transform_lane_policy.dart'
    show CanvasManipulator, canvasManipulatorsForLane;

/// The central drawing area: the interactive brush canvas with its layer
/// composites, camera overlay and playback swap.
///
/// Owns the [CanvasViewport] (pan/zoom) — the hottest piece of view state —
/// so panning rebuilds only this subtree. The brush tool and camera-view
/// state are owned by the workspace (they are shared with dockable panels)
/// and consumed here through listenables, again keeping their rebuilds
/// scoped to this subtree.
class EditorCanvasArea extends StatefulWidget {
  const EditorCanvasArea({
    super.key,
    required this.session,
    required this.brushToolState,
    required this.cameraViewEnabled,
    required this.cameraDimOpacity,
    this.onBrushToolStateChanged,
    this.canvasViewCommands,
    this.navigationRegionKey,
    this.canvasSelectionCommands,
    this.cutPieceSlot,
    this.expandedLaneLayerIds,
    this.fillOptions,
    this.selectionMaskOptions,
    this.transformOptions,
    this.eyedropperSource,
    this.onInvokeAction,
    this.flipHud,
  });

  final EditorSessionManager session;

  /// PEN-7b: the shell's action funnel — the flip touch slot fires the
  /// same registry ids as the arrow keys.
  final void Function(String actionId)? onInvokeAction;

  /// The flip HUD's state (shell-owned), forwarded to the panel that
  /// mounts the window.
  final FlipHudController? flipHud;

  /// The active brush tool + settings (workspace-owned; the tools and
  /// brush-settings panels write it).
  final ValueListenable<BrushToolState> brushToolState;

  /// Write-back to the workspace-owned tool state: eyedropper picks land
  /// the sampled color (and return to the painting tool) through here.
  final ValueChanged<BrushToolState>? onBrushToolStateChanged;

  /// The app-level rotate/flip shortcut channel (P8), forwarded to the
  /// canvas panel which binds the actual viewport handlers.
  final CanvasViewCommands? canvasViewCommands;

  /// D13: attached to the canvas panel's container so the playback
  /// actuation gate can measure the navigation region (pan/zoom keep
  /// working during playback inside this rect).
  final GlobalKey? navigationRegionKey;

  /// The app-level selection shortcut channel (P9: Ctrl+D, nudges),
  /// forwarded the same way.
  final CanvasSelectionCommands? canvasSelectionCommands;

  /// Where a finished cut lands — owned by the workspace so the piece
  /// outlives every project the canvas shows.
  final CutPieceSlot? cutPieceSlot;

  /// Camera view mode: overlay shown with the outside dimmed.
  final ValueListenable<bool> cameraViewEnabled;
  final ValueListenable<double> cameraDimOpacity;

  /// The timeline's lane twirl-down state (workspace-owned): the Position
  /// drag gizmo shows only while the active layer's Transform lanes are
  /// open, so the handle never blocks ordinary drawing.
  final ValueListenable<Set<LayerId>>? expandedLaneLayerIds;

  /// The fill tool's flood options (Tool Settings knobs, R11-④); null
  /// keeps the defaults.
  final ValueListenable<FloodFillOptions>? fillOptions;

  /// R28 #6: the eyedropper's reference source (Tool Settings knob); null
  /// keeps "pick what you see".
  final ValueListenable<CanvasColorSampleSource>? eyedropperSource;

  /// The Select tool's lift-time mask knobs (R26); null keeps the
  /// classic byte-preserving hard mask.
  final ValueListenable<SelectionMaskOptions>? selectionMaskOptions;

  /// The transform tool's settings (mode, scale anchor, resampler, mesh
  /// grid); null keeps the defaults.
  final ValueListenable<TransformToolOptions>? transformOptions;

  @override
  State<EditorCanvasArea> createState() => _EditorCanvasAreaState();
}

class _EditorCanvasAreaState extends State<EditorCanvasArea> {
  /// The last T12 probe line, so the inspector shows a line per CHANGE
  /// rather than one per build. See the probe in [build].
  String? _lastCanvasProbe;

  /// The brush size at the start of a 3-finger size drag (PEN-7b); the
  /// drag maps EXPONENTIALLY from here (120px per doubling) so the feel
  /// is uniform at every size.
  double? _brushSizeDragStartSize;

  /// The guides as they look MID-DRAG, before the release commits them.
  ///
  /// Null except while a handle is moving. The project is not written until
  /// the finger lifts, so dragging an axis across the canvas is one undo
  /// entry rather than one per pointer sample.
  CutGuides? _liveGuides;

  CanvasViewport _canvasViewport = CanvasViewport();

  /// [nodes] with the onion ghosts inserted directly UNDER the active
  /// layer — where they belong visually, and (since the merge) inside
  /// whatever folder buffer the active layer sits in.
  static List<CanvasLayerStackNode> _stackNodesWithGhosts(
    List<CanvasLayerStackNode> nodes,
    List<CanvasLayerImageRequest> ghosts,
  ) {
    if (ghosts.isEmpty) {
      return nodes;
    }
    final ghostNodes = [
      for (final ghost in ghosts) CanvasLayerImageNode(ghost),
    ];
    var placed = false;
    List<CanvasLayerStackNode> walk(List<CanvasLayerStackNode> list) {
      final out = <CanvasLayerStackNode>[];
      for (final node in list) {
        switch (node) {
          case CanvasActiveLayerNode():
            if (!placed) {
              out.addAll(ghostNodes);
              placed = true;
            }
            out.add(node);
          case CanvasLayerGroupNode(
            :final children,
            :final opacity,
            :final blendMode,
            :final effects,
          ):
            out.add(
              // Rebuilt field by field: the folder's effects (R6) have to
              // be carried or turning onion skin on would drop them.
              CanvasLayerGroupNode(
                children: walk(children),
                opacity: opacity,
                blendMode: blendMode,
                effects: effects,
              ),
            );
          case CanvasLayerAdjustmentNode(
            :final children,
            :final effects,
            :final mix,
          ):
            // Rebuilt field by field like the group above: the ghosts have
            // to be able to land INSIDE an adjustment's scope, or the row
            // you are drawing on would show the grade while its onion
            // ghosts did not.
            out.add(
              CanvasLayerAdjustmentNode(
                children: walk(children),
                effects: effects,
                mix: mix,
              ),
            );
          case CanvasLayerImageNode():
            out.add(node);
        }
      }
      return out;
    }

    final result = walk(nodes);
    // No active node (a brush-banned row, or nothing exposed): the ghosts
    // still show, on top like the old below-stack put them.
    return placed ? result : [...result, ...ghostNodes];
  }

  /// The live-stroke overlay, owned HERE so the layer stack can paint the
  /// active layer inside the composite tree — that is what lets a folder's
  /// group buffer enclose the layer being drawn on. The interactive view
  /// writes into it (input) and the merged stack painter reads it (paint).
  final ActiveStrokeOverlayModel _activeStrokeOverlay =
      ActiveStrokeOverlayModel();

  /// D12: the cut playback currently stands IN — the fit token's
  /// identity half. 🚨This notifier is the boundary's ONLY crossing
  /// signal: the session's own playback follow (`_followPlaybackCut`) is
  /// QUIET by design (R12-B — no session notify), and the cursor/row
  /// channels suppress the equal values a crossing publishes (local 0 on
  /// entry, the unchanged verb row), so without this the token would go
  /// stale and the next unrelated notify would land a fit mid-cut
  /// (adversarial review). Kept by [_syncPlaybackFitCut]'s per-tick int
  /// comparison against the cached entry interval: the position resolve
  /// (which allocates) runs once per cut CROSSING, never per frame
  /// (old-tablet law), and the notifier fires on the crossing only.
  final ValueNotifier<Cut?> _playbackFitCut = ValueNotifier<Cut?>(null);
  int _playbackFitStart = 0;
  int _playbackFitEnd = -1;

  /// R6q2 (유저 확정 08-18): the viewport as it stood when playback
  /// STARTED — camera view ON pairs its playback fit with a restore on
  /// stop, so the fit never costs the user their framing. Camera OFF
  /// never fits (and so never restores).
  CanvasViewport? _prePlaybackViewport;
  bool _playbackWasActive = false;

  void _syncPlaybackFitCut() {
    final playback = widget.session.playback;
    if (playback.isActive != _playbackWasActive) {
      _playbackWasActive = playback.isActive;
      if (playback.isActive) {
        _prePlaybackViewport = _canvasViewport;
      } else {
        final saved = _prePlaybackViewport;
        _prePlaybackViewport = null;
        if (saved != null && widget.cameraViewEnabled.value && mounted) {
          // 카메라 토글 ON: 재생 fit + 정지 시 복원. OFF stops fitting
          // altogether below, so there is nothing to undo there.
          setState(() => _canvasViewport = saved);
        }
      }
    }
    final global = playback.isActive
        ? playback.globalFrameIndexListenable.value
        : null;
    if (global != null &&
        global >= _playbackFitStart &&
        global < _playbackFitEnd) {
      return;
    }
    final position = global == null ? null : playback.position;
    if (position == null) {
      // A playlist GAP or no playback: no cut to fit — the request goes
      // null (never reframes), and the NEXT cut entry is a token change
      // even when the run loops back into the same cut.
      _playbackFitStart = 0;
      _playbackFitEnd = -1;
      if (_playbackFitCut.value != null) {
        _playbackFitCut.value = null;
      }
      return;
    }
    _playbackFitStart = position.globalFrameIndex - position.localFrameIndex;
    _playbackFitEnd = _playbackFitStart + position.cut.duration;
    if (!identical(_playbackFitCut.value, position.cut)) {
      _playbackFitCut.value = position.cut;
    }
  }

  @override
  void initState() {
    super.initState();
    final playback = widget.session.playback;
    playback.globalFrameIndexListenable.addListener(_syncPlaybackFitCut);
    playback.isActiveListenable.addListener(_syncPlaybackFitCut);
  }

  @override
  void dispose() {
    final playback = widget.session.playback;
    playback.globalFrameIndexListenable.removeListener(_syncPlaybackFitCut);
    playback.isActiveListenable.removeListener(_syncPlaybackFitCut);
    _playbackFitCut.dispose();
    _activeStrokeOverlay.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    return ListenableBuilder(
      // The session subscription lives HERE now (HomePage no longer
      // setStates the world). Committed seeks retarget the editing stack
      // through the _FrameRetargetScope below — deliberately NOT the frame
      // cursor, whose per-move scrub firehose must never rebuild the brush
      // host — and only when the playhead actually changed frames (R13-3).
      listenable: Listenable.merge([
        session,
        // Onion-skin pegs + the per-layer set re-plan the underlay
        // ghosts (P2 → UI-R17 #5).
        session.onionSkinSettings,
        session.onionSkinLayerIds,
        // Opacity drags preview through the editing stack per move (R4 #4)
        // — the canvas is the ONLY session-notify consumer that follows
        // live; everything else waits for the release commit.
        session.opacityDragPreview,
        // brushToolState is deliberately NOT here (R18 UI-2): nothing in
        // the area's derivations reads it — only the brush host consumes
        // it, through its own boundary builder below. Merging it here
        // made EVERY tool switch, color notch and slider tick re-derive
        // and re-diff the whole canvas area (the lab's one-jank-per-
        // tool-switch term).
        widget.cameraViewEnabled,
        widget.cameraDimOpacity,
        ?widget.expandedLaneLayerIds,
        // The pasteboard is PROJECT data now (R3b, R28 #9 reversed): its
        // changes arrive through the session subscription above. The
        // alpha-preview toggle is app VIEW state and repaints the stage
        // floors here.
        alphaPreviewEnabled,
      ]),
      builder: (context, _) {
        // Playback swaps only the viewport CONTENT (via the panel's
        // contentOverride), so the panel shell — zoom buttons, panbars —
        // keeps working while playing. Listen to enter/leave ONLY:
        // subscribing this subtree to every playback tick rebuilt the whole
        // panel at fps and caused real frame drops.
        return ValueListenableBuilder<bool>(
          valueListenable: session.playback.isActiveListenable,
          builder: (context, _, _) {
            // #26: a scrub no longer swaps the content — but the flag still
            // decides WHAT THE GAP ANSWER IS: a parked global only reads as
            // a gap while the gesture is live (`_gapGlobalFrame` is gated on
            // this), so `inGap` below flips at enter and leave. D6 adds the
            // TERRITORY edge: a drag that started inside the cut crosses
            // the boundary mid-gesture, and the parking alone is per-move
            // quiet — the out↔in flips arrive through
            // [EditorSessionManager.scrubOutOfTerritory]. Two rebuilds per
            // gesture, at most two more per territory transition; the
            // crossed frames come through the retarget scope, not here.
            return ListenableBuilder(
              listenable: Listenable.merge([
                session.frameScrubActive,
                session.scrubOutOfTerritory,
              ]),
              builder: (context, _) {
                return _FrameRetargetScope(
                  session: session,
                  builder: (context) {
                    // Derived HERE (not captured above) so a seek-driven
                    // rebuild re-reads them at the new playhead.
                    final isCameraLayerActive = session.isCameraLayerActive;
                    final showCameraOverlay =
                        widget.cameraViewEnabled.value || isCameraLayerActive;
                    return labProbe(
                      'canvasAreaBuild',
                      () => _buildInteractiveCanvas(
                        session,
                        isCameraLayerActive: isCameraLayerActive,
                        showCameraOverlay: showCameraOverlay,
                      ),
                    );
                  },
                );
              },
            );
          },
        );
      },
    );
  }

  /// The track stack (multitrack display path): one camera-frame
  /// projection per covered track, following [globalFrame] per move.
  /// Three mounts, one construction: the parked contentOverride, the
  /// scrub preview's gap branch (both on the gap parking) and ALL-CUTS
  /// playback (on the clock's global frame, R3a).
  ///
  /// 🚨[cameraView] is the CROP, and it belongs to PLAYBACK alone (user
  /// 2026-08-11). The parked canvas has always shown the whole canvas with the
  /// camera frame drawn OVER it, and a storyboard ruler drag parks per move
  /// (`scrubGlobalFrame` parks the moment the frame belongs to another cut) —
  /// so cropping here made the drag look nothing like the state it started
  /// from. Two mounts pass false and the answer is the same one the eye
  /// already had: preview = canvas + overlay, playback = crop.
  Widget _buildTrackStackView(
    EditorSessionManager session,
    CanvasViewport viewport, {
    ValueListenable<int?>? globalFrame,
    bool cameraView = false,
  }) {
    final project = session.repository.requireProject();
    return CanvasTrackStackView(
      globalFrame: globalFrame ?? session.gapParkingListenable,
      positionsOf: session.trackStackContributionsAt,
      compositeCache: session.cutFrameCompositeCache,
      qualityOf: () => session.playbackQuality,
      cameraFrameSize: session.cameraFrameSize,
      cameraViewEnabled: cameraView,
      cameraPoseOf: session.cameraPoseForCut,
      seNameTagsOf: session.seNameTagsForCutFrame,
      cutFxEnabledOf: session.isCutFxEnabled,
      trackStaticOpacityOf: session.trackStaticOpacityForCut,
      cutPictureVisibleOf: session.isCutPictureVisible,
      onFrameCached: session.enforcePlaybackCacheBudget,
      viewport: viewport,
      background: session.projectBackground,
      backdropArgb: project.backdropArgb,
      pasteboardArgb: project.pasteboardArgb,
      showAlphaCheckerboard: alphaPreviewEnabled.value,
      trackEffectsOf: session.trackEffectsForCut,
    );
  }

  // `_wrapInCutPose` went with the V row's transform: nothing poses a whole cut
  // on the editing canvas any more, so its content, gizmos and overlays all
  // draw straight in the layer's own canvas space.

  /// R26 #35: WHY the paint press did nothing — a drawing row simply has
  /// no cel at this frame; every other section cannot hold artwork at
  /// all. One shared message table, so the wording stays consistent
  /// wherever this refusal is reused.
  String _drawRefusalFor(EditorSessionManager session) {
    final strings = AppStrings.of(
      session.languageSettings.value.programLanguage,
    );
    // Standing on a PROPERTY LANE (user, 2026-08-08): the row you are on
    // is not a drawing surface, whatever the layer under it could take.
    // The layer-not-drawable wording is reused deliberately — the user
    // asked for that notice, and it is the true one: this row does not
    // accept strokes.
    if (!_rowAcceptsStrokes(session.currentRowListenable.value)) {
      return strings.noticeLayerNotDrawable;
    }
    final activeLayer = session.activeLayer;
    // R27 #16: the question is whether THIS LAYER takes strokes, not
    // which section it sits in — the CAM section is no longer uniformly
    // undrawable in the user's model, so the refusal names the layer
    // (media-REFERENCE layers included: strokes wait for a rasterize).
    final drawable = activeLayer != null && layerAcceptsBrushInput(activeLayer);
    return drawable
        ? strings.noticeNoFrameHere
        : strings.noticeLayerNotDrawable;
  }

  /// Whether the row the frame-axis verbs are on can take a stroke.
  ///
  /// A LANE cannot. Standing on a property used to keep drawing available
  /// on the layer beneath, which is the fudge the user retired: you stand
  /// in exactly one place, and if that place is `Blur ▸ Radius` then the
  /// brush has nothing to write on.
  static bool _rowAcceptsStrokes(TimelineRowAddress? row) =>
      row is! LaneRowAddress;

  Widget _buildInteractiveCanvas(
    EditorSessionManager session, {
    required bool isCameraLayerActive,
    required bool showCameraOverlay,
  }) {
    final isPlaybackActive = session.playback.isActive;
    // 🚨★★★ #26 (2026-08-15): A RULER SCRUB IS NOT A SECOND DISPLAY MODE.
    // 「그냥 액티브레이어급으로 그냥 원본 보여주게하고싶어 … 그냥 항상 full」
    //
    // A scrub used to swap the whole viewport to the composite-cache preview
    // — playback's display machinery — and every piece of editing chrome
    // below carried a `!isScrubbing` so it would not draw over a foreign
    // picture. That is the ENTIRE reason those gates existed, so removing
    // the stand-in removes them: PLAYBACK is the one thing that replaces the
    // canvas, and a scrub just moves the playhead the canvas already
    // follows (`_FrameRetargetScope`).
    // R16-⑥ (user semantics): a gap has NO cut — the canvas shows a
    // paperless VOID: no editable cel, no layer content, no paper.
    final inGap = !isPlaybackActive && session.editingPlayheadInGap;
    // The camera overlay authors the ACTIVE cut's pose — with no cut (a
    // gap parking) there is nothing to author and reading the pose would
    // throw (requireActiveCut).
    //
    // It survives a SCRUB (only `isPlaybackActive` gates the overlay builder),
    // and that is the whole answer to the ruler-drag framing: the overlay was
    // never the missing half — the track stack's crop was the extra one.
    final cameraOverlayVisible =
        showCameraOverlay && session.activeCutOrNull != null;
    final layerStack = inGap
        ? (nodes: const <CanvasLayerStackNode>[], activeLayerOpacity: 1.0)
        : session.editingCanvasStack;
    // T12 field probe (no-op while the Input Inspector is hidden, and it
    // prints only when one of the four answers CHANGES — a line per build
    // would bury the inspector's five-note window in a single scrub).
    //
    // 유저 실기: 컷 끝 너머로 가면 용지와 그림이 사라지고 흰 외곽선만 남는다.
    // The SESSION was measured and is right there (`past_cut_end_is_ordinary_test`
    // pins `inGap == false`, a non-empty stack and an unchanged duration in
    // all three arrangements), so the disagreement is between what the
    // session answers and what reaches the screen — and only the device can
    // say which. These are the four values the paper hangs on, in order:
    // if `gap` is true the session decided there is no cut here after all;
    // if `nodes` is 0 with `gap` false the plan came back empty; and if all
    // four look right while the paper is gone, the fault is below this
    // widget, in the painting.
    //
    // ⚠️NOT behind an `assert`: the builds the user actually reports from are
    // release ones, and an assert-gated probe is exactly the probe that is
    // missing when it is needed. The visibility flag is the guard instead, so
    // a hidden inspector costs one bool read and never builds the string —
    // the same shape the pan recogniser's probes use.
    if (InputInspector.visible.value) {
      // The FRAME leads, and it is not decoration: without it "no new line"
      // reads two ways — the four answers were the same, or this build never
      // ran at all — and those point at opposite halves of the app. With the
      // playhead in the string every move prints exactly once, so silence
      // means the build did not happen and nothing else.
      final probe =
          'canvas f=${session.editingGlobalFrame}'
          ' gap=$inGap'
          ' cut=${session.activeCutOrNull?.id.value ?? '-'}'
          ' nodes=${layerStack.nodes.length}'
          ' paper=${!inGap}';
      if (probe != _lastCanvasProbe) {
        _lastCanvasProbe = probe;
        InputInspector.note(probe);
      }
    }
    final selection = inGap
        ? null
        : isCameraLayerActive
        ? session.cameraBackdropSelection
        : session.activeBrushEditorSelection;
    // The layer shown in the interactive view draws POSED (always-applied
    // transforms, active layer included) with draw-through input.
    final interactivePose = selection == null
        ? null
        : session.layerCanvasPoseSample(selection.layerId);
    // There is no CUT-level pose to compose in: the V row's transform is gone,
    // so the only pose the editing canvas wraps is the active LAYER's.
    //
    // Gap state (no active cut, UI-R9 #3): the void keeps a stable stage
    // geometry — the camera frame size stands in for the missing cut.
    final canvasSize =
        session.activeCutOrNull?.canvasSize ?? session.cameraFrameSize;
    // The cut FADE still follows the cursor (R9-C: fx ALWAYS reflects — dark
    // faded frames are worked with fx off). It is the track's static opacity
    // times the TRANSITION row's ramp now.
    final cutFadeOpacity = session.activeCutEditingFadeOpacity();
    final showFadeWash = !isPlaybackActive && cutFadeOpacity < 1;
    // The SE rows' on-canvas name tags (R5b, §6-z15) — the editing
    // canvas's copy of what playback and export draw. Playback renders its
    // own (through the frame painter), so this stands down there exactly
    // like the other editing chrome.
    final activeCutForTags = session.activeCutOrNull;
    final seNameTags =
        isPlaybackActive || activeCutForTags == null
        ? const <ResolvedSeNameTag>[]
        : session.seNameTagsForCutFrame(
            activeCutForTags,
            session.currentFrameIndex,
          );
    // R5 #10: WHAT IS SELECTED IS WHAT YOU CAN GRAB.
    //
    // The crosshair used to answer to "the row's lanes are twirled open",
    // which is not a statement about intent at all: opening a row to read a
    // Blur radius put a Position handle on the artwork, and standing on
    // Opacity left that handle there, still moving Position. The standing
    // LANE declares its manipulators now, and a lane that declares none
    // (Opacity, every effect parameter) draws none.
    final activeLayer = session.activeLayer;
    final canPoseActiveLayer =
        !isPlaybackActive &&
        !isCameraLayerActive &&
        activeLayer != null &&
        // The gizmo COMMITS a transform track, so the row must actually
        // author one. Every non-camera kind used to, and the camera was
        // covered above — until R6b's adjustment row, which twirls open
        // for its effect lanes while owning no transform at all, and whose
        // commit path throws by design.
        layerKindHasLayerTransform(activeLayer.kind) &&
        layerKindShowsFxToggle(activeLayer.kind) &&
        // R8: the TRANSFORM group's switch, not the row master — a row
        // with a colour effect off still has a pose to drag.
        session.isLayerTransformFxEnabled(activeLayer.id);
    // Camera mode retargets the Fit button at the camera frame's bounds —
    // fitting the cut canvas there framed the wrong rectangle.
    final fitFocusRect = isCameraLayerActive
        ? cameraFrameBoundsInCanvas(
            pose: session.cameraPoseAtCurrentFrame,
            cameraFrameSize: session.cameraFrameSize,
          )
        : null;
    return RepaintBoundary(
      // D13: the actuation gate's navigation region — the canvas PANEL's
      // rect (viewport gestures, zoom buttons, panbars), measured by the
      // gate at event time. Attached here so the region is exactly what
      // the panel lays out, splitter drags and resizes included.
      key: widget.navigationRegionKey,
      child: KeyedSubtree(
        key: const ValueKey<String>('main-canvas-brush-host-container'),
        // The tool-state boundary (R18 UI-2): tool switches and setting
        // tweaks rebuild ONLY the host config — every session-derived
        // value above (layer stacks, poses, onion requests) is captured
        // and reused, and the host's element keeps all its state.
        //
        // The STANDING ROW rides the same boundary, SUBSCRIBED rather than
        // read at build time: it is published without a session notify (the
        // claim fires on pointer-down, inside gestures whose contract is
        // silence until release), so a canvas that read it above would go
        // on taking strokes after the user stepped onto a property lane.
        // One merged listenable instead of a second nested builder — both
        // only ever change the host's CONFIG.
        child: ListenableBuilder(
          listenable: Listenable.merge([
            widget.brushToolState,
            session.currentRowListenable,
            // D12: the playing cut's identity — fires once per cut
            // crossing (never per tick), and only the host CONFIG
            // changes, like everything else on this boundary.
            _playbackFitCut,
          ]),
          builder: (context, _) {
            final toolState = widget.brushToolState.value;
            // D12 × R6q2 (유저 확정 08-18): playback fit is the CAMERA
            // VIEW's — toggle ON fits the camera's output frame at the
            // origin per cut entry (the painter's frameRect) and the
            // stop restores the pre-play viewport; toggle OFF never
            // fits at all (the user's framing is the framing). One
            // request per cut ENTRY through the panel's own
            // playback-follow law (CanvasAutoFrameRequest); the
            // identity comes from [_playbackFitCut] — see its doc for
            // why no existing channel carries the crossing here.
            final cameraViewOn = widget.cameraViewEnabled.value;
            final playbackCut = cameraViewOn ? _playbackFitCut.value : null;
            final playbackAutoFrame = playbackCut == null
                ? null
                : CanvasAutoFrameRequest(
                    token: (playbackCut.id, cameraViewOn),
                    rect: Offset.zero &
                        Size(
                          session.cameraFrameSize.width.toDouble(),
                          session.cameraFrameSize.height.toDouble(),
                        ),
                  );
            // INSIDE the builder, deliberately: the standing row is
            // published without a session notify, so a manipulator gate
            // computed above would answer the row you left. Same trap the
            // stroke gate two lines down was written to avoid.
            final standing = session.currentRowListenable.value;
            final showPositionGizmo =
                canPoseActiveLayer &&
                standing is LaneRowAddress &&
                standing.layerId == activeLayer.id &&
                canvasManipulatorsForLane(
                  standing.laneId,
                ).contains(CanvasManipulator.transformBox);
            // The box frames the layer's INK, so a blank cel has no box —
            // the crosshair still answers for Position there. Resolved
            // only when something will use it: the scan is memoized on the
            // surface, but asking at all costs a frame lookup.
            final boundsRect = showPositionGizmo
                ? session.layerContentBoundsAt(
                    activeLayer,
                    session.currentFrameIndex,
                  )
                : null;
            final transformBoxBounds = boundsRect == null
                ? null
                : Rect.fromLTRB(
                    boundsRect.left.toDouble(),
                    boundsRect.top.toDouble(),
                    boundsRect.rightExclusive.toDouble(),
                    boundsRect.bottomExclusive.toDouble(),
                  );
            final showAnchorGizmo =
                canPoseActiveLayer &&
                standing is LaneRowAddress &&
                standing.layerId == activeLayer.id &&
                canvasManipulatorsForLane(
                  standing.laneId,
                ).contains(CanvasManipulator.anchorPoint);
            return MainCanvasBrushHost(
              rowAcceptsStrokes: _rowAcceptsStrokes(
                session.currentRowListenable.value,
              ),
              // MERGED canvas: we own the live-stroke overlay, so the
              // layer stack can paint the active layer inside the
              // composite tree and a folder's group buffer can enclose
              // the layer being drawn on. Playback swaps the whole viewport
              // content, so merged mode stands down there (no underlay
              // builder, no active painter).
              activeStrokeOverlayModel: isPlaybackActive
                  ? null
                  : _activeStrokeOverlay,
              // Camera mode still needs artwork on screen: fall
              // back to the first drawn layer at the playhead.
              selection: selection,
              canvasSize: canvasSize,
              // The cut's guides reach the stroke pipeline through here;
              // the panel maps them into the active layer's artwork space
              // before the view sees them.
              guides: session.activeCutGuides,
              frameStore: session.brushFrameStore,
              cacheInvalidationSink: session.cacheInvalidationHub,
              historyManager: session.historyManager,
              viewport: _canvasViewport,
              onViewportChanged: (viewport) {
                setState(() => _canvasViewport = viewport);
              },
              // 유저 R2 #14: the pill takes the corner AWAY from the tool
              // strip — the strip is where the hand already is.
              brushToolState: toolState,
              fitFocusRect: fitFocusRect,
              autoFrame: playbackAutoFrame,
              viewCommands: widget.canvasViewCommands,
              selectionCommands: widget.canvasSelectionCommands,
              cutPieceSlot: widget.cutPieceSlot,
              // R13-3: a live stroke holds the prerender warmer — composite
              // warming never shares the UI/raster threads with drawing.
              onStrokeInputActiveChanged: session.setBrushInputActive,
              // R15-⑤: selection drags block seeks/cut switches entirely.
              onSelectionInteractionChanged: (active) => active
                  ? session.beginSelectionInteraction()
                  : session.endSelectionInteraction(),
              // R26 #35: a paint press with no cel here says WHY, at the
              // cursor. Which refusal applies is a SECTION question, so
              // only the shell can answer it.
              onDrawRefused: () => cursorNotices.show(_drawRefusalFor(session)),
              // P5 eyedropper. Picks NEVER switch tools (R11-②): the
              // eyedropper stays armed until the user changes tools,
              // Alt-picks keep the painting tool.
              // R28 #6: the reference is a SETTING — display (the visible
              // composite) or the active layer alone. Either way the
              // sampler maps through a posed layer's inverse (R28 #7), so
              // a transformed layer picks what the screen shows instead of
              // silently reading as paper.
              // Lazy: only reachable with an editable selection, which a
              // gap state never offers (requireActiveCut = backstop).
              sampleColorAt: (point) => sampleCompositeColor(
                cut: session.requireActiveCut,
                frameIndex: session.currentFrameIndex,
                surfaceResolver: session.brushSurfaceForLayerFrame,
                point: point,
                paperColor: session.projectBackground.argb,
                source:
                    widget.eyedropperSource?.value ??
                    CanvasColorSampleSource.display,
                activeLayerId: session.activeLayer?.id,
              ),
              // BOTH stage colors are PROJECT data now (R3b): they go out
              // in exports, so they undo with everything else — the
              // pasteboard's app-state era (R28 #9) survives only as the
              // new-project default.
              //
              // ⛔The floor no longer READS them here. It used to, and being
              // the only host that did is exactly how the timesheet, conte,
              // envelope and viewer ended up on hard black: `CanvasStageColors`
              // says it once for all of them (유저, R4 #2). The COMMIT
              // handlers stay — this is still where the pill's swatches are
              // wired, and writing is not the same question as reading.
              paperColor: session.projectBackground.argb,
              onPaperColorChanged: (argb) =>
                  session.setProjectBackground(ProjectBackground.color(argb)),
              onPasteboardColorChanged: session.setPasteboardColor,
              onBackdropColorChanged: session.setProjectBackdrop,
              onEyedropperPick: (color) => widget.onBrushToolStateChanged?.call(
                widget.brushToolState.value.copyWith(color: color),
              ),
              onAltColorPick: (color) => widget.onBrushToolStateChanged?.call(
                widget.brushToolState.value.copyWith(color: color),
              ),
              // PEN-7a: the mapped hold temporarily switches the TOOL —
              // the user's design: reuse the one tool-switch path so the
              // cursor, panels and per-tool settings memory all follow.
              // Release springs back (default) or keeps the switched
              // tool, per the mapping.
              onTemporaryToolHold: (tool) {
                session.heldOriginalTool ??= widget.brushToolState.value.tool;
                widget.onBrushToolStateChanged?.call(
                  widget.brushToolState.value.copyWith(tool: tool),
                );
              },
              onTemporaryToolRelease: ({required keep}) {
                final original = session.heldOriginalTool;
                session.heldOriginalTool = null;
                if (!keep && original != null) {
                  widget.onBrushToolStateChanged?.call(
                    widget.brushToolState.value.copyWith(tool: original),
                  );
                }
              },
              // PEN-7b: the control-mode touch slots — the flip funnel
              // comes from the shell; the brush-size drag lands here
              // (this widget owns the tool state channel).
              onInvokeAction: widget.onInvokeAction,
              onBrushSizeDragStart: () =>
                  _brushSizeDragStartSize = widget.brushToolState.value.size,
              onBrushSizeDragUpdate: (upwardDelta, {required snap}) {
                final start = _brushSizeDragStartSize;
                if (start == null) {
                  return;
                }
                var next = start * math.pow(2, upwardDelta / 120).toDouble();
                if (snap) {
                  next = AppInput.snapToList(
                    next,
                    AppInput.settings.value.brushSizeSnaps,
                  );
                }
                widget.onBrushToolStateChanged?.call(
                  widget.brushToolState.value.copyWith(size: next),
                );
              },
              onBrushSizeDragEnd: () => _brushSizeDragStartSize = null,
              flipHud: widget.flipHud,
              // P6 fill: the flood region as ONE mask dab; the panel commits it
              // through the stroke funnel onto the active layer's frame.
              selectionMaskOptions: widget.selectionMaskOptions,
              transformOptions: widget.transformOptions,
              fillDabAt: (point, color) => buildFillDab(
                cut: session.requireActiveCut,
                frameIndex: session.currentFrameIndex,
                surfaceResolver: session.brushSurfaceForLayerFrame,
                point: point,
                color: color,
                // TP1: the FILL has its own opacity now — the strip's bar
                // writes the fill's field, not the brush's.
                opacity: toolState.activeOpacity,
                options: widget.fillOptions?.value ?? const FloodFillOptions(),
                paperColor: session.projectBackground.argb,
                // Extended fills refuse OPEN regions (the flood reached
                // the pasteboard apron wall) — say why nothing filled.
                onOpenRegion: () =>
                    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Region is not closed — nothing filled '
                          '(Fill Beyond Canvas needs an enclosed area).',
                        ),
                      ),
                    ),
              ),
              // The SHAPE fill's dab. No cut, no frame, no surfaces: a
              // drawn outline is filled whatever is under it, so it never
              // reads the picture — which is why this line is short and
              // the one above is not.
              shapeFillDabFor: (shape, color) => buildShapeFillDab(
                shape: shape,
                color: color,
                opacity: toolState.activeOpacity,
                options: widget.fillOptions?.value ?? const FloodFillOptions(),
              ),
              // Layers below/above the active one composite around the
              // interactive view from the layer image cache — this is what makes
              // the other layers (and their visibility/opacity) visible while
              // editing. During playback the composite covers everything. Under
              // an active CUT pose (R9-B) the paper splits out of the wrap: the
              // canvas is the static stage, only the content rides the pose.
              viewportUnderlayBuilder: isPlaybackActive
                  ? null
                  : (context, viewport, activeSurfacePainter, floatOverlay) {
                      final below = CanvasLayerStackView(
                        // MERGED: the whole tree, active layer included, so
                        // a folder's group buffer encloses the layer being
                        // drawn on. Onion ghosts (P2) sit above the other
                        // layers and directly UNDER the active drawing;
                        // playback and scrubs never reach here, so they
                        // auto-hide. A gap parking shows the VOID (R16-⑥):
                        // no ghosts either.
                        nodes: _stackNodesWithGhosts(
                          layerStack.nodes,
                          inGap ? const [] : session.onionSkinCanvasRequests(),
                        ),
                        activeSurfacePainter: activeSurfacePainter,
                        // TS1: the selection's float draws in the active
                        // layer's slot, so the rows above it occlude the live
                        // preview the way they occlude the landed pixels.
                        floatOverlay: floatOverlay,
                        imageCache: session.layerFrameImageCache,
                        canvasSize: canvasSize,
                        viewport: viewport,
                        // R16-⑥: no cut in a gap — no paper (per-cut papers
                        // make anything else confusing; the void is the truth).
                        paintPaper: !inGap,
                        paperBackground: session.projectBackground,
                      );
                      // The paper-stays-put split under a cut pose went with
                      // the V row's transform: nothing poses the whole cut on
                      // the editing canvas, so the layers draw straight.
                      return below;
                    },
              interactiveContentOpacity: layerStack.activeLayerOpacity,
              interactiveContentPose: interactivePose,
              // The playback view renders the camera framing itself; the editing
              // overlay would show a stale playhead pose on top of it. A scrub
              // keeps the CAMERA overlay only — the preview is the current view
              // moving through time, so the frame stays visible and rides the
              // cursor.
              // The ABOVE-layers stack is gone from here: the merged
              // underlay paints the whole tree in one picture now, which is
              // the only way a group buffer can span the active layer. What
              // is left in the overlay is chrome.
              viewportOverlayBuilder:
                  (cameraOverlayVisible ||
                          showPositionGizmo ||
                          showAnchorGizmo ||
                          showFadeWash ||
                          session.activeCutGuides.isNotEmpty ||
                          seNameTags.isNotEmpty) &&
                      !isPlaybackActive
                  ? (context, viewport) => Stack(
                      children: [
                        // Guides are EDITING scaffolding: they are drawn
                        // here and nowhere else — playback, thumbnails and
                        // export never see them, the way a ruler never
                        // prints. Under the camera frame and the gizmos,
                        // which are chrome about the shot rather than about
                        // the drawing.
                        if (session.activeCutGuides.isNotEmpty)
                          Positioned.fill(
                            child: IgnorePointer(
                              child: CustomPaint(
                                painter: GuideOverlayPainter(
                                  // The live drag value while a handle is
                                  // moving, so the drawn guide follows the
                                  // finger without a project write.
                                  guides:
                                      _liveGuides ?? session.activeCutGuides,
                                  viewport: viewport,
                                  canvasSize: canvasSize,
                                  emphasized:
                                      toolState.tool == CanvasTool.guide,
                                  color: Theme.of(context).colorScheme.primary,
                                  selectedGuideId: session.selectedGuideId,
                                ),
                              ),
                            ),
                          ),
                        // The handle layer mounts ONLY for the guide tool,
                        // so it never stands between the brush and the cel.
                        if (toolState.tool == CanvasTool.guide)
                          Positioned.fill(
                            child: GuideEditLayer(
                              guides: _liveGuides ?? session.activeCutGuides,
                              viewport: viewport,
                              onGuideSelected: (id) =>
                                  session.selectedGuideId = id,
                              // Live while dragging: the project is not
                              // touched, so a drag is one undo entry.
                              onGuidesChanged: (guides) =>
                                  setState(() => _liveGuides = guides),
                              onGuidesCommitted: (guides) {
                                setState(() => _liveGuides = null);
                                session.setActiveCutGuides(guides);
                              },
                            ),
                          ),
                        if (seNameTags.isNotEmpty)
                          Positioned.fill(
                            // Rides the cut pose like the gizmo: the tag
                            // annotates the posed picture, exactly as the
                            // frame painter draws it inside the pose.
                            child: IgnorePointer(
                              child: CustomPaint(
                                painter: _SeNameTagOverlayPainter(
                                  viewport: viewport,
                                  canvasSize: canvasSize,
                                  tags: seNameTags,
                                  devicePixelRatio:
                                      EffectiveDevicePixelRatio.of(context),
                                ),
                              ),
                            ),
                          ),
                        if (showFadeWash)
                          Positioned.fill(
                            // The cut fade on the EDITING canvas (R9-C →
                            // R3b): the fade is transparency, and here the
                            // whole viewport IS the cut's unit (pasteboard,
                            // paper, pictures) over the backdrop — so a
                            // backdrop-colored wash at (1 − fade) is
                            // pixel-equal to thinning the unit, without
                            // re-compositing the editing stack.
                            child: IgnorePointer(
                              child: CustomPaint(
                                painter: _CutFadeWashPainter(
                                  viewport: viewport,
                                  canvasSize: canvasSize,
                                  color:
                                      Color(
                                        session.repository
                                            .requireProject()
                                            .backdropArgb,
                                      ).withValues(
                                        alpha: (1 - cutFadeOpacity).clamp(
                                          0.0,
                                          1.0,
                                        ),
                                      ),
                                  devicePixelRatio:
                                      EffectiveDevicePixelRatio.of(context),
                                ),
                              ),
                            ),
                          ),
                        if (cameraOverlayVisible)
                          Positioned.fill(
                            // The cursor subscription keeps the frame gliding
                            // along its animated pose during scrubs (and after
                            // committed seeks) without any wider rebuild.
                            //
                            // ㊲: the PARKING is the other half of "where am
                            // I". A scrub that crosses a cut boundary moves
                            // only that — the cursor stays put, by design —
                            // so a pose read on the cursor alone stayed
                            // frozen on the cut being left.
                            child: ListenableBuilder(
                              listenable: session.editingFrameCursor,
                              builder: (context, _) =>
                                  ValueListenableBuilder<int?>(
                                    valueListenable:
                                        session.gapParkingListenable,
                                    builder: (context, _, _) {
                                      final pose = session.displayedCameraPose;
                                      // Nothing under the cursor to frame:
                                      // the scrub is over a gap.
                                      if (pose == null) {
                                        return const SizedBox.shrink();
                                      }
                                      return CameraFrameOverlay(
                                        pose: pose,
                                        cameraFrameSize: session.cameraFrameSize,
                                        viewport: viewport,
                                        // Dim belongs to camera-view mode;
                                        // plain manipulation keeps the
                                        // artwork undimmed.
                                        dimOpacity:
                                            widget.cameraViewEnabled.value
                                            ? widget.cameraDimOpacity.value
                                            : 0,
                                        interactive: isCameraLayerActive,
                                        onPoseCommitted: session
                                            .setCameraKeyframeAtCurrentFrame,
                                      );
                                    },
                                  ),
                            ),
                          ),
                        if (showPositionGizmo && transformBoxBounds != null)
                          Positioned.fill(
                            // R5 #10: the box frames the PICTURE, and its
                            // corners scale while its rotate handle turns —
                            // one member per handle. No cut pose to ride any
                            // more: the V row's transform is gone.
                            child: LayerTransformBox(
                                bounds: transformBoxBounds,
                                pose: session.layerPoseAtFrame(
                                  activeLayer,
                                  session.currentFrameIndex,
                                ),
                                anchorPoint: session.layerAnchorPointAtFrame(
                                  activeLayer,
                                  session.currentFrameIndex,
                                ),
                                canvasSize: canvasSize,
                                viewport: viewport,
                                onScaleCommitted: (zoom) =>
                                    session.updateLayerTransformTrack(
                                      activeLayer.id,
                                      transformTrackWithScaleDragged(
                                        activeLayer.transformTrack,
                                        frameIndex: session.currentFrameIndex,
                                        zoom: zoom,
                                      ),
                                      description: 'Scale ${activeLayer.name}',
                                    ),
                                onRotationCommitted: (degrees) =>
                                    session.updateLayerTransformTrack(
                                      activeLayer.id,
                                      transformTrackWithRotationDragged(
                                        activeLayer.transformTrack,
                                        frameIndex: session.currentFrameIndex,
                                        rotationDegrees: degrees,
                                      ),
                                      description:
                                          'Rotate ${activeLayer.name}',
                                    ),
                            ),
                          ),
                        if (showPositionGizmo)
                          Positioned.fill(
                            // No cut-pose wrap: the V row's transform is gone,
                            // so the crosshair sits directly on the layer's own
                            // canvas space and the committed Position needs no
                            // un-posing.
                            child: LayerPositionGizmo(
                                pose: session.layerPoseAtFrame(
                                  activeLayer,
                                  session.currentFrameIndex,
                                ),
                                viewport: viewport,
                                // ONE key at the playhead per drag (AE rule,
                                // one undo).
                                onPositionCommitted: (position) =>
                                    session.updateLayerTransformTrack(
                                      activeLayer.id,
                                      transformTrackWithPositionDragged(
                                        activeLayer.transformTrack,
                                        frameIndex: session.currentFrameIndex,
                                        position: position,
                                      ),
                                      description: 'Move ${activeLayer.name}',
                                    ),
                            ),
                          ),
                        if (showAnchorGizmo)
                          Positioned.fill(
                            // Unwrapped like the position handle, for the same
                            // reason.
                            child: LayerAnchorGizmo(
                                anchorPoint: session.layerAnchorPointAtFrame(
                                  activeLayer,
                                  session.currentFrameIndex,
                                ),
                                viewport: viewport,
                                onAnchorCommitted: (anchorPoint) =>
                                    session.updateLayerTransformTrack(
                                      activeLayer.id,
                                      transformTrackWithAnchorDragged(
                                        activeLayer.transformTrack,
                                        frameIndex: session.currentFrameIndex,
                                        anchorPoint: anchorPoint,
                                      ),
                                      description:
                                          'Anchor ${activeLayer.name}',
                                    ),
                            ),
                          ),
                      ],
                    )
                  : null,
              contentOverride: isPlaybackActive
                  // The streamer rides ON the picture (REC1-E): the ADR
                  // scribe belongs over the projection, never in a side
                  // panel. Constant two-child Stack (the overlay shrinks
                  // itself) — the sibling-count rule.
                  ? (context, viewport) => Stack(
                      fit: StackFit.expand,
                      children: [
                        CanvasPlaybackView(
                          controller: session.playback,
                          compositeCache: session.cutFrameCompositeCache,
                          qualityOf: () => session.playbackQuality,
                          prerenderProgress:
                              session.prerenderScheduler.progress,
                          cameraViewEnabled: widget.cameraViewEnabled.value,
                          cameraFrameSize: session.cameraFrameSize,
                          cameraPoseOf: session.cameraPoseForCut,
                          seNameTagsOf: session.seNameTagsForCutFrame,
                          cutFxEnabledOf: session.isCutFxEnabled,
                          trackStaticOpacityOf:
                              session.trackStaticOpacityForCut,
                          cutPictureVisibleOf: session.isCutPictureVisible,
                          viewport: viewport,
                          background: session.projectBackground,
                          pasteboardArgb: session.repository
                              .requireProject()
                              .pasteboardArgb,
                          trackEffectsOf: session.trackEffectsForCut,
                          trackGlobalFrameOf: session.trackGlobalFrameOf,
                          // ALL-CUTS playback watches the whole stage: the
                          // frame is the track stack on the clock's global
                          // axis (R3a) — a selected-track gap shows what
                          // the OTHER tracks hold there instead of the
                          // void. Single-cut playback keeps its
                          // single-cut frame (the editing context).
                          trackStack:
                              session.playback.scope == PlaybackScope.allCuts
                              ? _buildTrackStackView(
                                  session,
                                  viewport,
                                  globalFrame: session
                                      .playback
                                      .globalFrameIndexListenable,
                                  // Playback is the one place the crop
                                  // belongs, and there it answers the toggle.
                                  cameraView: widget.cameraViewEnabled.value,
                                )
                              : null,
                        ),
                        RecordingStreamerOverlay(session: session),
                      ],
                    )
                  // The parked state (no active cut): the multitrack
                  // display path — every covered track's composite stacks
                  // where the void used to be, in its own CANVAS space (the
                  // crop is playback's). An uncovered frame still shows the
                  // void (the stack view renders nothing there).
                  : inGap
                  ? (context, viewport) =>
                        _buildTrackStackView(session, viewport)
                  : null,
            );
          },
        ),
      ),
    );
  }
}

/// The editing canvas's cut-fade wash (R9-C): the fade target color over
/// the canvas rect at (1 − fadeOpacity), under the panel viewport — the
/// same overlay playback paints, so an fx-on faded frame reads identically
/// while editing.
class _CutFadeWashPainter extends CustomPainter {
  const _CutFadeWashPainter({
    required this.viewport,
    required this.canvasSize,
    required this.color,
    required this.devicePixelRatio,
  });

  final CanvasViewport viewport;
  final CanvasSize canvasSize;
  final Color color;

  /// The pan-phase snap's device grid — the wash covers the canvas rect
  /// the snapped stack painted, not a sub-pixel beside it.
  final double devicePixelRatio;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    applyViewportTransform(
      canvas,
      viewport,
      devicePixelRatio: devicePixelRatio,
    );
    canvas.drawRect(
      Rect.fromLTWH(
        0,
        0,
        canvasSize.width.toDouble(),
        canvasSize.height.toDouble(),
      ),
      Paint()..color = color,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _CutFadeWashPainter oldDelegate) =>
      oldDelegate.viewport != viewport ||
      oldDelegate.canvasSize != canvasSize ||
      oldDelegate.color != color ||
      oldDelegate.devicePixelRatio != devicePixelRatio;
}

/// The editing canvas's SE name tags (R5b): the same canvas-space draw
/// the frame painter makes during playback, so what you edit against is
/// what plays and what exports.
class _SeNameTagOverlayPainter extends CustomPainter {
  const _SeNameTagOverlayPainter({
    required this.viewport,
    required this.canvasSize,
    required this.tags,
    required this.devicePixelRatio,
  });

  final CanvasViewport viewport;
  final CanvasSize canvasSize;
  final List<ResolvedSeNameTag> tags;

  /// The pan-phase snap's device grid — the tags annotate the snapped
  /// picture, so they ride the same phase.
  final double devicePixelRatio;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    applyViewportTransform(
      canvas,
      viewport,
      devicePixelRatio: devicePixelRatio,
    );
    paintSeNameTags(canvas, tags: tags, canvasSize: canvasSize);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _SeNameTagOverlayPainter oldDelegate) =>
      oldDelegate.viewport != viewport ||
      oldDelegate.canvasSize != canvasSize ||
      oldDelegate.devicePixelRatio != devicePixelRatio ||
      seNameTagSignature(oldDelegate.tags) != seNameTagSignature(tags);
}

/// R13-3: committed seeks retarget the editing stack ONLY when the
/// playhead actually landed on a different frame. The seek signal alone
/// (same-frame commits, scrub releases in place) measured 30–45ms of pure
/// widget churn across the panel subtree — swallowed here. Frame content
/// edits never ride the seek signal (they notify the session/stores), so
/// an equal frame index proves the canvas inputs did not change.
///
/// R13-4 stroke pinning: while the pen is DOWN, seek retargets are
/// DEFERRED — the in-progress stroke keeps drawing on (and commits to)
/// its original cel, and the canvas swaps to the new frame the moment the
/// stroke ends. Retargeting mid-stroke used to tear the stroke down inside
/// the build phase (red-screen) and could land the commit on the wrong cel.
///
/// 🚨★★★ #26: A RULER SCRUB RETARGETS HERE TOO, and that is what lets a scrub
/// show the editing canvas instead of a stand-in. A scrub deliberately does
/// NOT notify the session — that law is what keeps a ruler drag from
/// rebuilding every panel per crossed frame — so the canvas used to sit on
/// the frame the gesture STARTED on, and the picture only arrived on release.
/// That law is about the PANELS; this scope is the canvas's own subscription,
/// so following the cursor here obeys it.
///
/// ⛔The cursor is not a second mechanism: `scrubFrameIndex` moves the
/// timeline controller, so [_retargetIfFrameChanged]'s existing question —
/// did `currentFrameIndex` actually change — is already the right one, and
/// the stroke deferral above covers a scrub exactly like a seek.
class _FrameRetargetScope extends StatefulWidget {
  const _FrameRetargetScope({required this.session, required this.builder});

  final EditorSessionManager session;
  final WidgetBuilder builder;

  @override
  State<_FrameRetargetScope> createState() => _FrameRetargetScopeState();
}

class _FrameRetargetScopeState extends State<_FrameRetargetScope> {
  int _builtFrameIndex = -1;
  bool _seekDeferredByStroke = false;

  @override
  void initState() {
    super.initState();
    widget.session.frameSeekCommitted.addListener(_onSeekCommitted);
    widget.session.editingFrameCursor.addListener(_onSeekCommitted);
    widget.session.brushInputActive.addListener(_onBrushInputChanged);
  }

  @override
  void didUpdateWidget(covariant _FrameRetargetScope oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.session, widget.session)) {
      oldWidget.session.frameSeekCommitted.removeListener(_onSeekCommitted);
      oldWidget.session.editingFrameCursor.removeListener(_onSeekCommitted);
      oldWidget.session.brushInputActive.removeListener(_onBrushInputChanged);
      widget.session.frameSeekCommitted.addListener(_onSeekCommitted);
      widget.session.editingFrameCursor.addListener(_onSeekCommitted);
      widget.session.brushInputActive.addListener(_onBrushInputChanged);
    }
  }

  @override
  void dispose() {
    widget.session.frameSeekCommitted.removeListener(_onSeekCommitted);
    widget.session.editingFrameCursor.removeListener(_onSeekCommitted);
    widget.session.brushInputActive.removeListener(_onBrushInputChanged);
    super.dispose();
  }

  void _onSeekCommitted() {
    if (widget.session.brushInputActive.value) {
      _seekDeferredByStroke = true;
      return;
    }
    _retargetIfFrameChanged();
  }

  void _onBrushInputChanged() {
    if (widget.session.brushInputActive.value || !_seekDeferredByStroke) {
      return;
    }
    _seekDeferredByStroke = false;
    // Post-frame: the stroke-end signal can arrive from the view's
    // deferred teardown callback — never retarget from inside a frame's
    // build/callback phases.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _retargetIfFrameChanged();
      }
    });
  }

  void _retargetIfFrameChanged() {
    if (widget.session.currentFrameIndex == _builtFrameIndex) {
      return;
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    _builtFrameIndex = widget.session.currentFrameIndex;
    return widget.builder(context);
  }
}
