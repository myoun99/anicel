import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/clipboard/layer_copy_payload.dart';
import 'package:anicel/src/services/commands/cut_command_input_planner.dart';
import 'package:anicel/src/services/commands/paste_layer_command.dart';
import 'package:anicel/src/services/project_repository.dart';

void main() {
  test('payload preserves source layer display and content fields', () {
    final source = _layer(kind: LayerKind.storyboard);

    final payload = copyLayerToPayload(source);

    expect(payload.name, source.name);
    expect(payload.kind, source.kind);
    expect(payload.isVisible, source.isVisible);
    expect(payload.opacity, source.opacity);
    expect(payload.frames, source.frames);
    expect(payload.timeline, source.timeline);
  });

  test('copying to payload does not mutate repository state', () {
    final repository = ProjectRepository(
      initialProject: _project(_cut(layers: [_layer()])),
    );
    final before = repository.requireProject();

    final payload = copyLayerToPayload(
      before.tracks.single.cuts.single.layers.single,
    );

    expect(payload.name, 'A');
    expect(repository.requireProject(), before);
  });

  test('paste planner creates new IDs, remaps frames, and preserves name', () {
    final project = _project(_cut(layers: [_layer()]));
    final targetCut = project.tracks.single.cuts.single;
    final payload = copyLayerToPayload(targetCut.layers.single);

    final plan = planPasteLayerCommandInput(
      project: project,
      targetCut: targetCut,
      payload: payload,
      insertionIndex: 1,
    );

    expect(plan.layer.id, isNot(targetCut.layers.single.id));
    expect(plan.layer.name, targetCut.layers.single.name);
    expect(
      plan.layer.frames.first.id,
      isNot(targetCut.layers.single.frames.first.id),
    );
    expect(plan.layer.timeline[0]!.frameId, plan.layer.frames.first.id);
    expect(plan.insertionIndex, 1);
  });

  test(
    'paste command undo removes and redo restores same layer at raw index',
    () {
      final repository = ProjectRepository(
        initialProject: _project(_cut(layers: [_layer()])),
      );
      final cut = repository.requireProject().tracks.single.cuts.single;
      final plan = planPasteLayerCommandInput(
        project: repository.requireProject(),
        targetCut: cut,
        payload: copyLayerToPayload(cut.layers.single),
        insertionIndex: 1,
      );
      final command = PasteLayerCommand(
        repository: repository,
        cutId: cut.id,
        layer: plan.layer,
        insertionIndex: plan.insertionIndex,
      );

      command.execute();
      expect(_layers(repository), [cut.layers.single, plan.layer]);
      command.undo();
      expect(_layers(repository), [cut.layers.single]);
      command.execute();
      expect(_layers(repository), [cut.layers.single, plan.layer]);
    },
  );

  test('storyboard payload pastes as storyboard only when target has none', () {
    final storyboardPayload = copyLayerToPayload(
      _layer(kind: LayerKind.storyboard),
    );
    final emptyStoryboardCut = _cut(
      layers: [_layer(id: const LayerId('layer-2'))],
    );
    final withStoryboardCut = _cut(
      layers: [
        _layer(id: const LayerId('layer-2'), kind: LayerKind.storyboard),
      ],
    );

    expect(
      planPasteLayerCommandInput(
        project: _project(emptyStoryboardCut),
        targetCut: emptyStoryboardCut,
        payload: storyboardPayload,
        insertionIndex: 1,
      ).layer.kind,
      LayerKind.storyboard,
    );
    expect(
      planPasteLayerCommandInput(
        project: _project(withStoryboardCut),
        targetCut: withStoryboardCut,
        payload: storyboardPayload,
        insertionIndex: 1,
      ).layer.kind,
      LayerKind.animation,
    );
  });

  test('animation payload always pastes as animation', () {
    final animationPayload = copyLayerToPayload(_layer());
    final targetCut = _cut(
      layers: [
        _layer(id: const LayerId('layer-2'), kind: LayerKind.storyboard),
      ],
    );

    expect(
      planPasteLayerCommandInput(
        project: _project(targetCut),
        targetCut: targetCut,
        payload: animationPayload,
        insertionIndex: 1,
      ).layer.kind,
      LayerKind.animation,
    );
  });
}

List<Layer> _layers(ProjectRepository repository) =>
    repository.requireProject().tracks.single.cuts.single.layers;

Project _project(Cut cut) => Project(
  id: const ProjectId('project'),
  name: 'Project',
  createdAt: DateTime.utc(2026),
  tracks: [
    Track(id: const TrackId('track'), name: 'Track', cuts: [cut]),
  ],
);

Cut _cut({required List<Layer> layers}) => Cut(
  id: const CutId('cut-1'),
  name: 'Cut',
  layers: layers,
  duration: 3,
  canvasSize: const CanvasSize(width: 1920, height: 1080),
);

Layer _layer({
  LayerId id = const LayerId('layer-1'),
  LayerKind kind = LayerKind.animation,
}) => Layer(
  id: id,
  name: 'A',
  kind: kind,
  isVisible: false,
  opacity: 0.5,
  frames: [
    Frame(
      id: const FrameId('frame-1'),
      duration: 1,
      strokes: const [],
      name: 'A1',
    ),
  ],
  timeline: {0: TimelineExposure.drawing(const FrameId('frame-1'), length: 1)},
);
