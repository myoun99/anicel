import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/ui/brush/brush_preset_panel.dart';

import 'settle_async.dart';

/// Lends both clocks until the workspace's brushes have landed — the
/// libraries are read off the disk, so on the real clock, and their landing
/// goes on on the fake one — and then settles.
///
/// Landed = the presets are listed AND a brush is in hand: the opening
/// brush is taken up only once the hand-settings bank has landed too
/// (H25-again), and that is one more file read after the libraries'.
///
/// ⚠️A test that asks what ANOTHER change rebuilt waits for this first: the
/// landing rebuilds the home page's shortcuts and every brush panel, and a
/// wait on the real clock for something else lets it land in the middle.
Future<void> untilTheBrushesLand(WidgetTester tester) async {
  expect(
    await settleAsync(tester, () {
      final panels = find.byType(BrushPresetPanel).evaluate();
      final shown = panels.isEmpty
          ? null
          : panels.first.widget as BrushPresetPanel;
      return shown != null &&
          shown.presets.isNotEmpty &&
          shown.selectedPresetId != null;
    }),
    isTrue,
    reason: 'the brushes landed',
  );
  await tester.pumpAndSettle();
}
