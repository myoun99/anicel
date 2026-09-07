// A SLIDING SE ROW PREVIEWS ITS GLOBAL FORM TOO — THE STORYBOARD'S STRIPS
// READ THAT MAP.
//
// A survivor of the mutation campaign (2026-09-04, the slide preview cut):
// the global-form entry was dropped from the preview and every range-move
// test stayed green. C2 (2026-08-17) is why it exists: the storyboard's
// track-global SE strips resolve the preview's global map, so a move
// follows the hand live there instead of jumping on release. This pin
// slides one SE row on the track axis and reads both maps.
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
import 'package:anicel/src/models/timeline_row_address.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/timeline/timeline_drag_preview.dart';

const _trackId = TrackId('slide-track');
const _seLayerId = LayerId('slide-se');

Cut _cut(String id, int duration) => Cut(
  id: CutId(id),
  name: id,
  duration: duration,
  canvasSize: const CanvasSize(width: 16, height: 16),
  layers: [
    Layer(
      id: LayerId('$id-anim'),
      name: 'A',
      frames: const [],
      timeline: const {},
    ),
  ],
);

Project _project() => Project(
  id: const ProjectId('slide-project'),
  name: 'Slide',
  createdAt: DateTime.utc(2026, 9, 4),
  tracks: [
    Track(
      id: _trackId,
      name: 'Video',
      cuts: [_cut('cut-1', 8), _cut('cut-2', 6)],
      seLayers: [
        Layer(
          id: _seLayerId,
          name: 'S1',
          kind: LayerKind.se,
          frames: [
            Frame(
              id: const FrameId('se-one'),
              duration: 3,
              name: 'One!',
              strokes: const [],
            ),
          ],
          timeline: const {
            2: TimelineExposure.drawing(FrameId('se-one'), length: 3),
          },
        ),
      ],
    ),
  ],
);

void main() {
  test('a track-axis slide previews the SE row in BOTH maps, moved', () {
    final session = EditorSessionManager(initialProject: _project());
    addTearDown(session.dispose);
    session.updateTrackRowRangeSelectionByFrame(
      layerId: _seLayerId,
      anchorGlobalFrame: 2,
      headGlobalFrame: 4,
      headRow: const LayerRowAddress(_seLayerId),
    );
    expect(session.rangeMove.beginTrackRangeMoveDrag(), isTrue);
    session.rangeMove.updateFrameRangeMoveDrag(frameDelta: 1);

    final preview = session.dragPreview.value;
    expect(preview, isA<BlockMoveDragPreview>());
    final blocks = preview! as BlockMoveDragPreview;
    final global = blocks.previewGlobalLayers[_seLayerId];
    expect(
      global,
      isNotNull,
      reason: "the storyboard's global SE strips resolve this map (C2)",
    );
    expect(global!.timeline.keys, [3], reason: 'the global form moved by one');
    expect(blocks.previewLayers[_seLayerId], isNotNull);
    session.rangeMove.cancelFrameRangeMoveDrag();
  });
}
