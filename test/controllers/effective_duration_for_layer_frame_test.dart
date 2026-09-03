// A FRAME'S EFFECTIVE DURATION IS ITS EXPOSURE'S LENGTH, AND A FRAME THE
// LAYER DOES NOT SHOW HAS NONE.
//
// The mutation campaign (2026-09-03) flipped the null check that guards the
// lookup — the found frame answered null and the missing one crashed — and
// nothing noticed. These pins do.
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

Layer _layer() => Layer(
  id: const LayerId('l'),
  name: 'L',
  frames: [
    Frame(id: const FrameId('a'), duration: 1, strokes: const []),
    Frame(id: const FrameId('b'), duration: 1, strokes: const []),
  ],
  timeline: {0: const TimelineExposure.drawing(FrameId('a'), length: 3)},
);

Project _project(Layer layer) => Project(
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
          layers: [layer],
        ),
      ],
    ),
  ],
);

void main() {
  test('a shown frame answers its exposure length', () {
    final layer = _layer();
    final controller = TimelineController(
      repository: ProjectRepository(initialProject: _project(layer)),
      cutId: _cutId,
    );
    expect(
      controller.effectiveDurationForLayerFrame(
        layer: layer,
        frameId: const FrameId('a'),
      ),
      3,
    );
  });

  test('a frame the timeline does not show answers null, not a crash', () {
    final layer = _layer();
    final controller = TimelineController(
      repository: ProjectRepository(initialProject: _project(layer)),
      cutId: _cutId,
    );
    expect(
      controller.effectiveDurationForLayerFrame(
        layer: layer,
        frameId: const FrameId('b'),
      ),
      isNull,
    );
  });
}
