import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/camera_instruction.dart';
import 'package:anicel/src/models/canvas_point.dart';
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
import 'package:anicel/src/models/property_track.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/timeline_row_address.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/models/transform_track.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';

/// 🚨H20 (유저 2026-08-23): 「선택한 곳만 움직이게」 — a band moves what each
/// of its rows holds, its lane rows their keys, down whichever path its move
/// takes: a hop onto a row of the same kind, and a band of nothing but
/// lanes.
///
/// 🔬The mutants of lane `lane-press-keeps-a-mixed-run` (2026-10-25): a hop
/// of an SE row or of a direction row could leave the band's keys where
/// they were, and a band of lanes alone could land its keys and leave its
/// selection behind, and no test said so.
TransformTrack _positionKeyedAt(List<int> frames) => TransformTrack.empty()
    .copyWith(
      position: frames.fold<PropertyTrack<CanvasPoint>>(
        PropertyTrack<CanvasPoint>.empty(),
        (track, frame) =>
            track.withKey(frame, CanvasPoint(x: 1, y: frame.toDouble())),
      ),
    );

const _s1 = LayerId('s1');
const _s2 = LayerId('s2');

/// Two SE rows on the track: S1 sounding from 2 for three frames with
/// Position keys at 2 and 4, S2 empty.
Project _withSeRows() => Project(
  id: const ProjectId('p'),
  name: 'P',
  createdAt: DateTime.utc(2026, 10, 25),
  tracks: [
    Track(
      id: const TrackId('t'),
      name: 'V',
      cuts: [
        Cut(
          id: const CutId('c'),
          name: '1',
          duration: 12,
          canvasSize: const CanvasSize(width: 32, height: 32),
          layers: [Layer(id: const LayerId('a'), name: 'A', frames: const [])],
        ),
      ],
      seLayers: [
        Layer(
          id: _s1,
          name: 'S1',
          kind: LayerKind.se,
          transformTrack: _positionKeyedAt([2, 4]),
          frames: [
            Frame(
              id: const FrameId('one'),
              duration: 3,
              name: 'One!',
              strokes: const [],
            ),
          ],
          timeline: const {
            2: TimelineExposure.drawing(FrameId('one'), length: 3),
          },
        ),
        Layer(
          id: _s2,
          name: 'S2',
          kind: LayerKind.se,
          frames: const [],
          timeline: const {},
        ),
      ],
    ),
  ],
);

const _a = LayerId('a');
const _x = LayerId('x');

/// A holding one three-frame drawing from 0, and X — attached to A — whose
/// own track keys Position at 0 and 2.
Project _withAnAttachRow() => Project(
  id: const ProjectId('p'),
  name: 'P',
  createdAt: DateTime.utc(2026, 10, 25),
  tracks: [
    Track(
      id: const TrackId('t'),
      name: 'V',
      cuts: [
        Cut(
          id: const CutId('c'),
          name: '1',
          duration: 12,
          canvasSize: const CanvasSize(width: 32, height: 32),
          layers: [
            Layer(
              id: _a,
              name: 'A',
              frames: [
                Frame(
                  id: const FrameId('a-f'),
                  duration: 3,
                  name: 'a',
                  strokes: const [],
                ),
              ],
              timeline: const {
                0: TimelineExposure.drawing(FrameId('a-f'), length: 3),
              },
            ),
            Layer(
              id: _x,
              name: 'X',
              attachedToLayerId: _a,
              transformTrack: _positionKeyedAt([0, 2]),
              frames: const [],
            ),
          ],
        ),
      ],
    ),
  ],
);

EditorSessionManager _session(Project project) {
  final s = EditorSessionManager(initialProject: project);
  addTearDown(s.dispose);
  return s;
}

List<int> _keysOf(Layer layer) =>
    layer.transformTrack.position.keys.keys.toList();

void main() {
  group('a hop onto a row of its own kind', () {
    test('an SE row carried onto another takes its sound there, and its '
        'keys go along their own lane', () {
      final s = _session(_withSeRows());
      Layer se(LayerId id) => s.repository
          .requireProject()
          .tracks
          .single
          .seLayers
          .firstWhere((layer) => layer.id == id);
      s.updateFrameRangeSelectionDrag(
        layerId: _s1,
        anchorIndex: 2,
        headIndex: 4,
        spanRows: const [LayerRowAddress(_s1), LaneRowAddress(_s1, 'position')],
      );

      expect(s.rangeMove.beginFrameRangeMoveDrag(_s1), isTrue);
      s.rangeMove.updateFrameRangeMoveDrag(frameDelta: 1, targetLayerId: _s2);
      s.rangeMove.endFrameRangeMoveDrag();

      expect(se(_s2).timeline.keys, [3]);
      expect(se(_s1).timeline, isEmpty);
      expect(_keysOf(se(_s1)), [3, 5]);
    });

    test('a direction row carried onto another takes its span there, and '
        'the keys its band holds go along their own lane', () {
      final s = _session(createDefaultProject());
      Layer row(LayerId id) =>
          s.requireActiveCut.layers.firstWhere((layer) => layer.id == id);
      final drawing = s.layers.firstWhere(
        (layer) => layer.kind == LayerKind.animation,
      );
      final source = s.layers.firstWhere(
        (layer) => layer.kind == LayerKind.instruction,
      );
      s.instructionVerbs.upsertInstructionEventAt(
        source.id,
        2,
        const InstructionEvent(instructionId: 'pan', length: 2),
        createLengthFrames: 2,
      );
      s.layerStack.addLayerOfKind(LayerKind.instruction);
      final target = s.requireActiveCut.layers.lastWhere(
        (layer) =>
            layer.kind == LayerKind.instruction && layer.id != source.id,
      );
      s.laneVerbs.updateLayerTransformTrack(
        drawing.id,
        _positionKeyedAt([2]),
      );
      s.updateFrameRangeSelectionDrag(
        layerId: source.id,
        anchorIndex: 2,
        headIndex: 3,
        spanRows: [
          LayerRowAddress(source.id),
          LaneRowAddress(drawing.id, 'position'),
        ],
      );

      expect(s.rangeMove.beginFrameRangeMoveDrag(source.id), isTrue);
      s.rangeMove.updateFrameRangeMoveDrag(
        frameDelta: 1,
        targetLayerId: target.id,
      );
      s.rangeMove.endFrameRangeMoveDrag();

      expect(row(target.id).instructions.keys, [3]);
      expect(row(source.id).instructions, isEmpty);
      expect(_keysOf(row(drawing.id)), [3]);
    });
  });

  test('a band of nothing but lanes stands where its keys went', () {
    final s = _session(createDefaultProject());
    final camera = s.layers.firstWhere((l) => l.kind == LayerKind.camera);
    s.selectLayer(camera.id);
    s.camera.updateCameraTrack(
      camera.id,
      _positionKeyedAt([2]),
      description: 'fixture',
    );
    s.updateFrameRangeSelectionDrag(
      layerId: camera.id,
      anchorIndex: 2,
      headIndex: 2,
    );

    expect(s.rangeMove.beginFrameRangeMoveDrag(), isTrue);
    s.rangeMove.updateFrameRangeMoveDrag(frameDelta: 3);
    s.rangeMove.endFrameRangeMoveDrag();

    expect(s.activeCutOrNull!.camera.track.position.keys.keys, [5]);
    final band = s.frameRangeSelection.value!;
    expect((band.startIndex, band.endIndexExclusive), (5, 6));
  });

  // An attach row's keys are its base's: every lane verb leaves its own
  // track alone ([LaneVerbs] stands it down), and so does a band's move.
  test('an attach row\'s lanes in a band stand down, its base\'s block goes',
      () {
    final s = _session(_withAnAttachRow());
    s.updateFrameRangeSelectionDrag(
      layerId: _a,
      anchorIndex: 0,
      headIndex: 2,
      spanRows: const [LayerRowAddress(_a), LaneRowAddress(_x, 'position')],
    );

    expect(s.rangeMove.beginFrameRangeMoveDrag(_a), isTrue);
    s.rangeMove.updateFrameRangeMoveDrag(frameDelta: 2, targetLayerId: _a);
    s.rangeMove.endFrameRangeMoveDrag();

    expect(s.commitLayerById(_a)!.timeline.keys, [2]);
    expect(_keysOf(s.commitLayerById(_x)!), [0, 2]);
  });
}
