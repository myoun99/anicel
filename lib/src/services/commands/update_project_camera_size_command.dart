import '../../models/canvas_size.dart';
import '../command.dart';
import '../project_repository.dart';

/// One project CAMERA (shooting frame) size change as one undo step.
///
/// Like the frame rate, the camera frame is a project-wide axis: the
/// canvas overlay, playback framing and export all read it, and every
/// `CameraPose.zoom` is stated against its width — so changing it
/// re-frames every cut without touching a single pose.
class UpdateProjectCameraSizeCommand implements Command {
  UpdateProjectCameraSizeCommand({
    required this.repository,
    required this.cameraSize,
  });

  final ProjectRepository repository;
  final CanvasSize cameraSize;

  CanvasSize? _previousSize;
  bool _hasExecuted = false;

  @override
  String get description => 'Change camera size';

  @override
  void execute() {
    _previousSize ??= repository.requireProject().cameraSize;
    repository.updateProjectCameraSize(cameraSize);
    _hasExecuted = true;
  }

  @override
  void undo() {
    final previous = _previousSize;
    if (!_hasExecuted || previous == null) {
      throw StateError('Command has not been executed.');
    }
    repository.updateProjectCameraSize(previous);
  }
}
