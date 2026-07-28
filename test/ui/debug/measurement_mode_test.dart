import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/main.dart';
import 'package:anicel/src/ui/debug/measurement_mode.dart';

/// The frame-timing overlay is a measurement switch, so what is worth
/// pinning is that it stays OFF unless asked for — an overlay left on
/// ships two graphs across the user's canvas — and that the toggle
/// actually reaches `MaterialApp`, which is the whole reason it is a
/// notifier and not just a build-time constant.
void main() {
  tearDown(MeasurementMode.reset);

  test('off unless --dart-define=QA_PERF_OVERLAY=true seeds it', () {
    expect(
      MeasurementMode.startWithFrameTimingOverlay,
      isFalse,
      reason: 'default builds must not draw the frame-timing graphs',
    );
    expect(
      MeasurementMode.frameTimingOverlay.value,
      MeasurementMode.startWithFrameTimingOverlay,
      reason: 'the notifier starts at the build default',
    );
  });

  testWidgets('toggling it reaches MaterialApp.showPerformanceOverlay', (
    tester,
  ) async {
    // The app shell only — mounting HomePage would spin up the whole
    // editor, and what is under test is that the notifier drives the
    // MaterialApp property.
    MaterialApp appOf(WidgetTester tester) =>
        tester.widget<MaterialApp>(find.byType(MaterialApp));

    await tester.pumpWidget(const AnicelApp());
    // HomePage is heavy; settle only what the shell needs.
    await tester.pump();
    expect(appOf(tester).showPerformanceOverlay, isFalse);

    MeasurementMode.frameTimingOverlay.value = true;
    await tester.pump();
    expect(
      appOf(tester).showPerformanceOverlay,
      isTrue,
      reason: 'the toggle must not need a rebuild of the app to take effect',
    );

    MeasurementMode.frameTimingOverlay.value = false;
    await tester.pump();
    expect(appOf(tester).showPerformanceOverlay, isFalse);
  });

  test('reset returns it to the build default', () {
    MeasurementMode.frameTimingOverlay.value = true;
    MeasurementMode.reset();
    expect(
      MeasurementMode.frameTimingOverlay.value,
      MeasurementMode.startWithFrameTimingOverlay,
    );
  });
}
