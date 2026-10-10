import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/key_mark.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/ui/timeline/property_lane_model.dart';
import 'package:anicel/src/ui/timeline/timeline_grid_metrics.dart';
import 'package:anicel/src/ui/timeline/timeline_lane_rows.dart';
import 'package:anicel/src/ui/timeline/transform_lane_policy.dart'
    show scrubTransformLaneValue;

/// 🗣️tool-settings-panel-tidy (유저 2026-10-10): 「fx에도 텍스트편집하는거
/// 있는데 거기도 사용하는거 어떻지? x랑 y값 안그래도 같이움직여서
/// 불편했고」 → 「A로하고 … 좀 더 여유롭게 크게하자」 — a lane's value is the
/// tool settings' number boxes, ONE PER NUMBER: a drag on one moves that
/// number alone, its ± step it alone and its pencil opens it alone
/// (「상자에 한걸음 올리기 내리기버튼들도 동일하게」 · 「연필은 상자마다」),
/// and a scrub still writes once, at the release.
void main() {
  final layer = Layer(id: const LayerId('a'), name: 'A', frames: const []);

  Future<({List<String> previews, List<String> writes})> pumpLane(
    WidgetTester tester, {
    required String id,
    required String value,
  }) async {
    final previews = <String>[];
    final writes = <String>[];
    final lane = PropertyLaneRow(
      laneId: id,
      label: id,
      keyMarks: const {0: KeyMark.linear},
      valueLabel: (_) => value,
      scrubValue: (label, delta) => scrubTransformLaneValue(id, label, delta),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: TimelineLaneControlsRow(
              layer: layer,
              lane: lane,
              metrics: TimelineGridMetrics.defaults,
              width: TimelineGridMetrics.defaults.layerControlsWidth,
              height: TimelineGridMetrics.defaults.layerRowHeight,
              laneEdit: PropertyLaneEditCallbacks(
                onToggleKeyAt: (_, _, _) {},
                onSetValue: (_, _, _, text) => writes.add(text),
                onPreviewValue: (_, _, _, text) => previews.add(text),
              ),
            ),
          ),
        ),
      ),
    );
    return (previews: previews, writes: writes);
  }

  String boxKey(String id, int part) => part == 0
      ? 'timeline-lane-value-a-$id'
      : 'timeline-lane-value-a-$id-$part';

  Finder box(String id, int part) =>
      find.byKey(ValueKey<String>(boxKey(id, part)));

  /// One of a box's hands: `step-up`, `step-down`, or `edit` — its pencil.
  Finder hand(String id, int part, String which) =>
      find.byKey(ValueKey<String>('${boxKey(id, part)}-$which'));

  /// A drag across [face] in steps — the way a hand scrubs.
  Future<void> scrub(WidgetTester tester, Finder face, Offset by) async {
    final gesture = await tester.startGesture(tester.getCenter(face));
    for (var step = 0; step < 10; step += 1) {
      await gesture.moveBy(by / 10);
      await tester.pump();
    }
    await gesture.up();
    await tester.pump();
  }

  testWidgets('🚨the Y box scrubs Y ALONE — the X it does not touch reads '
      'as it did', (tester) async {
    final seen = await pumpLane(tester, id: 'position', value: '100.00, 50.00');

    await scrub(tester, box('position', 1), const Offset(40, 0));

    expect(seen.writes, hasLength(1), reason: 'one drag, one write');
    final written = seen.writes.single.split(', ');
    expect(written.first, '100.00', reason: 'X untouched');
    expect(double.parse(written.last), greaterThan(50));
  });

  testWidgets('🚨the X box scrubs X ALONE, however far the hand wanders '
      'down', (tester) async {
    final seen = await pumpLane(tester, id: 'position', value: '100.00, 50.00');

    await scrub(tester, box('position', 0), const Offset(40, 30));

    final written = seen.writes.single.split(', ');
    expect(double.parse(written.first), greaterThan(100));
    expect(written.last, '50.00', reason: 'Y untouched');
  });

  testWidgets('a scrub is SHOWN while it runs and WRITTEN once, at the '
      'release', (tester) async {
    final seen = await pumpLane(tester, id: 'rotation', value: '10.00°');
    final gesture = await tester.startGesture(
      tester.getCenter(box('rotation', 0)),
    );
    for (var step = 0; step < 10; step += 1) {
      await gesture.moveBy(const Offset(6, 0));
      await tester.pump();
    }
    expect(seen.previews, isNotEmpty, reason: 'shown while it runs');
    expect(seen.writes, isEmpty, reason: 'not written yet');

    await gesture.up();
    await tester.pump();
    expect(seen.writes, [seen.previews.last]);
  });

  testWidgets('🚨its PENCIL opens ONE number, its unit outside the field — '
      'and what is typed goes back with the rest as it read', (tester) async {
    final seen = await pumpLane(tester, id: 'scale', value: '100.00, 80.00%');

    await tester.tap(box('scale', 1));
    await tester.pump();
    expect(
      find.byKey(
        const ValueKey<String>('timeline-lane-value-field-a-scale-1'),
      ),
      findsNothing,
      reason: 'a press on the box opens nothing',
    );

    await tester.tap(hand('scale', 1, 'edit'));
    await tester.pump();
    final field = find.byKey(
      const ValueKey<String>('timeline-lane-value-field-a-scale-1'),
    );
    expect(
      tester.widget<EditableText>(
        find.descendant(of: field, matching: find.byType(EditableText)),
      ).controller.text,
      '80.00',
      reason: 'the number alone',
    );

    await tester.enterText(field, '150');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();

    expect(seen.writes, ['100.00, 150%']);
  });

  testWidgets('🚨its ± step its number ALONE, each step one write', (
    tester,
  ) async {
    final seen = await pumpLane(tester, id: 'position', value: '100.00, 50.00');

    await tester.tap(hand('position', 1, 'step-up'));
    await tester.pump();
    expect(seen.writes, hasLength(1), reason: 'one step, one write');
    final up = seen.writes.single.split(', ');
    expect(up.first, '100.00', reason: 'X untouched');
    expect(double.parse(up.last), greaterThan(50));

    await tester.tap(hand('position', 0, 'step-down'));
    await tester.pump();
    final down = seen.writes.last.split(', ');
    expect(double.parse(down.first), lessThan(100));
    expect(down.last, '50.00', reason: 'Y untouched — the lane as it read');
  });

  /// 🗣️유저 2026-10-10: 「회전의 박스가 다른 박스랑 길이가 살짝 짧거든? …
  /// 행 열 느낌나게 신경써주고」.
  testWidgets('🚨a single number\'s box fills the column, and its hands stand '
      'where a pair\'s second box has its own — rows and columns', (
    tester,
  ) async {
    final lanes = [
      for (final (id, value) in const [
        ('position', '1218.00, 540.00'),
        ('rotation', '12.50°'),
        ('scale', '100.00, 100.00%'),
      ])
        PropertyLaneRow(
          laneId: id,
          label: id,
          keyMarks: const {0: KeyMark.linear},
          valueLabel: (_) => value,
        ),
    ];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final lane in lanes)
                  TimelineLaneControlsRow(
                    layer: layer,
                    lane: lane,
                    metrics: TimelineGridMetrics.defaults,
                    width: TimelineGridMetrics.defaults.layerControlsWidth,
                    height: TimelineGridMetrics.defaults.layerRowHeight,
                    laneEdit: PropertyLaneEditCallbacks(
                      onToggleKeyAt: (_, _, _) {},
                      onSetValue: (_, _, _, _) {},
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
    Rect at(Finder finder) => tester.getRect(finder);

    final single = box('rotation', 0);
    for (final pair in const ['position', 'scale']) {
      expect(at(single).left, at(box(pair, 0)).left, reason: '$pair: X');
      for (final which in const ['step-up', 'edit']) {
        expect(
          at(hand('rotation', 0, which)).left,
          at(hand(pair, 1, which)).left,
          reason: '$pair: its $which stands under the second box\'s',
        );
      }
      expect(
        at(single).right,
        at(box(pair, 1)).right,
        reason: '$pair: the single box ends where the second box does',
      );
    }
  });
}
