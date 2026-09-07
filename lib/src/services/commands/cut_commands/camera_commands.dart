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

    _coordinator._executeIfChanged<Cut, CameraPose?>(
      subject: _coordinator._requireCut(cutId),
      value: pose,
      read: (cut) => cut.camera.keyframeAt(frameIndex),
      command: (cut) => UpdateCutCameraCommand(
        repository: _coordinator.repository,
        cutId: cutId,
        camera: cut.camera.withKeyframe(frameIndex, pose),
        description: 'Set camera keyframe at frame ${frameIndex + 1}',
      ),
    );
  }

  void removeCutCameraKeyframe({
    required CutId cutId,
    required int frameIndex,
  }) {
    _coordinator._executeIfChanged<Cut, CameraPose?>(
      subject: _coordinator._requireCut(cutId),
      value: null,
      read: (cut) => cut.camera.keyframeAt(frameIndex),
      command: (cut) => UpdateCutCameraCommand(
        repository: _coordinator.repository,
        cutId: cutId,
        camera: cut.camera.withoutKeyframe(frameIndex),
        description: 'Remove camera keyframe at frame ${frameIndex + 1}',
      ),
    );
  }

  void clearCutCamera({required CutId cutId}) =>
      _coordinator._executeIfChanged(
        subject: _coordinator._requireCut(cutId),
        value: true,
        read: (cut) => cut.camera.isEmpty,
        command: (_) => UpdateCutCameraCommand(
          repository: _coordinator.repository,
          cutId: cutId,
          camera: CutCamera.empty(),
          description: 'Clear camera keyframes',
        ),
      );

  /// Replaces the cut's whole camera track in one undo step — the property
  /// lanes edit per-property keys (move/toggle/hold) that the pose-level
  /// APIs above cannot express.
  void updateCutCamera({
    required CutId cutId,
    required CutCamera camera,
    String description = 'Edit camera keyframes',
  }) => _coordinator._executeIfChanged(
    subject: _coordinator._requireCut(cutId),
    value: camera,
    read: (cut) => cut.camera,
    command: (_) => UpdateCutCameraCommand(
      repository: _coordinator.repository,
      cutId: cutId,
      camera: camera,
      description: description,
    ),
  );

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
