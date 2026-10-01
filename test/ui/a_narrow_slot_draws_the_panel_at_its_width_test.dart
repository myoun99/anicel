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
  Future<Rect> pumpNarrow(WidgetTester tester) async {
    // Narrower than 640, and wide enough for the top strip: at 560 the
    // strip's own row overflowed by 30, a failure about the strip and not
    // about the slot this pins.
    await tester.binding.setSurfaceSize(const Size(620, 1000));
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
