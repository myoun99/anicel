import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/editor_workspace.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/storyboard_panel.dart';

/// A tab strip whose sill leaves it no room for even one tab — the
/// storyboard docked on its own in a rail, at the rail's own width, whose
/// transport and settings take nearly all of it — keeps its overflow button
/// (the one way to its tabs) and CUTS it at the room's edge.
///
/// ↩️The button was laid out past the edge, and the strip's Row threw 「A
/// RenderFlex overflowed by 23 pixels」 (found 2026-09-25 while pinning the
/// rail button as a door).
void main() {
  testWidgets('the storyboard alone in a rail lays its strip out without '
      'overflowing', (tester) async {
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
    expect(
      find.byKey(ValueKey<String>('panel-tab-overflow-$railId')),
      findsOneWidget,
      reason: 'no room for a tab, and the way to the tabs is still there',
    );
    expect(tester.takeException(), isNull);
  });
}
