import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/ui/editor_workspace.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/theme/app_theme.dart';

/// **H22 — the timeline follows the window down.**
///
/// 유저 2026-08-23: 「타임라인패널 크기 키워둔채로 창 크기 축소하면 **그 크기
/// 그대로 유지**되어있음. 창 크기 바꾸면 사이드띠의 패널이랑 통일해서 비율대로
/// 작아져야하는데」
///
/// 🚨The rails already did this and the bottom dock was the one exception:
/// their 37.5% ceiling is applied where they are DRAWN, so shrinking the
/// window shrinks a rail that was dragged wide. The bottom dock clamped
/// against what the window could physically spare instead — which only
/// binds once the window is nearly as short as the canvas minimum — so a
/// dragged timeline sat there at its old pixels.
///
/// ⚠️결정 8 refused to clamp here once, for a reason that still stands: a
/// dock whose panels need more than half the window to render at all must
/// not be squeezed under its own floor. Both hold because the floor is
/// folded INTO the ceiling rather than left underneath it, and the last
/// case below is what says so.
void main() {
  Future<void> pumpAt(WidgetTester tester, Size size) async {
    await tester.binding.setSurfaceSize(size);
    await tester.pumpWidget(
      MaterialApp(theme: buildAppTheme(), home: const HomePage()),
    );
    await tester.pumpAndSettle();
  }

  Future<void> resizeTo(WidgetTester tester, Size size) async {
    await tester.binding.setSurfaceSize(size);
    await tester.pumpAndSettle();
  }

  Finder region() =>
      find.byKey(const ValueKey<String>('floating-bottom-region'));

  double regionHeight(WidgetTester tester) => tester.getRect(region()).height;

  /// Drags the bottom splitter up by [by] logical pixels — taller timeline.
  Future<void> growTimeline(WidgetTester tester, double by) async {
    await tester.drag(
      find.byKey(const ValueKey<String>('dock-resize-bottom')),
      Offset(0, -by),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('a timeline dragged tall shrinks with the window', (
    tester,
  ) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await pumpAt(tester, const Size(1600, 1200));
    await growTimeline(tester, 400);

    final tall = regionHeight(tester);
    expect(
      tall,
      greaterThan(800 * EditorWorkspace.bottomDockCeilingFraction),
      reason: 'fixture premise: the drag left the panel taller than the '
          'SMALL window will allow, so there is something to take back',
    );

    await resizeTo(tester, const Size(1600, 800));

    expect(
      regionHeight(tester),
      lessThan(tall),
      reason: 'the window shrank, so the panel did',
    );
    expect(
      regionHeight(tester),
      lessThanOrEqualTo(800 * EditorWorkspace.bottomDockCeilingFraction + 1),
      reason: '「하단은 화면의 절반까지」 — measured against the window it is '
          'in now, not the one it was dragged in',
    );
  });

  testWidgets('and grows back when the window does — the drag is not lost', (
    tester,
  ) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await pumpAt(tester, const Size(1600, 1200));
    await growTimeline(tester, 400);
    final tall = regionHeight(tester);

    await resizeTo(tester, const Size(1600, 800));
    await resizeTo(tester, const Size(1600, 1200));

    expect(
      regionHeight(tester),
      closeTo(tall, 1),
      reason: 'the window clamps what is DRAWN; it does not rewrite what the '
          'user chose',
    );
  });

  testWidgets('⛔an UNDRAGGED dock is not clamped by the half at all', (
    tester,
  ) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    // 🚨This is the case 결정 8 refused the clamp over, and it is still
    // refused. In a window this short the timeline's opening is its floor
    // rather than half the window, and clamping the opening too would draw
    // it under what its panels need — measured then as a row of lanes
    // going missing from two surfaces that never touch dock size.
    //
    // The first draft of THIS round did exactly that, and this case is what
    // caught it: 247px became 186px.
    await pumpAt(tester, const Size(1600, 420));

    expect(
      regionHeight(tester),
      greaterThan(420 * EditorWorkspace.bottomDockCeilingFraction),
      reason: 'nobody dragged this dock — its height is the opening, which '
          'already answers to this window, and to what it needs to render',
    );
  });
}
