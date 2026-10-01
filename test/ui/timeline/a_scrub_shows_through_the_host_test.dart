import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/ui/timeline/property_lane_model.dart';
import 'package:anicel/src/ui/timeline/timeline_grid_metrics.dart';
import 'package:anicel/src/ui/timeline/timeline_lane_rows.dart';
import 'package:anicel/src/ui/timeline/transform_lane_policy.dart'
    show scrubTransformLaneValue;

/// F-195 — A SCRUB IS SHOWN THROUGH THE HOST, and the label keeps only the
/// gesture's own accounting.
///
/// The label used to print the scrubbed text itself while nothing else saw
/// it. Now each step goes to the host ([PropertyLaneEditCallbacks.
/// onPreviewValue]), the label prints whatever lane it is handed, and the
/// release writes the last value once. The app's half — the preview coming
/// back through the row gate — is `an_edit_shows_while_it_is_dragged_test`.
void main() {
  final layer = Layer(id: const LayerId('sc'), name: 'S', frames: const []);
  PropertyLaneRow lane(String value) => PropertyLaneRow(
    laneId: 'rotation',
    label: 'Rotation',
    keyedFrames: const {},
    valueLabel: (_) => value,
    scrubValue: (label, delta) =>
        scrubTransformLaneValue('rotation', label, delta),
  );
  const cell = ValueKey<String>('timeline-lane-value-sc-rotation');

  testWidgets('each step is handed to the host, the label prints the lane it '
      'is given, and the release writes the last step once', (tester) async {
    final previews = <String>[];
    final commits = <String>[];
    var ends = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 600,
            height: 40,
            child: TimelineLaneControlsRow(
              layer: layer,
              lane: lane('0°'),
              metrics: TimelineGridMetrics.defaults,
              laneEdit: PropertyLaneEditCallbacks(
                onToggleKeyAt: (_, _, _) {},
                onSetValue: (_, _, _, input) => commits.add(input),
                onPreviewValue: (_, _, _, input) => previews.add(input),
                onEndPreview: () => ends += 1,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(cell)),
      kind: PointerDeviceKind.mouse,
    );
    await gesture.moveBy(const Offset(20, 0));
    await tester.pump();
    await gesture.moveBy(const Offset(20, 0));
    await tester.pump();

    expect(previews, ['10°', '20°']);
    expect(
      find.descendant(of: find.byKey(cell), matching: find.text('0°')),
      findsOneWidget,
      reason: 'the label prints the lane it is handed — the host shows the '
          'step by handing a new one back, as every other panel does',
    );
    expect(commits, isEmpty);

    await gesture.up();
    await tester.pump();
    expect(commits, ['20°'], reason: 'one write, of the last step');
    expect(ends, 0, reason: 'the write drops the preview itself');
  });

  testWidgets('a step inside the same value is not handed over twice', (
    tester,
  ) async {
    final previews = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 600,
            height: 40,
            child: TimelineLaneControlsRow(
              layer: layer,
              lane: lane('0°'),
              metrics: TimelineGridMetrics.defaults,
              laneEdit: PropertyLaneEditCallbacks(
                onToggleKeyAt: (_, _, _) {},
                onSetValue: (_, _, _, _) {},
                onPreviewValue: (_, _, _, input) => previews.add(input),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(cell)),
      kind: PointerDeviceKind.mouse,
    );
    await gesture.moveBy(const Offset(20, 0));
    await tester.pump();
    await gesture.moveBy(const Offset(0, 30));
    await tester.pump();
    await gesture.up();

    expect(
      previews,
      ['10°'],
      reason: 'rotation reads the horizontal only — a vertical move changes '
          'nothing to show, and a canvas redraw per nothing is the cost',
    );
  });

  testWidgets('a label taken away mid-scrub drops what it was showing once '
      'the tree settles', (tester) async {
    var ends = 0;
    final shown = ValueNotifier<bool>(true);
    addTearDown(shown.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ValueListenableBuilder<bool>(
            valueListenable: shown,
            builder: (context, visible, _) => SizedBox(
              width: 600,
              height: 40,
              child: visible
                  ? TimelineLaneControlsRow(
                      layer: layer,
                      lane: lane('0°'),
                      metrics: TimelineGridMetrics.defaults,
                      laneEdit: PropertyLaneEditCallbacks(
                        onToggleKeyAt: (_, _, _) {},
                        onSetValue: (_, _, _, _) {},
                        onPreviewValue: (_, _, _, _) {},
                        onEndPreview: () => ends += 1,
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(cell)),
      kind: PointerDeviceKind.mouse,
    );
    await gesture.moveBy(const Offset(20, 0));
    await tester.pump();

    shown.value = false;
    await tester.pump();
    await tester.pump();

    expect(ends, 1, reason: 'no release will come to drop it');
    await gesture.up();
  });
}
