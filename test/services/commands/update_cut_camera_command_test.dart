import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/editing_session_state.dart';
import 'package:anicel/src/models/camera_pose.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_camera.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/commands/cut_command_coordinator.dart';
import 'package:anicel/src/services/history_manager.dart';
import 'package:anicel/src/services/project_repository.dart';

void main() {
  late ProjectRepository repository;
  late HistoryManager historyManager;
  late CutCommandCoordinator coordinator;

  setUp(() {
    repository = ProjectRepository(
      initialProject: Project(
        id: const ProjectId('project-1'),
        name: 'Project',
        tracks: [
          Track(
            id: const TrackId('track-1'),
            name: 'Video',
            cuts: [
              Cut(
                id: const CutId('cut-1'),
                name: 'Cut',
                layers: const [],
                duration: 48,
                canvasSize: const CanvasSize(width: 1920, height: 1080),
              ),
            ],
          ),
        ],
        createdAt: DateTime.utc(2024),
      ),
    );
    historyManager = HistoryManager();
    coordinator = CutCommandCoordinator(
      repository: repository,
      editingSession: EditingSessionState(activeCutId: const CutId('cut-1')),
      historyManager: historyManager,
    );
  });

  CutCamera activeCamera() =>
      repository.requireProject().tracks.single.cuts.single.camera;

  group('setCutCameraKeyframe', () {
    test('adds a keyframe undoably', () {
      coordinator.setCutCameraKeyframe(
        cutId: const CutId('cut-1'),
        frameIndex: 12,
        pose: _pose(x: 100),
      );

      expect(activeCamera().keyframeAt(12), _pose(x: 100));

      historyManager.undo();
      expect(activeCamera().isEmpty, isTrue);

      historyManager.redo();
      expect(activeCamera().keyframeAt(12), _pose(x: 100));
    });

    test('replaces an existing keyframe at the same index', () {
      coordinator.setCutCameraKeyframe(
        cutId: const CutId('cut-1'),
        frameIndex: 12,
        pose: _pose(x: 100),
      );
      coordinator.setCutCameraKeyframe(
        cutId: const CutId('cut-1'),
        frameIndex: 12,
        pose: _pose(x: 200),
      );

      expect(activeCamera().keyframeAt(12), _pose(x: 200));
      expect(activeCamera().keyframes.length, 1);

      historyManager.undo();
      expect(activeCamera().keyframeAt(12), _pose(x: 100));
    });

    test('same pose at the same index is a no-op without history entry', () {
      coordinator.setCutCameraKeyframe(
        cutId: const CutId('cut-1'),
        frameIndex: 12,
        pose: _pose(x: 100),
      );
      coordinator.setCutCameraKeyframe(
        cutId: const CutId('cut-1'),
        frameIndex: 12,
        pose: _pose(x: 100),
      );

      expect(historyManager.undoCount, 1);
    });

    test('rejects negative frame indexes', () {
      expect(
        () => coordinator.setCutCameraKeyframe(
          cutId: const CutId('cut-1'),
          frameIndex: -1,
          pose: _pose(x: 0),
        ),
        throwsArgumentError,
      );
    });
  });

  group('removeCutCameraKeyframe', () {
    test('removes a keyframe undoably', () {
      coordinator.setCutCameraKeyframe(
        cutId: const CutId('cut-1'),
        frameIndex: 12,
        pose: _pose(x: 100),
      );

      coordinator.removeCutCameraKeyframe(
        cutId: const CutId('cut-1'),
        frameIndex: 12,
      );
      expect(activeCamera().isEmpty, isTrue);

      historyManager.undo();
      expect(activeCamera().keyframeAt(12), _pose(x: 100));
    });

    test('missing keyframe is a no-op without history entry', () {
      coordinator.removeCutCameraKeyframe(
        cutId: const CutId('cut-1'),
        frameIndex: 12,
      );

      expect(historyManager.canUndo, isFalse);
    });
  });

  group('clearCutCamera', () {
    test('clears all keyframes undoably', () {
      coordinator.setCutCameraKeyframe(
        cutId: const CutId('cut-1'),
        frameIndex: 0,
        pose: _pose(x: 0),
      );
      coordinator.setCutCameraKeyframe(
        cutId: const CutId('cut-1'),
        frameIndex: 12,
        pose: _pose(x: 100),
      );

      coordinator.clearCutCamera(cutId: const CutId('cut-1'));
      expect(activeCamera().isEmpty, isTrue);

      historyManager.undo();
      expect(activeCamera().keyframes.length, 2);
    });

    test('empty camera is a no-op without history entry', () {
      coordinator.clearCutCamera(cutId: const CutId('cut-1'));

      expect(historyManager.canUndo, isFalse);
    });
  });
}

CameraPose _pose({required double x}) =>
    CameraPose(center: CanvasPoint(x: x, y: 0));
