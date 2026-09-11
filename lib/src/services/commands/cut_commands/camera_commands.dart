part of '../cut_command_coordinator.dart';

/// THE CAMERA COMMANDS — a cut's camera keyframes, track and instruction
/// set — as their own object.
///
/// 🚨A collaborator carved out of `CutCommandCoordinator` (the audit's SRP
/// cut, 2026-09-02). Measured before cutting: three coordinator members
/// shared. It reaches the coordinator through `_coordinator`.
class _CameraCommands {
  _CameraCommands(this._coordinator);

  final CutCommandCoordinator _coordinator;

  void setCutCameraKeyframe({
    required CutId cutId,
    required int frameIndex,
    required CameraPose pose,
  }) {
    if (frameIndex < 0) {
      throw ArgumentError.value(
        frameIndex,
        'frameIndex',
        'Camera keyframe index must be non-negative.',
      );
    }

    final camera = _coordinator._requireCut(cutId).camera;
    if (camera.keyframeAt(frameIndex) == pose) {
      return;
    }
    _write(
      cutId: cutId,
      camera: camera.withKeyframe(frameIndex, pose),
      description: 'Set camera keyframe at frame ${frameIndex + 1}',
    );
  }

  void removeCutCameraKeyframe({
    required CutId cutId,
    required int frameIndex,
  }) {
    final camera = _coordinator._requireCut(cutId).camera;
    if (camera.keyframeAt(frameIndex) == null) {
      return;
    }
    _write(
      cutId: cutId,
      camera: camera.withoutKeyframe(frameIndex),
      description: 'Remove camera keyframe at frame ${frameIndex + 1}',
    );
  }

  void clearCutCamera({required CutId cutId}) {
    if (_coordinator._requireCut(cutId).camera.isEmpty) {
      return;
    }
    _write(
      cutId: cutId,
      camera: CutCamera.empty(),
      description: 'Clear camera keyframes',
    );
  }

  /// Replaces the cut's whole camera track in one undo step — the property
  /// lanes edit per-property keys (move/toggle/hold) that the pose-level
  /// APIs above cannot express.
  void updateCutCamera({
    required CutId cutId,
    required CutCamera camera,
    String description = 'Edit camera keyframes',
  }) => _write(cutId: cutId, camera: camera, description: description);

  /// Writes [camera] as [cutId]'s camera — THE one camera write: the pose
  /// verbs, the clear and the lanes all land here, as one undo step.
  ///
  /// The camera row is its cut's transform header (F-17), so it keeps the
  /// transform law ([namedTransformWrites]): the lanes are the cut's own,
  /// and a NAMED key this write moves drags every key of that name along —
  /// in this track and in the 겸용 siblings' cameras (F-84).
  void _write({
    required CutId cutId,
    required CutCamera camera,
    required String description,
  }) {
    final project = _coordinator.repository.requireProject();
    final cut = requireCut(project, cutId);
    if (cut.camera == camera) {
      return;
    }
    final row = cut.layers.cameraLayer;
    final writes = row == null
        // A cut with no camera row (a file from before the fixture) has no
        // lanes a key could have been named through: the write is its own.
        ? [(cutId: cutId, track: camera.track)]
        : [
            for (final write in namedTransformWrites(
              project,
              cutId: cutId,
              layerId: row.id,
              after: camera.track,
            ))
              (cutId: write.cutId, track: write.track),
          ];
    final commands = <Command>[
      for (final write in writes)
        UpdateCutCameraCommand(
          repository: _coordinator.repository,
          cutId: write.cutId,
          camera: CutCamera.fromTrack(write.track),
          description: description,
        ),
    ];
    _coordinator.historyManager.execute(
      commands.length == 1
          ? commands.single
          : CompositeCommand(description: description, commands: commands),
    );
  }

  /// Replaces the project's instruction vocabulary; one undo step, no-op
  /// when unchanged.
  void updateCameraInstructionSet(CameraInstructionSet instructionSet) =>
      _coordinator._executeIfChanged(
        subject: _coordinator.repository.requireProject(),
        value: instructionSet,
        read: (project) => project.cameraInstructions,
        command: (_) => UpdateCameraInstructionSetCommand(
          repository: _coordinator.repository,
          instructionSet: instructionSet,
        ),
      );
}
