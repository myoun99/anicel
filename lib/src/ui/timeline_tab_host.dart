import 'dart:async' show unawaited;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart' show ValueListenable, setEquals;
import 'package:flutter/material.dart';

import '../models/camera_instruction.dart';
import '../models/layer.dart';
import '../models/layer_effect.dart';
import '../models/layer_folder.dart';
import '../models/layer_id.dart';
import '../models/key_range_move.dart' show transformKeyFrameUnion;
import '../models/layer_kind.dart';
import '../models/text_cel_style.dart';
import 'camera/camera_view_toggle_button.dart';
import 'dialogs/camera_key_dialog.dart';
import 'dialogs/delete_layer_dialog.dart';
import 'dialogs/frame_name_conflict_dialog.dart';
import 'dialogs/instruction_event_dialog.dart';
import 'dialogs/instruction_set_editor_dialog.dart';
import 'dialogs/layer_audio_dialog.dart';
import 'dialogs/rename_frame_dialog.dart';
import 'dialogs/rename_layer_dialog.dart';
import 'dialogs/se_instance_dialog.dart';
import 'dialogs/text_cel_dialog.dart';
import 'editor_session_manager.dart';
import 'playback/canvas_playback_controller.dart';
import 'playback/playback_transport_controls.dart';
import '../models/transform_track.dart';
import '../services/camera_pose_resolver.dart';
import 'text/app_strings.dart';
import '../models/timeline_coverage.dart' show TimelineBlockEdge;
import 'timeline/camera_key_edit.dart';
import 'timeline/effect_lane_editing.dart';
import 'timeline/effect_lane_policy.dart';
import 'timeline/property_lane_model.dart';
import 'timeline/timeline_cel_content_source.dart';
import 'timeline/timeline_cut_end_handle.dart';
import 'timeline/timeline_frame_rows_scroll_body.dart' show TimelineRowMemoAux;
import 'timeline/se_audio_lane.dart';
import 'timeline/timeline_action_toolbar.dart';
import 'timeline/timeline_frame_range_gesture.dart';
import 'timeline/timeline_run_end_handles.dart';
import 'timeline/timeline_exposure_comma_drag_policy.dart';
import 'timeline/timeline_orientation.dart';
import 'timeline/timeline_panel.dart';
import 'timeline/timeline_layer_controls_header.dart' show LayerLegendCallbacks;
import 'timeline/timeline_row_filter.dart';
import 'timeline/timeline_section_bracket_rail.dart'
    show TimelineSectionRailCallbacks;
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
    required this.orientation,
    required this.onOrientationChanged,
    required this.pixelsPerFrame,
    this.pixelsPerFrameListenable,
    required this.onPixelsPerFrameChanged,
    required this.showSeconds,
    required this.onShowSecondsChanged,
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
    this.audioFilePicker,
    this.cameraViewEnabled,
    this.cameraDimOpacity,
    this.onRevealOnionSkinPanel,
  });

  final EditorSessionManager session;
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

  /// Injectable for tests; defaults to the platform open-file dialog.
  final Future<String?> Function()? audioFilePicker;

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

  late final Listenable _frameCachedSignal = Listenable.merge([
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
  /// Folds every OTHER hideable section (the bracket flyout's 'only this
  /// section'); the target unfolds if it was hidden.
  void _soloSection(TimelineSection section) {
    final onToggle = widget.onToggleSection;
    if (onToggle == null) {
      return;
    }
    for (final other in TimelineSection.values) {
      if (!timelineSectionHideable(other)) {
        continue;
      }
      final shouldHide = other != section;
      final isHidden = widget.hiddenSections.contains(other);
      if (shouldHide != isHidden) {
        onToggle(other);
      }
    }
  }

  /// R26 #3: maps a lane select-drag's cross-row delta onto the layer's
  /// DISPLAYED lane list (the same one the grids render) and returns the
  /// lane row under the pointer — member lanes only; headers and
  /// non-transform lanes (SE audio) cross silently, and rows past the
  /// group clamp to the farthest member reached. Null keeps the anchor.
  String? _laneSpanHeadLane(
    LayerId layerId,
    String anchorLaneId,
    int rowDelta,
  ) {
    if (rowDelta == 0) {
      return null;
    }
    final layer = _session.layers
        .where((candidate) => candidate.id == layerId)
        .firstOrNull;
    if (layer == null) {
      return null;
    }
    final lanes = _lanesForLayer(layer);
    final anchor = lanes.indexWhere((lane) => lane.laneId == anchorLaneId);
    if (anchor < 0) {
      return null;
    }
    final step = rowDelta > 0 ? 1 : -1;
    String? head;
    for (var moved = 1; moved <= rowDelta.abs(); moved += 1) {
      final index = anchor + moved * step;
      if (index < 0 || index >= lanes.length) {
        break;
      }
      final laneId = lanes[index].laneId;
      // Rows the span can END on: a transform member lane, or (R6) an
      // effect PARAMETER lane. Anything else — a group header, the SE
      // audio lane — is crossed silently, so a drag reaching past it still
      // spans the member lanes it covered. Without the effect case the
      // span could never hold two parameters of one effect, and
      // [effectLaneSpan]'s range branch would be unreachable.
      if (transformLaneDisplayOrder.contains(laneId) ||
          parseEffectLaneId(laneId)?.parameterId != null) {
        head = laneId;
      }
    }
    return head;
  }

  List<PropertyLaneRow> _lanesForLayer(Layer layer) {
    // Attach rows ride their BASE's transform/opacity lanes (W5 fx
    // sharing) — no lanes of their own in v1.
    if (layer.attachedToLayerId != null) {
      return const [];
    }
    switch (layer.kind) {
      case LayerKind.camera:
        // A camera row on screen implies an active cut.
        final cut = _session.requireActiveCut;
        return _collapsibleTransformGroup(
          layer,
          transformPropertyLanes(
            cut.camera.track,
            poseAt: (frameIndex) => resolveCameraPoseAt(
              camera: cut.camera,
              canvasSize: cut.canvasSize,
              frameIndex: frameIndex,
            ),
          ),
        );
      case LayerKind.se:
        // Audio controls lead the SE twirl-down (the row's main tool); the
        // Transform group sits below, collapsed by default.
        return [
          ...seAudioLanesFor(layer),
          ..._collapsibleTransformGroup(layer, _layerTransformLanes(layer)),
          ..._layerEffectLanes(layer),
        ];
      case LayerKind.adjustment:
        // R6b: an adjustment row has no picture to move, so its twirl-down
        // is the Effects groups alone — its whole content.
        return _layerEffectLanes(layer);
      case LayerKind.animation:
      case LayerKind.image:
      case LayerKind.text:
      case LayerKind.storyboard:
      case LayerKind.instruction:
      // A folder's FX lanes ARE layer lanes (R27 #26 asked for the layer
      // lane grammar verbatim; now it is literally the same code path).
      case LayerKind.folder:
        return [
          ..._collapsibleTransformGroup(layer, _layerTransformLanes(layer)),
          // R6: effects read below Transform, the AE panel's order.
          ..._layerEffectLanes(layer),
        ];
    }
  }

  /// The full AE Transform group — Anchor Point / Position / Scale /
  /// Rotation / Opacity — identical on EVERY layer-track kind (R6-④:
  /// SE/instruction match the drawing layers exactly; unified feel is the
  /// point, per user).
  List<PropertyLaneRow> _layerTransformLanes(Layer layer) {
    return transformPropertyLanes(
      layer.transformTrack,
      includeAnchorAndOpacity: true,
      poseAt: (frameIndex) => _session.layerPoseAtFrame(layer, frameIndex),
      anchorAt: (frameIndex) =>
          _session.layerAnchorPointAtFrame(layer, frameIndex),
      opacityAt: (frameIndex) =>
          _session.layerOpacityAtFrame(layer, frameIndex),
    );
  }

  /// AE group collapse: the Transform group header always shows; its
  /// member lanes only while the layer's group is twirled open (default
  /// collapsed, host-owned per layer so it survives tab switches).
  List<PropertyLaneRow> _collapsibleTransformGroup(
    Layer layer,
    List<PropertyLaneRow> group,
  ) {
    final expanded = widget.expandedLaneGroupKeys.contains(
      laneGroupKey(layer.id, transformGroupHeaderLane.laneId),
    );
    return [
      // The header carries the member lanes' KEY UNION (UI-R20 #13, the
      // camera row's summary pattern) — one glance shows where the
      // layer's transform keys sit even while the group is collapsed.
      transformGroupHeader(
        expanded: expanded,
        keyedFrames: transformKeyFrameUnion(_laneTrackOf(layer)),
        // R8: the group's own switch — on every row that owns a transform.
        // The camera's lives on the cut's track, so its header shows none
        // and the row-level master covers it.
        enabled: layerKindHasLayerTransform(layer.kind)
            ? layer.transformEnabled
            : null,
      ),
      if (expanded) ...group.where((lane) => !lane.isGroupHeader),
    ];
  }

  /// The row's EFFECT lanes (R6), below its Transform group: one collapsible
  /// header per effect with its parameter lanes inside. Empty for every row
  /// that carries no effects, which is the default everywhere.
  List<PropertyLaneRow> _layerEffectLanes(Layer layer) {
    if (layer.effects.isEmpty) {
      return const [];
    }
    return effectPropertyLanes(
      layer.effects,
      isExpanded: (effectId) => widget.expandedLaneGroupKeys.contains(
        laneGroupKey(layer.id, effectGroupLaneId(effectId)),
      ),
      valueAt: (effectId, parameterId, frameIndex) =>
          _session.layerEffectParameterAtFrame(
            layer,
            effectId,
            parameterId,
            frameIndex,
          ),
    );
  }

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
    // Track-owned SE rows: their display clones strip the transform track
    // (global keys cannot render at cut-local lane positions), so a
    // clone-based commit would plant LOCAL-frame keys on the GLOBAL
    // layer. SE transform-lane editing stands down until the lane path
    // converts through the cut window.
    if (_session.isTrackSeLayerId(layer.id)) {
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
  /// Track-owned SE rows stand down for the same reason their transform
  /// lanes do: the display clone strips FX, so a clone-based commit would
  /// plant the chain where nothing can edit it.
  void _commitEffectLaneEdit(
    Layer layer,
    List<LayerEffect>? next,
    String description,
  ) {
    if (next == null || _session.isTrackSeLayerId(layer.id)) {
      return;
    }
    _session.updateLayerEffects(layer.id, next, description: description);
  }

  PropertyLaneEditCallbacks get _laneEdit => PropertyLaneEditCallbacks(
    onToggleKeyAt: (layer, lane, frameIndex) {
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
    onMoveKey: (layer, lane, fromFrame, toFrame) {
      final description = 'Move ${lane.label} keyframe to frame ${toFrame + 1}';
      if (laneIsEffectLane(lane)) {
        _commitEffectLaneEdit(
          layer,
          effectsWithLaneKeyMoved(
            layer.effects,
            laneId: lane.laneId,
            fromFrame: fromFrame,
            toFrame: toFrame,
          ),
          description,
        );
        return;
      }
      _commitLaneEdit(
        layer,
        transformTrackWithLaneKeyMoved(
          _laneTrackOf(layer),
          laneId: lane.laneId,
          fromFrame: fromFrame,
          toFrame: toFrame,
        ),
        description,
      );
    },
    onRemoveKey: (layer, lane, frameIndex) {
      final description = 'Delete ${lane.label} keyframe';
      if (laneIsEffectLane(lane)) {
        _commitEffectLaneEdit(
          layer,
          effectsWithLaneKeyRemoved(
            layer.effects,
            laneId: lane.laneId,
            frameIndex: frameIndex,
          ),
          description,
        );
        return;
      }
      _commitLaneEdit(
        layer,
        transformTrackWithLaneKeyRemoved(
          _laneTrackOf(layer),
          laneId: lane.laneId,
          frameIndex: frameIndex,
        ),
        description,
      );
    },
    onToggleHold: (layer, lane, frameIndex) {
      final description = 'Toggle hold on ${lane.label} keyframe';
      if (laneIsEffectLane(lane)) {
        _commitEffectLaneEdit(
          layer,
          effectsWithLaneHoldToggled(
            layer.effects,
            laneId: lane.laneId,
            frameIndex: frameIndex,
          ),
          description,
        );
        return;
      }
      _commitLaneEdit(
        layer,
        transformTrackWithLaneHoldToggled(
          _laneTrackOf(layer),
          laneId: lane.laneId,
          frameIndex: frameIndex,
        ),
        description,
      );
    },
    onSetValue: (layer, lane, frameIndex, input) {
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

  Future<void> _deleteActiveLayer() async {
    final activeLayer = _session.activeLayer;
    if (activeLayer == null || !_session.canDeleteActiveLayer) {
      return;
    }

    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (context) => DeleteLayerDialog(layerName: activeLayer.name),
    );
    if (!mounted || shouldDelete != true) {
      return;
    }

    _session.deleteActiveLayer();
  }

  Future<void> _renameActiveLayer() async {
    final activeLayer = _session.activeLayer;
    if (activeLayer == null) {
      return;
    }

    final nextName = await showDialog<String>(
      context: context,
      builder: (context) => RenameLayerDialog(initialName: activeLayer.name),
    );
    if (!mounted || nextName == null) {
      return;
    }

    _session.renameActiveLayer(nextName);
  }

  Future<void> _renameFolder(LayerId folderId) async {
    final folder = _session.activeCutOrNull?.layers.folderById(folderId);
    if (folder == null) {
      return;
    }
    final nextName = await showDialog<String>(
      context: context,
      builder: (context) => RenameLayerDialog(initialName: folder.name),
    );
    if (!mounted || nextName == null) {
      return;
    }
    // A folder renames like any other row.
    _session.renameLayer(folderId, nextName);
  }

  /// THE unified instance-edit entrance (double-tap on any cell, and the
  /// toolbar's Edit Instance button), dispatched by row kind: drawing
  /// kinds edit the frame name, SE its name/dialogue, instruction its
  /// event, camera its keys at the frame.
  Future<void> _activateCellEditor(LayerId layerId, int frameIndex) async {
    final layer = _session.activeLayer;
    if (layer == null || layer.id != layerId) {
      return;
    }
    // Pin the EDITING selection to the tapped cell: during playback the
    // tap's select routes to the playback clock and leaves the editing
    // playhead parked elsewhere — every editor below reads/writes
    // selectedFrame, and a stale playhead made the dialog edit the wrong
    // cell (worst on text rows, where Save overwrites the cel).
    if (frameIndex >= 0 && _session.currentFrameIndex != frameIndex) {
      _session.selectFrameIndex(frameIndex);
    }
    switch (layer.kind) {
      case LayerKind.se:
        await _editSeLabel();
      case LayerKind.instruction:
        await _editInstructionEvent(layerId, frameIndex);
      case LayerKind.camera:
        await _editCameraKeys(frameIndex);
      case LayerKind.text:
        await _editTextCel();
      case LayerKind.folder:
      case LayerKind.adjustment:
        // A folder's band is the members' aggregate and an adjustment's is
        // empty: neither has a cell of its own to edit. Their work lives
        // in the twirl-down.
        break;
      case LayerKind.animation || LayerKind.storyboard || LayerKind.image:
        await _renameSelectedFrame();
    }
  }

  /// Toolbar 'Edit Instance': the same entrance at the playhead.
  Future<void> _editActiveInstance() async {
    final layer = _session.activeLayer;
    if (layer == null) {
      return;
    }
    await _activateCellEditor(layer.id, _session.currentFrameIndex);
  }

  /// Toolbar 'Add' — kind-dispatched creation. NO dialogs anywhere
  /// (UI-R25 #2, 조작 통일화): SE/instruction create a DEFAULT instance
  /// directly — the Edit Instance button / double-tap edits it after.
  /// A live selection fills the WHOLE selection instead (UI-R25 #3):
  /// anywhere selectable creates — drawing gaps, SE gaps, instruction
  /// gaps, camera keys, lane keys.
  Future<void> _createActiveInstance() async {
    if (_session.createInstancesForSelection()) {
      return;
    }
    final layer = _session.activeLayer;
    if (layer == null) {
      return;
    }
    switch (layer.kind) {
      case LayerKind.camera:
        _session.setCameraKeyframeAtCurrentFrame(
          _session.cameraPoseAtCurrentFrame,
        );
      case LayerKind.se:
        _session.createSeEntryAtCurrentFrame(name: '', lengthFrames: 1);
      case LayerKind.instruction:
        _session.createDefaultInstructionEventAtCurrentFrame();
      case LayerKind.folder:
      case LayerKind.adjustment:
        // Nothing to create on either row — a folder holds rows and an
        // adjustment holds effects; neither holds cels.
        break;
      // A text cel is born BLANK like a drawing cel (UI-R25 #2: creation
      // never opens a dialog) — double-tap types into it afterwards.
      case LayerKind.animation ||
          LayerKind.storyboard ||
          LayerKind.image ||
          LayerKind.text:
        _session.createDrawingAtCurrentFrame();
    }
  }

  /// Camera cells: per-lane key/value/interpolation dialog at the frame;
  /// the edited states fold into ONE track commit (one undo).
  Future<void> _editCameraKeys(int frameIndex) async {
    if (frameIndex < 0) {
      return;
    }
    final cut = _session.activeCutOrNull;
    if (cut == null) {
      return;
    }
    final before = cameraKeyLaneStatesAt(
      cut.camera.track,
      frameIndex: frameIndex,
      resolvedPose: resolveCameraPoseAt(
        camera: cut.camera,
        canvasSize: cut.canvasSize,
        frameIndex: frameIndex,
      ),
    );

    final after = await showDialog<List<CameraKeyLaneState>>(
      context: context,
      builder: (context) =>
          CameraKeyDialog(frameIndex: frameIndex, lanes: before),
    );
    if (!mounted || after == null) {
      return;
    }

    // Re-read after the dialog: the track may have changed underneath.
    final trackAfterDialog = _session.activeCutOrNull?.camera.track;
    if (trackAfterDialog == null) {
      return;
    }
    final next = transformTrackWithKeyDialogApplied(
      trackAfterDialog,
      frameIndex: frameIndex,
      before: before,
      after: after,
    );
    if (next != null) {
      _session.updateActiveCutCameraTrack(
        next,
        description: 'Edit camera keys at frame ${frameIndex + 1}',
      );
    }
  }

  /// The preview inside the instance dialogs follows the visible
  /// orientation (Axis policy in miniature).
  Axis get _previewAxis => widget.orientation == TimelineOrientation.horizontal
      ? Axis.horizontal
      : Axis.vertical;

  /// SE cells: covered cells edit the covering entry's name/dialogue in
  /// the dialog; EMPTY cells create a default one-frame entry DIRECTLY
  /// (UI-R25 #2 — creation never opens a dialog; edit it afterwards).
  Future<void> _editSeLabel() async {
    final creating = _session.selectedFrame == null;
    if (creating) {
      if (_session.canCreateDrawingAtCurrentFrame) {
        _session.createSeEntryAtCurrentFrame(name: '', lengthFrames: 1);
      }
      return;
    }

    final result = await showDialog<SeInstanceDialogResult>(
      context: context,
      builder: (context) => SeInstanceDialog(
        creating: false,
        initialSeName: _session.selectedFrameSeName ?? '',
        initialDialogue: _session.selectedFrameName ?? '',
        previewAxis: _previewAxis,
      ),
    );
    if (!mounted || result == null) {
      return;
    }

    final seName = result.seName.isEmpty ? null : result.seName;
    // SE edits never hit the link-conflict flow (duplicates allowed).
    _session.updateSelectedSeEntry(dialogue: result.dialogue, seName: seName);
  }

  /// Text cells (R5): covered cells open the parameter editor; EMPTY
  /// cells create a blank cel directly (UI-R25 #2) — the next double-tap
  /// types into it.
  Future<void> _editTextCel() async {
    if (_session.selectedFrame == null) {
      if (_session.canCreateDrawingAtCurrentFrame) {
        _session.createDrawingAtCurrentFrame();
      }
      return;
    }

    final cut = _session.activeCutOrNull;
    final content = _session.selectedTextCelContent;
    final result = await showDialog<TextCelContent>(
      context: context,
      builder: (context) => TextCelDialog(
        creating: content == null,
        initialContent: content,
        defaultPosition: cut == null
            ? null
            : Offset(
                cut.canvasSize.width / 2,
                cut.canvasSize.height / 2,
              ),
      ),
    );
    if (!mounted || result == null) {
      return;
    }
    _session.setTextCelContentForSelectedFrame(result);
  }

  /// Instruction cells: covered cells edit/delete the covering event in
  /// the dialog; EMPTY cells create a default one-frame event DIRECTLY
  /// (UI-R25 #2). The vocabulary editor is reachable from the picker.
  Future<void> _editInstructionEvent(LayerId layerId, int frameIndex) async {
    final covering = _session.instructionSpanAt(layerId, frameIndex);
    if (covering == null) {
      _session.createDefaultInstructionEventAtCurrentFrame();
      return;
    }

    final result = await showDialog<InstructionEventDialogResult>(
      context: context,
      builder: (context) => InstructionEventDialog(
        instructionSet: _session.cameraInstructionSet,
        initialInstructionId: covering.value.instructionId,
        initialText: covering.value.text,
        initialValueA: covering.value.valueA,
        initialValueB: covering.value.valueB,
        initialMemo: covering.value.memo,
        editing: true,
        onEditInstructionSet: () => _editInstructionSet(context),
        previewAxis: _previewAxis,
      ),
    );
    if (!mounted || result == null) {
      return;
    }

    if (result.delete) {
      _session.removeInstructionEventAt(layerId, frameIndex);
      return;
    }
    final instructionId = result.instructionId;
    if (instructionId == null) {
      return;
    }
    _session.upsertInstructionEventAt(
      layerId,
      frameIndex,
      InstructionEvent(
        instructionId: instructionId,
        length: 1,
        text: result.text,
        valueA: result.valueA,
        valueB: result.valueB,
        memo: result.memo,
      ),
      createLengthFrames: 1,
    );
  }

  /// Opens the vocabulary editor and commits the edited set immediately
  /// (its own undo step), so it sticks even when the event dialog is then
  /// cancelled. The already-open picker keeps its old list until reopened.
  Future<void> _editInstructionSet(BuildContext dialogContext) async {
    final edited = await showDialog<CameraInstructionSet>(
      context: dialogContext,
      builder: (context) =>
          InstructionSetEditorDialog(initialSet: _session.cameraInstructionSet),
    );
    if (!mounted || edited == null) {
      return;
    }
    _session.updateCameraInstructionSet(edited);
  }

  /// Imports a sound file onto the active SE layer at the playhead.
  Future<void> _importAudio() async {
    if (!_session.canImportAudioToActiveLayer) {
      return;
    }
    final picker = widget.audioFilePicker ?? _pickAudioFile;
    final path = await picker();
    if (!mounted || path == null) {
      return;
    }
    _session.addAudioClipToActiveSeLayer(path);
  }

  static Future<String?> _pickAudioFile() async {
    final file = await openFile(
      acceptedTypeGroups: const [
        XTypeGroup(
          label: 'Audio',
          extensions: ['mp3', 'wav', 'm4a', 'aac', 'flac', 'ogg'],
        ),
      ],
    );
    return file?.path;
  }

  Future<void> _renameSelectedFrame() async {
    if (_session.selectedFrame == null ||
        !_session.canRenameFrameAtCurrentFrame) {
      return;
    }

    final nextName = await showDialog<String>(
      context: context,
      builder: (context) =>
          RenameFrameDialog(initialName: _session.selectedFrameName ?? ''),
    );
    if (!mounted || nextName == null) {
      return;
    }

    final conflictingFrameId = _session.renameSelectedFrame(nextName);
    if (conflictingFrameId == null) {
      return;
    }

    final shouldLink = await showDialog<bool>(
      context: context,
      builder: (context) => const FrameNameConflictDialog(),
    );
    if (!mounted || shouldLink != true) {
      return;
    }

    _session.linkSelectedFrame(conflictingFrameId);
  }

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
  List<Layer> _displayLayers() {
    final view = widget.cameraViewEnabled;
    if (view == null) {
      return _session.layers;
    }
    return [
      for (final layer in _session.layers)
        layer.kind == LayerKind.camera
            ? _cameraDisplayLayer(layer, view.value)
            : layer,
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
    return ListenableBuilder(
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
          // Edit drags (comma/trim) preview through the scoped channel: a
          // step rebuilds the dragged row's gate + the cursor overlay only,
          // never this host (the release commit is the one session notify).
          dragPreview: _session.dragPreview,
          frameCursor: _frameCursor,
          frameCachedSignal: _frameCachedSignal,
          isFrameCached: _session.isPlaybackFrameCached,
          playbackFrameCount: _session.activeCutPlaybackFrameCount,
          exposureStateForLayer: _session.exposureStateForLayer,
          frameNameForLayer: _session.frameNameForLayer,
          // R26 #44: ACTION-section blocks whose cel is still blank gray
          // their paper; the token keys the row memo (cel pixels live
          // outside the Layer value).
          celContent: _celContent,
          onSelectLayer: _session.selectLayer,
          // Ruler scrubs during playback SEEK the playback clock instead of
          // moving the (hidden) editing playhead.
          onSelectFrame: (frameIndex) {
            if (_session.playback.isActive) {
              _session.playback.seekToLocalFrame(frameIndex);
            } else {
              _session.selectFrameIndex(frameIndex);
            }
          },
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
          audioLane: TimelineAudioLaneCallbacks(
            onRemoveClip: _session.removeAudioClipAt,
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
            onSetClipGain: _session.setAudioClipGain,
          ),
          onSetAudioClipFadeCurve: _session.setAudioClipFadeCurve,
          onSetAudioClipEnvelope: _session.setAudioClipEnvelope,
          resolveStrings: () => _session.uiStrings,
          onAddLayer: _session.addLayer,
          onToggleLayerMuted: _session.toggleLayerMuted,
          isLayerSoloed: (layerId) =>
              _session.soloedSeLayerIds.value.contains(layerId),
          onToggleLayerSolo: _session.toggleLayerSolo,
          onEditLayerAudio: (layerId) => unawaited(
            showLayerAudioDialog(context, session: _session, layerId: layerId),
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
          // already threaded above. Only the structural verbs land here.
          onToggleLayerCollapsed: _session.toggleLayerCollapsed,
          onRenameFolder: (folderId) => unawaited(_renameFolder(folderId)),
          onDissolveFolder: _session.dissolveFolder,
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
                (layerId, anchorIndex, headIndex, {headLayerId, headLaneId}) =>
                    _session.updateFrameRangeSelectionDrag(
                      layerId: layerId,
                      anchorIndex: anchorIndex,
                      headIndex: headIndex,
                      headLayerId: headLayerId,
                      headLaneId: headLaneId,
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
            selection: _session.laneRangeSelection,
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
            onTapClear: _session.clearLaneRangeSelection,
            onMoveBegin: _session.beginLaneRangeMoveDrag,
            onMoveUpdate: (frameDelta) =>
                _session.updateLaneRangeMoveDrag(frameDelta: frameDelta),
            onMoveEnd: _session.endLaneRangeMoveDrag,
            onMoveCancel: _session.cancelLaneRangeMoveDrag,
          ),
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
            onToggleMarkFilter: (mark) =>
                widget.onSetRowFilter?.call(widget.rowFilter.toggledMark(mark)),
            onToggleKindFilter: (kind) =>
                widget.onSetRowFilter?.call(widget.rowFilter.toggledKind(kind)),
            onToggleSheetOnlyFilter: () => widget.onSetRowFilter?.call(
              widget.rowFilter.copyWith(
                onTimesheetOnly: !widget.rowFilter.onTimesheetOnly,
              ),
            ),
            onToggleFxOnlyFilter: () => widget.onSetRowFilter?.call(
              widget.rowFilter.copyWith(fxOnly: !widget.rowFilter.fxOnly),
            ),
            onToggleFillReferenceOnlyFilter: () => widget.onSetRowFilter?.call(
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
          sectionRail: widget.onToggleSection == null
              ? null
              : TimelineSectionRailCallbacks(
                  onToggleSection: widget.onToggleSection!,
                  onAddLayerOfKind: _session.addLayerOfKind,
                  onSetSectionLayersVisibility:
                      _session.setSectionLayersVisibility,
                  onSoloSection: _soloSection,
                ),
          lanesForLayer: _lanesForLayer,
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
          timelineActionToolbar: timelineToolbar,
        );
        // The GAP empty state (UI-R9 #3): no cut selected — no rows, no
        // grid; the toolbar stays (its cut-scoped commands disable via
        // their own enablement gates).
        if (_session.activeCutOrNull == null) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              timelineToolbar,
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
      transportBuilder: (context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          PlaybackTransportControls(
            controller: _session.playback,
            scope: PlaybackScope.activeCut,
            quality: _session.playbackQuality,
            onQualityChanged: _session.setPlaybackQuality,
            playbackStartFrame: () => _session.currentFrameIndex,
            onSkipToStart: () => _session.selectFrameIndex(0),
            resolveMeterPeaks: () => _session.audioDeviceTransport.meterPeaks,
            isVoiceRecording: _session.isVoiceRecording,
            onToggleVoiceRecording: () =>
                toggleVoiceRecordingWithFeedback(context, _session),
            voiceRecordClipLit: _session.voiceRecordClipLit,
            resolveStrings: () => _session.uiStrings,
          ),
          // R27 #1: the CAMERA VIEW toggle, right beside the transport.
          // It lived only on the camera layer row, which meant scrolling
          // the rail to it every time; the state itself is a view mode,
          // so the command bar is its natural second home (both entrances
          // drive the one notifier). R28 #1 moved the button itself into
          // a shared widget the storyboard's command bar mounts too — and
          // that widget wears R26 #42's standard AppIconButton, so both
          // panels get the same button in the same style.
          CameraViewToggleButton(
            enabled: widget.cameraViewEnabled,
            keyValue: 'timeline-camera-view-button',
          ),
        ],
      ),
      actionsBuilder: (context) => TimelineActionToolbar(
        session: _session,
        onAddLayer: _session.addLayer,
        onRenameLayer: _renameActiveLayer,
        onDeleteLayer: _deleteActiveLayer,
        onEditInstance: _editActiveInstance,
        onCreateInstance: _createActiveInstance,
        onImportAudio: _importAudio,
        hiddenSections: widget.hiddenSections,
        onToggleSection: widget.onToggleSection,
      ),
    );
  }
}

/// Caches the timeline's transport + action toolbar and rebuilds each ONLY
/// when what ITS buttons SHOW changes — for BOTH a committed seek AND a
/// session notify (the host rebuild). The bar reconstructs a transport +
/// ~25 Material buttons; the scoped-notify measurement put that at a large,
/// row-independent share of every notify, even though a layer-select or a
/// far-away cell edit changes nothing it renders.
///
/// TWO groups, TWO tokens (frame-axis round): the transport and the action
/// toolbar read disjoint state, and the frequent change — landing a drawing
/// flips the frame-group enablements — belongs entirely to the actions. Under
/// one shared token that legitimate refresh dragged the transport's ~180
/// widgets along with it; measured at 24 layers, the whole bar was ~48% of a
/// notify's rebuilds and the transport was a third of that.
///
/// Each group's token holds every value that group's DIRECTLY-rendered
/// widgets read. Three kinds of state are deliberately absent from both,
/// because caching cannot make them stale:
///
/// - flyout menu contents (Layer / Frame / Cut / fps / sample-rate entries)
///   are built by `entriesBuilder` at OPEN time, so they always read fresh;
/// - the playback display rides the transport's own
///   AnimatedBuilder(controller), and the mic / clip lights are
///   ValueNotifiers the transport subscribes to itself — a ValueNotifier in
///   the token would compare a `final` field's identity, which never
///   changes: coverage in appearance only;
/// - the camera-view toggle follows its own notifier.
///
/// COMPLETENESS CONTRACT: any NEW directly-rendered value (an enablement, a
/// shown label, a lit indicator read as a plain value) MUST join ITS group's
/// token — [_deriveTransportToken] or [_deriveActionsToken] — otherwise a
/// notify that changes only that value leaves a stale button. And if its
/// source does not travel through a host rebuild or a committed seek, it
/// needs a listener here too (as the language settings do).
/// playhead_rebuild_guard_test.dart drives one mutation per dimension AND
/// pins which group each one may reconstruct; a dimension added without a
/// case there is unguarded.
class _SeekGatedTimelineToolbar extends StatefulWidget {
  const _SeekGatedTimelineToolbar({
    required this.session,
    required this.transportBuilder,
    required this.actionsBuilder,
    required this.hiddenSections,
  });

  final EditorSessionManager session;

  /// The playback transport + camera-view toggle: gated on
  /// [_SeekGatedTimelineToolbarState._deriveTransportToken].
  final WidgetBuilder transportBuilder;

  /// The action toolbar (frame group, layer buttons, project dropdowns):
  /// gated on [_SeekGatedTimelineToolbarState._deriveActionsToken].
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
  late Object _transportToken;
  late Object _actionsToken;

  /// The last-built groups. Held across BOTH seeks and host rebuilds so a
  /// notify with an unchanged token reuses that group's widgets — and a
  /// notify that changes only one group leaves the other's alone.
  Widget? _cachedTransport;
  Widget? _cachedActions;

  /// Every value the TRANSPORT group's directly-rendered widgets read.
  ///
  /// See the completeness contract on [_SeekGatedTimelineToolbar]. The
  /// playback clock is deliberately absent (its own AnimatedBuilder), as are
  /// the mic/clip lights (ValueNotifiers the transport subscribes to itself)
  /// and the camera-view state (its own notifier).
  Object _deriveTransportToken() {
    final session = widget.session;
    return (
      // The transport's one plain-value prop.
      session.playbackQuality,
      // It resolves its mic tooltips through `session.uiStrings` DURING
      // build, and a language switch fires no session notify at all (it moves
      // its own notifier), so without this the cached transport would keep
      // the old language until some unrelated token change.
      session.languageSettings.value,
    );
  }

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
      session.canCutExposureAtCurrentFrame,
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
      // Shown labels: the two project-axis dropdowns print their values.
      session.projectFrameRate,
      session.projectAudioSampleRate,
      // Button tooltips and menu labels print in the program language.
      session.languageSettings.value,
    );
  }

  /// Drops each group's cache iff what THAT group shows changed. Every entry
  /// point (a committed seek, a host rebuild, a language switch) funnels its
  /// decision here.
  bool _tokenOrSectionsChanged(Set<TimelineSection> oldSections) {
    var changed = false;
    final nextTransport = _deriveTransportToken();
    if (nextTransport != _transportToken) {
      _transportToken = nextTransport;
      _cachedTransport = null;
      changed = true;
    }
    final nextActions = _deriveActionsToken();
    if (nextActions != _actionsToken ||
        !setEquals(oldSections, widget.hiddenSections)) {
      _actionsToken = nextActions;
      _cachedActions = null;
      changed = true;
    }
    return changed;
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
    _transportToken = _deriveTransportToken();
    _actionsToken = _deriveActionsToken();
    widget.session.frameSeekCommitted.addListener(_handleExternalSignal);
    // A language switch moves its own notifier and fires NO session notify,
    // so nothing else would ever re-derive the tokens for it.
    widget.session.languageSettings.addListener(_handleExternalSignal);
  }

  @override
  void didUpdateWidget(covariant _SeekGatedTimelineToolbar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.session, widget.session)) {
      oldWidget.session.frameSeekCommitted.removeListener(
        _handleExternalSignal,
      );
      oldWidget.session.languageSettings.removeListener(_handleExternalSignal);
      widget.session.frameSeekCommitted.addListener(_handleExternalSignal);
      widget.session.languageSettings.addListener(_handleExternalSignal);
      _cachedTransport = null;
      _cachedActions = null;
    }
    _tokenOrSectionsChanged(oldWidget.hiddenSections);
  }

  @override
  void dispose() {
    widget.session.frameSeekCommitted.removeListener(_handleExternalSignal);
    widget.session.languageSettings.removeListener(_handleExternalSignal);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // The Row is rebuilt; its CHILDREN are the cached instances, so an
    // unchanged group's element subtree is skipped whole.
    return Row(
      children: [
        _cachedTransport ??= widget.transportBuilder(context),
        Expanded(child: _cachedActions ??= widget.actionsBuilder(context)),
      ],
    );
  }
}
