// A LAYER'S TRANSFORM TRACK ROUND-TRIPS THROUGH ITS COMMAND.
//
// No test named this command file (audit 2026-09-04); the transform lanes
// reached it through the session. These pins drive it directly: execute
// replaces the track, undo restores the track captured at the FIRST
// execute, and a layer that is not there is refused.
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/transform_track.dart';
import 'package:anicel/src/services/commands/update_layer_transform_command.dart';
import 'package:anicel/src/services/project_lookup.dart';
import 'package:anicel/src/services/project_repository.dart';

void main() {
  late ProjectRepository repository;
  late CutId cutId;
  late LayerId layerId;

  setUp(() {
    repository = ProjectRepository(initialProject: createDefaultProject());
    final cut = repository.requireProject().tracks.first.cuts.first;
    cutId = cut.id;
    layerId = cut.layers.first.id;
  });

  Iterable<int> positionKeys() => requireLayerAnywhere(
    repository.requireProject(),
    layerId,
  ).transformTrack.position.keys.keys;

  TransformTrack keyedAt(int frame) => TransformTrack().withKeyframe(
    frame,
    TransformPose(center: CanvasPoint(x: 1, y: 1)),
  );

  test('execute replaces the track, undo restores it, execute re-applies', () {
    final before = positionKeys().toList();
    final command = UpdateLayerTransformCommand(
      repository: repository,
      cutId: cutId,
      layerId: layerId,
      transformTrack: keyedAt(3),
    );
    command.execute();
    expect(positionKeys(), [3]);
    command.undo();
    expect(positionKeys(), before);
    command.execute();
    expect(positionKeys(), [3]);
  });

  test('undo restores what the first execute saw, not a later edit', () {
    final before = positionKeys().toList();
    final command = UpdateLayerTransformCommand(
      repository: repository,
      cutId: cutId,
      layerId: layerId,
      transformTrack: keyedAt(3),
    );
    command.execute();
    UpdateLayerTransformCommand(
      repository: repository,
      cutId: cutId,
      layerId: layerId,
      transformTrack: keyedAt(7),
    ).execute();
    command.undo();
    expect(positionKeys(), before);
  });

  test('a layer that is not there is refused, and undo stays refused', () {
    final command = UpdateLayerTransformCommand(
      repository: repository,
      cutId: cutId,
      layerId: const LayerId('no-such-layer'),
      transformTrack: TransformTrack(),
    );
    expect(command.execute, throwsA(isA<Error>()));
    expect(command.undo, throwsStateError);
  });
}
