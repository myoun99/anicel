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
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/commands/cut_command_input_planner.dart';

void main() {
  group('planCreateCutCommandInput', () {
    test('returns deterministic first-available IDs without mutation', () {
      final project = _projectWithCuts([
        _cut(
          id: 'cut-1',
          layers: [
            _layer(id: 'layer-1'),
            _layer(id: 'layer-3'),
          ],
        ),
        _cut(id: 'cut-2', layers: const []),
      ]);
      final before = project.toJson();

      final plan = planCreateCutCommandInput(project);

      expect(plan.cutId, const CutId('cut-3'));
      expect(plan.layerId, const LayerId('layer-2'));
      expect(_allCutIds(project), isNot(contains(plan.cutId)));
      expect(_allLayerIds(project), isNot(contains(plan.layerId)));
      expect(project.toJson(), before);
    });
  });

  group('planDeleteLastCutReplacementInput', () {
    test('returns deterministic first-available IDs without mutation', () {
      final project = _projectWithCuts([
        _cut(
          id: 'cut-1',
          layers: [_layer(id: 'layer-2')],
        ),
        _cut(
          id: 'cut-3',
          layers: [_layer(id: 'layer-1')],
        ),
      ]);
      final before = project.toJson();

      final plan = planDeleteLastCutReplacementInput(project);

      expect(plan.replacementCutId, const CutId('cut-2'));
      expect(plan.replacementLayerId, const LayerId('layer-3'));
      expect(_allCutIds(project), isNot(contains(plan.replacementCutId)));
      expect(_allLayerIds(project), isNot(contains(plan.replacementLayerId)));
      expect(project.toJson(), before);
    });
  });

  group('planDuplicateCutCommandInput', () {
    test('plans new IDs and complete maps without mutation', () {
      final source = _cut(
        id: 'cut-1',
        layers: [
          _layer(id: 'layer-1', frames: [_frame('frame-1'), _frame('frame-3')]),
          _layer(id: 'layer-3', frames: [_frame('frame-4')]),
        ],
      );
      final project = _projectWithCuts([
        source,
        _cut(
          id: 'cut-2',
          layers: [
            _layer(id: 'layer-4', frames: [_frame('frame-2')]),
          ],
        ),
      ]);
      final before = project.toJson();

      final plan = planDuplicateCutCommandInput(
        project: project,
        sourceCut: source,
      );

      expect(plan.newCutId, const CutId('cut-3'));
      expect(_allCutIds(project), isNot(contains(plan.newCutId)));
      expect(
        plan.layerIdMap.keys,
        unorderedEquals([const LayerId('layer-1'), const LayerId('layer-3')]),
      );
      expect(
        plan.frameIdMap.keys,
        unorderedEquals([
          const FrameId('frame-1'),
          const FrameId('frame-3'),
          const FrameId('frame-4'),
        ]),
      );
      expect(
        plan.layerIdMap[const LayerId('layer-1')],
        const LayerId('layer-2'),
      );
      expect(
        plan.layerIdMap[const LayerId('layer-3')],
        const LayerId('layer-5'),
      );
      expect(
        plan.frameIdMap[const FrameId('frame-1')],
        const FrameId('frame-5'),
      );
      expect(
        plan.frameIdMap[const FrameId('frame-3')],
        const FrameId('frame-6'),
      );
      expect(
        plan.frameIdMap[const FrameId('frame-4')],
        const FrameId('frame-7'),
      );
      for (final newLayerId in plan.layerIdMap.values) {
        expect(_allLayerIds(project), isNot(contains(newLayerId)));
      }
      for (final newFrameId in plan.frameIdMap.values) {
        expect(_allFrameIds(project), isNot(contains(newFrameId)));
      }
      for (final entry in plan.layerIdMap.entries) {
        expect(entry.value, isNot(entry.key));
      }
      for (final entry in plan.frameIdMap.entries) {
        expect(entry.value, isNot(entry.key));
      }
      expect(plan.layerIdMap.values.toSet(), hasLength(plan.layerIdMap.length));
      expect(plan.frameIdMap.values.toSet(), hasLength(plan.frameIdMap.length));
      expect(project.toJson(), before);
    });

    test('plans an empty source cut without throwing', () {
      final source = _cut(id: 'cut-1', layers: const []);
      final project = _projectWithCuts([source]);
      final before = project.toJson();

      final plan = planDuplicateCutCommandInput(
        project: project,
        sourceCut: source,
      );

      expect(plan.newCutId, const CutId('cut-2'));
      expect(plan.layerIdMap, isEmpty);
      expect(plan.frameIdMap, isEmpty);
      expect(project.toJson(), before);
    });

    test('plans source layers with no frames without throwing', () {
      final source = _cut(
        id: 'cut-1',
        layers: [
          _layer(id: 'layer-1'),
          _layer(id: 'layer-2'),
        ],
      );
      final project = _projectWithCuts([source]);
      final before = project.toJson();

      final plan = planDuplicateCutCommandInput(
        project: project,
        sourceCut: source,
      );

      expect(plan.newCutId, const CutId('cut-2'));
      expect(
        plan.layerIdMap.keys,
        unorderedEquals([const LayerId('layer-1'), const LayerId('layer-2')]),
      );
      expect(plan.layerIdMap.values.toSet(), hasLength(2));
      expect(plan.frameIdMap, isEmpty);
      expect(project.toJson(), before);
    });
  });
}

Project _projectWithCuts(List<Cut> cuts) {
  return Project(
    id: const ProjectId('project-1'),
    name: 'Project',
    tracks: [Track(id: const TrackId('track-1'), name: 'Track 1', cuts: cuts)],
    createdAt: DateTime.utc(2024),
  );
}

Cut _cut({required String id, required List<Layer> layers}) {
  return Cut(
    id: CutId(id),
    name: id,
    layers: layers,
    duration: 1,
    canvasSize: const CanvasSize(width: 1280, height: 720),
  );
}

Layer _layer({required String id, List<Frame> frames = const []}) {
  return Layer(id: LayerId(id), name: id, frames: frames);
}

Frame _frame(String id) {
  return Frame(id: FrameId(id), duration: 1, strokes: const []);
}

Set<CutId> _allCutIds(Project project) {
  return {
    for (final track in project.tracks)
      for (final cut in track.cuts) cut.id,
  };
}

Set<LayerId> _allLayerIds(Project project) {
  return {
    for (final track in project.tracks)
      for (final cut in track.cuts)
        for (final layer in cut.layers) layer.id,
  };
}

Set<FrameId> _allFrameIds(Project project) {
  return {
    for (final track in project.tracks)
      for (final cut in track.cuts)
        for (final layer in cut.layers)
          for (final frame in layer.frames) frame.id,
  };
}
