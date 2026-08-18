import 'dart:async' show unawaited;

import 'package:flutter/foundation.dart' show ValueListenable, setEquals;
import 'package:flutter/material.dart';

import '../models/layer.dart';
import '../models/layer_effect.dart';
import '../models/layer_id.dart';
import '../models/timeline_row_address.dart';
import '../models/layer_kind.dart';
import 'timeline/se_layer_mixer.dart';
import 'editor_command_actions.dart';
import 'editor_session_manager.dart';
import '../models/transform_track.dart';
import 'text/app_strings.dart';
import '../models/timeline_coverage.dart' show TimelineBlockEdge;
import '../models/se_name_tag.dart' show SeNameTag;
import 'timeline/se_name_tag_lane_policy.dart' show laneIsSeNameTag;
import 'timeline/se_name_tag_lane_editing.dart'
    show seNameTagWithLaneKeyToggled, seNameTagWithLaneValueEdited;
import 'timeline/layer_rail_window.dart' show LayerRailExtent;
import 'timeline/effect_lane_editing.dart';
import 'timeline/effect_lane_policy.dart';
import 'timeline/property_lane_model.dart';
import 'timeline/timeline_lane_provider.dart';
import 'timeline/layer_row_drag.dart'
    show
        EffectRowSubject,
        LayerRowDragSubject,
        LayerRowSubject,
        TimelineRowDragHooks,
        TrackRowSubject;
import 'timeline/timeline_cel_content_source.dart';
import 'timeline/timeline_current_row.dart';
import 'timeline/timeline_cut_end_handle.dart';
import 'timeline/timeline_frame_rows_scroll_body.dart' show TimelineRowMemoAux;
import 'timeline/se_audio_lane.dart';
import 'timeline/instance_editor_commands.dart';
import 'timeline/layer_name_commands.dart';
import 'timeline/timeline_action_toolbar.dart';
import 'timeline/toolbar_panel_context.dart';
import 'timeline/timeline_frame_range_gesture.dart';
import 'timeline/timeline_run_end_handles.dart';
import 'timeline/timeline_exposure_comma_drag_policy.dart';
import 'timeline/timeline_orientation.dart';
import 'timeline/timeline_panel.dart';
import 'timeline/timeline_layer_controls_header.dart' show LayerLegendCallbacks;
import 'timeline/timeline_row_filter.dart';
import 'timeline/timeline_section_policy.dart';
import 'timeline/transform_lane_editing.dart';
import 'timeline/transform_lane_policy.dart';

/// The Timeline tab's content: the timeline panel with its transport, cell
/// action toolbar and the layer/frame dialogs it triggers. All wiring lives
/// HERE (not in HomePage) so parallel work on other panels stays in other
/// files.
class TimelineTabHost extends StatefulWidget {
  const TimelineTabHost({
    super.key,
    required this.session,
    this.onPlaceMediaAsset,
    required this.orientation,
    required this.onOrientationChanged,
    required this.pixelsPerFrame,
    this.pixelsPerFrameListenable,
    required this.onPixelsPerFrameChanged,
    required this.showSeconds,
    required this.onShowSecondsChanged,
    this.timelineRailExtent,
    this.xsheetRailExtent,
    this.expandedLaneLayerIds = const {},
    this.onToggleLayerLanes,
    this.expandedLaneGroupKeys = const {},
    this.onToggleLaneGroupKey,
    this.hiddenSections = const {},
    this.onToggleSection,
    this.rowFilter = TimelineRowFilter.none,
    this.onSetRowFilter,
    this.collapsedAttachBaseIds = const {},
    this.onToggleAttachGroup,
    this.cameraViewEnabled,
    this.cameraDimOpacity,
    this.onRevealOnionSkinPanel,
  });

  final EditorSessionManager session;

  /// A media-browser row dropped on a drawing layer — the host opens the
  /// place window with the drop's answers filled in. Null leaves the rows
  /// refusing the drag, which is what a surface with nowhere to open a
  /// window should do.
  final void Function(LayerId layerId, int frameIndex, String path)?
  onPlaceMediaAsset;
  final TimelineOrientation orientation;
  final ValueChanged<TimelineOrientation> onOrientationChanged;
  final double pixelsPerFrame;

  /// Zoom scoping (UI-R6 #4): when provided, ONLY the panel subtree
  /// rebuilds per zoom step (the workspace shell and this host's build
  /// stay out of the loop). [pixelsPerFrame] is the fallback for hosts
  /// without the notifier.
  final ValueListenable<double>? pixelsPerFrameListenable;
  final ValueChanged<double> onPixelsPerFrameChanged;
  final bool showSeconds;
  final ValueChanged<bool> onShowSecondsChanged;

  /// The two grids' rail window sizes (workspace-owned so they survive a
  /// tab switch AND a restart).
  final LayerRailExtent? timelineRailExtent;
  final LayerRailExtent? xsheetRailExtent;

  /// AE-style property-lane twirl-down state (host-owned so it survives
  /// tab switches).
  final Set<LayerId> expandedLaneLayerIds;
  final ValueChanged<LayerId>? onToggleLayerLanes;

  /// LANE GROUPS twirled open (AE group collapse — default collapsed;
  /// host-owned so the state survives tab switches). Keyed by
  /// [laneGroupKey]: a row carries the Transform group AND one header per
  /// R6 effect, so the key has to name the group, not just the row.
  final Set<String> expandedLaneGroupKeys;
  final ValueChanged<String>? onToggleLaneGroupKey;

  /// SE/camera section visibility (host-owned, survives tab switches):
  /// hidden sections render no rows; the toolbar buttons toggle them.
  final Set<TimelineSection> hiddenSections;
  final ValueChanged<TimelineSection>? onToggleSection;

  /// The rail's row filter (host-owned, survives tab switches): hides
  /// layer rows failing its predicate. Null [onSetRowFilter] hides the
  /// filter UI.
  final TimelineRowFilter rowFilter;
  final ValueChanged<TimelineRowFilter>? onSetRowFilter;

  /// The attach-group fold state (UI-R20 #9, workspace-owned so it
  /// survives tab switches): bases listed here render no attach rows; the
  /// base row's chevron toggles them. Null [onToggleAttachGroup] hides
  /// the twirl UI.
  final Set<LayerId> collapsedAttachBaseIds;
  final ValueChanged<LayerId>? onToggleAttachGroup;

  /// Unified layer controls: the CAMERA row's visibility button and opacity
  /// slider drive the camera-view overlay state (workspace-owned notifiers,
  /// shared with the canvas and the camera panel). Null keeps the camera
  /// row's controls on the plain layer flags.
  final ValueNotifier<bool>? cameraViewEnabled;
  final ValueNotifier<double>? cameraDimOpacity;

  /// The workspace's onion-panel reveal (UI-R17 #5): open when hidden,
  /// flash-in-place when already open. Null hides the legend entry.
  final VoidCallback? onRevealOnionSkinPanel;

  @override
  State<TimelineTabHost> createState() => _TimelineTabHostState();
}

class _TimelineTabHostState extends State<TimelineTabHost> {
  EditorSessionManager get _session => widget.session;

  /// The frame cursor the panel's cursor-driven widgets subscribe to
  /// (playhead, rulers, lane values, frame counter). Playback ticks and
  /// editing seeks land HERE — never as a panel rebuild; that is the whole
  /// playback-performance architecture.
  late final ValueNotifier<int> _frameCursor = ValueNotifier<int>(
    _session.currentFrameIndex,
  );

  /// Everything that can change whether a frame reads as CACHED: frames
  /// warming in, and pixel edits invalidating composites. The rulers' green
  /// bar re-reads on this instead of comparing a token — cached-ness is
  /// derived state (composites self-validate by signature), so there is no
  /// token to compare. Built once: a fresh merge per build would make the
  /// painters re-subscribe on every rebuild.
  /// R26 #44: the unworked-block tint's fact and its event, bound once —
  /// a fresh bundle per build would re-subscribe the row painters on every
  /// pass and defeat their repaint gating.
  late final TimelineCelContentSource _celContent = TimelineCelContentSource(
    hasContent: _session.celHasContentForLayer,
    revision: _session.celTintRevision,
  );

  late final Listenable _frameReadySignal = Listenable.merge([
    _session.prerenderScheduler.progress,
    _session.brushFrameStore.celPixelRevision,
  ]);

  void _syncFrameCursor() {
    final playbackGlobalFrame =
        _session.playback.globalFrameIndexListenable.value;
    _frameCursor.value = playbackGlobalFrame == null
        ? _session.currentFrameIndex
        : _session.playback.position?.localFrameIndex ??
              _session.currentFrameIndex;
  }

  @override
  void initState() {
    super.initState();
    _session.playback.globalFrameIndexListenable.addListener(_syncFrameCursor);
    // Scrub moves fire the editing cursor WITHOUT a session notify — this
    // listener is what keeps the playhead glued to the pointer.
    _session.editingFrameCursor.addListener(_syncFrameCursor);
    _session.addListener(_syncFrameCursor);
  }

  @override
  void dispose() {
    _session.playback.globalFrameIndexListenable.removeListener(
      _syncFrameCursor,
    );
    _session.editingFrameCursor.removeListener(_syncFrameCursor);
    _session.removeListener(_syncFrameCursor);
    _frameCursor.dispose();
    super.dispose();
  }

  /// Every kind's twirl-down lanes — the SAME AE Transform lanes on truly
  /// every layer (unified layer controls): the camera rides the cut camera
  /// track, every other kind its own layer track (applied at composite
  /// time; SE transforms move the canvas dialogue, instruction transforms
  /// are authored state for parity). SE layers append their audio lane.
  /// R26 #3: maps a lane select-drag's cross-row delta onto the layer's
  /// DISPLAYED lane list (the same one the grids render) and returns the
  /// A plain tap on a property band: STAND there (R10).
  ///
  /// The user's rule when this was settled: wherever frame cells exist the
  /// playhead can be put, with no exceptions — and a lane band was the one
  /// place with visible cells that refused it, because the seek lived on
  /// the cell WIDGET and a band paints its cells.
  ///
  /// It still takes the lane's owner as the ACTIVE layer, but that no
  /// longer means you can draw (2026-08-08). Standing on a property is
  /// standing on a property; the canvas refuses strokes until you step
  /// back onto a row that is a surface. The active layer is what you
  /// return TO — pressing the layer's own row is one tap away.
  /// T4: through [EditorSessionManager.standOnRow], which is where 「어떤
  /// 행이든 액티브 바꾸면 선택이 풀린다」 lives now. This used to clear the
  /// LANE selection alone and reach for the session directly, so standing on
  /// a property row left a cell or row selection standing — 유저 2026-08-13:
  /// 「트랜스폼 멤버 행 액티브로하면 안풀림」.
  void _standOnLane(LayerId layerId, String laneId, int frameIndex) {
    _session.standOnRow(
      LaneRowAddress(layerId, laneId),
      frameIndex: frameIndex,
    );
  }

  /// T5: what a row drag's subject is CALLED in the selection's own words.
  ///
  /// The two vocabularies existed side by side — the drag names a subject,
  /// the selection names an address — and the seam between them was where
  /// 「이 종류는 선택 못 함」 hid. Naming every subject makes the question
  /// disappear rather than answering it per kind.
  ///
  /// An fx header's address is its GROUP LANE, which is what the rail already
  /// draws it as; nothing new is invented here.
  TimelineRowAddress _addressOfDragSubject(LayerRowDragSubject subject) =>
      switch (subject) {
        LayerRowSubject(:final layerId) => LayerRowAddress(layerId),
        EffectRowSubject(:final layerId, :final effectId) => LaneRowAddress(
          layerId,
          effectGroupLaneId(effectId),
        ),
        TrackRowSubject(:final trackId) => TrackRowAddress(trackId),
      };

  /// The LABEL half of the same rule: pressing a lane's name stands on it,
  /// exactly as the layer row's name selects its layer. No seek — a label
  /// names a ROW, and the frame stays where it was.
  void _standOnLaneRow(LayerId layerId, String laneId) {
    _session.standOnRow(LaneRowAddress(layerId, laneId));
  }

  /// Where a lane span ENDS — the rail's own row list, sliced.
  ///
  /// 🚨T13: the whitelist that used to live here (transform members and
  /// effect parameters only, everything else "crossed silently") is gone, and
  /// with it the private policy — see [resolveLaneSpanHead], which says why
  /// and is a pure function so the rule can be read without a widget around
  /// it. This is now only the part that is genuinely the host's: which lanes
  /// this layer is DRAWING.
  String? _laneSpanHeadLane(
    LayerId layerId,
    String anchorLaneId,
    int rowDelta,
  ) {
    final layer = _session.layers
        .where((candidate) => candidate.id == layerId)
        .firstOrNull;
    if (layer == null) {
      return null;
    }
    return resolveLaneSpanHead(
      lanes: _lanesForLayer(layer),
      anchorLaneId: anchorLaneId,
      rowDelta: rowDelta,
    );
  }

  /// R10 moved the lane list out to [timelineLanesForLayer] — the ↑/↓ row
  /// nav needs the same answer, and a second copy would have drifted from
  /// what the grids draw.
  List<PropertyLaneRow> _lanesForLayer(Layer layer) => timelineLanesForLayer(
    layer: layer,
    session: _session,
    expandedGroupKeys: widget.expandedLaneGroupKeys,
  );

  /// The track a layer's transform lanes edit: the camera rides the cut's
  /// camera track, every other kind its own layer track.
  TransformTrack _laneTrackOf(Layer layer) => layer.kind == LayerKind.camera
      ? _session.requireActiveCut.camera.track
      : layer.transformTrack;

  /// Commits an edited transform track as one undo step, dispatched by
  /// kind (camera → cut camera, drawing layers → the layer's own track).
  void _commitLaneEdit(Layer layer, TransformTrack? next, String description) {
    if (next == null) {
      return;
    }
    // Track-owned SE rows edit a cut-LOCAL clone of a GLOBAL layer, so the
    // edited track goes back through the window before it lands (R5 #8).
    // This used to stand down entirely — the row showed lanes and refused
    // every key, which is the bug the user reported.
    if (_session.isTrackSeLayerId(layer.id)) {
      _session.updateLayerTransformTrack(
        layer.id,
        _session.trackSeWindow.globalTransformTrack(next),
        description: description,
      );
      return;
    }
    if (layer.kind == LayerKind.camera) {
      _session.updateActiveCutCameraTrack(next, description: description);
      return;
    }
    _session.updateLayerTransformTrack(
      layer.id,
      next,
      description: description,
    );
  }

  // A folder's FX lanes used to need their own routing here: the lane id
  // carried a `folder-fx:<folderId>` ADDRESS because the carrier layer on
  // those rows was only a representative member, and the commit had to
  // reach a folder table the layer path could not see. A folder is a layer
  // now — the carrier IS the folder, so every lane edit below takes the
  // one path.

  /// Commits an edited EFFECT CHAIN as one undo step (R6).
  ///
  /// A NAME TAG lane edit (R5 #7) — one undo, through the session's own
  /// verb so the cut-window conversion happens in exactly one place.
  void _commitSeNameTagLaneEdit(
    Layer layer,
    SeNameTag? next,
    String description,
  ) {
    if (next == null) {
      return;
    }
    _session.setSeNameTagForLayer(layer.id, next);
  }

  /// Track-owned SE rows convert through the cut window for the same
  /// reason their transform lanes do (R5 #8) — the chain the row showed is
  /// cut-local, and the layer it lands on is global.
  void _commitEffectLaneEdit(
    Layer layer,
    List<LayerEffect>? next,
    String description,
  ) {
    if (next == null) {
      return;
    }
    _session.updateLayerEffects(
      layer.id,
      _session.isTrackSeLayerId(layer.id)
          ? _session.trackSeWindow.globalEffects(next)
          : next,
      description: description,
    );
  }

  PropertyLaneEditCallbacks get _laneEdit => PropertyLaneEditCallbacks(
    onToggleKeyAt: (layer, lane, frameIndex) {
      // R5 #7: the name tag is a fixed FIELD on the row, so it commits
      // through its own verb — not the transform track, not the chain.
      if (laneIsSeNameTag(lane.laneId)) {
        _commitSeNameTagLaneEdit(
          layer,
          seNameTagWithLaneKeyToggled(
            layer.seNameTag ?? const SeNameTag(),
            laneId: lane.laneId,
            frameIndex: frameIndex,
          ),
          '${lane.label} keyframe at frame ${frameIndex + 1}',
        );
        return;
      }
      if (laneIsEffectLane(lane)) {
        _commitEffectLaneEdit(
          layer,
          effectsWithLaneKeyToggled(
            layer.effects,
            laneId: lane.laneId,
            frameIndex: frameIndex,
          ),
          '${lane.label} keyframe at frame ${frameIndex + 1}',
        );
        return;
      }
      final isCamera = layer.kind == LayerKind.camera;
      _commitLaneEdit(
        layer,
        transformTrackWithLaneKeyToggled(
          _laneTrackOf(layer),
          laneId: lane.laneId,
          frameIndex: frameIndex,
          // The navigator toggles at the playhead: freeze the property's
          // CURRENT resolved value there (AE behavior).
          resolvedPose: isCamera
              ? _session.cameraPoseAtCurrentFrame
              : _session.layerPoseAtFrame(layer, frameIndex),
          resolvedAnchorPoint: isCamera
              ? null
              : _session.layerAnchorPointAtFrame(layer, frameIndex),
          resolvedOpacity: isCamera
              ? 1
              : _session.layerOpacityAtFrame(layer, frameIndex),
        ),
        '${lane.label} keyframe at frame ${frameIndex + 1}',
      );
    },
    onSetValue: (layer, lane, frameIndex, input) {
      if (laneIsSeNameTag(lane.laneId)) {
        _commitSeNameTagLaneEdit(
          layer,
          seNameTagWithLaneValueEdited(
            layer.seNameTag ?? const SeNameTag(),
            laneId: lane.laneId,
            frameIndex: frameIndex,
            input: input,
          ),
          'Set ${lane.label} at frame ${frameIndex + 1}',
        );
        return;
      }
      // The SE audio lane's value field edits the playhead span's offset
      // trim instead of a transform property (one undo via the session).
      if (laneIsSeAudio(lane)) {
        final offset = parseAudioOffsetInput(input);
        final span = seAudioSpanForLaneValue(layer, frameIndex);
        if (offset == null || span == null) {
          return;
        }
        _session.setAudioClipOffset(layer.id, span.clipIndex, offset);
        return;
      }
      final description = 'Set ${lane.label} at frame ${frameIndex + 1}';
      if (laneIsEffectLane(lane)) {
        _commitEffectLaneEdit(
          layer,
          effectsWithLaneValueEdited(
            layer.effects,
            laneId: lane.laneId,
            frameIndex: frameIndex,
            input: input,
          ),
          description,
        );
        return;
      }
      _commitLaneEdit(
        layer,
        transformTrackWithLaneValueEdited(
          _laneTrackOf(layer),
          laneId: lane.laneId,
          frameIndex: frameIndex,
          input: input,
        ),
        description,
      );
    },
  );

  // ⛔The two LAYER dialogs left this host (2026-08-10): the layer pill is
  // mounted on the storyboard's bar too now, and nothing in either flow was
  // ever about the timeline. See [layer_name_commands.dart].

  // ⛔THE INSTANCE EDITOR left this host (2026-08-11). Every flow it held —
  // the kind dispatch, the camera keys, the SE entry, the text cel, the
  // instruction event and its vocabulary editor, the frame rename and the
  // lane-key rename — is [instance_editor_commands.dart] now, because the
  // storyboard's bar carries the same `Edit Instance` entry and had to grey
  // it out for want of a way to reach them. Nothing in the dispatch was ever
  // about the timeline; the one thing a host still decides is the preview
  // axis, and it passes that.

  /// Toolbar 'Add' — kind-dispatched creation. NO dialogs anywhere
  /// (UI-R25 #2, 조작 통일화): SE/instruction create a DEFAULT instance
  /// directly — the Edit Instance button / double-tap edits it after.
  /// A live selection fills the WHOLE selection instead (UI-R25 #3):
  /// anywhere selectable creates — drawing gaps, SE gaps, instruction
  /// gaps, camera keys, lane keys.
  void _createActiveInstance() => createActiveInstance(_session);

  /// The preview inside the instance dialogs follows the visible
  /// orientation (Axis policy in miniature).
  Axis get _previewAxis => widget.orientation == TimelineOrientation.horizontal
      ? Axis.horizontal
      : Axis.vertical;

  Future<void> _activateCellEditor(LayerId layerId, int frameIndex) =>
      activateCellEditor(
        context,
        _session,
        layerId: layerId,
        frameIndex: frameIndex,
        previewAxis: _previewAxis,
      );

  /// 🚨T25 — the SELECTION's instance, not the playhead's.
  ///
  /// The button moved to the shared pill, so its subject moved with it:
  /// 「인스턴스 편집 버튼도 공통버튼으로 이동. 그래서 **선택범위 통해
  /// 동사통일화** 가능하게」. `editSelectionInstance` walks delete's ladder
  /// and falls through to the playhead's cell when nothing is selected,
  /// which is what this used to do unconditionally.
  Future<void> _editActiveInstance() =>
      editSelectionInstance(context, _session, previewAxis: _previewAxis);

  /// The end-line drag's session hooks (UI-R18 #14): the boundary grip
  /// end-trims the ACTIVE cut through the storyboard's trim channel.
  /// Null while no cut is active (gap parking) — the line stays static.
  TimelineCutEndDragCallbacks? _cutEndDragCallbacks() {
    final cutId = _session.activeCutId;
    if (cutId == null) {
      return null;
    }
    return TimelineCutEndDragCallbacks(
      cutId: cutId,
      onBegin: () =>
          _session.beginCutEdgeDrag(cutId: cutId, edge: TimelineBlockEdge.end),
      onUpdate: _session.updateCutEdgeDrag,
      onEnd: _session.endCutEdgeDrag,
      onCancel: _session.cancelCutEdgeDrag,
    );
  }

  /// Camera display-copy cache (UI-R20 #4): the per-build copyWith used
  /// to churn the camera layer's identity on EVERY host rebuild, so the
  /// camera row (rail + cells) missed its identity memos and rebuilt per
  /// session notify. Same source + same overlay state = the SAME copy.
  Layer? _cameraCopySource;
  bool? _cameraCopyVisible;
  Layer? _cameraCopy;

  Layer _cameraDisplayLayer(Layer layer, bool visible) {
    if (identical(_cameraCopySource, layer) && _cameraCopyVisible == visible) {
      return _cameraCopy!;
    }
    final copy = layer.copyWith(isVisible: visible);
    _cameraCopySource = layer;
    _cameraCopyVisible = visible;
    _cameraCopy = copy;
    return copy;
  }

  /// R27 #9: the camera row's opacity source. The dim is a VIEW notifier,
  /// so the slider subscribes to it directly instead of the value riding
  /// a display-copy through a host rebuild — a drag now repaints one
  /// slider, not the whole timeline (the "카메라레이어 불투명도 너무 느림"
  /// report). Every other row keeps its model opacity.
  ValueListenable<double>? _cameraDimOverrideFor(LayerId layerId) {
    final dim = widget.cameraDimOpacity;
    if (dim == null || _kindOf(layerId) != LayerKind.camera) {
      return null;
    }
    return dim;
  }

  /// Layers as DISPLAYED (unified layer controls): the camera row mirrors
  /// the camera-view overlay state on its visibility icon — the same
  /// notifier the canvas and the camera panel share. The DIM is deliberately
  /// not folded in here (R27 #9): it reaches the slider through
  /// [_cameraDimOverrideFor], so a dim drag never invalidates this list.
  /// The layer stack as the GRIDS should render it — display clones for
  /// the rows whose cells are not their own.
  ///
  /// R10 puts the folder band here, which is the one seam both grids read:
  /// the X-sheet has always sent folder columns to the shared cells row
  /// and drawn them blank, so the clone lights that column with no X-sheet
  /// edit at all. Same rule the camera and SE clones live under — it never
  /// leaves the display path, because commands re-read the real layer by
  /// id.
  List<Layer> _displayLayers() {
    final view = widget.cameraViewEnabled;
    return [
      for (final layer in _session.layers)
        if (layerKindGroupsLayers(layer.kind))
          _session.folderBandLayerFor(layer)
        else if (view != null && layer.kind == LayerKind.camera)
          _cameraDisplayLayer(layer, view.value)
        else
          layer,
    ];
  }

  LayerKind? _kindOf(LayerId layerId) {
    for (final layer in _session.layers) {
      if (layer.id == layerId) {
        return layer.kind;
      }
    }
    return null;
  }

  void _toggleLayerVisibility(LayerId layerId) {
    final view = widget.cameraViewEnabled;
    if (view != null && _kindOf(layerId) == LayerKind.camera) {
      view.value = !view.value;
      return;
    }
    _session.toggleLayerVisibility(layerId);
  }

  // Opacity drags preview per move and commit ONE write on release
  // (R4 #4): the camera row's slider is the camera-view dim notifier —
  // already cheap and live, so it applies on both hooks.
  void _previewLayerOpacity(LayerId layerId, double opacity) {
    final dim = widget.cameraDimOpacity;
    if (dim != null && _kindOf(layerId) == LayerKind.camera) {
      dim.value = opacity;
      return;
    }
    _session.previewLayerOpacity(layerId, opacity);
  }

  void _commitLayerOpacity(LayerId layerId, double opacity) {
    final dim = widget.cameraDimOpacity;
    if (dim != null && _kindOf(layerId) == LayerKind.camera) {
      dim.value = opacity;
      return;
    }
    _session.commitLayerOpacity(layerId, opacity);
  }

  @override
  Widget build(BuildContext context) {
    // Playback ticks flow into the frame cursor (see _syncFrameCursor) —
    // NEVER as a panel rebuild: only the cursor-driven widgets (playhead
    // layer, rulers, lane values, counter) subscribe, so the grids'
    // hundreds of cells stay untouched frame to frame. The prerender
    // progress listenable repaints the rulers' green bars the same way.
    // The camera-view notifiers keep the camera row's unified controls
    // live.
    //
    // Touching this panel makes it the one the frame-axis verbs answer to
    // (user, 2026-08-05). A row pick is no longer the only way to move the
    // flip's subject — working here at all is, which is what picking up a
    // panel actually feels like. Translucent so every child still gets its
    // own gesture; this only listens.
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => _session.claimTimelineRow(),
      child: ListenableBuilder(
        listenable: Listenable.merge([
          ?widget.cameraViewEnabled,
          // The camera DIM is NOT here (R27 #9): its slider subscribes to it
          // directly, so a drag repaints one control instead of the panel.
          // Live take preview (REC1-C): the armed SE lane swaps identity at
          // most once per FRAME while recording — this panel-scoped rebuild
          // is the notify-free channel (R12-B: ticks never notify the
          // session).
          _session.voiceRecordPreviewLane,
          // R27 #13: the empty-cel tint must clear the INSTANT a stroke
          // lands. Cel pixels live outside the Layer value, so nothing in
          // the ordinary notify path told this panel to look again — the
          // tint sat until an unrelated rebuild. Only EMPTY↔drawn crossings
          // bump this, so ordinary strokes cost nothing.
          _session.brushFrameStore.celContentRevision,
          // ⑨: the row selection grows PER POINTER MOVE inside a gesture,
          // which is exactly the contract the session's own notify does not
          // have (a drag is silent until release). Its notifier is the
          // channel, the same way the current row's is.
          _session.rowSelection,
        ]),
        builder: (context, _) {
          // Zoom scoping (UI-R6 #4): the toolbar widget is built ONCE per
          // host rebuild and reused across zoom steps — the identical
          // instance lets its transport + ~25 buttons skip rebuilding while
          // the ValueListenableBuilder below re-lays-out just the panel.
          final timelineToolbar = _buildTimelineToolbar();
          Widget buildPanel(
            BuildContext context,
            double pixelsPerFrame,
            Widget? child,
          ) => TimelinePanel(
            layers: _displayLayers(),
            activeLayerId: _session.activeLayerId,
            // #29: the (project, cut) world the rows' resolvers answer
            // from. Travels WITH the rebuild that carries the new cut's
            // rows — a setter could skew from what is on screen; a build
            // argument cannot.
            substrateGeneration:
                '${_session.repository.requireProject().id.value}'
                ':${_session.activeCutId?.value ?? '-'}',
            // ⑨: the rows the row verbs act on, banded on both surfaces.
            //
            // 🚨T1: ADDRESSES, not layer ids. T5 made every row kind
            // selectable, and a `Set<LayerId>` cannot spell a lane or an fx
            // header — the same shape of loss ③ found in the span itself.
            selectedRows: _session.rowSelection.value.toSet(),
            // Edit drags (comma/trim) preview through the scoped channel: a
            // step rebuilds the dragged row's gate + the cursor overlay only,
            // never this host (the release commit is the one session notify).
            dragPreview: _session.dragPreview,
            frameCursor: _frameCursor,
            frameReadySignal: _frameReadySignal,
            revealSelectionTick: _session.revealSelectionTick,
            isFrameReady: _session.isPlaybackFrameReady,
            playbackFrameCount: _session.activeCutPlaybackFrameCount,
            // The のりしろ: how far past the cut's end line it is DRAWN, and
            // the word the ruler spells across that. Same derivation the
            // sheet pages by, so the two cannot disagree.
            drawnFrameCount: _session.activeCutDrawnFrameCount,
            noriShiroLabel: _session.activeCutNoriShiroLabel,
            exposureStateForLayer: _session.exposureStateForLayer,
            frameNameForLayer: _session.frameNameForLayer,
            // R26 #44: ACTION-section blocks whose cel is still blank gray
            // their paper; the token keys the row memo (cel pixels live
            // outside the Layer value).
            celContent: _celContent,
            // A CLICK CLEARS (유저 확정) — and T4 moved that law OUT of this
            // wrapper into [EditorSessionManager.standOnRow], because a
            // wrapper only covers the doors that go through it. Standing on a
            // property lane went straight to the session and kept its
            // selection, and the next new door would have done the same.
            //
            // A claimed pan never reaches this callback, which is what keeps
            // the move-from-inside drag working.
            onSelectLayer: (layerId) =>
                _session.standOnRow(LayerRowAddress(layerId)),
            // Ruler scrubs during playback SEEK the playback clock instead of
            // moving the (hidden) editing playhead.
            onSelectFrame: (frameIndex) {
              if (_session.playback.isActive) {
                _session.playback.seekToLocalFrame(frameIndex);
              } else {
                _session.selectFrameIndex(frameIndex);
              }
            },
            // 🚨T10's second half (유저: 「클릭하고 떼면 뭐든 비우게」). The
            // press picks and may deliberately hold the selection — it could
            // be the start of a move — so something has to clear when the
            // press turns out to have been a tap. This is that something,
            // and it is the same verb for the cells and the rail rows.
            onSettledPress: _session.clearAllSelections,
            // Ruler drags: per-move seeks ride the cursor path (value-only —
            // the playhead and the canvas preview follow, nothing rebuilds);
            // the release commits the selection as ONE ordinary seek.
            onScrubFrame: (frameIndex) {
              if (_session.playback.isActive) {
                _session.playback.seekToLocalFrame(frameIndex);
              } else {
                _session.scrubFrameIndex(frameIndex);
              }
            },
            onScrubEnd: () {
              if (!_session.playback.isActive) {
                _session.commitFrameScrub();
              }
            },
            // End-line drag = cut length (UI-R18 #14): the boundary grip
            // end-trims the ACTIVE cut through the storyboard's trim
            // channel — live preview, ONE undo on release.
            cutEndDrag: _cutEndDragCallbacks(),
            // Sparse-row memo identities (UI-R20 #4): camera/instruction
            // rows re-enter the row memo, invalidated exactly by these.
            memoAux: TimelineRowMemoAux(
              cameraTrack: _session.activeCutOrNull?.camera.track,
              instructionDefs: _session.cameraInstructionSet,
            ),
            onActivateCell: _activateCellEditor,
            instructionDefById: (instructionId) =>
                _session.cameraInstructionSet.defById(instructionId),
            // D26: the crossing-fade refusal marker — this surface shows
            // the cut-local display clone, so the session answers by the
            // clone's PROJECTED keys. Always-on (a refusal warning takes
            // no settings gate).
            instructionCrossingTooltip:
                _session.transitionCrossingWarningInCutAt,
            // Display resolver: the live take's sentinel path maps to the
            // growing envelope (REC1-C), everything else to the conform
            // store's peaks.
            audioPeaksFor: _session.audioPeaksForDisplay,
            // The tooltip string doubles as the marker switch (REC1-D):
            // null while the clipping notice is off.
            seClipMarkerTooltip: _session.audioSyncSettings.value.clippingNotice
                ? _session.uiStrings.recordClipMarkerTooltip
                : null,
            // Everything the audio lane may ask of the session, bound once
            // here instead of threaded as six parameters through the panel
            // and both grids.
            //
            // The slide edit previews LOCALLY in the lane span (its own
            // painter, no session traffic per move) and commits ONE undo on
            // release — the repo-live drag session rebuilt every panel per
            // move and made the slide feel heavy (R5-⑧); the session drag
            // API stays for callers that need the cross-panel mirror.
            onDropMediaAssetOnLayer: widget.onPlaceMediaAsset,
            audioLane: TimelineAudioLaneCallbacks(
              // Media-browser drops: link the dragged sound to the block.
              onDropMediaAsset: (layerId, blockStartFrame, path) =>
                  _session.linkMediaAssetToSeBlock(
                    layerId: layerId,
                    blockStartFrame: blockStartFrame,
                    path: path,
                  ),
              onSetClipOffset: _session.setAudioClipOffset,
              onSetClipFades: (layerId, clipIndex, fadeIn, fadeOut) =>
                  _session.setAudioClipFades(
                    layerId,
                    clipIndex,
                    fadeInFrames: fadeIn,
                    fadeOutFrames: fadeOut,
                  ),
            ),
            onAddLayer: _session.addLayer,
            isLayerSoloed: (layerId) =>
                _session.soloedSeLayerIds.value.contains(layerId),
            onOpenLayerMixer: (anchorContext, layerId) => unawaited(
              showSeLayerMixer(
                anchorContext,
                session: _session,
                layerId: layerId,
              ),
            ),
            // Kind-dispatched (unified layer controls): the camera row drives
            // the camera-view notifiers, every other row the layer flags.
            onToggleLayerVisibility: _toggleLayerVisibility,
            onLayerOpacityChanged: _previewLayerOpacity,
            onLayerOpacityChangeEnd: _commitLayerOpacity,
            onToggleLayerTimesheet: _session.toggleLayerTimesheet,
            onToggleLayerFillReference: _session.toggleLayerFillReference,
            onLayerMarkSelected: _session.setLayerMark,
            // The AE-style fx MASTER over the row's per-group switches (R8:
            // model state, read straight off the layer).
            layerFxStateOf: _session.layerFxState,
            layerIsLinkedOf: _session.isLayerLinked,
            // Folder rows are layer rows: their eye, opacity, blend, fx
            // switch, FX lanes and selection all ride the layer hooks
            // already threaded above. Only the members' twirl lands here.
            onToggleLayerCollapsed: _session.toggleLayerCollapsed,
            onToggleLayerFx: _session.toggleLayerFx,
            // Per-layer onion skin (UI-R17 #5, TVPaint style).
            layerOnionSkinEnabledOf: _session.isLayerOnionSkinEnabled,
            onToggleLayerOnionSkin: _session.toggleLayerOnionSkin,
            displayedOnionSkinOn: _session.displayedLayersOnionSkinEnabled,
            // Comma edge drags preview live from the session's drag-start
            // snapshot and commit as ONE undo entry on release.
            commaDrag: TimelineCommaDragCallbacks(
              onBegin: (layerId, blockStartIndex, edge) =>
                  _session.beginExposureEdgeDrag(
                    layerId: layerId,
                    blockStartIndex: blockStartIndex,
                    edge: edge,
                  ),
              onUpdate: _session.updateExposureEdgeDrag,
              onEnd: _session.endExposureEdgeDrag,
              onCancel: _session.cancelExposureEdgeDrag,
            ),
            // TVP-style frame ranges (UI-R8): a cell drag SELECTS a range
            // (block-snapped), a drag starting inside the selection MOVES it
            // — the block-body immediate move's successor, same live-preview
            // + one-undo discipline.
            rangeHooks: TimelineFrameRangeHooks(
              selection: _session.frameRangeSelection,
              onSelectUpdate:
                  (
                    layerId,
                    anchorIndex,
                    headIndex, {
                    headLayerId,
                    headLaneId,
                    spanRows = const [],
                  }) => _session.updateFrameRangeSelectionDrag(
                    layerId: layerId,
                    anchorIndex: anchorIndex,
                    headIndex: headIndex,
                    headLayerId: headLayerId,
                    headLaneId: headLaneId,
                    spanRows: spanRows,
                  ),
              onClear: _session.clearFrameRangeSelection,
              move: TimelineRangeMoveCallbacks(
                onBegin: _session.beginFrameRangeMoveDrag,
                onUpdate: ({required frameDelta, targetLayerId}) =>
                    _session.updateFrameRangeMoveDrag(
                      frameDelta: frameDelta,
                      targetLayerId: targetLayerId,
                    ),
                onEnd: _session.endFrameRangeMoveDrag,
                onCancel: _session.cancelFrameRangeMoveDrag,
              ),
            ),
            // The LANE selection domain (UI-R23 #3 part 2; MULTI-LANE since
            // R26 #3): a lane-band pan selects lane rows — the cross-row
            // delta spans the layer's lane group like cells span layers,
            // the group header anchors the WHOLE group — and a pan inside
            // the selection moves every spanned lane's keys. Frame
            // selection ⊥ transform keys, mutually exclusive domains.
            laneRange: TimelineLaneRangeCallbacks(
              // This panel is a CUT's window. A track-owned SE row's span
              // is stated on the track's global axis, so what this rail
              // shows — and reads at press to pick its mode — is the part
              // of it that falls inside the window, on the window's own
              // numbers.
              selection: _session.cutLocalLaneRangeSelection,
              onSelectUpdate:
                  (layerId, laneId, anchorIndex, headIndex, headRowDelta) =>
                      _session.updateLaneRangeSelectionDrag(
                        layerId: layerId,
                        laneId: laneId,
                        anchorIndex: anchorIndex,
                        headIndex: headIndex,
                        headLaneId: _laneSpanHeadLane(
                          layerId,
                          laneId,
                          headRowDelta,
                        ),
                      ),
              onTapAt: _standOnLane,
              onMoveBegin: _session.beginLaneRangeMoveDrag,
              onMoveUpdate: (frameDelta) =>
                  _session.updateLaneRangeMoveDrag(frameDelta: frameDelta),
              onMoveEnd: _session.endLaneRangeMoveDrag,
              onMoveCancel: _session.cancelLaneRangeMoveDrag,
            ),
            // R10 #19's rail half: the row you are standing on is DRAWN,
            // and a lane's label is a place you can stand.
            currentRowHooks: TimelineCurrentRowHooks(
              currentRow: _session.currentRowListenable,
              onStandOnLane: _standOnLaneRow,
            ),
            // P2b: the rail row IS the handle. Pen and mouse move it; a
            // finger scrolls, because the rail scrolls along the very axis
            // this drag runs.
            rowDragHooks: TimelineRowDragHooks(
              drag: _session.layerRowDrag,
              onBegin: _session.beginLayerRowDrag,
              onUpdate: _session.updateLayerRowDrag,
              onRowTarget: _session.updateLayerRowDropOnRow,
              onEffectUpdate: _session.updateEffectRowDrag,
              onEnd: _session.endLayerRowDrag,
              onCancel: _session.cancelLayerRowDrag,
              // ⑨: the first drag SELECTS, and a drag that starts INSIDE the
              // selection moves it — the cells' grammar, transposed.
              //
              // 🚨T5 (유저 2026-08-13): 「모든 셀은 선택범위 자유롭게 규칙없이
              // 가능하듯이 **모든 행은 자유롭게 규칙없이 선택가능.** 지금 fx랑
              // fx멤버가 선택범위 안됨」 — and on the fx header's chain drag
              // specifically: 「셀과 같은문법으로 통일」.
              //
              // ⛔The old answer here was `null` for every subject that is not
              // a layer row, which this file called "not a row selection's
              // business". That was a KIND deciding whether a row may be
              // selected, and the whole of ③/⑨'s law is that kind decides
              // what an edit DOES, never whether the row can be named.
              //
              // The chain drag is not lost by this: it is the second phase
              // now, exactly as a layer row's move is. Start outside the
              // selection and the drag selects; start inside it and the drag
              // re-orders the chain.
              isInRowSelection: (subject) =>
                  _session.rowIsSelected(_addressOfDragSubject(subject)),
              onSelectBegin: (subject) => _session.beginRowSelection(
                _addressOfDragSubject(subject),
              ),
              onSelectEnd: _session.endRowSelection,
            ),
            onRowSelectionSpan: _session.updateRowSelection,
            // The TVP run-edge cluster (UI-R9 #10): [+] drags new one-frame
            // drawings onto a run; the property tag sets the edge's
            // None/Hold/Repeat mode (ghosts fill to the cut boundary).
            runEdit: TimelineRunEditCallbacks(
              onAddBegin: (layerId, blockStartIndex, {required atEnd}) =>
                  _session.beginRunFramesAddDrag(
                    layerId: layerId,
                    blockStartIndex: blockStartIndex,
                    atEnd: atEnd,
                  ),
              onAddUpdate: _session.updateRunFramesAddDrag,
              onAddEnd: _session.endRunFramesAddDrag,
              onAddCancel: _session.cancelRunFramesAddDrag,
              onEdgeModeSelected:
                  (
                    layerId,
                    blockStartIndex,
                    side,
                    mode, {
                    scopeToSelection = false,
                  }) => _session.setRunEdgeBehavior(
                    layerId: layerId,
                    blockStartIndex: blockStartIndex,
                    side: side,
                    mode: mode,
                    scopeToSelection: scopeToSelection,
                  ),
              // The flyout's "Repeat selection" entry gates on this
              // (UI-R19 #2).
              canScopeToSelection: (layerId, blockStartIndex, side) =>
                  _session.canScopeRepeatToSelection(
                    layerId: layerId,
                    blockStartIndex: blockStartIndex,
                    side: side,
                  ),
            ),
            orientation: widget.orientation,
            onOrientationChanged: widget.onOrientationChanged,
            pixelsPerFrame: pixelsPerFrame,
            onPixelsPerFrameChanged: widget.onPixelsPerFrameChanged,
            showSeconds: widget.showSeconds,
            onShowSecondsChanged: widget.onShowSecondsChanged,
            timelineRailExtent: widget.timelineRailExtent,
            xsheetRailExtent: widget.xsheetRailExtent,
            projectFrameRate: _session.projectFrameRate,
            expandedLaneLayerIds: widget.expandedLaneLayerIds,
            onToggleLayerLanes: widget.onToggleLayerLanes,
            hiddenSections: widget.hiddenSections,
            onToggleSection: widget.onToggleSection,
            rowFilter: widget.rowFilter,
            onSetRowFilter: widget.onSetRowFilter,
            collapsedAttachBaseIds: widget.collapsedAttachBaseIds,
            onToggleAttachGroup: widget.onToggleAttachGroup,
            visibilitySoloEnabled: _session.layerVisibilitySoloEnabled,
            // Master-bar drags (UI-R6 #2): rows' sliders follow the preview
            // channel live; at rest the bar shows the last committed value.
            opacityDragPreview: _session.opacityDragPreview,
            masterOpacityValue: _session.lastMasterOpacity,
            // R27 #6: the blend mode reads and commits from the LABEL now.
            onLayerBlendModeSelected: _session.setLayerBlendMode,
            blendLanguage: _session.languageSettings.value.programLanguage,
            // R27 #9: the camera row's opacity IS the camera-view dim
            // notifier — handing it to the slider keeps a drag off the host.
            layerOpacityOverrideOf: _cameraDimOverrideFor,
            // Sounds carrying over from the previous cut (UI-R7 #6): the
            // cut start draws `~` and the spill block's start grip stands
            // down.
            seSpillInLayerIds: _session.trackSeSpillInLayerIds,
            // The rail legend's bulk sweeps + the section brackets' flyout —
            // all session-backed (R-toolbar round); the R2 filter/dim/opacity
            // facets ride the same struct.
            legend: LayerLegendCallbacks(
              onShowAllLayers: () => _session.setAllLayersVisibility(true),
              onHideAllLayers: () => _session.setAllLayersVisibility(false),
              onToggleVisibilitySolo: _session.toggleLayerVisibilitySolo,
              // Onion legend (UI-R17 #5): displayed-layer bulk + the panel
              // reveal (already open = flash-in-place).
              onToggleOnionSkinForDisplayed:
                  _session.toggleOnionSkinForDisplayedLayers,
              onRevealOnionSkinPanel: widget.onRevealOnionSkinPanel,
              onSheetAllOn: () => _session.setAllLayersOnTimesheet(true),
              onSheetAllOff: () => _session.setAllLayersOnTimesheet(false),
              onClearAllMarks: _session.clearAllLayerMarks,
              onClearAllFillReferences: _session.clearAllFillReferences,
              onMuteAllSe: () => _session.setAllSeLayersMuted(true),
              onUnmuteAllSe: () => _session.setAllSeLayersMuted(false),
              onBypassAllFx: () => _session.setAllLayersFxBypassed(true),
              onEnableAllFx: () => _session.setAllLayersFxBypassed(false),
              onToggleMarkFilter: (mark) => widget.onSetRowFilter?.call(
                widget.rowFilter.toggledMark(mark),
              ),
              onToggleKindFilter: (kind) => widget.onSetRowFilter?.call(
                widget.rowFilter.toggledKind(kind),
              ),
              onToggleSheetOnlyFilter: () => widget.onSetRowFilter?.call(
                widget.rowFilter.copyWith(
                  onTimesheetOnly: !widget.rowFilter.onTimesheetOnly,
                ),
              ),
              onToggleFxOnlyFilter: () => widget.onSetRowFilter?.call(
                widget.rowFilter.copyWith(fxOnly: !widget.rowFilter.fxOnly),
              ),
              onToggleFillReferenceOnlyFilter: () =>
                  widget.onSetRowFilter?.call(
                    widget.rowFilter.copyWith(
                      fillReferenceOnly: !widget.rowFilter.fillReferenceOnly,
                    ),
                  ),
              // The legend master bar (R4 #6): preview per move, one commit.
              onPreviewLayersOpacity: _session.previewLayersOpacity,
              onCommitLayersOpacity: _session.commitLayersOpacity,
              // R27 #6: the blend column's bulk pick, same displayed set.
              onSetBlendModeForDisplayed: _session.setBlendModeForLayers,
            ),
            lanesForLayer: _lanesForLayer,
            // The CAMERA row's union summary (B4): the shared
            // transform-header union lane, re-derived per row rebuild from
            // the session's preview-aware camera track.
            unionLaneForLayer: (layer) =>
                timelineCameraUnionLane(layer: layer, session: _session),
            laneEdit: _laneEdit,
            // A group header's twirl (AE collapse) — Transform or one of the
            // row's effects, told apart by the lane the tap carries.
            onToggleLaneGroup: widget.onToggleLaneGroupKey == null
                ? null
                : (layer, lane) => widget.onToggleLaneGroupKey!(
                    laneGroupKey(layer.id, lane.laneId),
                  ),
            // R6: the per-effect eyeball on an effect's header row. One undo
            // step through the ordinary effect-chain commit.
            onToggleLaneGroupEnabled: (layer, lane) {
              // R8: the Transform group's switch is the layer's own field.
              if (lane.laneId == transformGroupHeaderLane.laneId) {
                _session.toggleLayerTransformFx(layer.id);
                return;
              }
              final effectId = parseEffectLaneId(lane.laneId)?.effectId;
              if (effectId == null) {
                return;
              }
              _commitEffectLaneEdit(
                layer,
                effectsWithEnabledToggled(layer.effects, effectId),
                'Toggle ${lane.label}',
              );
            },
            // R5: AE's group Reset. The session owns the scope rule (the
            // playhead, or a live lane range's keys) so both grids and the
            // storyboard ask the same question.
            onResetLaneGroup: (layer, lane) =>
                _session.resetLaneGroup(layer.id, lane.laneId),
            timelineActionToolbar: timelineToolbar,
          );
          // The GAP empty state (UI-R9 #3): no cut selected — no rows, no
          // grid; the toolbar stays (its cut-scoped commands disable via
          // their own enablement gates).
          if (_session.activeCutOrNull == null) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 🚨The SAME overflow scroller [TimelineCommandBar] gives
                // its leading (유저 2026-08-10: 「버튼 사라지기 시작하면
                // 생기는 스크롤바」). This state is the one place the toolbar
                // is mounted WITHOUT that bar, so it was the one place a bar
                // too wide for the window overflowed instead of scrolling —
                // and it only showed once ㉕ put three more buttons on it,
                // which is to say the row had been one button from the edge
                // for a while.
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: timelineToolbar,
                ),
                Expanded(
                  child: Center(
                    child: ValueListenableBuilder(
                      valueListenable: _session.languageSettings,
                      builder: (context, settings, _) => Text(
                        AppStrings.of(settings.programLanguage).noCutSelected,
                        key: const ValueKey<String>('timeline-empty-no-cut'),
                      ),
                    ),
                  ),
                ),
              ],
            );
          }
          final zoom = widget.pixelsPerFrameListenable;
          if (zoom == null) {
            return buildPanel(context, widget.pixelsPerFrame, null);
          }
          return ValueListenableBuilder<double>(
            valueListenable: zoom,
            builder: buildPanel,
          );
        },
      ),
    );
  }

  /// Button enablement reads the playhead, and committed seeks are no
  /// longer session notifies — the toolbar re-reads them here without
  /// the panel (or its grids) rebuilding. TOKEN-GATED (R13-2): the
  /// naive per-seek rebuild reconstructed the whole transport + ~25
  /// Material buttons on every frame flip — measured on device as
  /// the flip hitch. Seeks that land in the same enablement state
  /// (almost all of them) now rebuild nothing.
  Widget _buildTimelineToolbar() {
    return _SeekGatedTimelineToolbar(
      session: _session,
      hiddenSections: widget.hiddenSections,
      // ⛔The TRANSPORT and the camera-view toggle left this bar (유저 확정,
      // 2026-08-10). They are the 문턱's now — see [FramePanelSillControls],
      // mounted by the workspace through `EditorPanelTab.sillTrailing` —
      // because the sill's right edge is the one place in this region that
      // does not move when a panel is added. What is left here is what
      // reaches into THIS panel's own contents.
      actionsBuilder: (context) => TimelineActionToolbar(
        session: _session,
        // B8: this panel's dispatch context — the session's cut-local
        // verbs, verbatim (the baseline the storyboard's own context
        // diverges from).
        panelContext: TimelineToolbarPanelContext(_session),
        onAddLayer: _session.addLayer,
        onRenameLayer: () =>
            unawaited(renameActiveLayerWithDialog(context, _session)),
        onDeleteLayer: () =>
            unawaited(deleteActiveLayerWithDialog(context, _session)),
        // F: the shared delete's ROW rung keeps the confirmation the loose
        // layer button used to carry.
        onDeleteRowSelection: () =>
            unawaited(deleteRowSelectionWithDialog(context, _session)),
        onEditInstance: _editActiveInstance,
        onCreateInstance: _createActiveInstance,
        hiddenSections: widget.hiddenSections,
        onToggleSection: widget.onToggleSection,
      ),
    );
  }
}

/// Caches the timeline's action toolbar and rebuilds it ONLY when what its
/// buttons SHOW changes — for BOTH a committed seek AND a session notify
/// (the host rebuild). The bar reconstructs ~20 Material buttons; the
/// scoped-notify measurement put that at a large, row-independent share of
/// every notify, even though a layer-select or a far-away cell edit changes
/// nothing it renders.
///
/// ⛔It used to gate TWO groups on two tokens, because the playback transport
/// lived on this bar and read disjoint state from the action buttons. The
/// transport moved to the 문턱 (2026-08-10) and the workspace mounts it
/// there, so the second group — and the whole reason for two tokens — went
/// with it. The measurement that justified the split still stands; it just
/// describes a bar this one no longer is.
///
/// The token holds every value the toolbar's DIRECTLY-rendered widgets read.
/// One kind of state is deliberately absent: flyout menu contents (Cut /
/// Layer / Frame / FX entries) are built by `entriesBuilder` at OPEN time,
/// so they always read fresh.
///
/// COMPLETENESS CONTRACT: any NEW directly-rendered value (an enablement, a
/// shown label, a lit indicator read as a plain value) MUST join
/// [_deriveActionsToken] — otherwise a notify that changes only that value
/// leaves a stale button. And if its source does not travel through a host
/// rebuild or a committed seek, it needs a listener here too (as the
/// language settings do). playhead_rebuild_guard_test.dart drives one
/// mutation per dimension; a dimension added without a case there is
/// unguarded.
class _SeekGatedTimelineToolbar extends StatefulWidget {
  const _SeekGatedTimelineToolbar({
    required this.session,
    required this.actionsBuilder,
    required this.hiddenSections,
  });

  final EditorSessionManager session;

  /// The action toolbar (the four command pills): gated on
  /// [_SeekGatedTimelineToolbarState._deriveActionsToken].
  final WidgetBuilder actionsBuilder;

  /// Folds into the ACTIONS key: the Layer flyout's show/hide checkmarks read
  /// it (lazily), so a section toggle must drop the cached action toolbar.
  final Set<TimelineSection> hiddenSections;

  @override
  State<_SeekGatedTimelineToolbar> createState() =>
      _SeekGatedTimelineToolbarState();
}

class _SeekGatedTimelineToolbarState extends State<_SeekGatedTimelineToolbar> {
  // Initialized eagerly in initState — a `late … = _derive…Token()` field runs
  // its initializer on FIRST ACCESS, and the first access is the first
  // didUpdateWidget, which can coincide with the very notify that changed the
  // state (warming fires no session notify, so nothing accesses it earlier).
  // The token would then latch the NEW value and miss the change it exists to
  // catch.
  late Object _actionsToken;

  /// The last-built toolbar. Held across BOTH seeks and host rebuilds so a
  /// notify with an unchanged token reuses its widgets.
  Widget? _cachedActions;

  /// Every value the ACTION toolbar's directly-rendered widgets read. Split by
  /// the widget that consumes each so a future button's owner is obvious.
  ///
  /// Flyout entries are deliberately absent (they rebuild lazily on open).
  Object _deriveActionsToken() {
    final session = widget.session;
    return (
      // Frame-group icons + comma buttons (playhead-sensitive enablement).
      session.selectedFrame != null,
      session.canCreateDrawingAtCurrentFrame,
      session.canRenameFrameAtCurrentFrame,
      session.canBlankExposureAtCurrentFrame,
      session.canToggleMarkAtCurrentFrame,
      session.canCopyFrameAtCurrentFrame,
      session.canPasteLinkedFrameAtCurrentFrame,
      session.canDeleteCellAtCurrentFrame,
      session.canDecreaseSelectedExposure,
      session.canIncreaseSelectedExposure,
      session.canSetCommaForSelectionOrCurrent,
      // The Add button gates on the active layer's kind + cell state.
      // NOTE: these two move together with the can* getters above in every
      // reachable scenario, so the guard test cannot isolate them — they are
      // listed because the Add button genuinely reads them, not because a
      // test proves each one.
      session.activeLayer?.kind,
      session.hasActiveNonNegativeCell,
      // Edit Instance means THAT LANE'S KEY while you stand on a lane row,
      // an enablement no layer kind can answer. The row you stand on
      // publishes through its OWN notifier without a session notify, which
      // is why this entry needs the listener in initState as well.
      session.canNameLaneKeys,
      // The layer pill's promoted verb.
      session.canDeleteActiveLayer,
      // ⛔The two project-axis values LEFT this token with the dropdowns
      // that printed them: they are entries of the settings pill on the
      // 문턱 now, and a flyout's entries are built at open time.
      //
      // Button tooltips and menu labels print in the program language.
      session.languageSettings.value,
    );
  }

  /// Drops the cache iff what the toolbar shows changed. Every entry point
  /// (a committed seek, a host rebuild, a language switch) funnels its
  /// decision here.
  bool _tokenOrSectionsChanged(Set<TimelineSection> oldSections) {
    final nextActions = _deriveActionsToken();
    if (nextActions != _actionsToken ||
        !setEquals(oldSections, widget.hiddenSections)) {
      _actionsToken = nextActions;
      _cachedActions = null;
      return true;
    }
    return false;
  }

  /// Re-derives after a signal that does NOT come through a host rebuild.
  /// Both entry points compare against the current sections (neither a seek
  /// nor a language switch can change them).
  void _handleExternalSignal() {
    if (_tokenOrSectionsChanged(widget.hiddenSections)) {
      setState(() {});
    }
  }

  @override
  void initState() {
    super.initState();
    _actionsToken = _deriveActionsToken();
    widget.session.frameSeekCommitted.addListener(_handleExternalSignal);
    // 🚨유저 #6 (2026-08-14): 「룰러로 이동할때 … 버튼 상태 바꼈으면 좋겠는데
    // 안바뀜. **효율좋게** 하는데 … 해당 인덱스에 **버튼이 있으면 한번,
    // 없으면 한번** 이런식으로?」
    //
    // ⛔`frameSeekCommitted` fires on the RELEASE, so for a whole ruler drag
    // the toolbar kept whatever enablement it had when the drag began. A
    // scrub deliberately raises no session notify — that is what keeps the
    // drag cheap — so nothing else was ever going to re-ask.
    //
    // [EditorSessionManager.playheadHasCel] fires only when the ANSWER
    // flips, so this costs one rebuild on the frame that reaches a block
    // and one on the frame that leaves it, whatever the drag's length.
    widget.session.playheadHasCel.addListener(_handleExternalSignal);
    // A language switch moves its own notifier and fires NO session notify,
    // so nothing else would ever re-derive the tokens for it.
    widget.session.languageSettings.addListener(_handleExternalSignal);
    // Same story for the row you are STANDING on: it publishes on its own
    // notifier, and Edit Instance's enablement now reads it.
    widget.session.currentRowListenable.addListener(_handleExternalSignal);
  }

  @override
  void didUpdateWidget(covariant _SeekGatedTimelineToolbar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.session, widget.session)) {
      oldWidget.session.frameSeekCommitted.removeListener(
        _handleExternalSignal,
      );
      oldWidget.session.playheadHasCel.removeListener(_handleExternalSignal);
      oldWidget.session.languageSettings.removeListener(_handleExternalSignal);
      oldWidget.session.currentRowListenable.removeListener(
        _handleExternalSignal,
      );
      widget.session.frameSeekCommitted.addListener(_handleExternalSignal);
      widget.session.playheadHasCel.addListener(_handleExternalSignal);
      widget.session.languageSettings.addListener(_handleExternalSignal);
      widget.session.currentRowListenable.addListener(_handleExternalSignal);
      _cachedActions = null;
    }
    _tokenOrSectionsChanged(oldWidget.hiddenSections);
  }

  @override
  void dispose() {
    widget.session.frameSeekCommitted.removeListener(_handleExternalSignal);
    widget.session.playheadHasCel.removeListener(_handleExternalSignal);
    widget.session.languageSettings.removeListener(_handleExternalSignal);
    widget.session.currentRowListenable.removeListener(_handleExternalSignal);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      _cachedActions ??= widget.actionsBuilder(context);
}
