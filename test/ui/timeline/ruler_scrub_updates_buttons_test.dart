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
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';

/// 🚨★★★ 유저 #6 (2026-08-14): 「룰러로 이동할때, **블록이 있으면 사용가능**
/// 타임라인버튼 활성화되는식으로 버튼 상태 바꼈으면 좋겠는데 안바뀜.
/// **효율좋게** 하는데 바뀌게 하고싶음. 갱신을 매 룰러 드래그마다가 아니라
/// **해당 인덱스에 버튼이 있으면 한번, 없으면 한번** 이런식으로?」
///
/// ★Both halves are the contract, and the second is the harder one: a scrub
/// raises no session notify on purpose (that is what keeps a ruler drag
/// cheap), so the toolbar never re-asked. A notifier that fires on every
/// crossed frame would fix the staleness and re-introduce exactly the cost
/// the design avoids.
///
/// ⇒ The count is the test. Twenty frames of drag across one block boundary
/// is TWO notifications, not twenty.
void main() {
  EditorSessionManager session() {
    final manager = EditorSessionManager(
      initialProject: Project(
        id: const ProjectId('p'),
        name: 'P',
        createdAt: DateTime.utc(2026, 8, 14),
        tracks: [
          Track(
            id: const TrackId('default-track'),
            name: 'Track',
            cuts: [
              Cut(
                id: const CutId('cut-a'),
                name: 'A',
                duration: 24,
                canvasSize: const CanvasSize(width: 64, height: 64),
                layers: [
                  Layer(
                    id: const LayerId('draw'),
                    name: 'A',
                    frames: [
                      Frame(
                        id: const FrameId('cel'),
                        duration: 4,
                        strokes: const [],
                      ),
                    ],
                    // A block over frames 10..13 and nothing anywhere else,
                    // so a drag from 0 crosses exactly two boundaries.
                    timeline: {
                      10: const TimelineExposure.drawing(
                        FrameId('cel'),
                        length: 4,
                      ),
                    },
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
    addTearDown(manager.dispose);
    manager.selectLayer(const LayerId('draw'));
    return manager;
  }

  test('the answer flips as the ruler crosses the block', () {
    final manager = session();
    manager.scrubFrameIndex(0);
    expect(manager.playheadHasCel.value, isFalse);

    manager.scrubFrameIndex(11);
    expect(
      manager.playheadHasCel.value,
      isTrue,
      reason: 'the toolbar had no way to learn this during a drag',
    );

    manager.scrubFrameIndex(20);
    expect(manager.playheadHasCel.value, isFalse);
  });

  test('⛔and it fires ONCE per crossing, not once per frame', () {
    final manager = session();
    manager.scrubFrameIndex(0);

    var notifications = 0;
    manager.playheadHasCel.addListener(() => notifications += 1);

    // A twenty-frame drag over one block: in at 10, out at 14.
    for (var frame = 1; frame <= 20; frame += 1) {
      manager.scrubFrameIndex(frame);
    }

    expect(
      notifications,
      2,
      reason:
          'a notification per crossed frame would put back the per-frame '
          'rebuild the scrub exists to avoid — 「효율좋게」',
    );
  });
}
