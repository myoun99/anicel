import 'package:flutter_test/flutter_test.dart';
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
import 'package:anicel/src/services/commands/update_layer_timeline_command.dart';
import 'package:anicel/src/services/history_manager.dart';
import 'package:anicel/src/services/project_repository.dart';

void main() {
  test('execute applies after layer and undo restores before layer', () {
    final before = Layer(
      id: const LayerId('layer-1'),
      name: 'Layer 1',
      frames: [Frame(id: const FrameId('a'), duration: 1, strokes: const [])],
    );
    final after = before.copyWith(
      timeline: {0: TimelineExposure.drawing(const FrameId('a'), length: 4)},
    );
    final repository = ProjectRepository(initialProject: _project(before));
    final history = HistoryManager();

    history.execute(
      UpdateLayerTimelineCommand(
        repository: repository,
        before: before,
        after: after,
      ),
    );

    expect(_layer(repository).timeline[0]?.length, 4);

    history.undo();

    expect(_layer(repository), before);

    history.redo();

    expect(_layer(repository), after);
  });
}

Project _project(Layer layer) {
  return Project(
    id: const ProjectId('project-1'),
    name: 'Project',
    createdAt: DateTime.utc(2026),
    tracks: [
      Track(
        id: const TrackId('track-1'),
        name: 'Track',
        cuts: [
          Cut(
            id: const CutId('cut-1'),
            name: 'Cut',
            duration: 1,
            canvasSize: const CanvasSize(width: 100, height: 100),
            layers: [layer],
          ),
        ],
      ),
    ],
  );
}

Layer _layer(ProjectRepository repository) {
  return repository.requireProject().tracks.single.cuts.single.layers.single;
}
