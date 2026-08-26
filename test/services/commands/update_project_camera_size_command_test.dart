import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/services/commands/update_project_camera_size_command.dart';
import 'package:anicel/src/services/project_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Project project() => Project(
    id: const ProjectId('p'),
    name: 'p',
    tracks: const [],
    createdAt: DateTime.utc(2026),
    cameraSize: const CanvasSize(width: 960, height: 430),
  );

  group('UpdateProjectCameraSizeCommand', () {
    test('execute writes the frame; undo restores the one before', () {
      final repository = ProjectRepository(initialProject: project());
      final command = UpdateProjectCameraSizeCommand(
        repository: repository,
        cameraSize: const CanvasSize(width: 1920, height: 1080),
      );

      command.execute();
      expect(
        repository.requireProject().cameraSize,
        const CanvasSize(width: 1920, height: 1080),
      );

      command.undo();
      expect(
        repository.requireProject().cameraSize,
        const CanvasSize(width: 960, height: 430),
      );

      // Redo re-runs execute; the remembered "previous" must stay the
      // ORIGINAL frame, not the one redo just replaced.
      command.execute();
      expect(
        repository.requireProject().cameraSize,
        const CanvasSize(width: 1920, height: 1080),
      );
      command.undo();
      expect(
        repository.requireProject().cameraSize,
        const CanvasSize(width: 960, height: 430),
      );
    });

    test('undo before execute throws', () {
      final repository = ProjectRepository(initialProject: project());
      expect(
        () => UpdateProjectCameraSizeCommand(
          repository: repository,
          cameraSize: const CanvasSize(width: 1920, height: 1080),
        ).undo(),
        throwsStateError,
      );
    });
  });
}
