// ONLY THE FLOOR FOLLOWS THE CENTRE OF ITS WINDOW (08-06; 유저 2026-11-20,
// card a-canvas-panel-rebuilds-its-chrome-on-every-height-change, Q1:
// 「08-06 대로 — 메인 캔버스(바닥)만 가운데를 따라가고, 붙은 패널은 그림이
// 왼쪽 위에 가만히 있다」): the floor keeps what you look at where you look
// when its box changes size; a docked panel lets the artwork stand still.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/canvas_viewport.dart';
import 'package:anicel/src/ui/brush/brush_canvas_panel.dart';
import 'package:anicel/src/ui/brush/main_canvas_brush_host.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/theme/app_theme.dart';

import '../../helpers/rail_group_button.dart';

void main() {
  Future<void> pumpApp(WidgetTester tester, Size size) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(theme: buildAppTheme(), home: const HomePage()),
    );
    await tester.pumpAndSettle();
  }

  BrushCanvasPanel panelIn(WidgetTester tester, Finder host) =>
      tester.widget<BrushCanvasPanel>(
        find.descendant(of: host, matching: find.byType(BrushCanvasPanel)),
      );

  testWidgets('a docked panel whose box changes leaves its picture where it '
      'stood', (tester) async {
    await pumpApp(tester, const Size(1440, 907));
    await tester.tap(railGroupButton('rail-R1'));
    await tester.pumpAndSettle();
    final group = find.byKey(const ValueKey<String>('rail-group-body-rail-R2'));
    final sheet = find.descendant(
      of: group,
      matching: find.byType(BrushCanvasPanel),
    );
    final view = panelIn(tester, group).viewportController!;
    view.value = (view.value ?? CanvasViewport()).translated(dx: 7, dy: 11);
    await tester.pump();
    final stood = view.value;
    final box = tester.getSize(sheet);

    final rail = railPosition(tester, right: true);
    expect(rail.maxScrollExtent, greaterThan(40), reason: '⛔premise');
    rail.jumpTo(40);
    await tester.pump();
    await tester.pump();

    expect(
      tester.getSize(sheet).height,
      isNot(box.height),
      reason: '⛔premise: the rail cut the sheet\'s box anew',
    );
    expect(view.value, stood);
  });

  testWidgets('the floor whose box changes keeps the centre of its window', (
    tester,
  ) async {
    await pumpApp(tester, const Size(1440, 907));
    final floor = find.byType(MainCanvasBrushHost);
    final view = panelIn(tester, floor).viewportController!;
    view.value = (view.value ?? CanvasViewport()).translated(dx: 7, dy: 11);
    await tester.pump();
    final stood = view.value!;
    final box = tester.getSize(
      find.descendant(of: floor, matching: find.byType(BrushCanvasPanel)),
    );

    await tester.binding.setSurfaceSize(const Size(1440, 807));
    await tester.pumpAndSettle();

    final now = tester.getSize(
      find.descendant(of: floor, matching: find.byType(BrushCanvasPanel)),
    );
    expect(now.height, isNot(box.height), reason: '⛔premise: the box shrank');
    expect(view.value!.panX, closeTo(stood.panX, 1e-6));
    expect(view.value!.panY, isNot(closeTo(stood.panY, 1e-6)));
  });

  // the-view-stays-moved-after-the-screen-turns-and-back (2026-11-22): a
  // phone's screen turned and back puts the floor's view back where it
  // stood — its covers wider than the box it left, each way.
  testWidgets('the floor turned and back stands where it stood', (
    tester,
  ) async {
    const upright = Size(1080, 2424);
    tester.view.devicePixelRatio = 2.625;
    tester.view.physicalSize = upright;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(theme: buildAppTheme(), home: const HomePage()),
    );
    await tester.pumpAndSettle();
    final floor = find.byType(MainCanvasBrushHost);
    final view = panelIn(tester, floor).viewportController!;
    view.value = (view.value ?? CanvasViewport()).translated(dx: 7, dy: 11);
    await tester.pump();
    final stood = view.value!;

    tester.view.physicalSize = Size(upright.height, upright.width);
    await tester.pumpAndSettle();
    expect(
      view.value!.panX,
      isNot(closeTo(stood.panX, 1e-6)),
      reason: '⛔premise: turned, the view followed the centre',
    );
    tester.view.physicalSize = upright;
    await tester.pumpAndSettle();

    expect(view.value!.panX, closeTo(stood.panX, 1e-6));
    expect(view.value!.panY, closeTo(stood.panY, 1e-6));
  });
}
