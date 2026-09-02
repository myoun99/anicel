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

    final cut = _coordinator._requireCut(cutId);
    if (cut.camera.keyframeAt(frameIndex) == pose) {
      return;
    }

    _coordinator.historyManager.execute(
      UpdateCutCameraCommand(
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
    final cut = _coordinator._requireCut(cutId);
    if (cut.camera.keyframeAt(frameIndex) == null) {
      return;
    }

    _coordinator.historyManager.execute(
      UpdateCutCameraCommand(
        repository: _coordinator.repository,
        cutId: cutId,
        camera: cut.camera.withoutKeyframe(frameIndex),
        description: 'Remove camera keyframe at frame ${frameIndex + 1}',
      ),
    );
  }

  void clearCutCamera({required CutId cutId}) {
    final cut = _coordinator._requireCut(cutId);
    if (cut.camera.isEmpty) {
      return;
    }

    _coordinator.historyManager.execute(
      UpdateCutCameraCommand(
        repository: _coordinator.repository,
        cutId: cutId,
        camera: CutCamera.empty(),
        description: 'Clear camera keyframes',
      ),
    );
  }

  /// Replaces the cut's whole camera track in one undo step — the property
  /// lanes edit per-property keys (move/toggle/hold) that the pose-level
  /// APIs above cannot express.
  void updateCutCamera({
    required CutId cutId,
    required CutCamera camera,
    String description = 'Edit camera keyframes',
  }) {
    final cut = _coordinator._requireCut(cutId);
    if (cut.camera == camera) {
      return;
    }

    _coordinator.historyManager.execute(
      UpdateCutCameraCommand(
        repository: _coordinator.repository,
        cutId: cutId,
        camera: camera,
        description: description,
      ),
    );
  }

  /// Replaces the project's instruction vocabulary; one undo step, no-op
  /// when unchanged.
  void updateCameraInstructionSet(CameraInstructionSet instructionSet) {
    if (_coordinator.repository.requireProject().cameraInstructions ==
        instructionSet) {
      return;
    }
    _coordinator.historyManager.execute(
      UpdateCameraInstructionSetCommand(
        repository: _coordinator.repository,
        instructionSet: instructionSet,
      ),
    );
  }
}
