import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/theme/app_theme.dart';

/// 🗣️I-60 (유저 2026-10-02): 「패널의 꼭짓점 끌어서 x값y값 동시 조절하는기능
/// 추가」.
///
/// A panel's corner is its two edge grips at once: one drag moves both
/// edges, each through the travel its own grip spends — a rail panel's
/// inner-bottom corner, and the floating region's two corners on the edge
/// that faces the artwork.
void main() {
  Future<void> pumpApp(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1600, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(theme: buildAppTheme(), home: const HomePage()),
    );
    await tester.pumpAndSettle();
  }

  Rect rectOf(WidgetTester tester, String key) =>
      tester.getRect(find.byKey(ValueKey<String>(key)));

  testWidgets('a rail panel\'s corner moves its width edge and its height '
      'edge together', (tester) async {
    await pumpApp(tester);
    final width = rectOf(tester, 'dock-resize-rail-R2');
    final height = rectOf(tester, 'dock-resize-rail-R2-height');

    // R2 is on the right: its inner edge is the LEFT one, so pulling left
    // widens it, and pulling down makes it taller.
    await tester.drag(
      find.byKey(const ValueKey<String>('dock-resize-rail-R2-corner')),
      const Offset(-40, 30),
    );
    await tester.pumpAndSettle();

    expect(
      rectOf(tester, 'dock-resize-rail-R2').left,
      closeTo(width.left - 40, 0.5),
    );
    expect(
      rectOf(tester, 'dock-resize-rail-R2-height').top,
      closeTo(height.top + 30, 0.5),
    );
  });

  testWidgets('⛔each axis keeps its own debt: past one edge\'s ceiling the '
      'way back pays that axis only', (tester) async {
    await pumpApp(tester);
    final corner = find.byKey(
      const ValueKey<String>('dock-resize-rail-R2-corner'),
    );
    final gesture = await tester.startGesture(tester.getCenter(corner));
    // Far past the rail's foot: the height stops at its ceiling and the
    // rest of the travel is owed.
    await gesture.moveBy(const Offset(-20, 2000));
    await tester.pump();
    final width = rectOf(tester, 'dock-resize-rail-R2');
    final height = rectOf(tester, 'dock-resize-rail-R2-height');

    await gesture.moveBy(const Offset(-20, -100));
    await tester.pump();
    expect(
      rectOf(tester, 'dock-resize-rail-R2-height').top,
      height.top,
      reason: 'the height still owes the travel it could not use',
    );
    expect(
      rectOf(tester, 'dock-resize-rail-R2').left,
      closeTo(width.left - 20, 0.5),
      reason: 'and the width, which owed nothing, moved',
    );
    await gesture.up();
    await tester.pumpAndSettle();
  });

  // The region's width is symmetric, snaps to a rail and lets the rails
  // through, so where its edges END is the region's layout to say. What the
  // corner owes is that each axis of it IS that edge's grip.
  Future<(Rect, Rect)> regionAfter(
    WidgetTester tester,
    String grip,
    Offset pull,
  ) async {
    // A fresh workspace each time — pumped over the last one, the app would
    // keep that one's state and its sizes.
    await tester.pumpWidget(const SizedBox());
    await pumpApp(tester);
    await tester.drag(find.byKey(ValueKey<String>(grip)), pull);
    await tester.pumpAndSettle();
    return (
      rectOf(tester, 'bottom-inset-left'),
      rectOf(tester, 'dock-resize-bottom'),
    );
  }

  testWidgets('the floating region\'s corner, pulled along one axis, is that '
      'axis\'s edge', (tester) async {
    expect(
      await regionAfter(tester, 'bottom-corner-left', const Offset(30, 0)),
      await regionAfter(tester, 'bottom-inset-left', const Offset(30, 0)),
      reason: 'sideways it is the side grip',
    );
    // Down, because the region opens at the half the hand may not pass.
    expect(
      await regionAfter(tester, 'bottom-corner-left', const Offset(0, 40)),
      await regionAfter(tester, 'dock-resize-bottom', const Offset(0, 40)),
      reason: 'up and down it is the top grip',
    );
  });

  testWidgets('…and pulled on the diagonal, it moves both', (tester) async {
    await pumpApp(tester);
    final side = rectOf(tester, 'bottom-inset-left');
    final top = rectOf(tester, 'dock-resize-bottom');

    await tester.drag(
      find.byKey(const ValueKey<String>('bottom-corner-left')),
      const Offset(-20, 30),
    );
    await tester.pumpAndSettle();
    expect(rectOf(tester, 'bottom-inset-left').left, lessThan(side.left));
    expect(rectOf(tester, 'dock-resize-bottom').top, greaterThan(top.top));
  });

  testWidgets('⛔a sideways pull of the corner leaves the height un-chosen: '
      'it still follows the window', (tester) async {
    // D37: a region nobody has sized opens at half the window and follows
    // it; a height the hand chose stays in pixels. The corner pulled only
    // sideways chose no height.
    Future<double> topOnceGrown(Offset? pull) async {
      await tester.pumpWidget(const SizedBox());
      await pumpApp(tester);
      if (pull != null) {
        await tester.drag(
          find.byKey(const ValueKey<String>('bottom-corner-left')),
          pull,
        );
        await tester.pumpAndSettle();
      }
      await tester.binding.setSurfaceSize(const Size(1600, 1300));
      await tester.pumpAndSettle();
      return rectOf(tester, 'dock-resize-bottom').top;
    }

    expect(
      await topOnceGrown(const Offset(30, 0)),
      await topOnceGrown(null),
    );
  });

  testWidgets('the top edge\'s first pull moves the region by the pull — it '
      'starts from the height the region is drawn at', (tester) async {
    // ↩️Found by the corner: the edge fell back on the fixed 350 while the
    // region opens at half the window, so the first pull jumped it.
    await pumpApp(tester);
    final top = rectOf(tester, 'dock-resize-bottom');
    await tester.drag(
      find.byKey(const ValueKey<String>('dock-resize-bottom')),
      const Offset(0, 40),
    );
    await tester.pumpAndSettle();
    expect(
      rectOf(tester, 'dock-resize-bottom').top,
      closeTo(top.top + 40, 0.5),
    );
  });

  testWidgets('folded, the region has no corners — the height is the axis '
      'the fold is about', (tester) async {
    await pumpApp(tester);
    expect(
      find.byKey(const ValueKey<String>('bottom-corner-left')),
      findsOneWidget,
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('floating-bottom-collapse')),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey<String>('bottom-corner-left')),
      findsNothing,
    );
  });
}
