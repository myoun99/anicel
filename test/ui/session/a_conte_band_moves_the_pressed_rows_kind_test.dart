import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_camera.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/timeline_row_address.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';

/// 🗣️conte-v-row-band-moves-cuts-alone-Q1 (유저 2026-10-27): 「지금대로 —
/// 잡은 행 종류만」. A conte band that holds the V row and an S row moves
/// what the row it is pressed on holds: the cuts, by their slots, from the
/// V row; the sounds, by frames, from the S row. The two machines are
/// `CutMoveDrag` and `FrameRangeMoveDrag.beginOnTrackAxis`.
///
/// 🧪Measured with a real mouse before it was asked (2026-10-27, three cuts
/// of 12 and a sound at 14): a sweep from the V row's 13 to S1's 16 stands
/// the band 12..24 over both rows, and each press moved its own kind alone.
const _track = TrackId('kind-track');
const _s1 = LayerId('kind-s1');

Cut _cut(String id) => Cut(
  id: CutId(id),
  name: id,
  duration: 12,
  canvasSize: const CanvasSize(width: 64, height: 64),
  camera: CutCamera.empty(),
  layers: [
    Layer(
      id: LayerId('$id-conte'),
      name: 'Conte',
      kind: LayerKind.storyboard,
      frames: const [],
    ),
  ],
);

EditorSessionManager _session() {
  final session = EditorSessionManager(
    initialProject: Project(
      id: const ProjectId('kind-project'),
      name: 'Kind',
      createdAt: DateTime.utc(2026, 10, 27),
      tracks: [
        Track(
          id: _track,
          name: 'V',
          cuts: [_cut('c1'), _cut('c2'), _cut('c3')],
          seLayers: [
            Layer(
              id: _s1,
              name: 'S1',
              kind: LayerKind.se,
              frames: [
                Frame(
                  id: const FrameId('one'),
                  duration: 2,
                  name: 'One',
                  strokes: const [],
                ),
              ],
              timeline: const {
                14: TimelineExposure.drawing(FrameId('one'), length: 2),
              },
            ),
          ],
        ),
      ],
    ),
  );
  addTearDown(session.dispose);
  // The band over c2 and the sound under it, swept from the V row.
  session.updateStoryboardCutSelectionByFrame(
    anchorGlobalFrame: 13,
    headGlobalFrame: 16,
    trackId: _track,
    spanRows: const [TrackRowAddress(_track), LayerRowAddress(_s1)],
  );
  final band = session.trackFrameRangeSelection.value;
  expect(
    [band?.startFrame, band?.endFrameExclusive, band?.rows],
    [
      12,
      24,
      unorderedEquals(const [TrackRowAddress(_track), LayerRowAddress(_s1)]),
    ],
    reason: '⛔전제: one band over c2 and the sound under it',
  );
  return session;
}

List<String> _cuts(EditorSessionManager s) => [
  for (final cut in s.activeTrack.cuts) cut.id.value,
];

List<int> _sound(EditorSessionManager s) =>
    s.activeTrack.seLayers.single.timeline.keys.toList();

void main() {
  test('pressed on the V row, the band moves the cuts — the sound stays on '
      'its frames', () {
    final s = _session();

    expect(s.cutMove.beginCutMoveDrag(const CutId('c2')), isTrue);
    s.cutMove.updateCutMoveDrag(12);
    s.cutMove.endCutMoveDrag();

    expect(_cuts(s), ['c1', 'c3', 'c2']);
    expect(_sound(s), [14], reason: '「잡은 행 종류만」');
  });

  test('pressed on the S row, the band moves the sound — the cuts keep their '
      'order', () {
    final s = _session();

    expect(s.rangeMove.beginTrackRangeMoveDrag(_s1), isTrue);
    s.rangeMove.updateFrameRangeMoveDrag(frameDelta: 12);
    s.rangeMove.endFrameRangeMoveDrag();

    expect(_sound(s), [26]);
    expect(_cuts(s), ['c1', 'c2', 'c3'], reason: '「잡은 행 종류만」');
  });
}
