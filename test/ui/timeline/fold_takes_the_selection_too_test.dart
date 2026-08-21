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
import 'package:anicel/src/models/timeline_row_address.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/timeline/transform_lane_policy.dart'
    show transformGroupHeaderLane;

/// 🚨H6 (유저 2026-08-21) — THE FOLD LAW'S OTHER HALF.
///
/// > 「이 앱의 특징은 **행이 보이는 곳만 조작**한다는 점임 … 레이어 접고
/// > 펼치면 **fx행까지 선택한 게 남아있는데**, 접을 때 **선택범위 바꿔서
/// > 사라진 건 선택 안 하게** 되도록. 접고나서 이동할 때 fx행 반영 안 되는거
/// > 보니 **로직적으론 잘 되있는거같고 선택범위 UI만** 그에 맞춰 제대로」
///
/// ⛔The law was already written and already said this — `handOffCurrent
/// RowOnFold`'s doc opens with 「what disappears never keeps the
/// selection」 — and it only ever moved the ONE standing row. The band
/// kept its folded rows, so it drew over rows that were off the screen
/// while the verbs correctly ignored them. The user read exactly that:
/// the logic is right, the UI is not.
///
/// ⚠️The swallower TAKES THEIR PLACE rather than the selection emptying —
/// the same answer the standing row already gets. Someone who had rows
/// selected still has rows selected after a fold.
void main() {
  EditorSessionManager session() {
    final manager = EditorSessionManager(
      initialProject: Project(
        id: const ProjectId('p'),
        name: 'P',
        createdAt: DateTime.utc(2026, 8, 21),
        tracks: [
          Track(
            id: const TrackId('t'),
            name: 'T',
            cuts: [
              Cut(
                id: const CutId('cut'),
                name: '1',
                duration: 8,
                canvasSize: const CanvasSize(width: 32, height: 32),
                layers: [
                  Layer(
                    id: const LayerId('a'),
                    name: 'A',
                    frames: [
                      Frame(
                        id: const FrameId('f'),
                        duration: 1,
                        strokes: const [],
                      ),
                    ],
                    timeline: const {},
                  ),
                  Layer(
                    id: const LayerId('b'),
                    name: 'B',
                    frames: const [],
                    timeline: const {},
                    kind: LayerKind.animation,
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
    addTearDown(manager.dispose);
    return manager;
  }

  const layerA = LayerRowAddress(LayerId('a'));
  const layerB = LayerRowAddress(LayerId('b'));
  final laneOfA = LaneRowAddress(
    const LayerId('a'),
    transformGroupHeaderLane.laneId,
  );

  test('folding a layer\'s lanes drops its LANE rows from the band', () {
    final s = session();
    s.beginRowSelection(layerA);
    s.rowSelection.value = [layerA, laneOfA, layerB];

    s.handOffCurrentRowOnFold(const LayerId('a'));

    expect(
      s.rowSelection.value,
      [layerA, layerB],
      reason:
          'the lane went off the screen, so it leaves the band — and '
          'the rows that are still visible are untouched',
    );
  });

  test('a band of ONLY vanished rows becomes the swallower, never empty', () {
    final s = session();
    s.beginRowSelection(laneOfA);
    s.rowSelection.value = [laneOfA];

    s.handOffCurrentRowOnFold(const LayerId('a'));

    expect(
      s.rowSelection.value,
      [layerA],
      reason:
          'the same hand-off the standing row gets: what swallowed them '
          'takes their place, so a selection does not evaporate under a fold',
    );
  });

  test('a fold that hides nothing selected leaves the band alone', () {
    final s = session();
    s.beginRowSelection(layerB);
    s.rowSelection.value = [layerB];
    final before = s.rowSelection.value;

    s.handOffCurrentRowOnFold(const LayerId('a'));

    expect(
      identical(s.rowSelection.value, before),
      isTrue,
      reason:
          'not even a new list — a fold elsewhere must not notify the '
          'band\'s listeners into a rebuild',
    );
  });

  test('folding ONE GROUP takes its members and leaves the header', () {
    final s = session();
    final member = LaneRowAddress(const LayerId('a'), 'scale');
    s.beginRowSelection(layerA);
    s.rowSelection.value = [layerA, member];

    s.handOffCurrentRowOnFold(
      const LayerId('a'),
      laneId: transformGroupHeaderLane.laneId,
    );

    expect(
      s.rowSelection.value.contains(member),
      isFalse,
      reason: 'the member folded away with its group',
    );
    expect(
      s.rowSelection.value.contains(layerA),
      isTrue,
      reason: 'and the row that is still on screen stays selected',
    );
  });
}
