import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/ui/timeline/axis_turn.dart' show sizedAlong;
import 'package:anicel/src/ui/timeline/property_lane_model.dart';
import 'package:anicel/src/ui/timeline/timeline_grid_metrics.dart';
import 'package:anicel/src/ui/timeline/timeline_lane_rows.dart';
import 'package:anicel/src/ui/timeline/transform_lane_policy.dart'
    show scrubTransformLaneValue;
import 'package:anicel/src/ui/widgets/angle_dial.dart';

import '../../helpers/number_pad_keyboard.dart';

/// 🗣️I-132-Q17 a · Q18 b (유저 2026-10-28): an angle lane — a row's
/// rotation, an effect's angle — reads as After Effects writes an angle,
/// its turns and its degrees in two boxes (「1x」 · 「+90.0°」), and beside
/// them stands a small dial, always: its needle at the angle, a drag on it
/// turning it.
void main() {
  final layer = Layer(id: const LayerId('sc'), name: 'S', frames: const []);
  PropertyLaneRow lane(String laneId, String value) => PropertyLaneRow(
    laneId: laneId,
    label: laneId,
    keyMarks: const {},
    valueLabel: (_) => value,
    scrubValue: (label, delta) =>
        scrubTransformLaneValue(laneId, label, delta),
  );
  const dial = ValueKey<String>('timeline-lane-dial-sc-rotation');

  Future<void> pump(
    WidgetTester tester,
    PropertyLaneRow row, {
    PropertyLaneEditCallbacks? laneEdit,
    Axis axis = Axis.horizontal,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: sizedAlong(
              axis,
              along: 600,
              across: 40,
              child: TimelineLaneControlsRow(
                layer: layer,
                lane: row,
                metrics: TimelineGridMetrics.defaults,
                axis: axis,
                laneEdit: laneEdit,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  PropertyLaneEditCallbacks edits({
    List<String>? previews,
    List<String>? commits,
  }) => PropertyLaneEditCallbacks(
    onToggleKeyAt: (_, _, _) {},
    onSetValue: (_, _, _, input) => commits?.add(input),
    onPreviewValue: (_, _, _, input) => previews?.add(input),
  );

  testWidgets('an angle is two boxes, its turns and its degrees — no X and '
      'no Y — the dial before them, the degrees where a pair\'s second '
      'stands', (tester) async {
    await pump(tester, lane('rotation', '1x+90.00°'), laneEdit: edits());
    expect(
      find.byKey(const ValueKey<String>('timeline-lane-value-sc-rotation')),
      findsOneWidget,
    );
    expect(find.text('1x'), findsOneWidget);
    expect(find.text('+90.00°'), findsOneWidget);
    expect(find.text('X'), findsNothing);
    expect(find.text('Y'), findsNothing);
    expect(find.byKey(dial), findsOneWidget);
    expect(
      tester.widget<AngleDial>(find.byKey(dial)).degrees,
      450,
      reason: 'the needle at the angle',
    );
    expect(
      tester.getRect(find.byKey(dial)).right,
      lessThan(tester.getRect(find.text('1x')).left),
      reason: 'the dial, then the turns',
    );
    expect(
      tester.getRect(find.text('1x')).right,
      lessThan(tester.getRect(find.text('+90.00°')).left),
      reason: 'then the degrees',
    );
    // The same column, a pair in it.
    final degrees = tester.getRect(
      find.byKey(const ValueKey<String>('timeline-lane-value-sc-rotation-1')),
    );
    await pump(tester, lane('position', '12.00, 30.00'), laneEdit: edits());
    expect(
      tester.getRect(
        find.byKey(
          const ValueKey<String>('timeline-lane-value-sc-position-1'),
        ),
      ),
      degrees,
      reason: 'the degrees box stands where the pair\'s second does',
    );
  });

  testWidgets('its place is kept — the dial stands where the lane cannot be '
      'edited too', (tester) async {
    await pump(tester, lane('rotation', '0x+0.00°'));
    expect(find.byKey(dial), findsOneWidget);
    expect(tester.widget<AngleDial>(find.byKey(dial)).enabled, isFalse);
  });

  testWidgets('⛔a lane of no angle has no dial', (tester) async {
    await pump(tester, lane('position', '12.00, 30.00'), laneEdit: edits());
    expect(find.byType(AngleDial), findsNothing);
    expect(find.text('X'), findsOneWidget, reason: 'LIVENESS: the pair');
  });

  testWidgets('a number typed into a box is that box\'s: the turns, or the '
      'degrees, the other kept', (tester) async {
    final commits = <String>[];
    await pump(
      tester,
      lane('rotation', '1x+90.00°'),
      laneEdit: edits(commits: commits),
    );
    for (final (box, opens, typed) in [
      ('', '1', '2'),
      ('-1', '+90.00', '-30'),
    ]) {
      await tester.tap(
        find.byKey(
          ValueKey<String>('timeline-lane-value-sc-rotation$box-edit'),
        ),
      );
      await tester.pumpAndSettle();
      await openThePadsKeyboard(tester);
      final field = find.byKey(
        ValueKey<String>('timeline-lane-value-field-sc-rotation$box'),
      );
      expect(
        tester.widget<TextField>(field).controller!.text,
        opens,
        reason: 'the box opens on its number alone',
      );
      await tester.enterText(field, typed);
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
    }
    expect(commits, ['2x+90.00°', '1x-30°']);
  });

  testWidgets('a step of the turns box is a whole turn; of the degrees box, '
      'a step of the degrees', (tester) async {
    final commits = <String>[];
    await pump(
      tester,
      lane('rotation', '1x+90.00°'),
      laneEdit: edits(commits: commits),
    );
    for (final box in ['', '-1']) {
      await tester.tap(
        find.byKey(
          ValueKey<String>('timeline-lane-value-sc-rotation$box-step-up'),
        ),
      );
      await tester.pumpAndSettle();
    }
    expect(commits, ['2x+90.00°', '1x+90.50°']);
  });

  testWidgets('a drag round the dial turns the angle as far as the hand '
      'goes — whole turns counted — shown as it goes, written once', (
    tester,
  ) async {
    final previews = <String>[];
    final commits = <String>[];
    await pump(
      tester,
      lane('rotation', '0x+10.00°'),
      laneEdit: edits(previews: previews, commits: commits),
    );
    final middle = tester.getCenter(find.byKey(dial));
    const reach = 10.0;
    final gesture = await tester.startGesture(
      middle + const Offset(0, -reach),
      kind: PointerDeviceKind.mouse,
    );
    // Clockwise from the top, a quarter at a time, once round and a
    // quarter more.
    for (final at in const [
      Offset(reach, 0),
      Offset(0, reach),
      Offset(-reach, 0),
      Offset(0, -reach),
      Offset(reach, 0),
    ]) {
      await gesture.moveTo(middle + at);
      await tester.pump();
    }
    expect(previews.first, '0x+100.00°', reason: 'a quarter turn');
    expect(previews.last, '1x+100.00°', reason: 'round once, and a quarter');
    expect(commits, isEmpty, reason: 'nothing written while it turns');
    await gesture.up();
    await tester.pump();
    expect(commits, ['1x+100.00°'], reason: 'one write, of the last step');
  });

  testWidgets('a press on the dial that does not move turns nothing and '
      'writes nothing', (tester) async {
    final previews = <String>[];
    final commits = <String>[];
    await pump(
      tester,
      lane('rotation', '0x+10.00°'),
      laneEdit: edits(previews: previews, commits: commits),
    );
    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(dial)) + const Offset(0, -8),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();
    await gesture.up();
    await tester.pump();
    expect(previews, isEmpty);
    expect(commits, isEmpty);
  });

  testWidgets('in the sheet, which stands the value up, the dial stands '
      'upright', (tester) async {
    await pump(
      tester,
      lane('rotation', '0x+0.00°'),
      laneEdit: edits(),
      axis: Axis.vertical,
    );
    expect(find.byKey(dial), findsOneWidget);
    final turns = tester
        .widgetList<RotatedBox>(
          find.ancestor(of: find.byKey(dial), matching: find.byType(RotatedBox)),
        )
        .fold<int>(0, (sum, box) => sum + box.quarterTurns);
    expect(turns % 4, 0);
  });
}
