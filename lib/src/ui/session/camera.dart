import '../../models/camera_instruction.dart';
import '../../models/camera_pose.dart';
import '../../models/canvas_point.dart';
import '../../models/canvas_size.dart';
import '../../models/cut.dart';
import '../../models/cut_camera.dart';
import '../../models/transform_track.dart';
import '../../models/layer.dart';
import '../../models/layer_kind.dart';
import '../../models/timeline_frame_range.dart';
import '../../services/camera_pose_resolver.dart';
import '../../services/command.dart';
import '../../services/commands/update_cut_camera_command.dart';
import '../../services/commands/update_project_camera_size_command.dart';
import '../brush/brush_editor_selection.dart';
import 'active_cut_controllers.dart';
import 'active_cut_edits.dart';
import 'session_roles.dart';
import 'lane_range_move_drag.dart';

/// The CAMERA — the frame size, the pose at a frame, the keyframes and the
/// track that holds them, the instruction set and the block preview — as its
/// own object.
///
/// 🚨A collaborator carved out of `EditorSessionManager` (the audit's SRP cut,
/// 2026-09-02). Measured before cutting: three fields of its own and fifteen
/// session members touched (the timeline controller, the active cut, the cut
/// command coordinator). It names the roles it needs in its constructor.
class Camera {
  Camera({
    required ProjectAccess project,
    required SelectionAccess selection,
    required ChangeSink changes,
    required TimelineAccess timeline,
    required ActiveCutControllers controllers,
    required SessionInternals internals,
    required LaneRangeMoveDragVerbs laneMove,
    required ActiveCutEdits activeCut,
  }) : _project = project,
       _selection = selection,
       _changes = changes,
       _timeline = timeline,
       _controllers = controllers,
       _internals = internals,
       _laneMove = laneMove,
       _activeCut = activeCut;

  final ActiveCutEdits _activeCut;

  final ProjectAccess _project;
  final SelectionAccess _selection;
  final ChangeSink _changes;
  final TimelineAccess _timeline;
  final ActiveCutControllers _controllers;
  final SessionInternals _internals;
  final LaneRangeMoveDragVerbs _laneMove;

  CutCamera get activeCutCamera => _project.requireActiveCut.camera;

  /// The camera's output frame size (the exported picture size); the camera
  /// view rect on canvas is this divided by the pose zoom.
  CanvasSize get cameraFrameSize =>
      _project.repository.requireProject().cameraSize;

  /// Sets the project's camera (shooting) frame — one undo step, no-op
  /// when unchanged. Poses are untouched: `CameraPose.zoom` is stated
  /// against this frame's width, so every cut re-frames by itself.
  void setProjectCameraSize(CanvasSize size) {
    if (size.width < 1 || size.height < 1 || size == cameraFrameSize) {
      return;
    }
    _project.historyManager.execute(
      UpdateProjectCameraSizeCommand(
        repository: _project.repository,
        cameraSize: size,
      ),
    );
    _changes.notifyChanged();
  }

  /// Resolved camera pose at an arbitrary playback frame (for rendering).
  CameraPose cameraPoseAtFrame(int frameIndex) => resolveCameraPoseAt(
    camera: _project.requireActiveCut.camera,
    canvasSize: _project.requireActiveCut.canvasSize,
    frameIndex: frameIndex,
  );

  /// Resolved camera pose for any cut (play-all renders other cuts too).
  /// The camera ROW's fx switch bypasses the camera work on this render
  /// route (playback, export, storyboard thumbnails all resolve through
  /// here) — the authoring overlays keep reading the real pose.
  CameraPose cameraPoseForCut(Cut cut, int frameIndex) {
    if (_cameraFxBypassedFor(cut)) {
      return CameraPose(
        center: CanvasPoint(
          x: cut.canvasSize.width / 2,
          y: cut.canvasSize.height / 2,
        ),
      );
    }
    return resolveCameraPoseAt(
      camera: cut.camera,
      canvasSize: cut.canvasSize,
      frameIndex: frameIndex,
    );
  }

  /// Whether [cut]'s camera row has its camera work bypassed — the camera
  /// row's own transform switch (R8: persisted like every other row's).
  bool _cameraFxBypassedFor(Cut cut) {
    final camera = cut.layers.cameraLayer;
    return camera != null && !camera.transformEnabled;
  }

  /// The resolved camera pose at the current playhead frame (keyframe,
  /// interpolation, or the default pose when the cut has no camera work).
  CameraPose get cameraPoseAtCurrentFrame => resolveCameraPoseAt(
    camera: _project.requireActiveCut.camera,
    canvasSize: _project.requireActiveCut.canvasSize,
    frameIndex: _controllers.timelineController.currentFrameIndex,
  );

  /// The camera pose the canvas should FRAME right now — not always the
  /// ACTIVE cut's (㊲).
  ///
  /// "Which cut am I editing" and "which cut is under the playhead" are two
  /// questions, and a live scrub makes them disagree ON PURPOSE: crossing a
  /// boundary parks per move and leaves the active cut alone, because
  /// switching it per move rebuilt every panel ([FrameScrub.scrubGlobalFrame]). The
  /// camera frame read the active cut through that, so a T.U that ended
  /// zoomed kept framing the NEXT cut's pictures at the size the cut being
  /// left had finished on — and dragging the other way showed no camera
  /// work at all.
  ///
  /// Only a LIVE scrub asks the parked question: a committed parking means
  /// there is no cut here (a gap, or the V-row eye's hidden picture), and
  /// then there is nothing to frame. Null says exactly that.
  CameraPose? get displayedCameraPose {
    final parked = _internals.frameScrubActive.value
        ? _selection.gapGlobalFrame
        : null;
    if (parked == null) {
      return _project.activeCutOrNull == null ? null : cameraPoseAtCurrentFrame;
    }
    // 🚨[TrackFrameAxis.ownerOf] hands a gap frame to the PRECEDING cut on
    // purpose (its over-end runway) — it is an addressing rule, not a
    // containment test. [TrackFrameAxis.isGap] is the containment test, and
    // it is the same pair [selectGlobalFrame] asks, so what the drag frames
    // and what the release lands cannot disagree.
    final axis = _timeline.trackFrameAxis();
    final owner = axis.isGap(parked) ? null : axis.ownerOf(parked);
    if (owner == null) {
      return null;
    }
    // The RENDER route's resolver (fx bypass honoured), because the picture
    // under this rectangle came through it too: preview and camera frame
    // must not disagree about the same cut.
    return cameraPoseForCut(owner.cut, parked - owner.startFrame);
  }

  bool get hasCameraKeyframeAtCurrentFrame =>
      _project.activeCutOrNull?.camera.keyframeAt(
        _controllers.timelineController.currentFrameIndex,
      ) !=
      null;

  void setCameraKeyframeAtCurrentFrame(CameraPose pose) =>
      _activeCut.onActiveCut(
        (cutId) => _project.cutCommandCoordinator.setCutCameraKeyframe(
          cutId: cutId,
          frameIndex: _controllers.timelineController.currentFrameIndex,
          pose: pose,
        ),
      );

  void removeCameraKeyframeAtCurrentFrame() => _activeCut.onActiveCut(
    (cutId) => _project.cutCommandCoordinator.removeCutCameraKeyframe(
      cutId: cutId,
      frameIndex: _controllers.timelineController.currentFrameIndex,
    ),
  );

  void clearActiveCutCamera() => _activeCut.onActiveCut(
    (cutId) => _project.cutCommandCoordinator.clearCutCamera(cutId: cutId),
  );

  /// Replaces the active cut's camera track (one undo step) — the property
  /// lanes' per-property key edits route through here. "Same name, same
  /// value" is the coordinator's one camera write, the transform law across
  /// the 겸용 group (F-84) — no longer a copy here that stopped at the cut.
  void updateActiveCutCameraTrack(
    TransformTrack track, {
    String description = 'Edit camera keyframes',
  }) => _activeCut.onActiveCut(
    (cutId) => _project.cutCommandCoordinator.updateCutCamera(
      cutId: cutId,
      camera: CutCamera.fromTrack(track),
      description: description,
    ),
  );

  /// Whether the canvas is in camera manipulation mode.
  bool get isCameraLayerActive =>
      _selection.activeLayer?.kind == LayerKind.camera;

  /// What the canvas shows while the camera layer is active: the first
  /// visible drawing layer with a frame at the playhead, so there is artwork
  /// to frame. `null` when the cut has nothing drawn at this frame.
  BrushEditorSelection? get cameraBackdropSelection {
    final cut = _project.activeCutOrNull;
    if (cut == null) {
      return null;
    }
    final frameIndex = _controllers.timelineController.currentFrameIndex;
    for (final layer in cut.layers) {
      if (!layer.kind.paintsArtwork || !layer.isVisible) {
        continue;
      }
      final frame = _controllers.timelineController.resolveFrameForLayer(
        layer: layer,
        frameIndex: frameIndex,
      );
      if (frame == null) {
        continue;
      }
      return BrushEditorSelection(
        projectId: _project.repository.requireProject().id,
        trackId: _selection.selectedTrackId,
        cutId: cut.id,
        layerId: layer.id,
        frameId: frame.id,
      );
    }
    return null;
  }

  /// The project's instruction vocabulary (FI/FO/PAN …, user-editable).
  CameraInstructionSet get cameraInstructionSet =>
      _project.repository.requireProject().cameraInstructions;

  /// One undo step; no-op when unchanged.
  void updateCameraInstructionSet(CameraInstructionSet instructionSet) {
    _project.cutCommandCoordinator.updateCameraInstructionSet(instructionSet);
    _changes.notifyChanged();
  }

  Command? cameraKeysCommandForRange(TimelineFrameRangeSelection selection) {
    final cut = _project.activeCutOrNull;
    final cutId = _timeline.editingSession.activeCutId;
    if (cut == null || cutId == null) {
      return null;
    }
    var camera = cut.camera;
    var changed = false;
    for (
      var frame = selection.startIndex;
      frame < selection.endIndexExclusive;
      frame += 1
    ) {
      if (frame < 0 || camera.keyframeAt(frame) != null) {
        continue;
      }
      // Freeze the RESOLVED pose (AE behavior): keys appear, the picture
      // does not move.
      camera = camera.withKeyframe(
        frame,
        resolveCameraPoseAt(
          camera: cut.camera,
          canvasSize: cut.canvasSize,
          frameIndex: frame,
        ),
      );
      changed = true;
    }
    if (!changed) {
      return null;
    }
    return UpdateCutCameraCommand(
      repository: _project.repository,
      cutId: cutId,
      camera: camera,
      description: 'Create camera keys',
    );
  }

  /// The camera frame's aspect — what the conte's PICTURE column is shaped
  /// by, so a cell's silhouette matches the cut's.
  double get cameraFrameAspect {
    final size = cameraFrameSize;
    return size.height <= 0 ? 16 / 9 : size.width / size.height;
  }

  /// [_cameraKeysDragPreview] as a [TransformTrack], memoized by the map's
  /// identity — the getter below is read per cell during paints, and
  /// rebuilding a SplayTreeMap track per read would be O(cells·keys).
  Map<int, CameraPose>? _cameraBlockPreviewTrackSource;

  TransformTrack? _cameraBlockPreviewTrackMemo;

  TransformTrack? get _cameraBlockPreviewTrack {
    final keys = _cameraKeysDragPreview;
    if (keys == null) {
      return null;
    }
    if (!identical(keys, _cameraBlockPreviewTrackSource)) {
      _cameraBlockPreviewTrackSource = keys;
      // The pose-facade form — the exact shape the block-ride commit lands
      // (`CutCamera(keyframes: cameraShifted)`), so the preview can never
      // promise a landing the release won't keep.
      _cameraBlockPreviewTrackMemo = TransformTrack(keyframes: keys);
    }
    return _cameraBlockPreviewTrackMemo;
  }

  /// The camera track THE DISPLAY reads — the in-flight LANE-move preview,
  /// the in-flight BLOCK-ride preview (P3b-2), or the committed track. The
  /// lane provider, the union summary markers and the row's exposure states
  /// all read THIS one answer (B4, 2026-08-17), so a camera key follows any
  /// drag live instead of jumping on release — and every reader moves in
  /// the same frame.
  TransformTrack? get activeCutCameraTrack =>
      _laneMove.cameraLaneTrackPreview ??
      _cameraBlockPreviewTrack ??
      _project.activeCutOrNull?.camera.track;

  /// The in-flight camera-key preview the cell resolution consults
  /// (exposureStateForLayer): the camera row's cells follow the drag
  /// without the repository moving.
  Map<int, CameraPose>? _cameraKeysDragPreview;

  /// The block-ride drag hands its shifted keys in here per move and
  /// clears them (null) on release — the one writer outside this object.
  void showCameraKeysDragPreview(Map<int, CameraPose>? keys) =>
      _cameraKeysDragPreview = keys;
}
