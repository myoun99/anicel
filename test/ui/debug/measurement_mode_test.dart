import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/main.dart';
import 'package:anicel/src/ui/debug/input_inspector.dart';
import 'package:anicel/src/ui/debug/measurement_mode.dart';

/// The debug window is ONE switch (유저 2026-11-24,
/// one-debug-window-shows-everything Q2): what is worth pinning is that it
/// stays OFF unless asked for — a window left on ships the instruments
/// across the user's canvas —, that the inspector answers to it and no
/// switch of its own, and that Flutter's own graphs, which the window's
/// graph replaced, are never drawn.
void main() {
  tearDown(MeasurementMode.reset);

  test('off unless --dart-define=QA_DEBUG_WINDOW=true seeds it, and back '
      'to that after a reset', () {
    expect(
      MeasurementMode.startWithDebugWindow,
      isFalse,
      reason: 'default builds must not draw the debug window',
    );
    expect(
      MeasurementMode.debugWindow.value,
      MeasurementMode.startWithDebugWindow,
    );
    MeasurementMode.debugWindow.value = true;
    MeasurementMode.reset();
    expect(
      MeasurementMode.debugWindow.value,
      MeasurementMode.startWithDebugWindow,
    );
  });

  test('the input inspector answers to the one switch', () {
    expect(InputInspector.visible, same(MeasurementMode.debugWindow));
  });

  testWidgets('Flutter\'s frame-timing graphs are never drawn — the '
      'window\'s graph stands in their place', (tester) async {
    MeasurementMode.debugWindow.value = true;
    await tester.pumpWidget(const AnicelApp());
    await tester.pump();
    expect(
      tester.widget<MaterialApp>(find.byType(MaterialApp))
          .showPerformanceOverlay,
      isFalse,
    );
  });
}
