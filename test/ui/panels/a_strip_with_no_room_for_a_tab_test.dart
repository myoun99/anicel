import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/editor_workspace.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/panels/editor_panel_tabs.dart';
import 'package:anicel/src/ui/storyboard_panel.dart';
import 'package:anicel/src/ui/timeline/frame_panel_sill_controls.dart';

/// A tab strip whose sill leaves it no room for even one tab — the
/// storyboard docked on its own in a rail, the rail narrowed until the
/// sill's transport takes nearly all of it; a 340px window — keeps its
/// overflow button (the one way to its tabs) WHOLE, and shows the sill all
/// of it, smaller (`KeptTailRow`, the page turner's law).
///
/// ↩️The button was laid out past the edge, and the strip's Row threw 「A
/// RenderFlex overflowed by 23 pixels」 (found 2026-09-25 while pinning the
/// rail button as a door); then it was cut at the room's edge, and the sill
/// itself still ran over — 10px at 340 (2026-10-15). The rail at its own
/// width left no room then only while the project's ⚙ stood on the sill;
/// it moved to the top strip (playback-quality-home), so the rail is
/// narrowed by hand.
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
                      // A ROW, as a sill is: held narrower than itself it
                      // runs over, where a plain box would only be clamped.
                      sillTrailing: (context) => const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            key: sill,
                            width: sillWidth,
                            height: sillHeight,
                          ),
                        ],
                      ),
                    ),
                ],
                activeTabId: 'a',
                onTabSelected: (_) {},
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

  testWidgets('the storyboard alone in a rail, narrowed until its sill '
      'gives way, keeps its tab whole and runs nothing over', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1600, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const MaterialApp(home: HomePage()));
    await tester.pumpAndSettle();

    final railId = EditorWorkspace.railGroupId(right: true, slot: 6);
    final freeSlot = find.byKey(ValueKey<String>('rail-group-$railId'));
    final gesture = await tester.startGesture(
      tester.getCenter(
        find.byKey(const ValueKey<String>('panel-grip-storyboard')),
      ),
    );
    await tester.pump(const Duration(milliseconds: 20));
    await gesture.moveBy(const Offset(30, 0));
    await tester.pump();
    expect(freeSlot, findsOneWidget, reason: 'premise: the free slot');
    await gesture.moveTo(tester.getCenter(freeSlot));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
    expect(find.byType(StoryboardPanel), findsOneWidget, reason: 'premise');

    // A right rail narrows as its inner edge moves right. The grip runs the
    // group's height beside the panel's own controls, so it is taken where
    // nothing lies over it.
    final grip = find.byKey(ValueKey<String>('dock-resize-$railId'));
    Offset? handle() {
      final rect = tester.getRect(grip);
      final box = tester.renderObject(grip);
      for (var y = rect.top + 4; y < rect.bottom; y += 8) {
        final at = Offset(rect.center.dx, y);
        if (tester
            .hitTestOnBinding(at)
            .path
            .any((entry) => entry.target == box)) {
          return at;
        }
      }
      return null;
    }

    // Narrowed a step at a time until the sill gives way — shown smaller
    // than itself, the case this pins. Shown, it is scaled; laid out, it
    // keeps its own size.
    final tab = find.byKey(
      const ValueKey<String>('timeline-mode-storyboard-button'),
    );
    final sill = find.descendant(
      of: find.ancestor(of: tab, matching: find.byType(EditorPanelTabs)),
      matching: find.byType(FramePanelSillControls),
    );
    bool givesWay() =>
        tester.getRect(sill).width < tester.getSize(sill).width - 0.5;
    expect(
      givesWay(),
      isFalse,
      reason: '⛔premise: at the rail\'s own width the sill stands whole',
    );
    for (var step = 0; step < 60 && !givesWay(); step += 1) {
      final at = handle();
      expect(at, isNotNull, reason: 'premise: the rail\'s grip is free');
      await tester.dragFrom(
        at!,
        const Offset(4, 0),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'at step $step');
    }

    expect(givesWay(), isTrue, reason: '⛔LIVENESS: the sill gave way');
    expect(
      tester.getRect(tab).right,
      lessThanOrEqualTo(tester.getRect(sill).left),
      reason: 'the way to the panel stands whole, clear of the sill',
    );
  });
}
