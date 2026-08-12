import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/ui/timeline/property_lane_model.dart';
import 'package:anicel/src/ui/timeline/timeline_grid_metrics.dart';
import 'package:anicel/src/ui/timeline/timeline_lane_rows.dart';

/// ㉗ (user, 2026-08-12): 「fx(트랜스폼) 헤더의 유니언 마크를 카메라처럼
/// 크게 — 멤버 유니언들의 합이라는 느낌이 나야 한다」 and 「유니언 이름은
/// 오른쪽 위가 아니라 칸 중앙, 프레임블록의 텍스트 UI를 그대로 재사용」.
void main() {
  final layer = Layer(
    id: const LayerId('layer-a'),
    name: 'A',
    frames: const [],
  );

  const metrics = TimelineGridMetrics(frameCellWidth: 24);

  const member = PropertyLaneRow(
    laneId: 'position',
    label: 'Position',
    keyedFrames: {2},
    keyNames: {2: 'Wall'},
  );

  const union = PropertyLaneRow(
    laneId: 'transform-group',
    label: 'Transform',
    keyedFrames: {2},
    keyNames: {2: 'Wall'},
    isGroupHeader: true,
  );

  Future<void> pumpLane(WidgetTester tester, PropertyLaneRow lane) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Material(
          child: SizedBox(
            width: 480,
            height: 40,
            child: TimelineLaneFrameRow(
              layer: layer,
              lane: lane,
              frameStartIndex: 0,
              frameEndIndexExclusive: 20,
              leadingFrameSpacerWidth: 0,
              trailingFrameSpacerWidth: 0,
              metrics: metrics,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  Size markSizeOf(WidgetTester tester, String laneId) {
    final marker = find.byKey(
      ValueKey<String>('timeline-lane-key-layer-a-$laneId-2'),
    );
    // The painted shape inside the hit box — the hit box is deliberately
    // bigger than the mark and identical on both rows.
    return tester.getSize(
      find.descendant(of: marker, matching: find.byType(Container)).first,
    );
  }

  testWidgets('a UNION mark is bigger than the member key it summarises', (
    tester,
  ) async {
    await pumpLane(tester, member);
    final memberMark = markSizeOf(tester, 'position');

    await pumpLane(tester, union);
    final unionMark = markSizeOf(tester, 'transform-group');

    expect(unionMark.width, greaterThan(memberMark.width));
    expect(
      unionMark.height,
      lessThanOrEqualTo(metrics.layerRowHeight),
      reason: 'and it never outgrows the row it sits in',
    );
  });

  testWidgets('a UNION name sits in the middle of its cell; a member name '
      'stays beside its diamond', (tester) async {
    final cellCentre = 2 * metrics.frameCellWidth + metrics.frameCellWidth / 2;

    await pumpLane(tester, member);
    final memberName = tester.getRect(find.text('Wall'));
    expect(
      memberName.left,
      greaterThan(cellCentre),
      reason: 'a member label starts to the RIGHT of its diamond',
    );

    await pumpLane(tester, union);
    final unionName = tester.getRect(find.text('Wall'));
    expect(unionName.center.dx, moreOrLessEquals(cellCentre, epsilon: 0.5));
  });
}
