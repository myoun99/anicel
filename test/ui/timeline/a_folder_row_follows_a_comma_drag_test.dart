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
import 'package:anicel/src/models/timeline_coverage.dart'
    show TimelineBlockEdge;
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/ui/timeline/timeline_orientation.dart';

import '../../helpers/timeline_host.dart';
import 'timeline_cell_probe.dart';

/// 🐛folder-band-lags-a-comma-drag (10-27): a folder's row is what its rows
/// hold (F-311), so it follows the hand as they do — and it did for a block
/// MOVE alone. A comma drag on a row in it drew the folder as it stood
/// until the release. Read off the folder row each grid draws.
void main() {
  Layer row(String id, int start, int length) => Layer(
    id: LayerId(id),
    name: id,
    folderId: const LayerId('F'),
    frames: [
      Frame(id: FrameId('$id$start'), duration: 1, strokes: const []),
    ],
    timeline: {
      start: TimelineExposure.drawing(FrameId('$id$start'), length: length),
    },
  );

  /// F holds a over 0..4 and b over 6..8.
  Project film() => Project(
    id: const ProjectId('p'),
    name: 'P',
    createdAt: DateTime.utc(2026, 10, 28),
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
              row('a', 0, 4),
              row('b', 6, 2),
              Layer(
                id: const LayerId('F'),
                name: 'F',
                kind: LayerKind.folder,
                frames: const [],
                timeline: const {},
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
    testWidgets('$prefix: the folder\'s row stretches with a comma its row '
        'drags, and stands back when the drag is let go', (tester) async {
      final session = await pumpTimelineHost(
        tester,
        film(),
        orientation: orientation,
      );
      Map<int, int> folderBlocks() => {
        for (final MapEntry(:key, :value)
            in timelineRowCellsPainterFor(
              tester,
              'F',
              prefix: prefix,
            ).layer.timeline.entries)
          if (!value.ghost) key: value.length!,
      };
      expect(folderBlocks(), {0: 4, 6: 2}, reason: '⛔전제');

      expect(
        session.edgeDrag.beginExposureEdgeDrag(
          layerId: const LayerId('a'),
          blockStartIndex: 0,
          edge: TimelineBlockEdge.end,
        ),
        isTrue,
      );
      session.edgeDrag.updateExposureEdgeDrag(2);
      await tester.pump();
      expect(folderBlocks(), {0: 8}, reason: 'a reaches b under the hand');

      session.edgeDrag.cancelExposureEdgeDrag();
      await tester.pump();
      expect(folderBlocks(), {0: 4, 6: 2});
    });
  }
}
