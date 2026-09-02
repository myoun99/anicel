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

  const metrics = TimelineGridMetrics.defaults;

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

  /// ⚠️A WIDE CELL, and the reason is a test that measured nothing.
  ///
  /// `find.text` returns the Text WIDGET's box, not its ink — and at the
  /// default 24px cell the word 「Wall」 is exactly 24 wide, so the `Align`
  /// inside had no room to move it and every alignment produced the same
  /// rect. 🧪Mutation proved it: flipping `Alignment.center` to `centerLeft`
  /// left the suite green. At 72 the box is a third of the cell and the
  /// alignment is the only thing deciding where it sits.
  Future<void> pumpWideLane(WidgetTester tester, PropertyLaneRow lane) async {
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
              frameEndIndexExclusive: 6,
              leadingFrameSpacerWidth: 0,
              trailingFrameSpacerWidth: 0,
              metrics: const TimelineGridMetrics(frameCellWidth: 72),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

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

  testWidgets('🚨EVERY key name sits in the middle of its cell', (
    tester,
  ) async {
    // ⚠️THIS TEST USED TO ASSERT THE OPPOSITE, and the assertion was mine
    // rather than the user's. 유저 원문 ㉗ named the UNION alone — 「**유니언
    // 이름은** 오른쪽 위가 아니라 칸 중앙」 — and I extended it into a rule
    // for members, put the label beside the diamond, and wrote my reasoning
    // into the code and into this file as if it had been decided.
    //
    // `F-17-Q1` put the real question on 2026-08-26 and the answer was **B —
    // 「마크는 그대로, 이름만 칸 중앙에」**. The objection I had assumed (a
    // 6px mark cannot hold a word, so the word would swallow the mark) was
    // waved off in one line: 「키가 있는건 글자로도 아니까 아무문제없어」.
    const wideCell = 72.0;
    const cellCentre = 2 * wideCell + wideCell / 2;

    for (final lane in [member, union]) {
      await pumpWideLane(tester, lane);
      final name = tester.getRect(find.text('Wall'));
      expect(
        name.width,
        lessThan(wideCell - 8),
        reason:
            '${lane.laneId} — fixture premise: the word is NARROWER '
            'than its cell, or nothing below can move',
      );
      expect(
        name.center.dx,
        moreOrLessEquals(cellCentre, epsilon: 0.5),
        reason: '${lane.laneId} — 「이름만 칸 중앙에」',
      );
    }
  });

  testWidgets('⛔and the member mark is still 6px — that was option A', (
    tester,
  ) async {
    // Growing the member mark to make room for the name WAS on the ballot
    // (A) and was not chosen. A test that only checked the name would go
    // green on it, so the size is pinned here beside the decision.
    await pumpLane(tester, member);
    final memberMark = markSizeOf(tester, 'position');
    await pumpLane(tester, union);
    final unionMark = markSizeOf(tester, 'transform-group');
    expect(
      memberMark.width,
      lessThan(unionMark.width),
      reason:
          'the union is still the one that summarises, and it still '
          'looks like it',
    );
  });
}
