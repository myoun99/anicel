// CONVERTING A CUT TO A LINKED ONE ROUND-TRIPS: THE NAME-MATCHED LAYER PAIR
// JOINS ONE LINK GROUP, AND UNDO PUTS THE REGISTRY BACK.
//
// No test named this command file (audit 2026-09-03); the planner has its
// own tests and the coordinator reaches the command through the convert
// flow. These pins drive the command directly on two cuts whose drawing
// layers share a name.
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/services/brush_frame_store.dart';
import 'package:anicel/src/services/commands/convert_to_linked_cut_command.dart';
import 'package:anicel/src/services/commands/cut_command_input_planner.dart'
    show planConvertToLinkedCutCommandInput;
import 'package:anicel/src/services/project_repository.dart';

void main() {
  const targetCutId = CutId('target-cut');
  const targetLayerId = LayerId('target-layer');

  late ProjectRepository repository;
  late Cut origin;
  late Layer originLayer;

  setUp(() {
    repository = ProjectRepository(initialProject: createDefaultProject());
    final project = repository.requireProject();
    final track = project.tracks.first;
    origin = track.cuts.first;
    originLayer = origin.layers.first;
    final target = Cut(
      id: targetCutId,
      name: '2',
      duration: origin.duration,
      canvasSize: origin.canvasSize,
      layers: [
        Layer(
          id: targetLayerId,
          name: originLayer.name,
          frames: const [],
          kind: originLayer.kind,
        ),
      ],
    );
    repository.updateProject(
      (current) => current.copyWith(
        tracks: [
          for (final t in current.tracks)
            if (t.id == track.id) t.copyWith(cuts: [...t.cuts, target]) else t,
        ],
      ),
    );
  });

  /// The command with the ids the convert flow plans for it: every row the
  /// plan pairs or unions gets one. Since F-84 that includes the origin's
  /// CAMERA row, which links now, and which this hand-built target has no
  /// camera row to pair with.
  ConvertToLinkedCutCommand command() {
    final cuts = repository.requireProject().tracks.first.cuts;
    final input = planConvertToLinkedCutCommandInput(
      project: repository.requireProject(),
      originCut: cuts.firstWhere((cut) => cut.id == origin.id),
      targetCut: cuts.firstWhere((cut) => cut.id == targetCutId),
    );
    return ConvertToLinkedCutCommand(
      repository: repository,
      brushFrameStore: BrushFrameStore(),
      originCutId: origin.id,
      targetCutId: targetCutId,
      unionLayerIdMap: input.unionLayerIdMap,
      newGroupIdBySource: input.newGroupIdBySource,
      coveringFrameIdBySource: input.coveringFrameIdBySource,
    );
  }

  bool linked() {
    final group = repository.requireProject().linkRegistry.groupOf(
      cutId: targetCutId,
      layerId: targetLayerId,
    );
    return group != null &&
        group.contains(cutId: origin.id, layerId: originLayer.id);
  }

  test('execute links the name-matched pair', () {
    expect(linked(), isFalse, reason: 'fixture');
    command().execute();
    expect(linked(), isTrue);
  });

  test('undo puts the registry back', () {
    final groupsBefore = repository.requireProject().linkRegistry.groups.length;
    final convert = command();
    convert.execute();
    convert.undo();
    expect(linked(), isFalse);
    expect(
      repository.requireProject().linkRegistry.groups.length,
      groupsBefore,
    );
  });

  test("a target with no camera row gains a linked copy of the origin's "
      '(F-84), and undo takes it back out', () {
    Iterable<Layer> cameras() => repository
        .requireProject()
        .tracks
        .first
        .cuts
        .firstWhere((cut) => cut.id == targetCutId)
        .layers
        .where((layer) => layer.kind == LayerKind.camera);
    expect(cameras(), isEmpty, reason: 'fixture');

    final convert = command()..execute();
    expect(cameras(), hasLength(1));

    convert.undo();
    expect(cameras(), isEmpty);
  });

  test('undo before execute is refused', () {
    expect(command().undo, throwsStateError);
  });
}
