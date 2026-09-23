import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../models/layer_effect.dart';
import '../models/canvas_size.dart';
import '../models/composite_tree.dart';
import '../models/pasteboard_bounds.dart';
import '../models/canvas_viewport.dart';
import '../models/cut.dart' show Cut;
import '../models/layer_id.dart';
import '../models/project_background.dart';
import '../services/canvas_color_sampler.dart';
import '../services/canvas_flood_fill.dart';
import '../services/canvas_selection.dart' show SelectionMaskOptions;
import '../services/cut_piece_slot.dart';
import '../services/se_name_tag_plan.dart';
import 'brush/brush_editor_selection.dart';
import 'brush/brush_tool_state.dart';
import 'brush/temporary_tool.dart';
import '../core/dev_profile.dart';
import '../models/app_input_settings.dart' show AppInput;
import 'brush/canvas_selection_commands.dart';
import 'brush/transform_tool_options.dart';
import 'brush/canvas_view_commands.dart';
import 'canvas/viewport_canvas_transform.dart';
import 'brush/main_canvas_brush_host.dart';
import 'camera/camera_frame_overlay.dart';
import 'canvas/active_stroke_overlay.dart';
import 'canvas/bitmap_surface_painter.dart';
import 'canvas/selection_float_overlay.dart';
import 'canvas/flip_hud_controller.dart';
import '../models/drawing_guide.dart';
import 'canvas/guide_overlay.dart';
import 'canvas/canvas_layer_stack_view.dart';
import 'canvas/canvas_point_gizmo.dart';
import 'canvas/layer_transform_box.dart';
import 'editor_session_manager.dart';
import 'playback/canvas_playback_controller.dart' show PlaybackScope;
import 'playback/canvas_playback_view.dart';
import 'playback/canvas_track_stack_view.dart';
import 'playback/recording_streamer_overlay.dart';
import 'debug/input_inspector.dart';
import 'text/app_face.dart';
import 'text/app_strings.dart';
import 'dialogs/app_confirm_dialog.dart' show showAppNotice;
import 'text/se_name_tag_paint.dart';
import 'timeline/layer_label_controls.dart';
import '../models/layer.dart' show Layer, layerAcceptsBrushInput;
import '../services/layer_pose_matrix.dart' show LayerPoseSample;
import '../models/timeline_row_address.dart'
    show LaneRowAddress, TimelineRowAddress;
import 'widgets/cursor_notice.dart';
import 'timeline/transform_lane_editing.dart';
import 'effective_device_pixel_ratio.dart';
import 'timeline/transform_lane_policy.dart'
    show CanvasManipulator, canvasManipulatorsForLane;
import 'repaint_props.dart';

part 'canvas_area/interactive_canvas_build.dart';

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

  /// Null until something frames the canvas — the user, playback fit, or a
  /// camera restore.
  ///
  /// 🚨It used to be a bare `CanvasViewport()`: a render zoom of 1.0, which
  /// under R11's convention is `ratio × 100%`. The canvas opened at 150% on
  /// a 1.5 display and 200% on the iPad, and because the UI scale persists
  /// while this does not, reopening a project after raising the chrome to
  /// 150% brought the artwork back half again as large.
  ///
  /// Resolved at the READ site instead, so an untouched view re-derives the
  /// identity whenever the ratio moves — no hold and no notify, which is
  /// exactly the invariant this round wants.
  final ValueNotifier<CanvasViewport?> _canvasViewport = ValueNotifier(null);

  /// [nodes] with the onion ghosts inserted directly UNDER the active
  /// layer — where they belong visually, and (since the merge) inside
  /// whatever folder buffer the active layer sits in.
  static List<CompositeNode<CanvasStackRow>> _stackNodesWithGhosts(
    List<CompositeNode<CanvasStackRow>> nodes,
    List<CanvasLayerImageRequest> ghosts,
  ) {
    if (ghosts.isEmpty) {
      return nodes;
    }
    final ghostNodes = [
      for (final ghost in ghosts) CompositeLeaf<CanvasStackRow>(ghost),
    ];
    var placed = false;
    List<CompositeNode<CanvasStackRow>> walk(
      List<CompositeNode<CanvasStackRow>> list,
    ) {
      final out = <CompositeNode<CanvasStackRow>>[];
      for (final node in list) {
        switch (node) {
          case CompositeLeaf(payload: CanvasActiveLayerRow()):
            if (!placed) {
              out.addAll(ghostNodes);
              placed = true;
            }
            out.add(node);
          case CompositeGroup(
            :final children,
            :final opacity,
            :final blendMode,
            :final effects,
          ):
            out.add(
              // The folder's effects (R6) travel with it — turning onion
              // skin on must not drop them. One structural class carries
              // every field, so only the children are replaced.
              CompositeGroup<CanvasStackRow>(
                children: walk(children),
                opacity: opacity,
                blendMode: blendMode,
                effects: effects,
              ),
            );
          case CompositeAdjustment(:final children, :final effects, :final mix):
            // Like the group above: the ghosts have to be able to land
            // INSIDE an adjustment's scope, or the row you are drawing on
            // would show the grade while its onion ghosts did not.
            out.add(
              CompositeAdjustment<CanvasStackRow>(
                children: walk(children),
                effects: effects,
                mix: mix,
              ),
            );
          case CompositeLeaf(payload: CanvasLayerImageRequest()):
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

  /// R6q2 (유저 확정 08-18): playback's OWN framing — a second view object
  /// that stands in front of [_canvasViewport] for as long as it plays, so
  /// the fit never costs the user their framing.
  ///
  /// 🎯**Two framings are two OBJECTS, not one field taking turns.** This
  /// used to be a save-mutate-restore: playback wrote the fit into the
  /// document's own viewport, having copied the old value aside to write
  /// back on stop. Three things came free from making it a separate object
  /// the panel is handed instead (유저 08-22, 「좀 더 근본적인 해결법은 혹시
  /// 있나? 한프레임 늦추면 뭔가 시간적인 느낌이 이상해지지않을까」):
  ///
  ///  * **No frame of lag.** The fit was a WRITE, writes are illegal during
  ///    build, so it went out on a post-frame callback whose `setState`
  ///    cost a second frame. Handing over an EMPTY view plus the rect to
  ///    fit (`BrushCanvasPanel.unframedFit`) makes the fit a read, and the
  ///    first frame of playback is already fitted.
  ///  * **Nothing to put back.** Stopping is swapping this object out.
  ///    The old restore ran only if `mounted` and the camera toggle still
  ///    agreed — conditions under which a user's framing could quietly not
  ///    come back.
  ///  * **A save taken mid-playback keeps the user's framing**, because the
  ///    fit was never in the object that gets saved.
  ///
  /// ⚠️`null` in here is "playback has not framed yet", which is what makes
  /// D13 work: a pan during playback writes THIS object, taking over from
  /// the fit exactly as it takes over from the identity on a fresh canvas.
  /// [_syncPlaybackFitCut] re-arms it (back to null) on each cut entry, so
  /// every cut still gets the fit the way the token used to give it.
  final ValueNotifier<CanvasViewport?> _playbackViewport = ValueNotifier(null);

  void _syncPlaybackFitCut() {
    final playback = widget.session.playbackRig.playback;
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
      // ★Entering a cut re-arms the fit, which is what the old per-cut
      // token bought: a pan taken during the previous cut does not follow
      // the playhead into this one. Emptying the view IS the re-arm — the
      // panel resolves an unframed view to `unframedFit`.
      _playbackViewport.value = null;
    }
  }

  /// The framing playback stands in front of the user's with, or null when
  /// it is not standing there at all.
  ///
  /// 🚨It survives a playlist GAP on purpose. The gap has no cut and so no
  /// fit to re-take, but snapping back to the user's framing for the length
  /// of a hole and then away again is the flicker the fit exists to avoid —
  /// so this asks whether playback is RUNNING, not whether it is inside a
  /// cut. The camera frame is the project's, so every cut fits the same
  /// rect anyway; what changes per cut is only the re-arm above.
  ///
  /// 유저 확정 08-18 (R6q2): camera view OFF never fits — the user's framing
  /// is the framing.
  Rect? _playbackFramingRect() {
    if (!widget.cameraViewEnabled.value ||
        !widget.session.playbackRig.playback.isActive) {
      return null;
    }
    final frame = widget.session.camera.cameraFrameSize;
    return Offset.zero & Size(frame.width.toDouble(), frame.height.toDouble());
  }

  @override
  void initState() {
    super.initState();
    final playback = widget.session.playbackRig.playback;
    playback.globalFrameIndexListenable.addListener(_syncPlaybackFitCut);
    playback.isActiveListenable.addListener(_syncPlaybackFitCut);
  }

  @override
  void dispose() {
    final playback = widget.session.playbackRig.playback;
    playback.globalFrameIndexListenable.removeListener(_syncPlaybackFitCut);
    playback.isActiveListenable.removeListener(_syncPlaybackFitCut);
    _playbackFitCut.dispose();
    _playbackViewport.dispose();
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
        session.onionSkin.settings,
        session.onionSkin.layerIds,
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
        // changes arrive through the session subscription above.
      ]),
      builder: (context, _) {
        // Playback swaps only the viewport CONTENT (via the panel's
        // contentOverride), so the panel shell — zoom buttons, panbars —
        // keeps working while playing. Listen to enter/leave ONLY:
        // subscribing this subtree to every playback tick rebuilt the whole
        // panel at fps and caused real frame drops.
        return ValueListenableBuilder<bool>(
          valueListenable: session.playbackRig.playback.isActiveListenable,
          builder: (context, _, _) {
            // #26: a scrub no longer swaps the content — but the flag still
            // decides WHAT THE GAP ANSWER IS: a parked global only reads as
            // a gap while the gesture is live (`_gapGlobalFrame` is gated on
            // this), so `inGap` below flips at enter and leave. D6 adds the
            // TERRITORY edge: a drag that started inside the cut crosses
            // the boundary mid-gesture, and the parking alone is per-move
            // quiet — the out↔in flips arrive through
            // `session.frameScrub.outOfTerritory`. Two rebuilds per
            // gesture, at most two more per territory transition; the
            // crossed frames come through the retarget scope, not here.
            return ListenableBuilder(
              listenable: Listenable.merge([
                session.frameScrub.active,
                session.frameScrub.outOfTerritory,
              ]),
              builder: (context, _) {
                return _FrameRetargetScope(
                  session: session,
                  builder: (context) {
                    // Derived HERE (not captured above) so a seek-driven
                    // rebuild re-reads them at the new playhead.
                    final isCameraLayerActive = session.camera.isCameraLayerActive;
                    final showCameraOverlay =
                        widget.cameraViewEnabled.value || isCameraLayerActive;
                    return labProbe(
                      'canvasAreaBuild',
                      () =>
                          _InteractiveCanvasBuild(this).buildInteractiveCanvas(
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
      positionsOf: session.rowSpans.trackStackContributionsAt,
      compositeCache: session.renderCaches.cutFrameCompositeCache,
      qualityOf: () => session.playbackRig.playbackQuality,
      cameraFrameSize: session.camera.cameraFrameSize,
      cameraViewEnabled: cameraView,
      cameraPoseOf: session.camera.cameraPoseForCut,
      seNameTagsOf: session.seEntries.seNameTagsForCutFrame,
      cutFxEnabledOf: session.effectsAndFx.isCutFxEnabled,
      trackStaticOpacityOf: session.opacityVerbs.trackStaticOpacityForCut,
      cutPictureVisibleOf: session.isCutPictureVisible,
      onFrameCached:
          session.playbackRig.playbackCache.enforcePlaybackCacheBudget,
      viewport: viewport,
      background: session.projectSettings.projectBackground,
      backdropArgb: project.backdropArgb,
      backdropNone: project.backdropNone,
      pasteboardArgb: project.pasteboardArgb,
      pasteboardNone: project.pasteboardNone,
      trackEffectsOf: session.effectsAndFx.trackEffectsForCut,
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

  void _noteCanvasProbe(
    EditorSessionManager session,
    bool inGap,
    ({
      double activeLayerOpacity,
      List<ResolvedLayerEffect> activeSourceEffects,
      List<CompositeNode<CanvasStackRow>> nodes,
    })
    layerStack,
  ) {
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
  }

  void _dragBrushSize(double upwardDelta, {required bool snap}) {
    final start = _brushSizeDragStartSize;
    if (start == null) {
      return;
    }
    var next = start * math.pow(2, upwardDelta / 120).toDouble();
    if (snap) {
      next = AppInput.snapToList(next, AppInput.settings.value.brushSizeSnaps);
    }
    widget.onBrushToolStateChanged?.call(
      widget.brushToolState.value.copyWith(size: next),
    );
  }

  Stack _playbackContent(
    EditorSessionManager session,
    CanvasViewport viewport,
  ) {
    return Stack(
      fit: StackFit.expand,
      children: [
        CanvasPlaybackView(
          controller: session.playbackRig.playback,
          compositeCache: session.renderCaches.cutFrameCompositeCache,
          qualityOf: () => session.playbackRig.playbackQuality,
          prerenderProgress: session.playbackRig.prerenderScheduler.progress,
          cameraViewEnabled: widget.cameraViewEnabled.value,
          cameraFrameSize: session.camera.cameraFrameSize,
          cameraPoseOf: session.camera.cameraPoseForCut,
          seNameTagsOf: session.seEntries.seNameTagsForCutFrame,
          cutFxEnabledOf: session.effectsAndFx.isCutFxEnabled,
          trackStaticOpacityOf: session.opacityVerbs.trackStaticOpacityForCut,
          cutPictureVisibleOf: session.isCutPictureVisible,
          viewport: viewport,
          background: session.projectSettings.projectBackground,
          pasteboardArgb: session.repository.requireProject().pasteboardArgb,
          pasteboardNone: session.repository.requireProject().pasteboardNone,
          trackEffectsOf: session.effectsAndFx.trackEffectsForCut,
          trackGlobalFrameOf: session.rowSpans.trackGlobalFrameOf,
          // ALL-CUTS playback watches the whole stage: the
          // frame is the track stack on the clock's global
          // axis (R3a) — a selected-track gap shows what
          // the OTHER tracks hold there instead of the
          // void. Single-cut playback keeps its
          // single-cut frame (the editing context).
          trackStack:
              session.playbackRig.playback.scope == PlaybackScope.allCuts
              ? _buildTrackStackView(
                  session,
                  viewport,
                  globalFrame:
                      session.playbackRig.playback.globalFrameIndexListenable,
                  // Playback is the one place the crop
                  // belongs, and there it answers the toggle.
                  cameraView: widget.cameraViewEnabled.value,
                )
              : null,
        ),
        RecordingStreamerOverlay(session: session),
      ],
    );
  }

  bool _pressNeedsCel(BrushToolState toolState, EditorSessionManager session) {
    if (!canvasToolMarksCel(toolState.tool)) {
      return false;
    }
    if (session.autoFrame.beginAutoFrameForStroke()) {
      return true;
    }
    cursorNotices.show(_drawRefusalFor(session));
    return false;
  }

  Positioned _anchorGizmo(
    EditorSessionManager session,
    Layer activeLayer,
    CanvasViewport viewport,
  ) {
    // The handle stands where the row's value IS: for a track-SE row that is
    // the track's row at the global frame, not the cut's clone (F-102).
    final at = session.laneVerbs.laneValueSourceAt(
      activeLayer,
      session.currentFrameIndex,
    );
    return Positioned.fill(
      // Unwrapped like the position handle, for the same
      // reason.
      child: CanvasPointGizmo(
        glyph: HandleGlyph.anchor,
        point: session.layerAnchorPointAtFrame(at.layer, at.frame),
        viewport: viewport,
        onCommitted: (anchorPoint) =>
            session.laneVerbs.editLayerTransformAtPlayhead(
              activeLayer.id,
              (track, frameIndex) => transformTrackWithAnchorDragged(
                track,
                frameIndex: frameIndex,
                anchorPoint: anchorPoint,
              ),
              description: 'Anchor ${activeLayer.name}',
            ),
      ),
    );
  }

  Positioned _positionGizmo(
    EditorSessionManager session,
    Layer activeLayer,
    CanvasViewport viewport,
  ) {
    final at = session.laneVerbs.laneValueSourceAt(
      activeLayer,
      session.currentFrameIndex,
    );
    return Positioned.fill(
      // No cut-pose wrap: the V row's transform is gone,
      // so the crosshair sits directly on the layer's own
      // canvas space and the committed Position needs no
      // un-posing.
      child: CanvasPointGizmo(
        glyph: HandleGlyph.crosshair,
        point: session.layerPoseAtFrame(at.layer, at.frame).center,
        viewport: viewport,
        // ONE key at the playhead per drag (AE rule,
        // one undo) — on the row the project holds, at
        // the playhead on its own axis. ⚠️Not on
        // [activeLayer] as found: a track-SE row's is its
        // cut-local clone, and writing that back erased
        // the keys of earlier cuts (F-102).
        onCommitted: (position) =>
            session.laneVerbs.editLayerTransformAtPlayhead(
              activeLayer.id,
              (track, frameIndex) => transformTrackWithPositionDragged(
                track,
                frameIndex: frameIndex,
                position: position,
              ),
              description: 'Move ${activeLayer.name}',
            ),
      ),
    );
  }

  Positioned _transformBox(
    Rect transformBoxBounds,
    EditorSessionManager session,
    Layer activeLayer,
    CanvasSize canvasSize,
    CanvasViewport viewport,
  ) {
    final at = session.laneVerbs.laneValueSourceAt(
      activeLayer,
      session.currentFrameIndex,
    );
    return Positioned.fill(
      // R5 #10: the box frames the PICTURE, and its
      // corners scale while its rotate handle turns —
      // one member per handle. No cut pose to ride any
      // more: the V row's transform is gone.
      child: LayerTransformBox(
        bounds: transformBoxBounds,
        pose: session.layerPoseAtFrame(at.layer, at.frame),
        anchorPoint: session.layerAnchorPointAtFrame(at.layer, at.frame),
        canvasSize: canvasSize,
        viewport: viewport,
        onScaleCommitted: (zoom) =>
            session.laneVerbs.editLayerTransformAtPlayhead(
              activeLayer.id,
              (track, frameIndex) => transformTrackWithScaleDragged(
                track,
                frameIndex: frameIndex,
                zoom: zoom,
              ),
              description: 'Scale ${activeLayer.name}',
            ),
        onRotationCommitted: (degrees) =>
            session.laneVerbs.editLayerTransformAtPlayhead(
              activeLayer.id,
              (track, frameIndex) => transformTrackWithRotationDragged(
                track,
                frameIndex: frameIndex,
                rotationDegrees: degrees,
              ),
              description: 'Rotate ${activeLayer.name}',
            ),
      ),
    );
  }

  Positioned _cameraOverlay(
    EditorSessionManager session,
    CanvasViewport viewport,
    bool isCameraLayerActive,
  ) {
    return Positioned.fill(
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
        builder: (context, _) => ValueListenableBuilder<int?>(
          valueListenable: session.gapParkingListenable,
          builder: (context, _, _) {
            final pose = session.camera.displayedCameraPose;
            // Nothing under the cursor to frame:
            // the scrub is over a gap.
            if (pose == null) {
              return const SizedBox.shrink();
            }
            return CameraFrameOverlay(
              pose: pose,
              cameraFrameSize: session.camera.cameraFrameSize,
              viewport: viewport,
              // Dim belongs to camera-view mode;
              // plain manipulation keeps the
              // artwork undimmed.
              dimOpacity: widget.cameraViewEnabled.value
                  ? widget.cameraDimOpacity.value
                  : 0,
              interactive: isCameraLayerActive,
              onPoseCommitted: session.camera.setCameraKeyframeAtCurrentFrame,
            );
          },
        ),
      ),
    );
  }

  Positioned _cutFadeWash(
    CanvasViewport viewport,
    CanvasSize canvasSize,
    EditorSessionManager session,
    double cutFadeOpacity,
    BuildContext context,
  ) {
    return Positioned.fill(
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
            color: Color(
              session.repository.requireProject().backdropArgb,
            ).withValues(alpha: (1 - cutFadeOpacity).clamp(0.0, 1.0)),
            devicePixelRatio: EffectiveDevicePixelRatio.of(context),
          ),
        ),
      ),
    );
  }

  Positioned _seNameTagOverlay(
    CanvasViewport viewport,
    CanvasSize canvasSize,
    List<ResolvedSeNameTag> seNameTags,
    BuildContext context,
  ) {
    return Positioned.fill(
      // Rides the cut pose like the gizmo: the tag
      // annotates the posed picture, exactly as the
      // frame painter draws it inside the pose.
      child: IgnorePointer(
        child: CustomPaint(
          painter: _SeNameTagOverlayPainter(
            viewport: viewport,
            canvasSize: canvasSize,
            tags: seNameTags,
            devicePixelRatio: EffectiveDevicePixelRatio.of(context),
          ),
        ),
      ),
    );
  }

  Positioned _guideEditLayer(
    EditorSessionManager session,
    CanvasViewport viewport,
  ) {
    return Positioned.fill(
      child: GuideEditLayer(
        guides: _liveGuides ?? session.cutVerbs.activeCutGuides,
        viewport: viewport,
        onGuideSelected: (id) => session.selectedGuideId = id,
        // Live while dragging: the project is not
        // touched, so a drag is one undo entry.
        onGuidesChanged: (guides) => setState(() => _liveGuides = guides),
        onGuidesCommitted: (guides) {
          setState(() => _liveGuides = null);
          session.cutVerbs.setActiveCutGuides(guides);
        },
      ),
    );
  }

  Positioned _guideOverlay(
    EditorSessionManager session,
    CanvasViewport viewport,
    CanvasSize canvasSize,
    BrushToolState toolState,
    BuildContext context,
  ) {
    return Positioned.fill(
      child: IgnorePointer(
        child: CustomPaint(
          painter: GuideOverlayPainter(
            // The live drag value while a handle is
            // moving, so the drawn guide follows the
            // finger without a project write.
            guides: _liveGuides ?? session.cutVerbs.activeCutGuides,
            viewport: viewport,
            canvasSize: canvasSize,
            emphasized: toolState.tool == CanvasTool.guide,
            vanishingPointLabel: AppText.strings.guideVanishingPoint,
            color: Theme.of(context).colorScheme.primary,
            face: appFaceOf(DefaultTextStyle.of(context).style),
            selectedGuideId: session.selectedGuideId,
          ),
        ),
      ),
    );
  }
}

/// The editing canvas's cut-fade wash (R9-C): the fade target color over
/// the canvas rect at (1 − fadeOpacity), under the panel viewport — the
/// same overlay playback paints, so an fx-on faded frame reads identically
/// while editing.
class _CutFadeWashPainter extends CustomPainter with RepaintOnProps {
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
    canvas.drawRect(canvasSize.canvasRect, Paint()..color = color);
    canvas.restore();
  }

  @override
  Object get props => (viewport, canvasSize, color, devicePixelRatio);
}

/// The editing canvas's SE name tags (R5b): the same canvas-space draw
/// the frame painter makes during playback, so what you edit against is
/// what plays and what exports.
class _SeNameTagOverlayPainter extends CustomPainter with RepaintOnProps {
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
  Object get props =>
      (viewport, canvasSize, devicePixelRatio, seNameTagSignature(tags));
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
