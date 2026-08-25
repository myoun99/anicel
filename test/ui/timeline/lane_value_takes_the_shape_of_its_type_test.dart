import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/ui/timeline/property_lane_model.dart';
import 'package:anicel/src/ui/timeline/se_name_tag_lane_policy.dart';
import 'package:anicel/src/ui/timeline/timeline_grid_metrics.dart';
import 'package:anicel/src/ui/timeline/timeline_lane_rows.dart';

/// **F-22 — a flag is a button, not a word you type.**
///
/// 유저 2026-08-24: 「fx의 멤버 편집, **타입에 따라 확실하게 나누기. 지금 싹 다
/// 텍스트임.** … **Bold같은 불리언 타입은 그냥 누르면 전환되는 버튼**이도록」
///
/// The KIND lives on the LANE, because only the provider knows that
/// `name-tag:bold` is a flag — a switch on lane ids inside the row widget
/// would be a second place to keep that.
void main() {
  test('the flags say they are flags, and nothing else does', () {
    expect(
      seNameTagLaneValueKind(seNameTagBoldLaneId),
      PropertyLaneValueKind.boolean,
    );
    expect(
      seNameTagLaneValueKind(seNameTagShowLineLaneId),
      PropertyLaneValueKind.boolean,
    );
    for (final laneId in [
      seNameTagSizeLaneId,
      seNameTagTrackingLaneId,
      // ⚠️The three INK lanes are numbers ON PURPOSE, not by omission: a
      // colour circle cannot say `none`, which the box colour really is
      // when the アフレコ box is off, and the value editor is the only way
      // back to it today. Boarded rather than invented.
      seNameTagNameInkLaneId,
      seNameTagBoxColorLaneId,
      seNameTagLineInkLaneId,
    ]) {
      expect(
        seNameTagLaneValueKind(laneId),
        PropertyLaneValueKind.number,
        reason: laneId,
      );
    }
  });

  testWidgets('a flag lane draws a toggle, and one tap flips it', (
    tester,
  ) async {
    final commits = <({String laneId, String input})>[];
    final layer = Layer(
      id: const LayerId('nt-se'),
      name: 'SE',
      kind: LayerKind.se,
      frames: const [],
    );
    const lane = PropertyLaneRow(
      laneId: seNameTagBoldLaneId,
      label: 'Bold',
      keyedFrames: {},
      valueKind: PropertyLaneValueKind.boolean,
      valueLabel: _off,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 600,
            height: 40,
            child: TimelineLaneControlsRow(
              layer: layer,
              lane: lane,
              metrics: const TimelineGridMetrics(),
              laneEdit: PropertyLaneEditCallbacks(
                onToggleKeyAt: (_, _, _) {},
                onSetValue: (_, row, _, input) =>
                    commits.add((laneId: row.laneId, input: input)),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final toggle = find.byKey(
      const ValueKey<String>('timeline-lane-toggle-nt-se-name-tag:bold'),
    );
    expect(
      toggle,
      findsOneWidget,
      reason: 'the value cell IS the control for a flag',
    );
    expect(
      find.byKey(
        const ValueKey<String>(
          'timeline-lane-value-nt-se-name-tag:bold',
        ),
      ),
      findsNothing,
      reason: 'and it is not ALSO the text readout — one cell, one control',
    );

    await tester.tap(toggle);
    await tester.pumpAndSettle();

    expect(
      commits,
      [(laneId: seNameTagBoldLaneId, input: 'on')],
      reason: 'off flips to on, in the one word the parser already takes — '
          'nobody has to type it',
    );
  });
}

String _off(int frameIndex) => 'off';
