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
import 'package:anicel/src/models/timeline_coverage.dart'
    show TimelineBlockEdge;
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/ui/timeline/timeline_orientation.dart';

import '../../helpers/dots_at.dart';
import '../../helpers/timeline_host.dart';
import 'timeline_cell_probe.dart';

/// 🗣️F-519 (유저 2026-10-31): 「프레임 블록에 붙이는 중간나누기마크, 지금
/// 앞엣지를 움직일때 같이움직이는데. 이게아니라 뒤엣지 움직일때
/// 같이움직이도록」 — read where the hand sees it: off the row each grid
/// draws, under the drag and after it.
void main() {
  const row = LayerId('a');

  /// a: one block over cells 4..12, its dots on cells 7 and 10.
  Project film() => Project(
    id: const ProjectId('p'),
    name: 'P',
    createdAt: DateTime.utc(2026, 10, 31),
    tracks: [
      Track(
        id: const TrackId('t'),
        name: 'Video',
        cuts: [
          Cut(
            id: const CutId('c'),
            name: '1',
            duration: 24,
            canvasSize: const CanvasSize(width: 640, height: 360),
            layers: [
              Layer(
                id: row,
                name: 'a',
                frames: [
                  Frame(
                    id: const FrameId('a1'),
                    duration: 1,
                    strokes: const [],
                  ),
                ],
                timeline: {
                  4: TimelineExposure.drawing(
                    const FrameId('a1'),
                    length: 8,
                    breakdownMarks: dotsAt(const [3, 6]),
                  ),
                },
              ),
            ],
          ),
        ],
      ),
    ],
  );

  for (final (orientation, prefix) in [
    (TimelineOrientation.horizontal, 'timeline'),
    (TimelineOrientation.vertical, 'xsheet'),
  ]) {
    for (final (name, edge, delta, cells) in [
      ('the tail grown', TimelineBlockEdge.end, 3, [10, 13]),
      ('the tail drawn back', TimelineBlockEdge.end, -2, [5, 8]),
      ('the head grown', TimelineBlockEdge.start, -2, [7, 10]),
      ('the head drawn in', TimelineBlockEdge.start, 2, [7, 10]),
    ]) {
      testWidgets('$prefix: $name — the dots stand on $cells under the hand '
          'and after it', (tester) async {
        final session = await pumpTimelineHost(
          tester,
          film(),
          orientation: orientation,
        );
        List<int> dotCells() {
          final timeline = timelineRowCellsPainterFor(
            tester,
            'a',
            prefix: prefix,
          ).layer.timeline;
          return [
            for (final MapEntry(key: start, value: block) in timeline.entries)
              for (final offset in block.breakdownOffsets) start + offset,
          ];
        }

        expect(dotCells(), [7, 10], reason: '⛔전제');
        expect(
          session.edgeDrag.beginExposureEdgeDrag(
            layerId: row,
            blockStartIndex: 4,
            edge: edge,
          ),
          isTrue,
        );
        session.edgeDrag.updateExposureEdgeDrag(delta);
        await tester.pump();
        expect(dotCells(), cells, reason: 'under the hand');

        session.edgeDrag.endExposureEdgeDrag();
        await tester.pump();
        expect(dotCells(), cells, reason: 'after it');

        session.playbackRig.prerenderScheduler.cancel();
      });
    }
  }
}
