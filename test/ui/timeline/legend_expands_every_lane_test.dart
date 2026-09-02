import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/theme/app_theme.dart';

/// THE LEGEND'S LANE TOGGLE EXPANDS EVERY LANE — MEASURED.
///
/// The legend header carries one toggle for all lanes: expand every
/// layer's lanes when none are open, collapse them all when any is. When
/// the layer grid's lanes were carved out of its State as `_LayerGridLanes`
/// (2026-09-02), the adversarial check made `_expandAllLanes` a no-op and
/// thirty-nine lane tests stayed green — every one of them opened lanes
/// through the per-layer twirl, and none pressed the legend. So this
/// presses it and counts the lane rows the rail then shows.
void main() {
  Finder laneRows() => find.byWidgetPredicate((widget) {
    final key = widget.key;
    if (key is! ValueKey<String>) {
      return false;
    }
    final value = key.value;
    return value.startsWith('timeline-rail-row-') &&
        !value.endsWith('-row') &&
        !value.contains('-folder-');
  });

  testWidgets('one press on the legend opens every lane in the rail', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1400, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(theme: buildAppTheme(), home: const HomePage()),
    );
    await tester.pumpAndSettle();
    // Room for lane rows: pull the timeline dock up.
    await tester.drag(
      find.byKey(const ValueKey<String>('dock-resize-bottom')),
      const Offset(0, -520),
    );
    await tester.pumpAndSettle();

    final toggle = find.byKey(const ValueKey<String>('legend-lanes-toggle'));
    expect(toggle, findsOneWidget, reason: 'premise — the legend offers it');
    expect(laneRows(), findsNothing, reason: 'premise — no lane is open');

    await tester.tap(toggle);
    await tester.pumpAndSettle();

    expect(
      laneRows(),
      findsAtLeastNWidgets(1),
      reason:
          'the toggle asked the grid to expand every layer that has '
          'lanes; a rail with none open afterwards means it asked nothing',
    );
  });
}
