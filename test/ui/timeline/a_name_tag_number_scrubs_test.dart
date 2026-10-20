import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/se_name_tag.dart';
import 'package:anicel/src/services/cel_text_box_edits.dart'
    show celTextMinFontSize;
import 'package:anicel/src/ui/timeline/property_lane_model.dart';
import 'package:anicel/src/ui/timeline/se_name_tag_lane_policy.dart';
import 'package:anicel/src/ui/timeline/timeline_grid_metrics.dart';
import 'package:anicel/src/ui/timeline/timeline_lane_rows.dart';

/// F-407 — 「S행의 이름표, 크기나 자간 변경하려해도 값 변경 안됨」.
///
/// The name tag's number members wore no scrub, so a drag on their readout
/// did nothing. They scrub now at the rate every number lane scrubs at
/// ([scrubbedNumber]: half the dragged distance).
void main() {
  const tag = SeNameTag();
  final rows = seNameTagPropertyLanes(
    tag,
    expanded: true,
    resolveAt: tag.resolveAt,
  );
  PropertyLaneRow row(String laneId) =>
      rows.firstWhere((lane) => lane.laneId == laneId);
  final layer = Layer(id: const LayerId('se'), name: 'S', frames: const []);

  for (final laneId in [seNameTagSizeLaneId, seNameTagTrackingLaneId]) {
    testWidgets('$laneId: a drag on its readout writes the number moved by '
        'half the distance', (tester) async {
      final commits = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 600,
              height: 40,
              child: TimelineLaneControlsRow(
                layer: layer,
                lane: row(laneId),
                metrics: TimelineGridMetrics.defaults,
                laneEdit: PropertyLaneEditCallbacks(
                  onToggleKeyAt: (_, _, _) {},
                  onSetValue: (_, _, _, input) => commits.add(input),
                  onPreviewValue: (_, _, _, _) {},
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final start = double.parse(row(laneId).valueLabel!(0));

      final gesture = await tester.startGesture(
        tester.getCenter(
          find.byKey(ValueKey<String>('timeline-lane-value-se-$laneId')),
        ),
        kind: PointerDeviceKind.mouse,
      );
      await gesture.moveBy(const Offset(20, 0));
      await tester.pump();
      await gesture.moveBy(const Offset(20, 0));
      await tester.pump();
      await gesture.up();
      await tester.pump();

      expect(commits, hasLength(1), reason: 'one write, of the last step');
      expect(double.parse(commits.single), closeTo(start + 20, 1e-9));
    });
  }

  test('the size stops at the smallest a text can be set in; the tracking '
      'goes below nothing', () {
    expect(
      double.parse(
        scrubSeNameTagLaneValue(
          seNameTagSizeLaneId,
          '4',
          const Offset(-100, 0),
        )!,
      ),
      celTextMinFontSize,
    );
    expect(
      double.parse(
        scrubSeNameTagLaneValue(
          seNameTagTrackingLaneId,
          '0',
          const Offset(-10, 0),
        )!,
      ),
      -5,
    );
  });

  test('a member that is not a number wears no scrub', () {
    for (final lane in rows.where((lane) => !lane.isGroupHeader)) {
      final isNumber = lane.valueKind == PropertyLaneValueKind.number;
      expect(lane.scrubValue != null, isNumber, reason: lane.laneId);
    }
  });
}
