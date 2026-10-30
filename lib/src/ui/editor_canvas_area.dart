import 'dart:async' show unawaited;
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../models/app_frame_grid_settings.dart';
import '../models/brush_frame_key.dart';
import '../models/cel_number_letters.dart' show celNumberText;
import '../models/layer_effect.dart';
import '../services/cel_numbered_row.dart' show celNumberLettersOf;
import 'text/cel_number_paint.dart' show celNumberBox;
import 'timeline/effect_lane_policy.dart'
    show effectBoxedOn, effectLaneId;
import '../models/camera_path_settings.dart';
import '../models/camera_pose.dart';
import '../models/canvas_size.dart';
import '../models/composite_tree.dart';
import '../models/pasteboard_bounds.dart';
import '../models/canvas_viewport.dart';
import '../models/cut.dart' show Cut;
import '../models/layer_id.dart';
import '../models/key_path_walk.dart' show KeyPathKnob, keyPathKnobs;
import '../models/project_background.dart';
import '../models/property_track.dart' show PropertyTrack;
import '../services/canvas_color_sampler.dart';
import '../services/canvas_read_source.dart';
import '../services/canvas_flood_fill.dart';
import '../services/canvas_selection.dart' show SelectionMaskOptions;
import '../services/camera_path.dart' show CameraPath;
import '../services/canvas_selection_shape.dart' show CanvasSelectionShape;
import '../services/cut_piece_slot.dart';
import '../services/playback/frame_demand.dart'
    show DemandedPicture, FrameGhosts, standingPicturesOf;
import '../services/playback/playback_frame_mapping.dart'
    show TrackStackContribution;
import '../services/last_stroke_slot.dart';
import '../services/se_name_tag_plan.dart';
import 'brush/brush_editor_selection.dart';
import 'brush/brush_tool_state.dart';
import 'brush/brush_value_group.dart' show BrushValueBars;
import 'brush/temporary_tool.dart';
import '../core/collection_equality.dart' show listsMatch;
import '../core/dev_profile.dart';
import '../core/tree_nodes.dart' show preorderNodes;
import '../models/app_input_settings.dart' show AppInput;
import 'brush/canvas_selection_commands.dart';
import 'brush/cel_text_commands.dart';
import 'brush/text_tool_options.dart';
import 'brush/transform_tool_options.dart';
import 'brush/canvas_view_commands.dart';
import 'canvas/display_resample.dart' show displayScaleOf;
import 'canvas/paper_background.dart' show paintAbsentPlane;
import 'canvas/stage_planes_painter.dart'
    show StagePlane, backdropOnScreen, stageColorOnScreen, stageGroundOf;
import 'canvas/viewport_canvas_transform.dart';
import '../services/composite_effect_paint.dart' show alphaOnly;
import 'brush/main_canvas_brush_host.dart';
import 'brush/brush_canvas_panel.dart'
    show BrushCanvasPanel, CanvasEdgePill, CanvasFloats;
import 'sliced_value_listenable_builder.dart';
import '../models/canvas_shape_kind.dart';
import 'camera/camera_frame_overlay.dart';
import 'camera/camera_path_overlay.dart';
import 'canvas/active_stroke_overlay.dart';
import 'canvas/camera_adjust_layer.dart';
import 'canvas/canvas_adjust_layer.dart';
import 'cut_command_group.dart' show landCanvasAdjust;
import 'dialogs/behind_the_wait_window.dart' show resizeBehindTheWaitWindow;
import 'session/canvas_adjust.dart' show CameraSizeDraft;
import 'canvas/bitmap_surface_painter.dart';
import 'canvas/flip_hud_controller.dart';
import '../models/drawing_guide.dart';
import 'canvas/guide_overlay.dart';
import 'canvas/canvas_layer_stack_view.dart';
import 'canvas/canvas_look.dart';
import 'canvas/row_transform_box.dart';
import 'editor_session_manager.dart';
import 'playback/camera_shot.dart';
import 'playback/canvas_track_stack_view.dart';
import 'playback/frame_picture_view.dart';
import 'playback/playback_run_layer.dart';
import 'playback/recording_streamer_overlay.dart';
import 'playback/transition_veil_paint.dart';
import 'panels/tool_size_preset_panel.dart' show ToolSizePresetPanel;
import 'debug/device_grid_probe.dart';
import 'debug/input_inspector.dart';
import 'text/app_face.dart';
import 'text/app_strings.dart';
import 'dialogs/app_confirm_dialog.dart' show showAppNotice;
import 'text/se_name_tag_paint.dart';
import 'timeline/layer_label_controls.dart';
import 'timeline/memo_token.dart' show ByIdentity, ByList;
import 'timeline/timeline_drag_preview.dart'
    show
        BlockMoveDragPreview,
        TimelineDragPreview,
        timelineDragPreviewGlobalLayerFor,
        timelineDragPreviewLayerFor;
import '../models/layer.dart' show Layer;
import '../models/layer_kind.dart';
import '../models/reference_swap.dart' show referenceRedrawFor;
import '../services/layer_pose_matrix.dart'
    show
        LayerPlacement,
        canvasToArtwork,
        picturePlacement,
        placedCorners,
        placementOf;
import '../models/canvas_point.dart';
import '../models/transform_track.dart'
    show
        TransformPose,
        TransformPropertyId,
        TransformTrack,
        transformPathLaneOf,
        transformPropertyOfLaneId,
        uniformScale,
        walksAPath;
import '../models/transition_geometry.dart' show TransitionVeil;
import '../models/timeline_row_address.dart'
    show LaneRowAddress, TimelineRowAddress;
import 'widgets/cursor_notice.dart';
import 'widgets/tick_layer.dart';
import 'timeline/transform_lane_editing.dart';
import 'effective_device_pixel_ratio.dart';
import 'timeline/transform_lane_policy.dart'
    show CanvasManipulator, canvasManipulatorsForLane;
import 'timeline/reference_lane_policy.dart' show laneIsReference;
import 'repaint_props.dart';
import 'session/editing_canvas.dart' show StrokeRefusal;

part 'canvas_area/interactive_canvas_build.dart';

/// What one mount of the track stack says of itself: the frame it follows,
/// whose contributions it draws there, whether it lays its own floor,
/// whether it crops to the camera, who makes the pictures it shows (a
/// run's warmer — or its own cuts, when null) and the key it is found by.
typedef _TrackStackMount = ({
  ValueListenable<int?> globalFrame,
  List<TrackStackContribution> Function(int globalFrame) positionsOf,
  bool paintsFloor,
  bool cameraView,
  TrackStackRun? run,
  Key key,
});

/// Where a row's value shows on the canvas, and back — through [placement],
/// or straight through where that is null.
typedef _ShownSpace = ({
  LayerPlacement? placement,
  CanvasPoint Function(CanvasPoint point) toCanvas,
  CanvasPoint Function(CanvasPoint point) fromCanvas,
});

/// What a row's transform fx box frames, in the row's own space before its
/// pose: what it [drawn] at the playhead — null when it shows nothing — and
/// the whole [space] it is posed in, which stands in for a picture with
/// nothing in it (F-387 ③).
typedef _RowPicture = ({Rect? drawn, Rect space});

/// One edit of a transform track at a frame — what a canvas handle's drag
/// makes of the track it drives ([_EditorCanvasAreaState._handleLandings]).
typedef _TrackEdit =
    TransformTrack Function(TransformTrack track, int frameIndex);

/// How an effect's box hands what a handle's drag makes of the lane's keys
/// to the lane ([_EditorCanvasAreaState._effectBox]) — one for every handle
/// of whichever box the effect declares.
typedef _EffectLanding =
    RowBoxLanding<T> Function<T>(
      _TrackEdit Function(T value) editOf, {
      required String description,
    });

/// A row's [lane] — its transform [property] — whose keys walk a path, as
/// the canvas shows it: its frames [axisOffset] ahead of the cut's, its
/// points shown through [space].
typedef _PathShown = ({
  TransformPropertyId property,
  PropertyTrack<CanvasPoint> lane,
  int axisOffset,
  _ShownSpace space,
});

/// The backdrop's share of the editing canvas over the live cut once the
/// O.L's other cuts are laid above it: the live cut keeps [cutFadeOpacity],
/// each partner its own share ([partnerShares] — its ramp, the unit alpha
/// the track stack weighs it by), the backdrop the rest. `1 − fade` with no
/// partner (the wash as it always was), nothing when an O.L's two halves
/// are the whole frame.
///
/// ↩️Two statics of the canvas area's state spelled this, and each partner's
/// share was its ramp times its track's own opacity until the V row lost it
/// (I-73, 2026-10-08). One function, outside the state, so the sum can be
/// pinned where it is cheapest.
double backdropShareUnder(
  double cutFadeOpacity,
  Iterable<double> partnerShares,
) {
  var claimed = 0.0;
  for (final share in partnerShares) {
    claimed += share;
  }
  return claimed >= 1
      ? 0
      : (1 - cutFadeOpacity / (1 - claimed)).clamp(0.0, 1.0);
}

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
    this.canvasTextCommands,
    this.textToolOptions,
    this.cutPieceSlot,
    this.lastStroke,
    this.toolHold,
    this.expandedLaneLayerIds,
    this.fillOptions,
    this.selectionMaskOptions,
    this.transformOptions,
    this.eyedropperSource,
    this.onInvokeAction,
    this.flipHud,
    this.leftPill,
  });

  final EditorSessionManager session;

  /// PEN-7b: the shell's action funnel — the flip touch slot fires the
  /// same registry ids as the arrow keys.
  final void Function(String actionId)? onInvokeAction;

  /// The flip HUD's state (shell-owned), forwarded to the panel that
  /// mounts the window.
  final FlipHudController? flipHud;

  /// What stands on the canvas's left edge, forwarded to its panel — see
  /// [BrushCanvasPanel.leftPill].
  final CanvasEdgePill? leftPill;

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

  /// The app-level text channel and the next text's values (R9-rest),
  /// forwarded to the canvas that holds texts.
  final CelTextCommands? canvasTextCommands;
  final ValueNotifier<TextToolOptions>? textToolOptions;

  /// Where a finished cut lands — owned by the workspace so the piece
  /// outlives every project the canvas shows.
  final CutPieceSlot? cutPieceSlot;

  /// The last drawing action, which this canvas records and 확정 lays down
  /// again — shell-owned for the same reason as [cutPieceSlot].
  final LastStrokeSlot? lastStroke;

  /// The tool a hold sprang from — shell-owned for the same reason as
  /// [cutPieceSlot]: the tool is the app's, and a tab switch remounts this
  /// canvas mid-hold. Null keeps one of this canvas's own.
  final ToolHoldMemory? toolHold;

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
  final ValueListenable<CanvasReadSource>? eyedropperSource;

  /// The Select tool's lift-time mask knobs (R26); null keeps the
  /// classic byte-preserving hard mask.
  final ValueListenable<SelectionMaskOptions>? selectionMaskOptions;

  /// The transform tool's settings (mode, scale anchor, resampler, mesh
  /// grid); null keeps the defaults.
  final ValueListenable<TransformToolOptions>? transformOptions;

  /// What the canvas shows of the session: the area hears the session only
  /// when this changes ([SlicedListenableBuilder]).
  ///
  /// 🔬Every session notify built the area again — 77 elements, and the
  /// panel laid out under them — for a guide picked with another tool in
  /// hand or a sheet's title typed (session-news-rebuilds-unsliced,
  /// measured 2026-10-22 in the app at 1600x1000).
  ///
  /// The session announces from 165 places (counted 2026-10-22). The 137
  /// that change the project reach the canvas through the project's fields
  /// it draws from — every field but the work's name, id and date, the
  /// sheet's, the sound's rate, the export's and the viewer's, which
  /// `the_canvas_hears_what_it_shows_test` names. The other 28 change what
  /// is kept beside the project. Where the user stands — a gap is no cut
  /// stood on — and the cels' pictures (an open or an import lays them
  /// without a project change) are drawn and heard here; the frame and a
  /// run come by channels of their own (`_FrameRetargetScope`, the playback
  /// flag). The clipboards, the solo switches, the timeline's master
  /// opacity, the media's existence and movies' lengths, the file the work
  /// is bound to, the playback mode and the sound's conforms are drawn
  /// nowhere on the canvas; the guide picked and a recording's streamer
  /// are, by the guides and the streamer, which hear them themselves.
  static Object shownBy(EditorSessionManager session) {
    final project = session.repository.requireProject();
    final cels = session.renderCaches.brushFrameStore;
    // ⚠️A project's lists are made anew by every write (`Project` holds them
    // unmodifiable), so they compare by what they hold: the tracks each by
    // identity — a write keeps the ones it did not touch — and the media's
    // and the fonts' entries, small values, by `==`.
    return (
      tracks: ByList([for (final track in project.tracks) ByIdentity(track)]),
      frameRate: project.frameRate,
      cameraSize: project.cameraSize,
      trailingFrames: project.trailingFrames,
      background: project.background,
      backdrop: (project.backdropArgb, project.backdropNone),
      pasteboard: (
        project.pasteboardArgb,
        project.pasteboardNone,
        project.pasteboardSize,
        project.pasteboardInUse,
      ),
      cameraInstructions: ByIdentity(project.cameraInstructions),
      mediaAssets: ByList(project.mediaAssets),
      fonts: ByList(project.fonts),
      linkRegistry: ByIdentity(project.linkRegistry),
      // A movie's frames are timed by the sound's pull (`MovieClock`).
      audioSpeed: (project.audioSpeedNumerator, project.audioSpeedDenominator),
      cut: session.activeCutId,
      layer: session.activeLayerId,
      celContent: cels.celContentRevision.value,
      celPixels: cels.celPixelRevision.value,
    );
  }

  @override
  State<EditorCanvasArea> createState() => _EditorCanvasAreaState();
}

class _EditorCanvasAreaState extends State<EditorCanvasArea> {
  /// The last T12 probe line, so the inspector shows a line per CHANGE
  /// rather than one per build. See the probe in [build].
  String? _lastCanvasProbe;

  /// See [EditorCanvasArea.toolHold].
  late final ToolHoldMemory _toolHold = widget.toolHold ?? ToolHoldMemory();

  /// The brush size at the start of a 3-finger size drag (PEN-7b); the
  /// drag maps EXPONENTIALLY from here (120px per doubling) so the feel
  /// is uniform at every size.
  double? _brushSizeDragStartSize;

  /// The project's framing ([EditorSessionManager.canvasViewport]) — null
  /// until something frames the canvas: the user, playback fit, or a camera
  /// restore.
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
  ValueNotifier<CanvasViewport?> get _canvasViewport =>
      widget.session.canvasViewport;

  /// The live-stroke overlay, owned HERE so the layer stack can paint the
  /// active layer inside the composite tree — that is what lets a folder's
  /// group buffer enclose the layer being drawn on. The interactive view
  /// writes into it (input) and the merged stack painter reads it (paint).
  final ActiveStrokeOverlayModel _activeStrokeOverlay =
      ActiveStrokeOverlayModel();

  /// D12: the cut playback currently stands IN — the fit token's
  /// identity half, kept on the RUN's own clock. 🚨It was the boundary's
  /// ONLY crossing signal while the session's follow was quiet (R12-B); the
  /// follow lands the cut through the session's notify since I-57 ②, but
  /// the fit still turns on the run's crossing itself, tick-exact: the
  /// cursor/row channels suppress the equal values a crossing publishes
  /// (local 0 on entry, the unchanged verb row), so a token read off them
  /// would go stale and the next unrelated notify would land a fit mid-cut
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

  /// Whether the run that plays is drawn ON THIS CANVAS — a cut played
  /// alone, through the camera or not: the clock moves the playhead
  /// ([_followTheRun]) and the canvas draws the frame it stands on, from the
  /// images it draws standing still (playback-plays-the-screen-material).
  /// The whole film plays on the track stack, from the same images.
  ///
  /// The rig's answer, not a copy of it ([PlaybackRig.playsOnTheCanvas]).
  bool get _playsOnTheCanvas {
    final rig = widget.session.playbackRig;
    return rig.playback.isActive && rig.playsOnTheCanvas;
  }

  /// A run this canvas plays moves the playhead, as a scrub does
  /// ([FrameScrub.followTheRun]), to the frame of the cut's own it shows.
  void _followTheRun() {
    if (!_playsOnTheCanvas) {
      return;
    }
    final session = widget.session;
    final position = session.playbackRig.playback.position;
    if (position == null) {
      return;
    }
    session.frameScrub.followTheRun(
      session.playheadCursors.ownFrameOf(position),
    );
  }

  @override
  void initState() {
    super.initState();
    final playback = widget.session.playbackRig.playback;
    playback.globalFrameIndexListenable.addListener(_syncPlaybackFitCut);
    playback.isActiveListenable.addListener(_syncPlaybackFitCut);
    playback.globalFrameIndexListenable.addListener(_followTheRun);
  }

  @override
  void dispose() {
    final playback = widget.session.playbackRig.playback;
    playback.globalFrameIndexListenable.removeListener(_syncPlaybackFitCut);
    playback.isActiveListenable.removeListener(_syncPlaybackFitCut);
    playback.globalFrameIndexListenable.removeListener(_followTheRun);
    _playbackFitCut.dispose();
    _playbackViewport.dispose();
    _activeStrokeOverlay.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    // A drag in flight moves what the canvas shows (F-195;
    // canvas-follows-block-moves, 유저 2026-09-28 「따라가게」). The picture
    // and the chrome over it hear it for themselves, each in its own
    // TickLayer (`_InteractiveCanvasBuild._followingDragAndRun`); the AREA is
    // rebuilt only for what it hands the panel ([_panelShows]).
    return SlicedValueListenableBuilder<TimelineDragPreview?, Object?>(
      valueListenable: session.dragPreview,
      slice: (preview) => _panelShows(session, preview),
      builder: (context, _) => _buildFollowingSession(session),
    );
  }

  /// The rows [_panelShows] last answered for, and its answer — a drag step
  /// that moves none of them cannot change it (the lookup is cheap, the
  /// answer walks the composite).
  _DragAsShown? _panelRows;
  Object? _panelShown;

  /// What the canvas AREA takes from a drag: the row being drawn on as the
  /// panel is handed it — its display opacity, its colour keys and the pose
  /// the pen draws in ([_InteractiveCanvasBuild.standingOf]) — and, in
  /// camera mode, the camera's pose the Fit button frames.
  ///
  /// 🚨canvas-wakes-for-what-it-shows: a block carried under the playhead
  /// changes the PICTURE, which the underlay follows by itself — not these.
  /// Rebuilding the area for it relaid out the whole panel content a step.
  Object? _panelShows(
    EditorSessionManager session,
    TimelineDragPreview? preview,
  ) {
    final rows = _rowsShownBy(session, preview);
    if (rows == _panelRows) {
      return _panelShown;
    }
    _panelRows = rows;
    final isCameraLayerActive = session.camera.isCameraLayerActive;
    final inGap =
        !session.playbackRig.playback.isActive &&
        session.editingSession.playheadInGap;
    final stack = inGap ? null : session.editingCanvas.stack;
    return _panelShown = (
      stack?.activeLayerOpacity,
      stack == null ? null : ByList(stack.activeSourceEffects),
      _InteractiveCanvasBuild.standingOf(
        session,
        inGap: inGap,
        isCameraLayerActive: isCameraLayerActive,
      ).pose,
      isCameraLayerActive ? session.camera.cameraPoseAtCurrentFrame : null,
    );
  }

  /// Every row of the open cut and of its track as a drag shows it, in both
  /// forms, the pictures it moves among cels with no row changing (F-330,
  /// [celPixelsOf]), the camera the canvas draws and where the open cut
  /// stands as the drag lays it — the fade reads the spans against that
  /// ([Transitions.activeCutPlaceShown]) — equal while the drag changes
  /// none of them (a movie's end, a sound's silhouette on an SE cell, a V
  /// track's chain, another cut's rows).
  ///
  /// ⚠️A new reader of the channel on the canvas reads rows by the same two
  /// functions ([timelineDragPreviewLayerFor], [timelineDragPreviewGlobalLayerFor])
  /// or the camera's one answer; one that read something else would need it
  /// here too, or it would go stale between steps.
  static _DragAsShown _rowsShownBy(
    EditorSessionManager session,
    TimelineDragPreview? preview,
  ) {
    final track = session.activeTrack;
    return _DragAsShown([
      for (final row in [
        ...?session.activeCutOrNull?.layers,
        ...track.seLayers,
        track.transitionLayer,
      ]) ...[
        timelineDragPreviewLayerFor(preview, row.id),
        timelineDragPreviewGlobalLayerFor(preview, row.id),
      ],
      if (preview case BlockMoveDragPreview(:final picturesMoved))
        picturesMoved,
      session.camera.activeCutCameraTrack,
      if (session.transitions.activeCutPlaceShown case final place?) ...[
        place.start,
        place.end,
        place.mediaStart,
      ],
    ]);
  }

  Widget _buildFollowingSession(EditorSessionManager session) {
    // The session subscription lives HERE now (HomePage no longer setStates
    // the world), for what the canvas shows of it
    // ([EditorCanvasArea.shownBy]). Committed seeks retarget the editing
    // stack through the _FrameRetargetScope below — deliberately NOT the
    // frame cursor, whose per-move scrub firehose must never rebuild the
    // brush host — and only when the playhead actually changed frames
    // (R13-3).
    return SlicedListenableBuilder<Object>(
      listenable: session,
      slice: () => EditorCanvasArea.shownBy(session),
      builder: (context, _) => _buildFollowingItsChannels(session),
    );
  }

  Widget _buildFollowingItsChannels(EditorSessionManager session) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        // Onion-skin pegs + the per-layer set re-plan the underlay
        // ghosts (P2 → UI-R17 #5).
        session.onionSkin.settings,
        session.onionSkin.layerIds,
        // Opacity drags preview through the editing stack per move (R4 #4)
        // — the canvas is the ONLY session-notify consumer that follows
        // live; everything else waits for the release commit.
        session.opacityVerbs.dragPreview,
        // brushToolState is deliberately NOT here (R18 UI-2): nothing in
        // the area's derivations reads it — only the brush host consumes
        // it, through its own boundary builder below. Merging it here
        // made EVERY tool switch, color notch and slider tick re-derive
        // and re-diff the whole canvas area (the lab's one-jank-per-
        // tool-switch term).
        widget.cameraViewEnabled,
        widget.cameraDimOpacity,
        ?widget.expandedLaneLayerIds,
        // The mark an unnamed drawing's cel number writes (F-489): the
        // letters ride the editing stack, which a pick does not notify.
        AppFrameGridSettings.settings,
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
            // #26: a scrub no longer swaps the content. The gap answer is
            // read off the parking when the canvas builds; what builds it
            // mid-gesture is these two flags — the gesture starting and
            // ending, and D6's GAP edge: a drag that started on a cut walks
            // into a gap, and the parking alone is per-move quiet, so the
            // gap↔cut flips arrive through `session.frameScrub.inGap`. A
            // tap's pointer-down park flips neither (the no-flash rule).
            // Two rebuilds per gesture, at most two more per gap; the
            // crossed frames come through the retarget scope, and a
            // crossing into another cut through the session (I-57 ②).
            return ListenableBuilder(
              listenable: Listenable.merge([
                session.frameScrub.active,
                session.frameScrub.inGap,
              ]),
              builder: (context, _) {
                return _FrameRetargetScope(
                  session: session,
                  runPlaysHere: () => _playsOnTheCanvas,
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
  /// projection per covered track, following [globalFrame] per move — the
  /// parked contentOverride, the scrub's gap branch (both on the gap
  /// parking) and ALL-CUTS playback (on the clock's global frame, R3a).
  ///
  /// 🚨The camera view is the CROP, and it belongs to PLAYBACK alone (user
  /// 2026-08-11). The parked canvas has always shown the whole canvas with the
  /// camera frame drawn OVER it, and a ruler drag parks per move in a gap
  /// (`scrubGlobalFrame`) — so cropping here made the drag look nothing like
  /// the state it started from. The parked mounts never crop, and the answer
  /// is the same one the eye already had: preview = canvas + overlay,
  /// playback = crop.
  ///
  /// [ofTheRun] is the mount ALL-CUTS playback shows: it follows the run's
  /// clock, answers the camera toggle, and leaves its pictures to the
  /// warmer, repainting as they land. The parked mounts follow the gap
  /// parking and make their own.
  Widget _buildTrackStackView(
    EditorSessionManager session,
    CanvasViewport viewport, {
    bool ofTheRun = false,
  }) => _trackStack(session, viewport, (
    globalFrame: ofTheRun
        ? session.playbackRig.playback.globalFrameIndexListenable
        : session.editingSession.gapParkingListenable,
    positionsOf: session.rowSpans.trackStackContributionsAt,
    paintsFloor: true,
    cameraView: ofTheRun && widget.cameraViewEnabled.value,
    run: ofTheRun ? (frameIsThere: session.playbackRig.frameIsThere) : null,
    key: const ValueKey<String>('canvas-track-stack-view'),
  ));

  /// The editing canvas's O.L partner ([_cutFadeWash]): [partners] held at
  /// [standing], laid OVER the live cut — so no floor of its own — and seen
  /// through the camera when the live cut is.
  static _TrackStackMount _olPartnerMount(
    int standing,
    List<TrackStackContribution> partners, {
    required bool throughCamera,
  }) => (
    globalFrame: AlwaysStoppedAnimation<int?>(standing),
    positionsOf: (_) => partners,
    paintsFloor: false,
    cameraView: throughCamera,
    run: null,
    key: const ValueKey<String>('canvas-ol-partner'),
  );

  /// The one construction every mount of the track stack shares.
  Widget _trackStack(
    EditorSessionManager session,
    CanvasViewport viewport,
    _TrackStackMount mount,
  ) {
    final project = session.repository.requireProject();
    // 🚨canvas-stack-relays-the-panel-per-scrub-crossing (I-22 계측, 09-28): the
    // view rebuilds itself as the frame it follows crosses into another cut
    // (a run's clock; a scrub's parking did too until I-57 ②), and bare under
    // the panel content's LayoutBuilder every such rebuild relaid out and
    // repainted the whole panel content. Its own TickLayer takes that scope —
    // every mount hands it the panel's size (a Positioned.fill, a
    // StackFit.expand).
    return TickLayer(
      child: CanvasTrackStackView(
        key: mount.key,
        globalFrame: mount.globalFrame,
        positionsOf: mount.positionsOf,
        paintsFloor: mount.paintsFloor,
        stackOf: session.editingCanvas.playedStackAt,
        pictures: (
          landings: session.playbackRig.prerenderScheduler.landings,
          pictures: session.playbackRig.framePictures,
        ),
        cameraFrameSize: session.camera.cameraFrameSize,
        cameraViewEnabled: mount.cameraView,
        cameraPoseOf: session.camera.cameraPoseForCut,
        seNameTagsOf: session.seEntries.seNameTagsForCutFrame,
        run: mount.run,
        viewport: viewport,
        background: session.projectSettings.projectBackground,
        backdropArgb: project.backdropArgb,
        backdropNone: project.backdropNone,
        pasteboardArgb: project.pasteboardArgb,
        pasteboardNone: project.pasteboardNone,
        pasteboardReach: project.pasteboardReach,
      ),
    );
  }

  // `_wrapInCutPose` went with the V row's transform: nothing poses a whole cut
  // on the editing canvas any more, so its content, gizmos and overlays all
  // draw straight in the layer's own canvas space.

  /// R26 #35: WHY the paint press did nothing — a drawing row simply has
  /// no cel at this frame; a hidden one has it out of sight; every other
  /// section cannot hold artwork at all. One shared message table, so the
  /// wording stays consistent wherever this refusal is reused.
  String _drawRefusalFor(EditorSessionManager session) {
    final strings = AppStrings.of(
      session.languageSettings.value.programLanguage,
    );
    // Standing on a PROPERTY LANE (user, 2026-08-08): the row you are on
    // is not a drawing surface, whatever the layer under it could take.
    // The layer-not-drawable wording is reused deliberately — the user
    // asked for that notice, and it is the true one: this row does not
    // accept strokes.
    if (!_rowAcceptsStrokes(session.standing.currentRowListenable.value)) {
      return strings.noticeLayerNotDrawable;
    }
    // R27 #16: the question is whether THIS LAYER takes strokes, not
    // which section it sits in — the CAM section is no longer uniformly
    // undrawable in the user's model, so the refusal names the layer
    // (media-REFERENCE layers included: strokes wait for a rasterize).
    // F-242: and the answer is the stroke target's own, reason and all.
    return switch (session.editingCanvas.activeRowStrokeRefusal) {
      StrokeRefusal.notDrawable => strings.noticeLayerNotDrawable,
      StrokeRefusal.hidden => strings.noticeLayerHidden,
      null => strings.noticeNoFrameHere,
    };
  }

  /// Whether the row the frame-axis verbs are on can take a stroke.
  ///
  /// A LANE cannot. Standing on a property used to keep drawing available
  /// on the layer beneath, which is the fudge the user retired: you stand
  /// in exactly one place, and if that place is `Blur ▸ Radius` then the
  /// brush has nothing to write on.
  static bool _rowAcceptsStrokes(TimelineRowAddress? row) =>
      row is! LaneRowAddress;

  /// Whether the row you stand on takes a stroke — H19's ROW question, the
  /// one a press and every pixel verb ask: not a property lane
  /// ([_rowAcceptsStrokes]), and a layer the stroke target's own gates let
  /// draw (`EditingCanvas.activeRowStrokeRefusal`).
  ///
  /// 🗣️F-223 (유저 2026-09-28): 「카메라 레이어에 서있을때 변형툴쓰면
  /// 콘티그림?이 옮겨짐. 그림이 없으면 아무것도 안하는 로직인건데.」 The
  /// camera row shows the first drawn row's cel so there is artwork to frame
  /// (`Camera.cameraBackdropSelection`) — a cel it SHOWS, not one it stands
  /// on — and this used to ask only 「is it a lane」, so the pixel verbs
  /// took the borrowed cel for the row's own.
  static bool _standingRowTakesStrokes(EditorSessionManager session) =>
      _rowAcceptsStrokes(session.standing.currentRowListenable.value) &&
      session.editingCanvas.activeRowStrokeRefusal == null;

  /// Whether the row you stand on is a DRAWING SURFACE at all: not a
  /// property lane, and a layer whose kind takes strokes — the rows
  /// [_drawRefusalFor] does not call undrawable. A HIDDEN row is one: it
  /// takes no stroke while its eye is off, and is still the tool's.
  ///
  /// 🗣️F-285 (유저 2026-10-17): 「카메라 레이어에선 그냥 기본커서로. 이런식으로
  /// 도구가 연관이 없는 곳에선 기본커서. 트랜스폼fx든 뭐 그런거 전부」 — on any
  /// other row a marking tool wears no cursor of its own.
  static bool _standingRowIsDrawn(EditorSessionManager session) =>
      _rowAcceptsStrokes(session.standing.currentRowListenable.value) &&
      session.editingCanvas.activeRowStrokeRefusal !=
          StrokeRefusal.notDrawable;

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
      // 🗣️F-391 (유저 2026-10-17): 「브러시 크기 스냅은 … 툴 사이즈 패널을
      // 바탕으로」 — the rack the size bar's ± step through (F-325).
      next = AppInput.snapToList(next, ToolSizePresetPanel.presets);
    }
    widget.onBrushToolStateChanged?.call(
      widget.brushToolState.value.withActiveSize(
        // On the numbers the size bar writes, as the bar holds them (F-488).
        BrushValueBars.heldSize(next),
      ),
    );
  }

  /// What a run puts over whatever draws it ([PlaybackRunLayer]): the ticker
  /// the clock runs on, the press that stops it, the bar — and the streamer
  /// the ADR scribe rides on the picture (REC1-E).
  ///
  /// 🚨ONE OF IT, IN ONE PLACE, for every run — the canvas, the composite
  /// view and the track stack alike. A run can change what draws it under
  /// itself (the camera view turned on or off), and a layer for each would
  /// mount the next before the last was let go, the one going taking the
  /// clock's ticker with it.
  Widget _runLayer(EditorSessionManager session) => PlaybackRunLayer(
    controller: session.playbackRig.playback,
    prerenderProgress: session.playbackRig.prerenderScheduler.progress,
    child: RecordingStreamerOverlay(session: session),
  );

  bool _pressNeedsCel(CanvasTool tool, EditorSessionManager session) {
    if (!canvasToolMarksCel(tool)) {
      return false;
    }
    return _strokeNeedsCel(session);
  }

  /// A STROKE with no cel under it: make the block if the toggle and the row
  /// allow it, otherwise say why at the cursor.
  ///
  /// The press asks this once its tool turned out to mark. 확정's 재입력
  /// asks it directly — it IS a stroke, whichever tool is up, so the door
  /// it takes on an empty cell is the stroke's (confirm-button).
  bool _strokeNeedsCel(EditorSessionManager session) {
    // 🚨F-196: the ROW first. `beginAutoFrameForStroke` asks the toggle and
    // the LAYER, never the row you stand on, so a press on a lane's empty
    // frame made a block on the layer beneath it and then drew into it —
    // the stroke the lane refuses. F-242: nor does it ask the eye, so a
    // hidden row's empty frame got a block no stroke could draw into.
    if (_standingRowTakesStrokes(session) &&
        session.autoFrame.beginAutoFrameForStroke()) {
      return true;
    }
    cursorNotices.show(_drawRefusalFor(session));
    return false;
  }

  /// Where a value of [layer]'s OWN pose shows on the canvas, and back —
  /// through the placement of the folders above it
  /// ([FrameVerbs.layerParentPlacement]); an unfoldered row's parent is the
  /// canvas itself, and its values pass straight through.
  ///
  /// 🚨The layer's box below edits that own pose, so each of its grabs
  /// stands where the parent shows its value and each drag comes back
  /// through the parent: a row in a folder moved right by 200 had its
  /// crosshair 200 to the left of its picture, and under a 2× folder a drag
  /// moved the picture twice as far as the pointer (measured 2026-09-25).
  _ShownSpace _parentSpaceOf(EditorSessionManager session, Layer layer) =>
      _shownThrough(session.frameVerbs.layerParentPlacement(layer.id));

  static _ShownSpace _shownThrough(LayerPlacement? placement) {
    if (placement == null) {
      return (placement: null, toCanvas: (p) => p, fromCanvas: (p) => p);
    }
    final back = canvasToArtwork(placement);
    return (
      placement: placement,
      toCanvas: placement.apply,
      fromCanvas: (p) => back?.apply(p) ?? p,
    );
  }

  /// Where a value of [layer]'s POSITION shows on the canvas, and back: an
  /// SE row's through the shot it lies in (I-67-Q1), any other row's
  /// through the folders above it ([_parentSpaceOf]) — its box's grabs and
  /// its path's points alike.
  _ShownSpace _positionSpaceOf(EditorSessionManager session, Layer layer) =>
      layer.kind == LayerKind.se
      ? _shownThrough(_shotAtThePlayhead(session))
      : _parentSpaceOf(session, layer);

  /// Where the active cut's SHOT lies on the canvas at the playhead — the
  /// space an SE row's position is in (I-67-Q1).
  static LayerPlacement _shotAtThePlayhead(EditorSessionManager session) =>
      session.seEntries.shotForCutFrame(
        session.requireActiveCut,
        session.currentFrameIndex,
      );

  /// Where a point of [layer]'s own picture shows on the canvas: its own
  /// placement at the playhead — its pose about its anchor
  /// ([placementOf]) — under where its position shows ([_positionSpaceOf]).
  LayerPlacement _picturePlacementOf(
    EditorSessionManager session,
    Layer layer,
    CanvasSize canvasSize,
  ) {
    final at = session.laneVerbs.laneValueSourceAt(
      _shownRow(session, layer),
      session.currentFrameIndex,
    );
    final own = placementOf((
      pose: session.layerPoseAtFrame(at.layer, at.frame),
      anchorPoint: session.layerAnchorPointAtFrame(at.layer, at.frame),
    ), canvasSize);
    return _positionSpaceOf(session, layer).placement?.compose(own) ?? own;
  }

  /// Where a value of [layer]'s lane [property] — one whose keys walk a
  /// path — shows on the canvas, and back: a position where the row's
  /// position shows ([_positionSpaceOf]); an anchor point on the row's
  /// picture as it stands now ([_picturePlacementOf]), where After Effects
  /// draws an anchor's path in the layer panel — on the layer's own
  /// picture (anchor-walks-a-path-Q1 A, 유저 2026-10-13 「A로 가자」: 「그
  /// 행의 그림 위에 — 그림과 같이 움직인다」). The anchor where it stands now
  /// lands on the position, so the cross is always on its path.
  _ShownSpace _pathSpaceOf(
    EditorSessionManager session,
    Layer layer,
    TransformPropertyId property,
    CanvasSize canvasSize,
  ) => property == TransformPropertyId.anchorPoint
      ? _shownThrough(_picturePlacementOf(session, layer, canvasSize))
      : _positionSpaceOf(session, layer);

  /// [layer] as the canvas shows it — the drag in flight on it, if one is
  /// (F-195, canvas-follows-block-moves), so a handle stands where the
  /// picture is, not where the release will have put it.
  static Layer _shownRow(EditorSessionManager session, Layer layer) =>
      timelineDragPreviewLayerFor(session.dragPreview.value, layer.id) ??
      layer;

  /// [layer]'s lane [property] — one whose keys walk a path ([walksAPath])
  /// — of the row as the canvas shows it and where its values come from
  /// ([LaneVerbs.laneValueSourceAt]: a track-SE row's is the track's), and
  /// how far that lane's frames run ahead of the cut's
  /// ([EditorSessionManager.rowAxisOffset]). Null for a lane that walks
  /// none.
  static ({PropertyTrack<CanvasPoint> lane, int axisOffset})? _pathLaneOf(
    EditorSessionManager session,
    Layer layer,
    TransformPropertyId property,
  ) {
    final source = session.laneVerbs.laneValueSourceAt(
      _shownRow(session, layer),
      session.currentFrameIndex,
    );
    final lane = transformPathLaneOf(source.layer.transformTrack, property);
    return lane == null
        ? null
        : (lane: lane, axisOffset: session.rowAxisOffset(layer.id));
  }

  /// The path [layer]'s lane [property] walks ([CameraPath.ofLane]) — built
  /// again only for another lane: its points between keys are read as the
  /// canvas asks for them, and kept while it asks again at every step of a
  /// scrub.
  CameraPath? _rowPathOf(
    EditorSessionManager session,
    Layer layer,
    TransformPropertyId property,
  ) {
    final shown = _pathLaneOf(session, layer, property);
    if (shown == null) {
      return null;
    }
    final (:lane, :axisOffset) = shown;
    if (_rowPathMemo case (
      lane: final memoLane,
      axisOffset: final memoOffset,
      :final path,
    ) when identical(memoLane, lane) && memoOffset == axisOffset) {
      return path;
    }
    final path = CameraPath.ofLane(lane, axisOffset: axisOffset);
    _rowPathMemo = (lane: lane, axisOffset: axisOffset, path: path);
    return path;
  }

  ({PropertyTrack<CanvasPoint> lane, int axisOffset, CameraPath? path})?
  _rowPathMemo;

  /// A canvas handle's ONE edit, landed two ways (F-195): shown while the
  /// handle moves, written when it lets go — and dropped when it is
  /// cancelled, through the box's [RowTransformBox.onCancelled]
  /// (`endLaneEditPreview`).
  ///
  /// ⛔[editOf] is the SAME edit for both landings — the release keeps what
  /// the drag showed because it is the drag's own computation, not a second
  /// one that happens to agree.
  ///
  /// [reference]: the edit is of the row's REFERENCE FX (F-374) — the
  /// transform's lanes in their other home, keyed the same way.
  RowBoxLanding<T> _handleLandings<T>(
    EditorSessionManager session,
    LayerId layerId,
    _TrackEdit Function(T value) editOf, {
    required String description,
    bool reference = false,
  }) {
    final verbs = session.laneVerbs;
    return reference
        ? _landedThrough(
            editOf,
            preview: (edit) =>
                verbs.previewReferenceFxAtPlayhead(layerId, edit),
            write: (edit) => verbs.editReferenceFxAtPlayhead(
              layerId,
              edit,
              description: description,
            ),
          )
        : _landedThrough(
            editOf,
            preview: (edit) =>
                verbs.previewLayerTransformAtPlayhead(layerId, edit),
            write: (edit) => verbs.editLayerTransformAtPlayhead(
              layerId,
              edit,
              description: description,
            ),
          );
  }

  /// [editOf]'s ONE edit of a value a handle drags ([_handleLandings]):
  /// [preview]ed while the handle moves, [write]n when it lets go.
  static RowBoxLanding<T> _landedThrough<T>(
    _TrackEdit Function(T value) editOf, {
    required void Function(_TrackEdit edit) preview,
    required void Function(_TrackEdit edit) write,
  }) => (
    changed: (value) => preview(editOf(value)),
    committed: (value) => write(editOf(value)),
  );

  /// The edits a box's grabs make of the track they drive — ONE key at the
  /// playhead on the one lane the grab is about (R5 #10) — for every box
  /// alike: a row's, a reference's, an effect's and the camera's.
  static _TrackEdit _movedTo(CanvasPoint position) =>
      (track, frameIndex) => transformTrackWithPositionDragged(
        track,
        frameIndex: frameIndex,
        position: position,
      );

  static _TrackEdit _scaledTo(CanvasPoint scale) =>
      (track, frameIndex) => transformTrackWithScaleDragged(
        track,
        frameIndex: frameIndex,
        scale: scale,
      );

  static _TrackEdit _turnedTo(double degrees) =>
      (track, frameIndex) => transformTrackWithRotationDragged(
        track,
        frameIndex: frameIndex,
        rotationDegrees: degrees,
      );

  static _TrackEdit _anchoredAt(CanvasPoint anchorPoint) =>
      (track, frameIndex) => transformTrackWithAnchorDragged(
        track,
        frameIndex: frameIndex,
        anchorPoint: anchorPoint,
      );

  /// The active row's transform fx box (F-222 ②): the inside moves its
  /// position, a corner scales it, outside on stage turns it, and the cross
  /// places its anchor point — as much of that as the standing lane
  /// declares (R5 #10: the box for position, scale and rotation, the cross
  /// for the anchor).
  ///
  /// ONE box for every row a transform fx poses — a layer's picture and an
  /// SE row's name tag alike; [picture] is all that differs
  /// ([_layerPicture], [_sePicture]).
  ///
  /// 🗣️F-387 (유저 2026-10-19): 「일반 그림 레이어에서는 트랜스폼fx의 헤더에
  /// 서면 변형도구 ui 그대로써서 회전같은거 가능한데 se의 트랜스폼fx는
  /// 그런게안됨. 그런 관련 로직 사본만든거같은데 법 통일. 같은 fx인데
  /// 다른건 말이안됨」. ↩️An SE row's box was a second one that only moved.
  ///
  /// ONE key at the playhead per drag (AE rule, one undo) — on the row the
  /// project holds, at the playhead on its own axis. ⚠️Not on the active
  /// layer as found: a track-SE row's is its cut-local clone, and writing
  /// that back erased the keys of earlier cuts (F-102).
  Widget _layerBox(
    _HostFrame frame,
    CanvasViewport viewport,
    CanvasSize canvasSize, {
    required _RowPicture picture,
  }) {
    final session = frame.session;
    final activeLayer = frame.activeLayer!;
    // The handles stand where the row's value IS: for a track-SE row that is
    // the track's row at the global frame, not the cut's clone (F-102).
    final at = session.laneVerbs.laneValueSourceAt(
      _shownRow(session, activeLayer),
      session.currentFrameIndex,
    );
    final own = session.layerPoseAtFrame(at.layer, at.frame);
    final anchorPoint = session.layerAnchorPointAtFrame(at.layer, at.frame);
    final parent = _positionSpaceOf(session, activeLayer);
    // The box draws the row as the canvas SHOWS it — its own pose where
    // its position shows ([_positionSpaceOf]: under the folders', or an SE
    // row's shot) — and turns and scales about the row's anchor where that
    // shows. The scale and the turn it stands on are the ROW'S OWN: a
    // handle scales by a ratio and outside turns by an angle, and what
    // comes back is the value the lane keys.
    //
    // ↩️It stood on the parent's zoom times the row's and the parent's turn
    // plus the row's, and each landing took the parent's back off — a
    // second fold of the folders beside the plan's, which only a parent
    // that is a similarity has a zoom and a turn to give.
    //
    // The TURN is measured in the parent's space
    // ([RowTransformBox.turnSpace]): the row's rotation lives there, and a
    // folder may stretch or flip now.
    final pose = own.copyWith(center: parent.toCanvas(own.center));
    final name = activeLayer.name;
    final box = frame.boxGrabbable;
    final shown = _picturePlacementOf(session, activeLayer, canvasSize);
    // 🗣️F-387 (유저 2026-10-17): 「그림이나 소재 … 가 없을때 변형에 서면
    // 움직여지는데 기준점은 움직이는게 안보인다던가 하는 문제 해결. 위치
    // 변형하듯 무언가 변형되는 박스를 임시로 만들어서 조작중임을 표시하도록」
    // — a row that shows nothing has its box drawn under the cross alone
    // too: the anchor's drag moves it as it moves a picture.
    final drawn = picture.drawn;
    return RowTransformBox(
      // The box frames the row's PICTURE (the user chose that on the
      // mockup: 「레이어 그림의 바운드에 걸리는게 알기쉬울거같기도하고?
      // 그렇게하자」) — and a row with nothing to show frames the whole of
      // the space it is posed in, the transform tool's own rule for a
      // picture with nothing in it.
      corners: box || drawn == null
          ? placedCorners(shown, drawn ?? picture.space)
          : const [],
      pose: pose,
      pasteboard: session.pasteboardOf(canvasSize),
      viewport: viewport,
      presses: frame.boxPresses,
      onCancelled: session.laneVerbs.endLaneEditPreview,
      move: box
          ? _handleLandings<CanvasPoint>(
              session,
              activeLayer.id,
              (dropped) => _movedTo(parent.fromCanvas(dropped)),
              description: 'Move $name',
            )
          : null,
      scale: box
          ? RowBoxTwoScales(
              _handleLandings<CanvasPoint>(
                session,
                activeLayer.id,
                _scaledTo,
                description: 'Scale $name',
              ),
            )
          : null,
      turnSpace: parent.fromCanvas,
      turn: box
          ? _handleLandings<double>(
              session,
              activeLayer.id,
              _turnedTo,
              description: 'Rotate $name',
            )
          : null,
      // 🗣️F-222-box-Q3 (유저 2026-10-01, chat — replacing the board's 「그림은
      // 가만히」): 「레이어 상자 십자가는 앵커포인트로서 작동하게, 즉 각자
      // 대응하는 ui로직이됨. 그래서 그림은 가만히라기보다 지금 로직
      // 그대로이고 앵커포인트위치를 십자가로 조정하도록」 — a drag keys the
      // anchor point alone, and the picture moves as scrubbing its value does.
      // 🗣️And it is After Effects' (same day): 「ae랑 똑같으면 문제없어.
      // 애초에 트랜스폼 fx는 똑같도록하는게 목표」. AE draws the anchor where
      // it LANDS — the position, the centre the layer turns and scales about
      // — so the cross stands there, never apart from the box's pivot, and
      // stays with the position while the drag moves the picture under it.
      cross: frame.crossGrabbable
          ? (
              at: pose.center,
              value: parent.toCanvas(anchorPoint),
              landing: _handleLandings<CanvasPoint>(
                session,
                activeLayer.id,
                (dropped) => _anchoredAt(parent.fromCanvas(dropped)),
                description: 'Anchor $name',
              ),
            )
          : null,
      tangents: _rowPathTangents(frame, canvasSize),
    );
  }

  /// A REFERENCE row's box (I-68): where the file it shows stands. The
  /// inside moves it, a corner or an edge's middle scales it, outside on
  /// stage turns it — the layer's box's grabs — and what each writes is the
  /// row's reference fx (유저 2026-10-10 「참조 행에서 이동(변형) 도구로 끌면
  /// 참조 fx 의 값이 바뀐다」): ONE key at the playhead, as the layer's box
  /// writes its transform's (F-374 — 「지금 움직여도 키 안생긴다거나 … 싹
  /// 통일」). It frames the PICTURE — its own corners where the fx stands
  /// them at the playhead, under the row's transform and its folders, where
  /// the canvas shows it.
  Widget _referenceBox(
    _HostFrame frame,
    CanvasViewport viewport,
    CanvasSize canvasSize,
  ) {
    final session = frame.session;
    final row = _shownRow(session, frame.activeLayer!);
    final reference = row.mediaReference!;
    final pose = reference.poseAt(session.currentFrameIndex);
    final space = _shownThrough(
      session.frameVerbs.layerReferenceSpace(row.id),
    );
    final name = row.name;
    return RowTransformBox(
      corners: _referenceBoxCorners(
        pose,
        reference.pictureSize,
        space.toCanvas,
      ),
      pose: pose.copyWith(center: space.toCanvas(pose.center)),
      pasteboard: session.pasteboardOf(canvasSize),
      viewport: viewport,
      presses: frame.boxPresses,
      onCancelled: session.laneVerbs.endLaneEditPreview,
      move: _handleLandings<CanvasPoint>(
        session,
        row.id,
        (dropped) => _movedTo(space.fromCanvas(dropped)),
        description: 'Move $name reference',
        reference: true,
      ),
      scale: RowBoxTwoScales(
        _handleLandings<CanvasPoint>(
          session,
          row.id,
          _scaledTo,
          description: 'Scale $name reference',
          reference: true,
        ),
      ),
      turnSpace: space.fromCanvas,
      turn: _handleLandings<double>(
        session,
        row.id,
        _turnedTo,
        description: 'Rotate $name reference',
        reference: true,
      ),
    );
  }

  /// The box an effect declares while the lane [_HostFrame.effectBox]
  /// names is stood on ([effectBoxedOn]) — over the picture it draws
  /// ([_effectPictureBox]) or a point's cross ([_effectPointBox]) — on the
  /// row whose value the lanes show: a track-SE row's at the global frame
  /// (F-102). Each grab writes ONE key at the playhead, one undo, through
  /// the lane's own keys ([LaneVerbs.editEffectKeysAtPlayhead]), as the
  /// row's box writes its transform's.
  Widget _effectBox(
    _HostFrame frame,
    CanvasViewport viewport,
    CanvasSize canvasSize,
  ) {
    final session = frame.session;
    final at = session.laneVerbs.laneValueSourceAt(
      _shownRow(session, frame.activeLayer!),
      session.currentFrameIndex,
    );
    final row = at.layer;
    final (:effect, :lane) = frame.effectBox!;
    final laneId = effectLaneId(effect.id, lane);
    final boxed = effectBoxedOn(row.effects, laneId);
    if (boxed == null) {
      return const SizedBox.shrink();
    }
    final verbs = session.laneVerbs;
    RowBoxLanding<T> landing<T>(
      _TrackEdit Function(T value) editOf, {
      required String description,
    }) => _landedThrough(
      editOf,
      preview: (edit) => verbs.previewEffectKeysAtPlayhead(row.id, laneId, edit),
      write: (edit) => verbs.editEffectKeysAtPlayhead(
        row.id,
        laneId,
        edit,
        description: description,
      ),
    );
    final space = _shownThrough(
      session.frameVerbs.layerCanvasPoseSample(row.id),
    );
    final resolved = resolveLayerEffectsAt(
      effects: [boxed.effect],
      frameIndex: at.frame,
    ).single;
    final name = '${row.name} ${boxed.effect.label}';
    return boxed.effect.kind.drawsItsOwnPicture
        ? _effectPictureBox(
            frame,
            viewport,
            canvasSize,
            row: row,
            number: resolved,
            space: space,
            name: name,
            landing: landing,
          )
        : _effectPointBox(
            frame,
            viewport,
            canvasSize,
            point: effectPointOnPaper(resolved.points[lane], canvasSize),
            space: space,
            name: name,
            landing: landing,
          );
  }

  /// The box of an effect that draws its own picture — a cel number's
  /// letters (F-477) — while its header or where it stands is stood on
  /// ([effectBoxedOn]): the inside moves the letters, a corner or an edge's
  /// middle scales them, as a row's box moves and scales its picture; no
  /// turn, the effect keys none (I-65-Q2 「위치/비율 두개 키」). What each
  /// writes is where the effect stands. It frames the letters where the
  /// canvas shows them: on the row's paper, laid where the row is.
  Widget _effectPictureBox(
    _HostFrame frame,
    CanvasViewport viewport,
    CanvasSize canvasSize, {
    required Layer row,
    required ResolvedLayerEffect number,
    required _ShownSpace space,
    required String name,
    required _EffectLanding landing,
  }) {
    final session = frame.session;
    final letters = celNumberLettersOf(
      number,
      text: celNumberText(
        rowName: row.name,
        drawingName: session.selectedFrame?.name,
        kind: row.kind,
      ),
      paper: canvasSize,
    );
    final stand = effectStandPose(number.stand!, canvasSize);
    final box = celNumberBox(letters);
    return RowTransformBox(
      corners: [
        for (final corner in [
          box.topLeft,
          box.topRight,
          box.bottomRight,
          box.bottomLeft,
        ])
          space.toCanvas(CanvasPoint(x: corner.dx, y: corner.dy)),
      ],
      pose: stand.copyWith(center: space.toCanvas(stand.center)),
      pasteboard: session.pasteboardOf(canvasSize),
      viewport: viewport,
      presses: frame.boxPresses,
      onCancelled: session.laneVerbs.endLaneEditPreview,
      move: landing<CanvasPoint>(
        (dropped) => _movedTo(space.fromCanvas(dropped)),
        description: 'Move $name',
      ),
      scale: RowBoxTwoScales(
        landing<CanvasPoint>(_scaledTo, description: 'Scale $name'),
      ),
    );
  }

  /// A point's cross (I-132-Q12 b) — a radial blur's centre — while its
  /// lane or its effect's header is stood on ([effectBoxedOn]): the cross a
  /// row's anchor point is placed with, where the canvas shows [point] — on
  /// the row's paper, laid where the row is — and a drag keys the point
  /// where it lets go, as Position's key is laid ([_movedTo]).
  Widget _effectPointBox(
    _HostFrame frame,
    CanvasViewport viewport,
    CanvasSize canvasSize, {
    required CanvasPoint point,
    required _ShownSpace space,
    required String name,
    required _EffectLanding landing,
  }) {
    final session = frame.session;
    final shown = space.toCanvas(point);
    return RowTransformBox(
      // A point frames nothing: the cross alone, as a row's anchor stands
      // over a row with nothing drawn.
      corners: const [],
      pose: TransformPose(center: shown),
      pasteboard: session.pasteboardOf(canvasSize),
      viewport: viewport,
      presses: frame.boxPresses,
      onCancelled: session.laneVerbs.endLaneEditPreview,
      cross: (
        at: shown,
        value: shown,
        landing: landing<CanvasPoint>(
          (dropped) => _movedTo(space.fromCanvas(dropped)),
          description: 'Move $name',
        ),
      ),
    );
  }

  /// [picture]'s own corners where [pose] lays it, on the canvas through
  /// [toCanvas] — the reference box's frame, as [_seTagBoxOf] is the SE
  /// box's.
  static List<CanvasPoint> _referenceBoxCorners(
    TransformPose pose,
    CanvasSize picture,
    CanvasPoint Function(CanvasPoint point) toCanvas,
  ) => [
    for (final corner in placedCorners(
      picturePlacement(pose, picture),
      Offset.zero & Size(picture.width.toDouble(), picture.height.toDouble()),
    ))
      toCanvas(corner),
  ];

  /// A layer's picture at the playhead (F-222 ②): its ink, and the canvas
  /// it is posed in ([CanvasSelectionShape.wholePicture] — the transform
  /// tool's rule for the whole picture).
  static _RowPicture _layerPicture(
    _HostFrame frame,
    PasteboardWall pasteboard,
  ) {
    final ink = frame.inkBounds;
    Rect rectOf(CanvasSelectionShape shape) => Rect.fromPoints(
      Offset(shape.points[0].x, shape.points[0].y),
      Offset(shape.points[2].x, shape.points[2].y),
    );
    return (
      drawn: ink == null
          ? null
          : rectOf(CanvasSelectionShape.wholePicture(pasteboard, ink)),
      space: rectOf(CanvasSelectionShape.wholePicture(pasteboard, null)),
    );
  }

  /// An SE row's picture at the playhead: its name tag among [tags]
  /// ([_seTagBoxOf]), and the SHOT it is posed in (I-67-Q1).
  ///
  /// 🗣️F-387 (유저 2026-10-17): 「특히 지금 se행 네임태그 se블록없는곳에서
  /// 변형 조작되는데 화면엔 안보임」. ↩️The stand-in was the canvas, laid as
  /// it stood: a drag keyed the row's position and nothing on screen
  /// moved. A layer's blank cel stands in the same way ([_layerPicture]) —
  /// the whole of the space the row is posed in, placed as its picture is.
  static _RowPicture _sePicture(
    EditorSessionManager session,
    Layer row,
    List<ResolvedSeNameTag> tags,
    CanvasSize canvasSize,
  ) {
    final shot = session.camera.cameraFrameSize;
    return (
      drawn: _seTagBoxOf(row, tags, canvasSize),
      space: Offset.zero &
          Size(shot.width.toDouble(), shot.height.toDouble()),
    );
  }

  /// [row]'s name tag box among [tags], in the tag's own space
  /// ([ResolvedSeNameTag.placement] lays it) — null with no tag of the row
  /// under the playhead.
  static Rect? _seTagBoxOf(
    Layer row,
    List<ResolvedSeNameTag> tags,
    CanvasSize canvasSize,
  ) {
    Rect? box;
    for (final tag in tags) {
      final tagBox = tag.layerId == row.id.value
          ? seNameTagBoxBounds(tag, canvasSize: canvasSize)
          : Rect.zero;
      if (!tagBox.isEmpty) {
        box = tagBox;
      }
    }
    return box;
  }

  /// The camera row's box ([CameraFrameBox], F-222 ③).
  ///
  /// It drives the CAMERA ROW's transform — the cut's camera track —
  /// through the one handle path the layer handles take (「트랜스폼이나
  /// 카메라나 법 하나」): one key at the playhead, shown while it moves, on
  /// the ONE member the grab drives — as the user chose
  /// (camera-frame-keys-what-you-grab-Q1 「잡은 것만」). A curved key's
  /// tangent bends its path ([_cameraPathTangents]) on the box, so only
  /// where the box is: the path's handles are worked where the frame is
  /// (유저 2026-10-12: 「카메라 사각형 조작 가능한것처럼 거기 서야만 핸들이나
  /// 이런거 조작하도록」).
  Widget _cameraBox(
    _HostFrame frame,
    CanvasViewport viewport,
    CanvasSize canvasSize,
  ) {
    final session = frame.session;
    final cameraRow = session.activeLayer!;
    final at = 'at frame ${session.currentFrameIndex + 1}';
    final move = _handleLandings<CanvasPoint>(
      session,
      cameraRow.id,
      _movedTo,
      description: 'Move camera $at',
    );
    final zoom = _handleLandings<double>(
      session,
      cameraRow.id,
      (zoom) => _scaledTo(uniformScale(zoom)),
      description: 'Zoom camera $at',
    );
    final turn = _handleLandings<double>(
      session,
      cameraRow.id,
      _turnedTo,
      description: 'Rotate camera $at',
    );
    // The box follows the frame along its animated pose, as the frame does.
    return _atTheCameraPose(
      session,
      (pose) => CameraFrameBox(
        pose: pose,
        cameraFrameSize: session.camera.cameraFrameSize,
        pasteboard: session.pasteboardOf(canvasSize),
        viewport: viewport,
        presses: frame.boxPresses,
        onCancelled: session.laneVerbs.endLaneEditPreview,
        move: move,
        zoom: zoom,
        turn: turn,
        tangents: _cameraPathTangents(session, cameraRow.id),
      ),
    );
  }

  /// The handles of the camera's curved position keys on its path
  /// ([_pathTangents]), where the camera moves at all.
  List<RowBoxTangent> _cameraPathTangents(
    EditorSessionManager session,
    LayerId cameraRowId,
  ) {
    final track = session.camera.activeCutCameraTrack;
    if (track == null ||
        session.camera.activeCutCameraPath(_cameraFrameSizeShown(session)) ==
            null) {
      return const [];
    }
    return _pathTangents(
      session,
      cameraRowId,
      (
        property: TransformPropertyId.position,
        lane: track.position,
        axisOffset: 0,
        space: _shownThrough(null),
      ),
      description: 'Bend camera path',
    );
  }

  /// The handles of the active layer's curved keys on the path of the lane
  /// it stands on ([_pathTangents]: I-89-Q9), while that path is drawn
  /// ([_rowPath]) — where that lane's values show ([_pathSpaceOf]).
  List<RowBoxTangent> _rowPathTangents(
    _HostFrame frame,
    CanvasSize canvasSize,
  ) {
    final session = frame.session;
    final layer = frame.activeLayer!;
    final property = frame.pathLane;
    final shown = property == null
        ? null
        : _pathLaneOf(session, layer, property);
    if (property == null ||
        shown == null ||
        _rowPathOf(session, layer, property) == null) {
      return const [];
    }
    final (:lane, :axisOffset) = shown;
    return _pathTangents(
      session,
      layer.id,
      (
        property: property,
        lane: lane,
        axisOffset: axisOffset,
        space: _pathSpaceOf(session, layer, property, canvasSize),
      ),
      description: 'Bend ${layer.name} path',
    );
  }

  /// The handles of a row's curved keys on the path its [path]'s lane
  /// walks (I-89 ④): drawn wherever it is, in space and in space and time
  /// alike (🗣️F-368, 유저 2026-10-16: 「공간이든 공간+시간이든 공간이라는
  /// 정보로서」 · F-368-Q1 A 「중앙 궤적 선 + 핸들(두 모드 공통, 서 있을
  /// 때)」 — ↩️in time alone, 2026-10-10, where the mock's 5판 drew them),
  /// over the frames it is drawn for, each tangent carried bending its key
  /// — one undo where it is let go — where the canvas shows the lane's
  /// values (a camera's position is on it already).
  List<RowBoxTangent> _pathTangents(
    EditorSessionManager session,
    LayerId rowId,
    _PathShown path, {
    required String description,
  }) {
    final settings = CameraPathSettings.settings.value;
    if (settings.show == CameraPathShow.off) {
      return const [];
    }
    final (:property, :lane, :axisOffset, space: shown) = path;
    final (:from, :to) = settings.framesShownAt(session.currentFrameIndex);
    RowBoxKnob? knobOf(KeyPathKnob knob, {required bool ahead}) {
      final end = ahead ? knob.ahead : knob.behind;
      if (end == null) {
        return null;
      }
      return (
        at: shown.toCanvas(end),
        landing: _handleLandings<CanvasPoint>(
          session,
          rowId,
          (carried) => (track, _) {
            final reached = shown.fromCanvas(carried);
            return transformTrackWithPathHandle(
              track,
              property: property,
              frameIndex: knob.frame,
              handle: (
                ahead: ahead,
                reach: CanvasPoint(
                  x: reached.x - knob.at.x,
                  y: reached.y - knob.at.y,
                ),
              ),
            );
          },
          description: '$description at frame '
              '${knob.frame - axisOffset + 1}',
        ),
      );
    }

    return [
      for (final knob in keyPathKnobs(
        lane.keys,
        from: from == null ? null : from + axisOffset,
        to: to == null ? null : to + axisOffset,
      ))
        (
          at: shown.toCanvas(knob.at),
          ahead: knobOf(knob, ahead: true),
          behind: knobOf(knob, ahead: false),
        ),
    ];
  }

  /// The camera frame's size as the canvas shows it: the size being dragged
  /// while it is adjusted on the canvas (I-80), else the project camera's.
  static CanvasSize _cameraFrameSizeShown(EditorSessionManager session) =>
      session.canvasAdjust.cameraSizeShown ?? session.camera.cameraFrameSize;

  /// The camera's path (I-89 ④) under its frame, as the canvas's camera path
  /// settings say, whether or not the frame is drawn (유저 2026-10-13: 「카메라
  /// on하든 off하든 상관없어보이니까 on하든 off하든 설정한대로 보이도록」 —
  /// ↩️ it was drawn wherever the frame was, 10-12 「비지블버튼처럼 어느
  /// 상태에 있던 카메라 사각형을 보여주는 규칙 그대로 경로도」, and before
  /// that standing on the camera row or its position lane alone) — at the
  /// size the frame is shown at, around the playhead the cursor moves, and
  /// nowhere in a gap. Standing on the camera's row, where its box is
  /// ([_cameraBox]), it is drawn with the line its middle walks, and in
  /// time where the settings say; elsewhere as the export writes it
  /// ([CameraPathOverlay.standing]). What the export writes lies on the
  /// picture as large as it prints at the playhead's camera
  /// ([CameraPathOverlay.printedAt]).
  Positioned _cameraPath(
    _HostFrame frame,
    CanvasViewport viewport,
  ) => Positioned.fill(
    child: ValueListenableBuilder<CameraPathSettings>(
      valueListenable: CameraPathSettings.settings,
      builder: (context, settings, _) => settings.show == CameraPathShow.off
          ? const SizedBox.shrink()
          : ListenableBuilder(
              listenable: frame.session.canvasAdjust,
              builder: (context, _) => _atTheCameraPose(frame.session, (pose) {
                final path = frame.session.camera.activeCutCameraPath(
                  _cameraFrameSizeShown(frame.session),
                );
                return path == null
                    ? const SizedBox.shrink()
                    : CameraPathOverlay(
                        path: path,
                        playhead: frame.session.currentFrameIndex,
                        settings: settings,
                        viewport: viewport,
                        standing: frame.isCameraLayerActive,
                        printedAt: pose,
                      );
              }),
            ),
    ),
  );

  /// The path the active layer's lane [property] walks — its position's
  /// (I-89-Q9, 유저 2026-10-12 「같은 코드로 레이어 위치 레인에도」) or its
  /// anchor point's (anchor-walks-a-path-Q1 A) — by the camera's path's
  /// code, a point where the camera has its frame, drawn standing on that
  /// lane, where the box that moves its keys is: as the canvas's camera
  /// path settings say, in time as well, and laid where the lane's values
  /// show ([_pathSpaceOf]).
  Positioned _rowPath(
    _HostFrame frame,
    TransformPropertyId property,
    CanvasViewport viewport,
    CanvasSize canvasSize,
  ) => Positioned.fill(
    child: ValueListenableBuilder<CameraPathSettings>(
      valueListenable: CameraPathSettings.settings,
      builder: (context, settings, _) {
        final session = frame.session;
        final layer = frame.activeLayer!;
        final path = settings.show == CameraPathShow.off
            ? null
            : _rowPathOf(session, layer, property);
        return path == null
            ? const SizedBox.shrink()
            : CameraPathOverlay(
                path: path,
                playhead: session.currentFrameIndex,
                settings: settings,
                viewport: viewport,
                standing: true,
                toCanvas: _pathSpaceOf(
                  session,
                  layer,
                  property,
                  canvasSize,
                ).toCanvas,
              );
      },
    ),
  );

  /// The camera's frame — the dim outside it and its hairline — drawn for
  /// every row. It takes no press: on the camera row the frame's box does
  /// ([_cameraBox]), over the tools. While its size is adjusted on the
  /// canvas (I-80) it is the size being dragged, so the dim and the box
  /// stand on one frame.
  Positioned _cameraOverlay(
    EditorSessionManager session,
    CanvasViewport viewport,
  ) {
    return Positioned.fill(
      child: ListenableBuilder(
        listenable: session.canvasAdjust,
        builder: (context, _) => _atTheCameraPose(
          session,
          (pose) => CameraFrameOverlay(
            pose: pose,
            cameraFrameSize: _cameraFrameSizeShown(session),
            viewport: viewport,
            // Dim belongs to camera-view mode; plain manipulation keeps the
            // artwork undimmed.
            dimOpacity: widget.cameraViewEnabled.value
                ? widget.cameraDimOpacity.value
                : 0,
          ),
        ),
      ),
    );
  }

  /// [build] at the camera's pose as the canvas shows it, again whenever the
  /// pose moves — and nothing where there is no pose: under the cursor is a
  /// gap. The camera's frame, its box and its path (I-89 ④) all stand on it.
  ///
  /// The cursor subscription keeps the frame gliding along its animated
  /// pose during scrubs (and after committed seeks) without any wider
  /// rebuild. A crossing into another cut and a scrub's step into a gap
  /// rebuild the area around it — the session's notify, the scrub's gap
  /// edge.
  ///
  /// ↩️㊲ watched the gap's PARKING too: a scrub that crossed a cut boundary
  /// moved only that, the cursor staying put, so a pose read on the cursor
  /// alone stayed frozen on the cut being left. The scrub crosses into the
  /// cut now (I-57 ②), and the parking moves per step only inside a gap,
  /// where there is no pose to move.
  Widget _atTheCameraPose(
    EditorSessionManager session,
    Widget Function(CameraPose pose) build,
  ) => ListenableBuilder(
    listenable: session.editingFrameCursor,
    builder: (context, _) {
      final pose = session.camera.displayedCameraPose;
      return pose == null ? const SizedBox.shrink() : build(pose);
    },
  );

  Positioned _cutFadeWash(
    CanvasViewport viewport,
    CanvasSize canvasSize,
    EditorSessionManager session,
    double cutFadeOpacity,
    List<TransitionVeil> veils,
    BuildContext context, {
    required bool throughCamera,
  }) {
    final standing = session.editingGlobalFrame;
    final partners = _olPartnersAt(session, standing);
    final frame = session.camera.cameraFrameSize;
    final project = session.repository.requireProject();
    return Positioned.fill(
      // The cut fade on the EDITING canvas (R9-C →
      // R3b): the fade is transparency, and here the
      // whole viewport IS the cut's unit (pasteboard,
      // paper, pictures) over the backdrop — so a
      // backdrop-colored wash at (1 − fade) is
      // pixel-equal to thinning the unit, without
      // re-compositing the editing stack.
      //
      // The backdrop AS THE SCREEN SHOWS IT ([backdropOnScreen]): over the
      // panel's ground, opaque — what the film's floor is under the thinned
      // unit. ↩️The wash took the backdrop's own colour at the fade's share,
      // its alpha dropped: a translucent backdrop thinned the cut to a
      // colour the film never showed (a-translucent-backdrop-lies-twice-
      // on-the-film, measured 10-23).
      //
      // A run seen through the camera has the camera's frame for its unit
      // ([PlaybackFramePainter.veils]), and its O.L partner the camera too.
      // Seen through none the unit reaches as far as the pasteboard: its
      // plane and what is drawn on it thin with the paper, as the film
      // thins them (conte-playback-hides-the-pasteboard). ↩️The wash
      // covered the canvas alone — what only a film cut at the canvas's
      // edge agreed with.
      //
      // F-192: a one-sided transition's own screen is part of the unit,
      // so it goes down FIRST and the wash thins it with the rest.
      //
      // 🗣️F-227 (유저 2026-09-29): 「컷ol은 두 컷이 동시에 존재하는 상태면서
      // 오버랩하는건데 … 컷1이 fo하다가 갑자기 컷2가 fi하는 상태」. Inside an
      // O.L the share the fade takes is not backdrop: it is the OTHER cut,
      // and the canvas used to dip the cut to the backdrop there — half an
      // O.L on each side of the boundary. The partner is laid over the live
      // cut at its own share, the backdrop keeping whatever is left (none,
      // when the two halves are the whole frame): the mix playback paints.
      child: IgnorePointer(
        child: Stack(
          fit: StackFit.expand,
          children: [
            CustomPaint(
              painter: _CutFadeWashPainter(
                viewport: viewport,
                unit: throughCamera
                    ? frame.canvasRect
                    : session.pasteboardOf(canvasSize).rect,
                veils: veils,
                backdrop: backdropOnScreen((
                  color: stageColorOnScreen(project.backdropArgb),
                  none: project.backdropNone,
                ), stageGroundOf(context)),
                share: backdropShareUnder(cutFadeOpacity, [
                  for (final partner in partners) partner.opacity,
                ]),
                devicePixelRatio: EffectiveDevicePixelRatio.of(context),
              ),
            ),
            if (partners.isNotEmpty)
              _trackStack(
                session,
                viewport,
                _olPartnerMount(
                  standing,
                  partners,
                  throughCamera: throughCamera,
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// The other cuts an O.L composites at [globalFrame] on the ACTIVE
  /// track — the partner the editing canvas lays over the live cut. Other
  /// tracks stay off the editing canvas, as they always have.
  List<TrackStackContribution> _olPartnersAt(
    EditorSessionManager session,
    int globalFrame,
  ) {
    final activeCutId = session.activeCutId;
    final trackId = session.activeTrack.id;
    return [
      for (final contribution in session.rowSpans.trackStackContributionsAt(
        globalFrame,
      ))
        if (contribution.cutId != activeCutId &&
            session.trackOwningCut(contribution.cutId)?.id == trackId)
          contribution,
    ];
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
    final verbs = session.cutVerbs;
    return Positioned.fill(
      child: GuideEditLayer(
        guides: verbs.activeCutGuidesForDisplay,
        viewport: viewport,
        onGuideSelected: (id) => session.cutVerbs.selectedGuideId = id,
        // A drag PREVIEWS and the release COMMITS, so it is one undo entry.
        // ⛔Through the cut verbs' one preview, not a copy kept here: the
        // settings panel edits the same guides from another subtree
        // (guide-slider-one-undo).
        onGuidesChanged: verbs.previewActiveCutGuides,
        onGuidesCommitted: verbs.setActiveCutGuides,
      ),
    );
  }

  Positioned _guideOverlay(
    EditorSessionManager session,
    CanvasViewport viewport,
    CanvasSize canvasSize,
    CanvasTool tool,
    BuildContext context,
  ) {
    final verbs = session.cutVerbs;
    return Positioned.fill(
      child: IgnorePointer(
        // The drag in flight repaints the guides and nothing else: the
        // preview is a channel of its own, where a `setState` here used to
        // rebuild the whole canvas area per pointer sample. So does the
        // guide picked, which the area does not hear
        // ([EditorCanvasArea.shownBy]).
        child: SlicedListenableBuilder<({CutGuides guides, GuideId? picked})>(
          listenable: Listenable.merge([session, verbs.guidesDragPreview]),
          slice: () => (
            guides: verbs.activeCutGuidesForDisplay,
            picked: verbs.selectedGuideId,
          ),
          builder: (context, shown) => CustomPaint(
            painter: GuideOverlayPainter(
              guides: shown.guides,
              viewport: viewport,
              canvasSize: canvasSize,
              emphasized: tool == CanvasTool.guide,
              vanishingPointLabel: AppText.strings.guideVanishingPoint,
              color: guideColorOf(context),
              face: appFaceOf(DefaultTextStyle.of(context).style),
              selectedGuideId: shown.picked,
            ),
          ),
        ),
      ),
    );
  }
}

/// The editing canvas's cut-fade wash (R9-C): the backdrop over the cut's
/// unit at its [share] of the frame, under the panel viewport — what
/// playback's thinning of the unit shows, so an fx-on faded frame reads
/// identically while editing.
///
/// 🚨An ABSENT backdrop washes the CHECKERBOARD (F-114,
/// fade-wash-ignores-an-absent-backdrop, 2026-10-23): what the thinned unit
/// reveals on the film is its floor, and an absent backdrop's floor is the
/// checkerboard — in the screen's cells, so the wash's lie exactly on the
/// floor's own. ↩️It washed the backdrop's kept colour, so standing on a
/// fade showed a colour the film never did.
class _CutFadeWashPainter extends CustomPainter with RepaintOnProps {
  const _CutFadeWashPainter({
    required this.viewport,
    required this.unit,
    required this.veils,
    required this.backdrop,
    required this.share,
    required this.devicePixelRatio,
  });

  final CanvasViewport viewport;

  /// The cut's unit in the space [viewport] shows — its pasteboard, or the
  /// camera's frame a run is seen through.
  final Rect unit;

  /// The screens one-sided transitions lay over the cut (F-192), under the
  /// wash — they are the unit's, and the wash thins the unit.
  final List<TransitionVeil> veils;

  /// The stage's backdrop as the screen shows it ([backdropOnScreen]) —
  /// opaque, or absent — so laid at [share] over the unit it is the unit
  /// thinned over the film's floor.
  final StagePlane backdrop;

  /// How much of the frame the backdrop takes over the unit
  /// ([backdropShareUnder]).
  final double share;

  /// The pan-phase snap's device grid — the wash covers the unit the
  /// snapped stack painted, not a sub-pixel beside it.
  final double devicePixelRatio;

  @override
  void paint(Canvas canvas, Size size) {
    final screen = canvas.getTransform();
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    applyViewportTransform(
      canvas,
      viewport,
      devicePixelRatio: devicePixelRatio,
    );
    paintTransitionVeils(canvas, unit, veils);
    if (!backdrop.none) {
      canvas.drawRect(
        unit,
        Paint()..color = backdrop.color.withValues(alpha: share),
      );
    } else if (share > 0) {
      canvas.saveLayer(unit, Paint()..color = alphaOnly(share));
      paintAbsentPlane(canvas, unit, screen: screen, antiAlias: true);
      canvas.restore();
    }
    canvas.restore();
  }

  @override
  Object get props =>
      (viewport, unit, ByList(veils), backdrop, share, devicePixelRatio);
}

/// The editing canvas's SE name tags (R5b): the same draw the frame
/// painter makes during playback — each tag in its shot, laid on the
/// canvas — so what you edit against is what plays and what exports.
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
    paintSeNameTags(
      canvas,
      tags: tags,
      canvasSize: canvasSize,
      rasterScale: displayScaleOf(viewport.zoom, devicePixelRatio),
    );
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
///
/// 🚨A RUN THE CANVAS PLAYS IS NOT RETARGETED HERE. It steps the cursor
/// every frame, and following it here built the whole canvas again for
/// each — the host configured anew, the panel under it laid out — to change
/// a picture (measured 10-09 on cut 301: the frame's build p50 22.1ms,
/// against 5.8 for the same run on the composite view). The host takes no
/// press while a run plays, so what shows the frame follows the run alone
/// ([_InteractiveCanvasBuild._followingDragAndRun]). A committed seek still
/// retargets, and the run's end builds the canvas again through the
/// playback flag above, at the frame it stopped on.
class _FrameRetargetScope extends StatefulWidget {
  const _FrameRetargetScope({
    required this.session,
    required this.runPlaysHere,
    required this.builder,
  });

  final EditorSessionManager session;

  /// Whether a run plays on this canvas
  /// ([_EditorCanvasAreaState._playsOnTheCanvas]) — then a step of the
  /// cursor is not this scope's to follow.
  final bool Function() runPlaysHere;
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
    widget.session.editingFrameCursor.addListener(_onCursorStepped);
    widget.session.brushInputActive.addListener(_onBrushInputChanged);
  }

  @override
  void didUpdateWidget(covariant _FrameRetargetScope oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.session, widget.session)) {
      oldWidget.session.frameSeekCommitted.removeListener(_onSeekCommitted);
      oldWidget.session.editingFrameCursor.removeListener(_onCursorStepped);
      oldWidget.session.brushInputActive.removeListener(_onBrushInputChanged);
      widget.session.frameSeekCommitted.addListener(_onSeekCommitted);
      widget.session.editingFrameCursor.addListener(_onCursorStepped);
      widget.session.brushInputActive.addListener(_onBrushInputChanged);
    }
  }

  @override
  void dispose() {
    widget.session.frameSeekCommitted.removeListener(_onSeekCommitted);
    widget.session.editingFrameCursor.removeListener(_onCursorStepped);
    widget.session.brushInputActive.removeListener(_onBrushInputChanged);
    super.dispose();
  }

  void _onCursorStepped() {
    if (widget.runPlaysHere()) {
      return;
    }
    _onSeekCommitted();
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

/// A drag as the canvas shows it ([_EditorCanvasAreaState._rowsShownBy]):
/// equal while every part is the SAME object — the rule a timeline row's
/// gate keeps for its one row, over every row the canvas draws.
final class _DragAsShown {
  const _DragAsShown(this.parts);

  final List<Object?> parts;

  @override
  bool operator ==(Object other) =>
      other is _DragAsShown && listsMatch(parts, other.parts, identical);

  @override
  int get hashCode => Object.hashAll(parts.map(identityHashCode));
}
