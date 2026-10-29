import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/ui/timeline/property_lane_model.dart';
import 'package:anicel/src/ui/timeline/se_sound_lane_policy.dart';
import 'package:anicel/src/ui/timeline/timeline_grid_metrics.dart';
import 'package:anicel/src/ui/timeline/timeline_lane_rows.dart';

/// 🗣️F-488 (유저 2026-10-27): a step that writes the same number is no
/// step. 🤖AI 검증 10-29 found the Pan's ± dead one way: 「C 에서 ＋ 는
/// R1 · R2 로 가는데 R2 에서 − 를 네 번 눌러도 R2 그대로」 — a press is one
/// pixel of the lanes' one rate, half a per cent, and the Pan writes whole
/// per cents, so R2 − ½ rounded back to R2 (and L2 + ½ to L2).
void main() {
  final layer = Layer(id: const LayerId('s1'), name: 'S1', frames: const []);

  Future<List<String>> pumpPan(WidgetTester tester, String value) async {
    final writes = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: TimelineLaneControlsRow(
              layer: layer,
              lane: PropertyLaneRow(
                laneId: seSoundPanLaneId,
                label: 'Pan',
                keyMarks: const {},
                showsKeyNavigator: false,
                valueLabel: (_) => value,
                scrubValue: scrubSeSoundPan,
              ),
              metrics: TimelineGridMetrics.defaults,
              width: TimelineGridMetrics.defaults.layerControlsWidth,
              height: TimelineGridMetrics.defaults.layerRowHeight,
              laneEdit: PropertyLaneEditCallbacks(
                onToggleKeyAt: (_, _, _) {},
                onSetValue: (_, _, _, text) => writes.add(text),
              ),
            ),
          ),
        ),
      ),
    );
    return writes;
  }

  Finder hand(String which) => find.byKey(
    ValueKey<String>('timeline-lane-value-s1-$seSoundPanLaneId-step-$which'),
  );

  for (final (from, which, to) in const [
    ('R2', 'down', 'R1'),
    ('R2', 'up', 'R3'),
    ('L2', 'up', 'L1'),
    ('L2', 'down', 'L3'),
    ('C', 'up', 'R1'),
    ('C', 'down', 'L1'),
  ]) {
    testWidgets('a ${which == 'up' ? '+' : '−'} press on $from writes $to',
        (tester) async {
      final writes = await pumpPan(tester, from);

      await tester.tap(hand(which));
      await tester.pump();

      expect(writes, [to]);
    });
  }

  test('a drag still moves the Pan half a per cent a pixel', () {
    expect(scrubSeSoundPan('R2', const Offset(-4, 0)), 'C');
    expect(scrubSeSoundPan('R2', const Offset(4, 0)), 'R4');
    expect(scrubSeSoundPan('R2', Offset.zero), 'R2');
    expect(scrubSeSoundPan('R100', const Offset(1, 0)), 'R100');
  });
}
