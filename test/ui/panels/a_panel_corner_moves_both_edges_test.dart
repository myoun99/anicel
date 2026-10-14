import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/shortcuts/editor_action_registry.dart';
import 'package:anicel/src/ui/theme/app_theme.dart';

import '../../helpers/app_shortcuts.dart';

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

  // 🗣️I-60 (유저 2026-10-13): 「꼭짓점 스플리터를 우선으로, 이 가로나 세로
  // 스플리터의 ui?를 딱 그 앞까지만 하도록 … 꼭짓점 반대도 마찬가지로 곡선
  // 전에 끝나도록」.
  testWidgets('🎯an edge grip runs the straight part of its edge alone: it '
      'meets its corner without crossing it, and stops where a bare '
      'corner\'s curve begins', (tester) async {
    await pumpApp(tester);
    const curve = AppShapes.floatingPanelRadius;

    // R2 is on the right: its corner is the inner (left) one at its foot.
    final panel = rectOf(tester, 'rail-group-body-rail-R2');
    final width = rectOf(tester, 'dock-resize-rail-R2');
    final height = rectOf(tester, 'dock-resize-rail-R2-height');
    final corner = rectOf(tester, 'dock-resize-rail-R2-corner');
    expect(height.overlaps(corner), isFalse);
    expect(width.overlaps(corner), isFalse);
    expect(height.left, corner.right, reason: '딱 그 앞까지');
    expect(width.bottom, corner.top, reason: '딱 그 앞까지');
    expect(height.right, panel.right - curve, reason: '곡선 전에');
    expect(width.top, panel.top + curve, reason: '곡선 전에');

    // The floating region faces the artwork with its top edge: a corner
    // at each end of it, and each side edge starts below one.
    final top = rectOf(tester, 'dock-resize-bottom');
    final left = rectOf(tester, 'bottom-corner-left');
    final right = rectOf(tester, 'bottom-corner-right');
    final side = rectOf(tester, 'bottom-inset-left');
    expect(top.overlaps(left) || top.overlaps(right), isFalse);
    expect(side.overlaps(left), isFalse);
    expect(top.left, left.right, reason: '딱 그 앞까지');
    expect(top.right, right.left, reason: '딱 그 앞까지');
    expect(side.top, left.bottom, reason: '딱 그 앞까지');
  });

  testWidgets('…and with the region at the top of the window its corners '
      'are at its foot, and its edges stop at them the same way', (
    tester,
  ) async {
    await pumpApp(tester);
    final keys = appShortcuts(tester);
    keys.setActivators(EditorActionIds.regionOnTop, const [
      SingleActivator(LogicalKeyboardKey.keyK, control: true, shift: true),
    ]);
    expect(
      keys.conflictedActionIds,
      isEmpty,
      reason: '⛔premise: a chord no other action is on',
    );
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();

    final foot = rectOf(tester, 'dock-resize-bottom');
    final left = rectOf(tester, 'bottom-corner-left');
    final right = rectOf(tester, 'bottom-corner-right');
    final side = rectOf(tester, 'bottom-inset-left');
    expect(
      foot.top,
      greaterThan(side.top),
      reason: '⛔premise: the edge facing the artwork is its foot now',
    );
    expect(foot.overlaps(left) || foot.overlaps(right), isFalse);
    expect(side.overlaps(left), isFalse);
    expect(foot.left, left.right, reason: '딱 그 앞까지');
    expect(foot.right, right.left, reason: '딱 그 앞까지');
    expect(side.bottom, left.top, reason: '딱 그 앞까지');
  });

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
