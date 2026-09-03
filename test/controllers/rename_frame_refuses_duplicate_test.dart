// RENAMING A FRAME TO A NAME ANOTHER FRAME HOLDS IS REFUSED — UNLESS THE
// CALLER SAYS DUPLICATES ARE FINE.
//
// The mutation campaign (2026-09-03) flipped `allowDuplicateName`'s default
// to true and nothing noticed: no test renamed a frame into a clash. These
// pins do, both ways.
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
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/project_repository.dart';

const _cutId = CutId('c');
const _layerId = LayerId('l');

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
          duration: 8,
          canvasSize: const CanvasSize(width: 32, height: 32),
          layers: [
            Layer(
              id: _layerId,
              name: 'L',
              frames: [
                Frame(
                  id: const FrameId('a'),
                  duration: 1,
                  strokes: const [],
                  name: 'A',
                ),
                Frame(
                  id: const FrameId('b'),
                  duration: 1,
                  strokes: const [],
                  name: 'B',
                ),
              ],
              timeline: {
                0: const TimelineExposure.drawing(FrameId('a'), length: 2),
                2: const TimelineExposure.drawing(FrameId('b'), length: 2),
              },
            ),
          ],
        ),
      ],
    ),
  ],
);

String? _nameOf(ProjectRepository repository, FrameId id) => repository
    .currentProject!
    .tracks
    .single
    .cuts
    .single
    .layers
    .single
    .frames
    .firstWhere((frame) => frame.id == id)
    .name;

void main() {
  test('by default the clash is refused and the frame keeps its name', () {
    final repository = ProjectRepository(initialProject: _project());
    final controller = TimelineController(
      repository: repository,
      cutId: _cutId,
    );
    controller.renameFrameForLayer(
      layerId: _layerId,
      frameId: const FrameId('b'),
      name: 'A',
    );
    expect(_nameOf(repository, const FrameId('b')), 'B');
  });

  test('allowDuplicateName lets the clash through', () {
    final repository = ProjectRepository(initialProject: _project());
    final controller = TimelineController(
      repository: repository,
      cutId: _cutId,
    );
    controller.renameFrameForLayer(
      layerId: _layerId,
      frameId: const FrameId('b'),
      name: 'A',
      allowDuplicateName: true,
    );
    expect(_nameOf(repository, const FrameId('b')), 'A');
  });
}
