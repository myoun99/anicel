import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/editor_workspace.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/storyboard_panel.dart';

/// A tab strip whose sill leaves it no room for even one tab — the
/// storyboard docked on its own in a rail, the rail narrowed until the
/// sill's transport takes nearly all of it — keeps its overflow button (the
/// one way to its tabs) and CUTS it at the room's edge.
///
/// ↩️The button was laid out past the edge, and the strip's Row threw 「A
/// RenderFlex overflowed by 23 pixels」 (found 2026-09-25 while pinning the
/// rail button as a door). The rail at its own width left no room then
/// only while the project's ⚙ stood on the sill; it moved to the top
/// strip (playback-quality-home), so the rail is narrowed by hand.
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

    // Narrowed a step at a time, and no further than the moment the sill
    // leaves no room for a tab — the case this pins. Narrower still, the
    // sill itself would not fit: another case than this one.
    final overflow = find.byKey(ValueKey<String>('panel-tab-overflow-$railId'));
    for (var step = 0; step < 60 && overflow.evaluate().isEmpty; step += 1) {
      final at = handle();
      expect(at, isNotNull, reason: 'premise: the rail\'s grip is free');
      await tester.dragFrom(
        at!,
        const Offset(4, 0),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pumpAndSettle();
    }

    expect(
      overflow,
      findsOneWidget,
      reason: 'no room for a tab, and the way to the tabs is still there',
    );
    expect(tester.takeException(), isNull);
  });
}
