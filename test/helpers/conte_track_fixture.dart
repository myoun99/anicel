import 'dart:collection';

import 'package:anicel/src/models/camera_instruction.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/layer_section_defaults.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';

/// A film whose one track has something on every storyboard row, laid out
/// so the flip's material is visible on each:
///
/// - `cut-1` is frames 0..12 and holds a CONTE row of three panels, 4 frames
///   each; then a three-frame GAP; `cut-2` is frames 15..25, no conte row.
/// - The S row sounds at [2, 5) and [17, 19) — one in each cut.
/// - The transition row fades inside each cut, [6, 9) and [18, 20) —
///   one-sided fades, which a cut's row shows where they are (an O.L shows
///   only across a boundary).
const conteTrackId = TrackId('t');
const conteSeId = LayerId('se-1');
const conteCelId = LayerId('cut-1-cel');

Project conteTrackProject() {
  Layer cel(String cut) =>
      Layer(id: LayerId('$cut-cel'), name: 'A', frames: const [], timeline: {});
  return Project(
    id: const ProjectId('conte-track'),
    name: 'conte track',
    createdAt: DateTime.utc(2026, 9, 24),
    tracks: [
      Track(
        id: conteTrackId,
        name: 'V',
        cuts: [
          Cut(
            id: const CutId('cut-1'),
            name: '1',
            duration: 12,
            canvasSize: const CanvasSize(width: 32, height: 32),
            layers: [
              cel('cut-1'),
              Layer(
                id: const LayerId('cut-1-conte'),
                name: 'Conte',
                kind: LayerKind.storyboard,
                frames: [
                  for (final id in ['p1', 'p2', 'p3'])
                    Frame(id: FrameId(id), duration: 1, strokes: const []),
                ],
                timeline: {
                  0: const TimelineExposure.drawing(FrameId('p1'), length: 4),
                  4: const TimelineExposure.drawing(FrameId('p2'), length: 4),
                  8: const TimelineExposure.drawing(FrameId('p3'), length: 4),
                },
              ),
            ],
          ),
          Cut(
            id: const CutId('cut-2'),
            name: '2',
            duration: 10,
            leadingGapFrames: 3,
            canvasSize: const CanvasSize(width: 32, height: 32),
            layers: [cel('cut-2')],
          ),
        ],
        seLayers: [
          Layer(
            id: conteSeId,
            name: 'S1',
            kind: LayerKind.se,
            frames: [
              for (final id in ['s1', 's2'])
                Frame(id: FrameId(id), duration: 1, strokes: const []),
            ],
            timeline: {
              2: const TimelineExposure.drawing(FrameId('s1'), length: 3),
              17: const TimelineExposure.drawing(FrameId('s2'), length: 2),
            },
          ),
        ],
        transitionLayer: createTrackTransitionLayer(conteTrackId).copyWith(
          instructions: SplayTreeMap.of({
            6: const InstructionEvent(instructionId: 'fo', length: 3),
            18: const InstructionEvent(instructionId: 'fi', length: 2),
          }),
        ),
      ),
    ],
  );
}
