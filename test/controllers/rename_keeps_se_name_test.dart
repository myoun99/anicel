// RENAMING A FRAME LEAVES ITS SE NAME ALONE UNLESS THE CALL SAYS OTHERWISE.
//
// A survivor of the mutation campaign (2026-09-03): `renameFrameForLayer`'s
// `updateSeName` default flipped to true, so every plain rename also wrote
// the (absent) SE name and wiped the one the frame had. Nothing noticed;
// this pins the default beside the opt-in.
//
// ↩️I-20 (2026-10-01): the opt-in is a record now — `seEntry` carries the
// speaker AND the delivery, so no flag answers for two fields.
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/controllers/timeline_controller.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/se_line_type.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/project_repository.dart';

const _cutId = CutId('c');
const _layerId = LayerId('l');
const _frameId = FrameId('a');

Project _project() => Project(
  id: const ProjectId('p'),
  name: 'P',
  createdAt: DateTime.utc(2026, 9, 3),
  tracks: [
    Track(
      id: const TrackId('t'),
      name: 'V',
      cuts: [
        Cut(
          id: _cutId,
          name: '1',
          duration: 4,
          canvasSize: const CanvasSize(width: 32, height: 32),
          layers: [
            Layer(
              id: _layerId,
              name: 'L',
              frames: [
                Frame(
                  id: _frameId,
                  duration: 1,
                  strokes: const [],
                  name: 'A',
                  seName: 'boom',
                  seType: SeLineType.off,
                ),
              ],
              timeline: {
                0: const TimelineExposure.drawing(_frameId, length: 2),
              },
            ),
          ],
        ),
      ],
    ),
  ],
);

Frame _frameOf(ProjectRepository repository) => repository
    .currentProject!
    .tracks
    .single
    .cuts
    .single
    .layers
    .single
    .frames
    .single;

void main() {
  test('a plain rename keeps the SE name and the delivery', () {
    final repository = ProjectRepository(initialProject: _project());
    final controller = TimelineController(
      repository: repository,
      cutId: _cutId,
    );
    controller.renameFrameForLayer(
      layerId: _layerId,
      frameId: _frameId,
      name: 'A2',
    );
    expect(_frameOf(repository).name, 'A2');
    expect(_frameOf(repository).seName, 'boom');
    expect(_frameOf(repository).seType, SeLineType.off);
  });

  test('an SE entry edit writes the fields the call carries — name and '
      'delivery (I-20) — in the same step as the dialogue', () {
    final repository = ProjectRepository(initialProject: _project());
    final controller = TimelineController(
      repository: repository,
      cutId: _cutId,
    );
    controller.renameFrameForLayer(
      layerId: _layerId,
      frameId: _frameId,
      name: 'B',
      seEntry: (seName: 'crash', seType: SeLineType.mono),
    );
    expect(_frameOf(repository).name, 'B');
    expect(_frameOf(repository).seName, 'crash');
    expect(_frameOf(repository).seType, SeLineType.mono);
  });
}
