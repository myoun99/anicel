import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/brush_settings.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/stroke.dart';
import 'package:anicel/src/models/stroke_id.dart';
import 'package:anicel/src/models/stroke_point.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/commands/add_cut_command.dart';
import 'package:anicel/src/services/commands/add_frame_command.dart';
import 'package:anicel/src/services/commands/add_layer_command.dart';
import 'package:anicel/src/services/commands/add_stroke_command.dart';
import 'package:anicel/src/services/commands/add_track_command.dart';
import 'package:anicel/src/services/history_manager.dart';
import 'package:anicel/src/services/project_repository.dart';

void main() {
  group('Add commands', () {
    test('AddTrackCommand executes, undoes, and redoes', () {
      final originalProject = _project();
      final repository = ProjectRepository(initialProject: originalProject);
      final historyManager = HistoryManager();
      final track = _track(id: 'track-1', name: 'Video');

      historyManager.execute(
        AddTrackCommand(repository: repository, track: track),
      );

      expect(repository.requireProject().tracks, [track]);

      historyManager.undo();

      expect(repository.requireProject(), originalProject);
      expect(repository.requireProject().tracks, isEmpty);

      historyManager.redo();

      expect(repository.requireProject().tracks, [track]);
    });

    test('AddCutCommand executes, undoes, and redoes', () {
      final track = _track(id: 'track-1', name: 'Video');
      final originalProject = _project(tracks: [track]);
      final repository = ProjectRepository(initialProject: originalProject);
      final historyManager = HistoryManager();
      final cut = _cut(id: 'cut-1', name: 'Cut 1');

      historyManager.execute(
        AddCutCommand(
          repository: repository,
          trackId: const TrackId('track-1'),
          cut: cut,
        ),
      );

      expect(repository.requireProject().tracks.single.cuts, [cut]);

      historyManager.undo();

      expect(repository.requireProject(), originalProject);
      expect(repository.requireProject().tracks.single.cuts, isEmpty);

      historyManager.redo();

      expect(repository.requireProject().tracks.single.cuts, [cut]);
    });

    test('AddLayerCommand executes, undoes, and redoes', () {
      final cut = _cut(id: 'cut-1', name: 'Cut 1');
      final track = _track(id: 'track-1', name: 'Video', cuts: [cut]);
      final originalProject = _project(tracks: [track]);
      final repository = ProjectRepository(initialProject: originalProject);
      final historyManager = HistoryManager();
      final layer = _layer(id: 'layer-1', name: 'Line');

      historyManager.execute(
        AddLayerCommand(
          repository: repository,
          cutId: const CutId('cut-1'),
          layer: layer,
        ),
      );

      expect(repository.requireProject().tracks.single.cuts.single.layers, [
        layer,
      ]);

      historyManager.undo();

      expect(repository.requireProject(), originalProject);
      expect(
        repository.requireProject().tracks.single.cuts.single.layers,
        isEmpty,
      );

      historyManager.redo();

      expect(repository.requireProject().tracks.single.cuts.single.layers, [
        layer,
      ]);
    });

    test('AddFrameCommand executes, undoes, and redoes', () {
      final layer = _layer(id: 'layer-1', name: 'Line');
      final cut = _cut(id: 'cut-1', name: 'Cut 1', layers: [layer]);
      final track = _track(id: 'track-1', name: 'Video', cuts: [cut]);
      final originalProject = _project(tracks: [track]);
      final repository = ProjectRepository(initialProject: originalProject);
      final historyManager = HistoryManager();
      final frame = _frame(id: 'frame-1');

      historyManager.execute(
        AddFrameCommand(
          repository: repository,
          layerId: const LayerId('layer-1'),
          frame: frame,
        ),
      );

      expect(
        repository
            .requireProject()
            .tracks
            .single
            .cuts
            .single
            .layers
            .single
            .frames,
        [frame],
      );

      historyManager.undo();

      expect(repository.requireProject(), originalProject);
      expect(
        repository
            .requireProject()
            .tracks
            .single
            .cuts
            .single
            .layers
            .single
            .frames,
        isEmpty,
      );

      historyManager.redo();

      expect(
        repository
            .requireProject()
            .tracks
            .single
            .cuts
            .single
            .layers
            .single
            .frames,
        [frame],
      );
    });

    test('AddStrokeCommand executes, undoes, and redoes', () {
      final frame = _frame(id: 'frame-1');
      final layer = _layer(id: 'layer-1', name: 'Line', frames: [frame]);
      final cut = _cut(id: 'cut-1', name: 'Cut 1', layers: [layer]);
      final track = _track(id: 'track-1', name: 'Video', cuts: [cut]);
      final originalProject = _project(tracks: [track]);
      final repository = ProjectRepository(initialProject: originalProject);
      final historyManager = HistoryManager();
      final stroke = _stroke(id: 'stroke-1');

      historyManager.execute(
        AddStrokeCommand(
          repository: repository,
          frameId: const FrameId('frame-1'),
          stroke: stroke,
        ),
      );

      expect(
        repository
            .requireProject()
            .tracks
            .single
            .cuts
            .single
            .layers
            .single
            .frames
            .single
            .strokes,
        [stroke],
      );

      historyManager.undo();

      expect(repository.requireProject(), originalProject);
      expect(
        repository
            .requireProject()
            .tracks
            .single
            .cuts
            .single
            .layers
            .single
            .frames
            .single
            .strokes,
        isEmpty,
      );

      historyManager.redo();

      expect(
        repository
            .requireProject()
            .tracks
            .single
            .cuts
            .single
            .layers
            .single
            .frames
            .single
            .strokes,
        [stroke],
      );
    });

    test('undo before execute throws', () {
      final repository = ProjectRepository(initialProject: _project());
      final command = AddTrackCommand(
        repository: repository,
        track: _track(id: 'track-1', name: 'Video'),
      );

      expect(command.undo, throwsStateError);
    });

    test('missing target propagates repository error', () {
      final repository = ProjectRepository(initialProject: _project());
      final command = AddCutCommand(
        repository: repository,
        trackId: const TrackId('missing'),
        cut: _cut(id: 'cut-1', name: 'Cut 1'),
      );

      expect(command.execute, throwsStateError);
    });
  });
}

Project _project({List<Track> tracks = const []}) {
  return Project(
    id: const ProjectId('project-1'),
    name: 'Project',
    tracks: tracks,
    createdAt: DateTime.utc(2026),
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
}) {
  return Cut(
    id: CutId(id),
    name: name,
    layers: layers,
    duration: 24,
    canvasSize: const CanvasSize(width: 1920, height: 1080),
  );
}

Layer _layer({
  required String id,
  required String name,
  List<Frame> frames = const [],
}) {
  return Layer(id: LayerId(id), name: name, frames: frames);
}

Frame _frame({required String id, List<Stroke> strokes = const []}) {
  return Frame(id: FrameId(id), duration: 1, strokes: strokes);
}

Stroke _stroke({required String id}) {
  return Stroke(
    id: StrokeId(id),
    points: const [StrokePoint(x: 1, y: 2), StrokePoint(x: 3, y: 4)],
    brushSettings: BrushSettings(),
  );
}
