import '../../helpers/screens_left_of_the_engine.dart';
import 'package:anicel/src/models/canvas_viewport.dart';
import 'package:anicel/src/ui/brush/brush_canvas_panel.dart';
import 'package:anicel/src/ui/brush/brush_edit_cache_invalidation_sink.dart';
import 'package:anicel/src/ui/brush/canvas_floor_insets.dart';
import 'package:anicel/src/ui/brush/canvas_view_commands.dart';
import 'package:anicel/src/ui/brush/main_canvas_brush_host.dart';
import 'package:anicel/src/ui/canvas/interactive_brush_edit_canvas_view.dart';
import 'package:anicel/src/ui/conte/conte_tab_host.dart';
import 'package:anicel/src/ui/editor_workspace.dart';
import 'package:anicel/src/ui/envelope/cut_envelope_tab_host.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/shortcuts/editor_action_registry.dart';
import 'package:anicel/src/ui/theme/app_theme.dart';
import 'package:anicel/src/ui/timesheet_tab_host.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/app_shortcuts.dart';
import '../../helpers/brush_canvas_fixture.dart';

/// 🗣️F-623 (유저 2026-11-19): 「바닥에 깔린 패널에 단축키 적용되도록. 예를들어
/// 화면 확대 축소 단축키같은거. 바닥에 깔린 타임시트패널이나 콘티패널같은데서
/// 적용되도록」 — the view keys drive whichever panel lies on the floor, and
/// press there what its bar has.
void main() {
  itsTestsLeaveScreensOfTheEngine({ScreensLeft.ofAShot});
  const zoomIn = LogicalKeyboardKey.f9;
  const turn = LogicalKeyboardKey.f10;

  Future<void> pumpApp(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1600, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(theme: buildAppTheme(), home: const HomePage()),
    );
    await tester.pumpAndSettle();
    appShortcuts(tester)
      ..setActivators(EditorActionIds.canvasZoomIn, const [
        SingleActivator(zoomIn),
      ])
      ..setActivators(EditorActionIds.canvasRotateCw, const [
        SingleActivator(turn),
      ]);
    await tester.pump();
  }

  /// The top strip's floor switch presses exactly this.
  Future<void> layOnTheFloor(WidgetTester tester, String tabId) async {
    tester
        .widget<EditorWorkspace>(find.byType(EditorWorkspace))
        .panelsMenu!
        .selectFloorTab(tabId);
    await tester.pumpAndSettle();
  }

  CanvasViewport viewOf(WidgetTester tester, Type host) => tester
      .widget<BrushCanvasPanel>(
        find
            .descendant(
              of: find.byType(host),
              matching: find.byType(BrushCanvasPanel),
            )
            .first,
      )
      .publishedViewport;

  Future<void> press(WidgetTester tester, LogicalKeyboardKey key) async {
    await tester.sendKeyEvent(key);
    await tester.pumpAndSettle();
  }

  testWidgets('the zoom key zooms whatever lies on the floor — the canvas, '
      'and each sheet laid there', (tester) async {
    await pumpApp(tester);
    for (final (tabId, host) in [
      (EditorWorkspace.canvasTabId, MainCanvasBrushHost),
      (EditorWorkspace.timesheetTabId, TimesheetTabHost),
      (EditorWorkspace.conteTabId, ConteTabHost),
      (EditorWorkspace.envelopeTabId, CutEnvelopeTabHost),
    ]) {
      await layOnTheFloor(tester, tabId);
      // A sheet's view is published once it moves; before that it reads
      // one pixel to one, whatever it framed itself (the conte's did).
      await press(tester, zoomIn);
      final before = viewOf(tester, host).zoom;

      await press(tester, zoomIn);

      expect(viewOf(tester, host).zoom, greaterThan(before), reason: '$host');
    }
  });

  testWidgets('⛔a sheet docked in its rail takes no key: the canvas lying on '
      'the floor does', (tester) async {
    await pumpApp(tester);
    expect(
      find.byType(TimesheetTabHost),
      findsOneWidget,
      reason: '⛔premise: the timesheet opens docked in its rail',
    );
    final sheet = viewOf(tester, TimesheetTabHost).zoom;
    final canvas = viewOf(tester, MainCanvasBrushHost).zoom;

    await press(tester, zoomIn);

    expect(viewOf(tester, TimesheetTabHost).zoom, sheet);
    expect(viewOf(tester, MainCanvasBrushHost).zoom, greaterThan(canvas));
  });

  testWidgets('a sheet laid on the floor never turns, as its bar has no '
      'turn — the canvas laid back turns', (tester) async {
    await pumpApp(tester);
    await layOnTheFloor(tester, EditorWorkspace.timesheetTabId);

    await press(tester, turn);

    expect(viewOf(tester, TimesheetTabHost).rotationDegrees, 0);

    await layOnTheFloor(tester, EditorWorkspace.canvasTabId);
    await press(tester, turn);

    expect(
      viewOf(tester, MainCanvasBrushHost).rotationDegrees,
      isNot(0),
      reason: '⛔premise: the key turns what turns',
    );
  });

  // F-77 (유저: 「뷰어패널 열린거 없으면 확대나 스크롤바같은 조작 버튼
  // 비활성화」): with no view to operate, the zoom buttons are off, and the
  // keys press what the bar has.
  for (final (hasView, moves) in [(true, true), (false, false)]) {
    testWidgets('a panel ${hasView ? 'with' : 'with NO'} view to operate '
        '${moves ? 'zooms' : 'takes no zoom key'}', (tester) async {
      final frameKeys = BrushCanvasFixture.createFrameKeys();
      final commands = CanvasViewCommands();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CanvasFloorInsets(
              insets: EdgeInsets.zero,
              viewCommands: commands,
              child: BrushCanvasPanel(
                coordinator: BrushCanvasFixture.createCoordinator(
                  frameKeys: frameKeys,
                ),
                availableFrameKeys: frameKeys,
                cacheInvalidationSink: BrushEditCacheInvalidationSink(),
                hasContentToView: hasView,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      double zoom() => tester
          .widget<InteractiveBrushEditCanvasView>(
            find.byType(InteractiveBrushEditCanvasView),
          )
          .viewport
          .zoom;
      final before = zoom();

      commands.zoomStep(zoomIn: true);
      await tester.pumpAndSettle();

      expect(zoom() > before, moves);
    });
  }
}
