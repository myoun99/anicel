import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/editing_session_state.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/commands/rename_cut_command.dart';
import 'package:anicel/src/services/history_manager.dart';
import 'package:anicel/src/services/project_repository.dart';

void main() {
  group('RenameCutCommand', () {
    test('renames the target cut by id and allows duplicate names', () {
      final targetLayer = _layer(
        id: 'layer-target',
        name: 'Line',
        frames: [_frame(id: 'frame-1', name: 'A')],
        timeline: {
          0: TimelineExposure.drawing(const FrameId('frame-1'), length: 3),
        },
      );
      final targetCut = _cut(
        id: 'cut-target',
        name: 'Original',
        layers: [targetLayer],
        duration: 48,
        canvasSize: const CanvasSize(width: 1920, height: 1080),
      );
      final otherCut = _cut(id: 'cut-other', name: 'Duplicate');
      final repository = ProjectRepository(
        initialProject: _project(
          tracks: [
            _track(id: 'track-1', name: 'Video', cuts: [targetCut, otherCut]),
          ],
        ),
      );
      final editingSession = EditingSessionState(
        activeCutId: const CutId('cut-other'),
      );

      RenameCutCommand(
        repository: repository,
        cutId: const CutId('cut-target'),
        newName: 'Duplicate',
      ).execute();

      final cuts = repository.requireProject().tracks.single.cuts;
      expect(cuts.first, targetCut.copyWith(name: 'Duplicate'));
      expect(cuts.first.id, targetCut.id);
      expect(cuts.first.layers, [targetLayer]);
      expect(cuts.first.layers.single.frames, targetLayer.frames);
      expect(cuts.first.layers.single.timeline, targetLayer.timeline);
      expect(cuts.first.duration, targetCut.duration);
      expect(cuts.first.canvasSize, targetCut.canvasSize);
      expect(cuts.last, otherCut);
      expect(editingSession.activeCutId, const CutId('cut-other'));
    });

    test('undo restores the previous cut name without changing active cut', () {
      final targetCut = _cut(id: 'cut-target', name: 'Original');
      final repository = ProjectRepository(
        initialProject: _project(
          tracks: [
            _track(id: 'track-1', name: 'Video', cuts: [targetCut]),
          ],
        ),
      );
      final editingSession = EditingSessionState(
        activeCutId: const CutId('cut-target'),
      );
      final historyManager = HistoryManager();

      historyManager.execute(
        RenameCutCommand(
          repository: repository,
          cutId: const CutId('cut-target'),
          newName: 'Renamed',
        ),
      );

      historyManager.undo();

      expect(repository.requireProject().tracks.single.cuts.single, targetCut);
      expect(editingSession.activeCutId, const CutId('cut-target'));
    });

    test('redo restores the new cut name without changing cut identity', () {
      final targetCut = _cut(id: 'cut-target', name: 'Original');
      final repository = ProjectRepository(
        initialProject: _project(
          tracks: [
            _track(id: 'track-1', name: 'Video', cuts: [targetCut]),
          ],
        ),
      );
      final editingSession = EditingSessionState(
        activeCutId: const CutId('cut-target'),
      );
      final historyManager = HistoryManager();
      final command = RenameCutCommand(
        repository: repository,
        cutId: const CutId('cut-target'),
        newName: 'Renamed',
      );

      historyManager.execute(command);
      historyManager.undo();
      historyManager.redo();

      expect(
        repository.requireProject().tracks.single.cuts.single,
        targetCut.copyWith(name: 'Renamed'),
      );
      expect(repository.requireProject().tracks.single.cuts.single.id, cutId);
      expect(editingSession.activeCutId, const CutId('cut-target'));
    });

    test('throws when undo is called before execute', () {
      final repository = ProjectRepository(initialProject: _project());
      final command = RenameCutCommand(
        repository: repository,
        cutId: const CutId('cut-target'),
        newName: 'Renamed',
      );

      expect(command.undo, throwsStateError);
    });

    test('throws when the target cut id is missing', () {
      final repository = ProjectRepository(initialProject: _project());
      final command = RenameCutCommand(
        repository: repository,
        cutId: const CutId('missing'),
        newName: 'Renamed',
      );

      expect(command.execute, throwsStateError);
    });
  });
}

const cutId = CutId('cut-target');

Project _project({List<Track> tracks = const []}) {
  return Project(
    id: const ProjectId('project-1'),
    name: 'Project',
    tracks: tracks,
    createdAt: DateTime.utc(2024),
  );
}

Track _track({
  required String id,
  required String name,
  List<Cut> cuts = const [],
}) {
  return Track(id: TrackId(id), name: name, cuts: cuts);
}

Cut _cut({
  required String id,
  required String name,
  List<Layer> layers = const [],
  int duration = 24,
  CanvasSize canvasSize = const CanvasSize(width: 1280, height: 720),
}) {
  return Cut(
    id: CutId(id),
    name: name,
    layers: layers,
    duration: duration,
    canvasSize: canvasSize,
  );
}

Layer _layer({
  required String id,
  required String name,
  List<Frame> frames = const [],
  Map<int, TimelineExposure>? timeline,
}) {
  return Layer(id: LayerId(id), name: name, frames: frames, timeline: timeline);
}

Frame _frame({required String id, String? name}) {
  return Frame(id: FrameId(id), name: name, duration: 3, strokes: const []);
}
