import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/attached_layer_resolve.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/timeline_exposure.dart';

/// 🚨F-48 — **싱크 어태치는 중간나누기 점도 나른다.**
///
/// > 「사진 반드시참고. **싱크 어태치레이어에 동화 중간나누기 점이 반영이안됨.
/// > 싱크되도록.**」
///
/// 🖼️스샷에서 보이는 것: B 의 첫 블록에 점(•)이 있는데 그 밑의 싱크 어태치
/// B+1·B+2·B+3 블록에는 없다. 숫자(1·2·3)만 따라갔다.
///
/// ⛔[attachedDisplayTimeline] 이 `length`·`ghost`·`ghostOwnerId` 는 옮기면서
/// **`breakdownOffsets` 만 두고 갔다** — 「무엇을 나르는가」 목록에서 빠진 것이다.
void main() {
  const baseId = LayerId('base');
  const attachId = LayerId('attach');
  const baseCel = FrameId('base-cel');
  const attachCel = FrameId('attach-cel');

  Layer base({List<int> dots = const []}) => Layer(
    id: baseId,
    name: 'B',
    frames: [Frame(id: baseCel, duration: 4, strokes: const [])],
    timeline: {
      0: TimelineExposure.drawing(baseCel, length: 4, breakdownOffsets: dots),
    },
  );

  Layer attach() => Layer(
    id: attachId,
    name: 'B+1',
    frames: [Frame(id: attachCel, duration: 4, strokes: const [])],
    timeline: const {},
    attachedToLayerId: baseId,
    baseFrameLinks: {baseCel: attachCel},
  );

  test('전제 — 점이 없으면 미러에도 없다', () {
    final mirrored = attachedDisplayTimeline(
      attached: attach(),
      base: base(),
    );
    expect(mirrored[0]?.breakdownOffsets, isEmpty);
    expect(
      mirrored[0]?.length,
      4,
      reason: '⛔블록 자체가 안 실렸으면 빈 것을 쟀다',
    );
  });

  test('🚨베이스의 중간나누기 점이 미러에 그대로 실린다', () {
    final mirrored = attachedDisplayTimeline(
      attached: attach(),
      base: base(dots: const [1, 2]),
    );
    expect(
      mirrored[0]?.breakdownOffsets,
      const [1, 2],
      reason: '유저: 「싱크 어태치레이어에 동화 중간나누기 점이 반영이안됨. 싱크되도록」',
    );
  });
}
