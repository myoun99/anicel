import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/ui/timeline/property_lane_model.dart';
import 'package:anicel/src/ui/timeline/se_name_tag_lane_policy.dart';
import 'package:anicel/src/ui/timeline/transform_lane_policy.dart';

/// 🚨T13 (유저 2026-08-13): 「se행의 네임태그에선 이번엔 행 하나만 선택범위
/// 작동가능. 다른 행 걸쳐서 선택불가. 트랜스폼이랑 같은 fx 아닌가? **왜 이렇게
/// 또 규칙이 다르지? 제발 규칙다른거 그만좀하자**」.
///
/// The rule that used to live inside the timeline host was a WHITELIST: a
/// span could end on a transform member lane or an effect parameter lane, and
/// every other row was "crossed silently". The name-tag group is neither, so
/// its head never left the anchor and the selection folded to one row —
/// while `seNameTagLaneSpan`, a complete twin of `transformLaneSpan`, sat
/// there unreachable.
///
/// ★So these are about ROW KINDS not mattering. Each case picks a kind that
/// the old rule refused, which is why they are listed by kind rather than
/// collapsed into one loop.
void main() {
  PropertyLaneRow lane(String id, {bool isGroupHeader = false}) =>
      PropertyLaneRow(
        laneId: id,
        label: id,
        keyedFrames: const {},
        isGroupHeader: isGroupHeader,
      );

  /// An SE row as the rail draws it: the transform group, then the name-tag
  /// group with its own header, then the audio lane. Three kinds, one list.
  List<PropertyLaneRow> seRowLanes() => [
    lane(transformLaneDisplayOrder.first),
    lane(transformLaneDisplayOrder[1]),
    lane(seNameTagGroupLaneId, isGroupHeader: true),
    lane(seNameTagLaneDisplayOrder.first),
    lane(seNameTagLaneDisplayOrder[1]),
    lane('se-audio'),
  ];

  test('a span inside the NAME TAG group reaches its members', () {
    expect(
      resolveLaneSpanHead(
        lanes: seRowLanes(),
        anchorLaneId: seNameTagLaneDisplayOrder.first,
        rowDelta: 1,
      ),
      seNameTagLaneDisplayOrder[1],
      reason: 'this is the report — it used to answer null and fold to the '
          'anchor row',
    );
  });

  test('a group HEADER can be the head', () {
    expect(
      resolveLaneSpanHead(
        lanes: seRowLanes(),
        anchorLaneId: transformLaneDisplayOrder[1],
        rowDelta: 1,
      ),
      seNameTagGroupLaneId,
    );
  });

  test('and so can the SE AUDIO lane, the other row the old rule skipped', () {
    expect(
      resolveLaneSpanHead(
        lanes: seRowLanes(),
        anchorLaneId: seNameTagLaneDisplayOrder[1],
        rowDelta: 1,
      ),
      'se-audio',
    );
  });

  test('a span crosses group boundaries — kinds do not stop it', () {
    expect(
      resolveLaneSpanHead(
        lanes: seRowLanes(),
        anchorLaneId: transformLaneDisplayOrder.first,
        rowDelta: 4,
      ),
      seNameTagLaneDisplayOrder[1],
    );
  });

  test('upward reads the same', () {
    expect(
      resolveLaneSpanHead(
        lanes: seRowLanes(),
        anchorLaneId: 'se-audio',
        rowDelta: -3,
      ),
      seNameTagGroupLaneId,
    );
  });

  test('past the end it stops at the farthest row REACHED, not at the '
      'anchor', () {
    expect(
      resolveLaneSpanHead(
        lanes: seRowLanes(),
        anchorLaneId: seNameTagLaneDisplayOrder[1],
        rowDelta: 40,
      ),
      'se-audio',
    );
  });

  test('no travel and an unknown anchor both keep the head where it is', () {
    expect(
      resolveLaneSpanHead(
        lanes: seRowLanes(),
        anchorLaneId: seNameTagGroupLaneId,
        rowDelta: 0,
      ),
      isNull,
    );
    expect(
      resolveLaneSpanHead(
        lanes: seRowLanes(),
        anchorLaneId: 'not-a-lane',
        rowDelta: 2,
      ),
      isNull,
    );
  });
}
