import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/panels/editor_panel_tabs.dart';

/// A tab strip whose sill leaves it no room for even one tab — a 340px
/// window, a rail narrowed by hand — keeps its overflow button (the one way
/// to its tabs) WHOLE, and shows the sill all of it, smaller (`KeptTailRow`,
/// the page turner's law).
///
/// ↩️The button was laid out past the edge, and the strip's Row threw 「A
/// RenderFlex overflowed by 23 pixels」 (found 2026-09-25 while pinning the
/// rail button as a door); then it was cut at the room's edge, and the sill
/// itself still ran over — 10px at 340 (2026-10-15). The case in the app
/// was the storyboard alone in a narrowed rail, while the frame panels'
/// transport stood on the sill; it is on their bar now (F-111, F-463), and
/// that case is the bar's (`the_bar_is_two_groups_test`).
void main() {
  testWidgets('🚨a strip narrower than its sill and one tab keeps the '
      'overflow button whole, clear of the sill, and shows the sill all of '
      'it, smaller', (tester) async {
    const sill = ValueKey<String>('sill');
    const sillWidth = 200.0;
    // Taller than the strip, as a 48px button is: the sill is laid out in
    // the strip's height, as the strip's stretched row always laid it, and
    // only a lack of WIDTH shows it smaller.
    const sillHeight = 100.0;
    expect(sillHeight, greaterThan(EditorPanelTabs.stripHeight));
    Future<void> pumpStrip(double width) => tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: width,
              height: 150,
              child: EditorPanelTabs(
                groupId: 'g',
                tabs: [
                  for (final id in ['a', 'b', 'c'])
                    EditorPanelTab(
                      id: id,
                      label: id,
                      icon: Icons.abc,
                      builder: (context) => const SizedBox(),
                    ),
                ],
                activeTabId: 'a',
                onTabSelected: (_) {},
                // The group's own controls, which the strip lays in a ROW:
                // held narrower than itself it runs over, where a plain box
                // would only be clamped.
                trailing: const [
                  SizedBox(key: sill, width: sillWidth, height: sillHeight),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    final overflow = find.byKey(const ValueKey<String>('panel-tab-overflow-g'));

    await pumpStrip(600);
    expect(overflow, findsNothing, reason: '⛔premise: all three fit');
    expect(
      tester.getRect(find.byKey(sill)).width,
      sillWidth,
      reason: 'where the strip holds it, the sill stands at its own width',
    );

    await pumpStrip(150);

    expect(tester.takeException(), isNull);
    expect(overflow, findsOneWidget);
    final button = tester.getRect(overflow);
    final shown = tester.getRect(find.byKey(sill));
    expect(button.left, greaterThanOrEqualTo(0));
    expect(
      button.right,
      lessThanOrEqualTo(shown.left),
      reason: 'the button whole, clear of the sill',
    );
    expect(shown.width, lessThan(sillWidth), reason: 'the sill, smaller');
    expect(shown.right, lessThanOrEqualTo(150), reason: 'none of it runs off');
  });
}
