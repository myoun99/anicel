import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/storyboard_tab_host.dart';
import 'package:anicel/src/ui/theme/app_theme.dart';
import 'package:anicel/src/ui/timeline_tab_host.dart';

/// 🗣️scrollbar-unify-Q1 (유저 2026-09-30): 「640 을 걷는다 — 콘티·컷봉투와
/// 같은 법」. In a slot narrower than 640 the timeline and the storyboard used
/// to lay out 640 wide inside the tab shell's sideways scroller, whose bar sat
/// on the panel's own frame rail. They draw at the slot's width now, as the
/// conte and the envelope have since R3 #11.
void main() {
  // 🪦A helper stood here that set the TOP STRIP's overflow aside: only a
  // window under 736 gives a slot under 640, and below ~770 the strip ran
  // off its end. The strip gives way now (top-strip-narrow-overflow,
  // `test/ui/menu/the_top_strip_gives_way_test.dart`), so a narrow window is
  // pumped like any other and every error is this test's own.
  Future<Rect> pumpNarrow(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(640, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(theme: buildAppTheme(), home: const HomePage()),
    );
    await tester.pumpAndSettle();
    return tester.getRect(
      find.byKey(const ValueKey<String>('floating-bottom-region')),
    );
  }

  testWidgets('the timeline draws at the slot\'s width, not at 640', (
    tester,
  ) async {
    final region = await pumpNarrow(tester);
    expect(region.width, lessThan(640), reason: 'the premise: a narrow slot');

    expect(
      tester.getSize(find.byType(TimelineTabHost)).width,
      lessThanOrEqualTo(region.width),
    );
  });

  testWidgets('so does the storyboard', (tester) async {
    final region = await pumpNarrow(tester);
    await tester.tap(
      find.byKey(const ValueKey<String>('timeline-mode-storyboard-button')),
    );
    await tester.pumpAndSettle();

    expect(
      tester.getSize(find.byType(StoryboardTabHost)).width,
      lessThanOrEqualTo(region.width),
    );
  });
}
