import 'package:flutter/foundation.dart' show ValueNotifier;
import '../../models/camera_instruction.dart';
import '../../models/camera_pose.dart';
import '../../models/canvas_point.dart';
import '../../models/canvas_size.dart';
import '../../models/cut.dart';
import '../../models/cut_camera.dart';
import '../../models/transform_track.dart';
import '../../models/layer.dart';
import '../../models/layer_id.dart';
import '../../models/layer_kind.dart';
import '../../models/timeline_frame_range.dart';
import '../../services/camera_path.dart';
import '../../services/camera_pose_resolver.dart';
import '../../services/command.dart';
import '../../services/commands/update_cut_camera_command.dart';
import '../../services/commands/update_project_camera_size_command.dart';
import '../brush/brush_editor_selection.dart';
import 'active_cut_controllers.dart';
import 'active_cut_edits.dart';
import 'cut_under_playhead.dart';
import 'session_roles.dart';
import '../timeline/timeline_drag_preview.dart'
    show TimelineDragPreview, timelineDragPreviewCameraTrackFor;

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
    required ValueNotifier<TimelineDragPreview?> dragPreview,
    required ActiveCutEdits activeCut,
    required CutUnderPlayhead cutUnderPlayhead,
  }) : _project = project,
       _selection = selection,
       _changes = changes,
       _timeline = timeline,
       _controllers = controllers,
       _dragPreview = dragPreview,
       _activeCut = activeCut,
       _cutUnderPlayhead = cutUnderPlayhead;

  final ActiveCutEdits _activeCut;
  final CutUnderPlayhead _cutUnderPlayhead;

  final ProjectAccess _project;
  final SelectionAccess _selection;
  final ChangeSink _changes;
  final TimelineAccess _timeline;
  final ActiveCutControllers _controllers;
  final ValueNotifier<TimelineDragPreview?> _dragPreview;

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
    if (cut.layers.cameraWorkBypassed) {
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

  /// The camera pose [cut]'s frame [frameIndex] is SHOWN through — the
  /// render route's ([cameraPoseForCut], the camera row's fx switch
  /// included), the open cut's read from the track the display reads
  /// ([activeCutCameraTrack]) so what rides the camera follows a camera
  /// edit in flight. What stands in the shot is placed by it: an SE row's
  /// name tag (I-67-Q1).
  CameraPose cameraPoseShowingCut(Cut cut, int frameIndex) {
    final shown = cut.id == _project.activeCutOrNull?.id
        ? activeCutCameraTrack
        : null;
    return cameraPoseForCut(
      shown == null ? cut : cut.copyWith(camera: CutCamera.fromTrack(shown)),
      frameIndex,
    );
  }

  /// The resolved camera pose at the current playhead frame (keyframe,
  /// interpolation, or the default pose when the cut has no camera work) —
  /// of the track the display reads ([activeCutCameraTrack]), so the frame
  /// on the canvas follows a camera edit while it is still in flight.
  CameraPose get cameraPoseAtCurrentFrame {
    final cut = _project.requireActiveCut;
    final shown = activeCutCameraTrack;
    return resolveCameraPoseAt(
      camera: shown == null ? cut.camera : CutCamera.fromTrack(shown),
      canvasSize: cut.canvasSize,
      frameIndex: _controllers.timelineController.currentFrameIndex,
    );
  }

  /// The camera pose the canvas should FRAME right now — the active cut's,
  /// and none where the playhead is parked: a parking is a gap (or the
  /// V-row eye's hidden picture), and there is nothing to frame there.
  ///
  /// ↩️㊲: a live scrub used to park over ANOTHER cut's frames too and leave
  /// the active cut alone, so this asked the parked frame's cut for its pose
  /// (a T.U that ended zoomed had kept framing the next cut's pictures at
  /// the size the cut being left finished on). A scrub crosses into the cut
  /// under it now (I-57 ②, [FrameScrub.scrubGlobalFrame]), so the cut under
  /// the playhead is the active cut, and the parked question is only ever
  /// asked of a gap.
  CameraPose? get displayedCameraPose {
    if (_cutUnderPlayhead.liveParkedFrame != null ||
        _project.activeCutOrNull == null) {
      return null;
    }
    return cameraPoseAtCurrentFrame;
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

  /// Replaces the camera track of the cut holding [cameraRow], stood in or
  /// not (one undo step) — the property lanes' per-property key edits
  /// route through here. "Same name, same value" is the coordinator's one
  /// camera write, the transform law across the 겸용 group (F-84) — no
  /// longer a copy here that stopped at the cut.
  ///
  /// ↩️It wrote the ACTIVE cut's camera, whichever cut's camera row the
  /// edit was made on: a header graph's line of another cut wrote nothing
  /// (I-89-Q23 — that cut is edited where it is:
  /// [ActiveCutEdits.onCutOfRow]).
  ///
  /// QUIET, as a layer's transform lanes are
  /// (`LaneVerbs.updateLayerTransformTrack`): a key is the row's attribute,
  /// and nothing the controllers hold reads the camera. ↩️It took the
  /// structural refresh, so a key edited on the camera row dropped the
  /// frame range a key edited on a layer's lanes keeps — one edit with two
  /// after-maths (camera-key-edit-clears-the-frame-range, 10-17).
  void updateCameraTrack(
    LayerId cameraRow,
    TransformTrack track, {
    String description = 'Edit camera keyframes',
  }) => _activeCut.onCutOfRowQuietly(
    cameraRow,
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
    // Keys only on the frames the cut is drawn for (I-73-camera-row-Q2).
    final drawn = _project.activeCutDrawnFrameCount;
    for (
      var frame = selection.startIndex;
      frame < selection.endIndexExclusive;
      frame += 1
    ) {
      if (!cameraKeyFits(frame, drawnFrameCount: drawn) ||
          camera.keyframeAt(frame) != null) {
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

  /// The camera track THE DISPLAY reads — the in-flight LANE edit (a value
  /// scrubbed, the frame dragged on the canvas, a key range slid), the
  /// in-flight BLOCK-ride preview (P3b-2), or the committed track. The lane
  /// provider, the union summary markers, the row's exposure states and the
  /// canvas's camera frame all read THIS one answer (B4, 2026-08-17), so a
  /// camera key follows any drag live instead of jumping on release — and
  /// every reader moves in the same frame.
  ///
  /// 🚨F-195: the camera FRAME was the reader B4 missed — it resolved the
  /// committed camera, so dragging a camera value in its lane moved every
  /// marker and label and left the frame where it was until the release.
  ///
  /// …and a length change in flight — a trim (I-73-camera-row-Q4) or an
  /// O.L's edge (Q7): the key on the cut's last frame moves with it under
  /// the hand (`timelineDragPreviewCarriedCamera`).
  ///
  /// ↩️A block ride's track was handed in here by the drag, a channel of
  /// its own beside the preview that already carried it; it rides that
  /// preview alone now (H20), read as the storyboard's lanes read it.
  TransformTrack? get activeCutCameraTrack {
    final cut = _project.activeCutOrNull;
    if (cut == null) {
      return null;
    }
    return timelineDragPreviewCameraTrackFor(_dragPreview.value, cut.id) ??
        cut.camera.track;
  }

  /// The path the active cut's camera takes (I-89 ④), its frames [frameSize]
  /// canvas pixels at zoom 1 — of the track the display reads
  /// ([activeCutCameraTrack]), so it follows a camera edit in flight; null
  /// where there is no cut or the camera moves nothing ([CameraPath.of]).
  ///
  /// Built again only for another track or size: the frames between its
  /// keys are read as the canvas asks for them, and kept while it asks
  /// again at every step of a scrub.
  CameraPath? activeCutCameraPath(CanvasSize frameSize) {
    final cut = _project.activeCutOrNull;
    final track = activeCutCameraTrack;
    if (cut == null || track == null) {
      return null;
    }
    if (_path case (
      track: final pathTrack,
      canvasSize: final canvasSize,
      frameSize: final pathFrameSize,
      :final path,
    ) when identical(pathTrack, track) &&
        canvasSize == cut.canvasSize &&
        pathFrameSize == frameSize) {
      return path;
    }
    final path = CameraPath.of(
      cut.copyWith(camera: CutCamera.fromTrack(track)),
      frameSize,
    );
    _path = (
      track: track,
      canvasSize: cut.canvasSize,
      frameSize: frameSize,
      path: path,
    );
    return path;
  }

  ({
    TransformTrack track,
    CanvasSize canvasSize,
    CanvasSize frameSize,
    CameraPath? path,
  })?
  _path;
}
