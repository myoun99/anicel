import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/canvas/canvas_viewport_gesture_layer.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/theme/app_theme.dart';

/// THE FLIP HUD'S AXIS FOLLOWS THE TIMELINE — MEASURED THROUGH THE WORKSPACE.
///
/// F-28 (유저 2026-08-24): on the X-sheet the frames run down the page, so
/// the canvas flip's vertical axis means frames. The gesture layer's half is
/// measured (flip_axis_follows_the_sheet); the WORKSPACE's half — telling
/// the HUD when the timeline turns — was not: when the flip HUD was carved
/// out of the workspace State (2026-09-02) the adversarial check made
/// `syncFlipAxisWithTimeline` a no-op and every flip test stayed green. So
/// this turns the timeline through its own button and reads the HUD the
/// canvas gesture layer holds.
void main() {
  testWidgets('turning the timeline vertical tells the flip HUD', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1600, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(theme: buildAppTheme(), home: const HomePage()),
    );
    await tester.pumpAndSettle();

    FlipHudReading hud() {
      final layer = tester.widget<CanvasViewportGestureLayer>(
        find.byType(CanvasViewportGestureLayer).first,
      );
      return FlipHudReading(layer.flipHud!.framesRunVertically);
    }

    expect(
      hud().framesRunVertically,
      isFalse,
      reason: 'premise — the timeline opens horizontal, frames run sideways',
    );

    await tester.tap(
      find.byKey(const ValueKey<String>('timeline-orientation-toggle-button')),
    );
    await tester.pumpAndSettle();

    expect(
      hud().framesRunVertically,
      isTrue,
      reason:
          'the X-sheet runs frames down the page, and the workspace tells '
          'the HUD so when the timeline turns',
    );
  });
}

/// A named reading, so the assertion reads as the sentence it is.
class FlipHudReading {
  const FlipHudReading(this.framesRunVertically);
  final bool framesRunVertically;
}
