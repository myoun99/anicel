import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/app_frame_grid_settings.dart';
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
import 'package:anicel/src/ui/timeline/timeline_orientation.dart';

import '../../helpers/timeline_host.dart';
import 'timeline_cell_probe.dart';

/// 🗣️F-489 (유저 2026-10-27): 「이름 없는 블록의 기본 마크1,2인지
/// 설정할수있게 … 기본값은 마크2로 둠」 — the mark an unnamed block's head
/// wears is the user's pick in Preferences ▸ Display, mark 2 until another
/// is picked, and a pick reaches the rows where they stand: on the timeline
/// and on the X-sheet alike.
void main() {
  tearDown(
    () => AppFrameGridSettings.settings.value = const AppFrameGridSettings(),
  );

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
            duration: 12,
            canvasSize: const CanvasSize(width: 640, height: 360),
            layers: [
              Layer(
                id: const LayerId('a'),
                name: 'A',
                frames: [
                  Frame(id: const FrameId('f'), duration: 1, strokes: const []),
                ],
                timeline: const {
                  0: TimelineExposure.drawing(FrameId('f'), length: 3),
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
    testWidgets('$prefix: the unnamed head wears mark 2, and a pick reaches '
        'it where it stands', (tester) async {
      final session = await pumpTimelineHost(
        tester,
        film(),
        orientation: orientation,
      );
      InbetweenMark? head() =>
          timelineCellModel(tester, 'a', 0, prefix: prefix).mark;
      expect(head(), InbetweenMark.two);

      session.appSettings.setFrameGridSettings(
        const AppFrameGridSettings(unnamedMark: InbetweenMark.one),
      );
      await tester.pump();
      expect(head(), InbetweenMark.one);
    });
  }
}
