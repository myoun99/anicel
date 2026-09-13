import 'package:flutter/gestures.dart'
    show PointerDeviceKind, kSecondaryMouseButton;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_shape_kind.dart';
import 'package:anicel/src/models/canvas_viewport.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/ui/brush/brush_tool_state.dart';
import 'package:anicel/src/ui/brush/main_canvas_brush_host.dart';
import 'package:anicel/src/ui/brush/tools_panel.dart';
import 'package:anicel/src/ui/brush/transform_tool_options.dart';
import 'package:anicel/src/ui/canvas/canvas_pan_hold.dart';
import 'package:anicel/src/ui/canvas/canvas_selection_layer.dart';
import 'package:anicel/src/ui/editor_workspace.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/timeline/timeline_layer_controls_row.dart';

import '../flyout_test_helpers.dart';
import '../../helpers/app_icon_button_probe.dart';

/// P1: the app-level shortcut layer end to end — flipping, tools, undo,
/// the text-field bare-letter guard and live re-recording through the
/// Keyboard Shortcuts dialog.
void main() {
  Future<void> pumpHome(WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: HomePage()));
    await tester.pumpAndSettle();
  }

  // The counter stacks track-global over cut-local (2026-08-10); the flip
  // these tests drive is a CUT-local move, so the local line is the reading.
  String counterText(WidgetTester tester) => tester
      .widget<Text>(
        find.byKey(const ValueKey<String>('timeline-local-frame-counter')),
      )
      .data!;

  testWidgets('comma/period flip frames; Ctrl variants jump drawings', (
    tester,
  ) async {
    await pumpHome(tester);
    expect(counterText(tester), '1');

    await tester.sendKeyEvent(LogicalKeyboardKey.period);
    await tester.pumpAndSettle();
    expect(counterText(tester), '2');

    // PEN-7c: Ctrl+arrows are the ONE-FRAME step now (plain arrows walk
    // drawings).
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(counterText(tester), '3');

    await tester.sendKeyEvent(LogicalKeyboardKey.comma);
    await tester.pumpAndSettle();
    expect(counterText(tester), '2');

    // A PLAIN arrow walks to the drawing (the block at frame 1), and the
    // comma stays clamped at the cut start.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.comma);
    await tester.pumpAndSettle();
    expect(counterText(tester), '1');

    // A drawing at the cut start, playhead moved ahead: Ctrl+, walks back
    // one COLUMN a press — the empty frame between is a column of its
    // own, which is the half of the rule the old jump skipped.
    // Making a drawing is the timeline's Add button now — the Edit menu
    // that used to carry it is gone.
    await tester.tap(find.byKey(const ValueKey<String>('new-frame-button')));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.period);
    await tester.sendKeyEvent(LogicalKeyboardKey.period);
    await tester.pumpAndSettle();
    expect(counterText(tester), '3');

    Future<void> ctrlComma() async {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.comma);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
    }

    await ctrlComma();
    expect(counterText(tester), '2', reason: 'the empty frame between');
    await ctrlComma();
    expect(counterText(tester), '1', reason: 'the drawing');
  });

  testWidgets('B/E switch tools; typing in a text field never does', (
    tester,
  ) async {
    await pumpHome(tester);
    CanvasTool toolOf() =>
        tester.widget<ToolsPanel>(find.byType(ToolsPanel)).tool;

    expect(toolOf(), CanvasTool.brush);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyE);
    await tester.pumpAndSettle();
    expect(toolOf(), CanvasTool.eraser);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyB);
    await tester.pumpAndSettle();
    expect(toolOf(), CanvasTool.brush);

    // A focused text field absorbs bare letters (the rename dialog).
    // Renaming a cut lives in the Cut flyout; the helper opens the owning
    // menu and brings it into view first.
    await tapCommandButton(tester, const ValueKey<String>('rename-cut-button'));
    await tester.tap(find.byType(TextField).last);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.keyE);
    await tester.pumpAndSettle();
    expect(toolOf(), CanvasTool.brush, reason: 'typing must not switch tools');
    // Close the dialog.
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
  });

  testWidgets('I enters the eyedropper (it stays armed, R11-②); F fills, G '
      'guides, C cuts, W lassoes; Ctrl+T and Ctrl+Y transform in a mode', (
    tester,
  ) async {
    await pumpHome(tester);
    CanvasTool toolOf() =>
        tester.widget<ToolsPanel>(find.byType(ToolsPanel)).tool;

    await tester.sendKeyEvent(LogicalKeyboardKey.keyE);
    await tester.pumpAndSettle();
    expect(toolOf(), CanvasTool.eraser);

    await tester.sendKeyEvent(LogicalKeyboardKey.keyI);
    await tester.pumpAndSettle();
    expect(toolOf(), CanvasTool.eyedropper);

    // Repeated I keeps the eyedropper (no return-tool machinery — picks
    // never switch tools).
    await tester.sendKeyEvent(LogicalKeyboardKey.keyI);
    await tester.pumpAndSettle();
    expect(toolOf(), CanvasTool.eyedropper);

    // 🗣️유저 2026-09-13: 「채우기툴을 f로 변경하고, 가이드 툴을 g로 지정」 ·
    // 「잘라내기는 잘라내기 툴 자체에 c로 설정」.
    await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
    await tester.pumpAndSettle();
    expect(toolOf(), CanvasTool.fill);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyG);
    await tester.pumpAndSettle();
    expect(toolOf(), CanvasTool.guide);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
    await tester.pumpAndSettle();
    expect(toolOf(), CanvasTool.cut);

    // 「선택도구의 올가미 선택에 w로 두고싶어」 — the select tool, tracing the
    // lasso. Read it off the DRAG SURFACE, not off the tool library: the
    // library lives in a per-tool keep-alive stack, so several instances are
    // mounted at once and the first one found is whichever tool was visited
    // first — it would answer "rectangle" forever.
    CanvasShapeKind shapeOf() => tester
        .widget<CanvasSelectionLayer>(find.byType(CanvasSelectionLayer))
        .shapeKind;
    await tester.sendKeyEvent(LogicalKeyboardKey.keyW);
    await tester.pumpAndSettle();
    expect(toolOf(), CanvasTool.select);
    expect(shapeOf(), CanvasShapeKind.lasso);

    // 「일반변형에 컨트롤+t로 연결 … 자유변형을 컨트롤+y로」 — the transform
    // tool, in that mode.
    TransformMode modeOf() => tester
        .widget<EditorWorkspace>(find.byType(EditorWorkspace))
        .transformOptions!
        .value
        .mode;
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyY);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(toolOf(), CanvasTool.move);
    expect(modeOf(), TransformMode.perspective);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyT);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(toolOf(), CanvasTool.move);
    expect(modeOf(), TransformMode.normal);

    // 🪦The keys that had grown up beside the tools press nothing now.
    for (final retired in [
      LogicalKeyboardKey.keyV,
      LogicalKeyboardKey.keyM,
      LogicalKeyboardKey.keyL,
    ]) {
      await tester.sendKeyEvent(LogicalKeyboardKey.keyB);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(retired);
      await tester.pumpAndSettle();
      expect(toolOf(), CanvasTool.brush, reason: retired.keyLabel);
    }
  });

  testWidgets('🗣️I-15: holding Alt over the brush IS the eyedropper tool '
      '(「툴 바껴서 해당툴을 사용한다」); letting go returns it — the '
      'selection keeps its own Alt', (tester) async {
    await pumpHome(tester);
    CanvasTool toolOf() =>
        tester.widget<ToolsPanel>(find.byType(ToolsPanel)).tool;

    await tester.sendKeyEvent(LogicalKeyboardKey.keyB);
    await tester.pumpAndSettle();
    expect(toolOf(), CanvasTool.brush);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    await tester.pump();
    expect(toolOf(), CanvasTool.eyedropper);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    await tester.pump();
    expect(toolOf(), CanvasTool.brush);

    // W: the select tool, tracing its lasso.
    await tester.sendKeyEvent(LogicalKeyboardKey.keyW);
    await tester.pumpAndSettle();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    await tester.pump();
    expect(toolOf(), CanvasTool.select, reason: 'Alt subtracts there');
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    await tester.pumpAndSettle();
    expect(toolOf(), CanvasTool.select);
  });

  testWidgets('🗣️I-15 one law: a held RIGHT button on the canvas switches '
      'the tool through the same road as Alt — and springs back', (
    tester,
  ) async {
    await pumpHome(tester);
    CanvasTool toolOf() =>
        tester.widget<ToolsPanel>(find.byType(ToolsPanel)).tool;
    final addFrame = find.byKey(const ValueKey<String>('new-frame-button'));
    await tester.ensureVisible(addFrame);
    await tester.pumpAndSettle();
    await tester.tap(addFrame);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.keyB);
    await tester.pumpAndSettle();
    expect(toolOf(), CanvasTool.brush);

    final panel = tester.getRect(
      find.byKey(const ValueKey<String>('main-canvas-brush-host-container')),
    );
    final right = await tester.startGesture(
      Offset(panel.center.dx, panel.top + panel.height / 4),
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryMouseButton,
    );
    await tester.pump();
    expect(toolOf(), CanvasTool.eyedropper);
    await right.up();
    await tester.pump();
    expect(toolOf(), CanvasTool.brush);
  });

  testWidgets('R/Shift+R rotate the canvas view; H flips it (P8)', (
    tester,
  ) async {
    await pumpHome(tester);
    // ⚠️`publishedViewport`, not `.viewport` — the canvas area OWNS the view
    // through a notifier now, so the value prop it used to echo into is
    // permanently null and this oracle would assert about a default.
    CanvasViewport viewportOf() => tester
        .widget<MainCanvasBrushHost>(find.byType(MainCanvasBrushHost))
        .publishedViewport;

    await tester.sendKeyEvent(LogicalKeyboardKey.keyR);
    await tester.pumpAndSettle();
    expect(viewportOf().rotationDegrees, -15);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyR);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyR);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pumpAndSettle();
    expect(viewportOf().rotationDegrees, 15);

    await tester.sendKeyEvent(LogicalKeyboardKey.keyH);
    await tester.pumpAndSettle();
    expect(viewportOf().flipHorizontal, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyH);
    await tester.pumpAndSettle();
    expect(viewportOf().flipHorizontal, isFalse);
  });

  testWidgets('Ctrl+Z undoes; Space HOLDS the pan and plays nothing — '
      'during playback it only stops it (I-15)', (tester) async {
    await pumpHome(tester);

    // Create an undoable step (a drawing via the menu).
    // Making a drawing is the timeline's Add button now — the Edit menu
    // that used to carry it is gone.
    // The app reserves two 48px strips now, so the timeline's toolbar has
    // less room and scrolls sooner — bring the button into view before
    // aiming at it. (띠는 스크롤하지 않는다 will retire the scrolling itself;
    // until then this is what a hand does.)
    final addFrame = find.byKey(const ValueKey<String>('new-frame-button'));
    await tester.ensureVisible(addFrame);
    await tester.pumpAndSettle();
    await tester.tap(addFrame);
    await tester.pumpAndSettle();
    final undoButton = find.byKey(const ValueKey<String>('undo-button'));
    expect(tester.appIconButton(undoButton).onPressed, isNotNull);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(tester.appIconButton(undoButton).onPressed, isNull);

    // 🗣️I-15 (유저 2026-09-11): 「기존 재생단축키가 스페이스바인데 그냥
    // 해제」 — Space HOLDS the pan now, and starts nothing.
    expect(
      await tester.sendKeyDownEvent(LogicalKeyboardKey.space),
      isTrue,
      reason: 'the pan took the key — it does nothing else',
    );
    await tester.pump();
    expect(CanvasPanHold.held.value, isTrue);
    expect(
      find.byKey(const ValueKey<String>('canvas-playback-view')),
      findsNothing,
    );
    await tester.sendKeyUpEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(CanvasPanHold.held.value, isFalse);

    // Playback starts from its button (the playback view mounts). Plain
    // pumps: the playback ticker never lets pumpAndSettle settle.
    await tester.tap(
      find.byKey(const ValueKey<String>('playback-play-button')),
    );
    await tester.pump();
    await tester.pump();
    expect(
      find.byKey(const ValueKey<String>('canvas-playback-view')),
      findsOneWidget,
    );

    // 🪦This used to read 「Space again PAUSES without leaving playback
    // mode」, and it was green for the wrong reason. T28 deleted pause
    // (유저 2026-08-13: 「재생/정지 상태만」), and T28-c made the second
    // press a plain STOP — but the consuming half of that law did not work
    // for keys until 2026-09-08, so Space was stopping playback and then
    // ALSO running its binding, which started it again. The view stayed up
    // because the key did two things, which is exactly what 「입력 일 안함」
    // forbids. I-15 keeps that law for the space bar's new job: the press
    // that stops playback takes no pan hold on the way.
    await tester.sendKeyDownEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(
      find.byKey(const ValueKey<String>('canvas-playback-view')),
      findsNothing,
      reason: 'the actuation stopped playback and did nothing else, so the '
          'canvas is back to its drawing surface — and no ticker is left '
          'running for the teardown to trip over',
    );
    expect(CanvasPanHold.held.value, isFalse);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.space);
    await tester.pumpAndSettle();
  });

  testWidgets('↑/↓ walk the displayed layer rows when no canvas selection '
      'is live (UI-R20 #14)', (tester) async {
    await pumpHome(tester);
    // The rail rows in visual top-to-bottom order: the default stack shows
    // [transition, camera, instructions, se2, se1, drawing] with the
    // drawing layer active at the BOTTOM.
    //
    // Steps are counted from the ends rather than by literal index so that
    // adding a row is a one-line change here instead of a puzzle.
    //
    // The TRANSITION row joins the walk on purpose. It is READ-ONLY — its
    // verbs refuse and its spans are edited on the global axis — but the
    // arrow keys must not skip a row the eye can see, or the walk would
    // jump a gap the user cannot account for.
    List<TimelineLayerControlsRow> rails() => tester
        .widgetList<TimelineLayerControlsRow>(
          find.byType(TimelineLayerControlsRow),
        )
        .toList();
    LayerId activeId() => rails().singleWhere((r) => r.active).layer.id;

    final order = [for (final rail in rails()) rail.layer.id];
    expect(order.length, 6);
    expect(activeId(), order.last, reason: 'drawing layer starts active');

    // Clamped at the bottom row: ↓ has nowhere to go.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(activeId(), order.last);

    // ↑ climbs the visual stack one row at a time.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();
    expect(activeId(), order[order.length - 2]);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();
    expect(activeId(), order[order.length - 3]);

    // Clamped at the top row.
    for (var i = 0; i < order.length; i += 1) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    }
    await tester.pumpAndSettle();
    expect(activeId(), order.first);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(activeId(), order[1]);
  });

  testWidgets('the Keyboard Shortcuts dialog re-records a binding LIVE '
      'and Reset All restores the defaults', (tester) async {
    await pumpHome(tester);

    await tester.tap(
      find.byKey(const ValueKey<String>('top-strip-settings-button')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('menu-edit-keyboard-shortcuts')),
    );
    await tester.pumpAndSettle();

    // Record N as the new Next Frame key.
    await tester.tap(
      find.byKey(const ValueKey<String>('shortcut-record-frame-next')),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey<String>('shortcut-recording-hint')),
      findsOneWidget,
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.keyN);
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byKey(const ValueKey<String>('shortcut-action-list')),
        matching: find.text('N'),
      ),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(const ValueKey<String>('shortcut-close-button')),
    );
    await tester.pumpAndSettle();

    // The NEW key flips; the replaced default no longer does.
    await tester.sendKeyEvent(LogicalKeyboardKey.keyN);
    await tester.pumpAndSettle();
    expect(counterText(tester), '2');
    await tester.sendKeyEvent(LogicalKeyboardKey.period);
    await tester.pumpAndSettle();
    expect(counterText(tester), '2');

    // Reset All restores the stock bindings.
    await tester.tap(
      find.byKey(const ValueKey<String>('top-strip-settings-button')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('menu-edit-keyboard-shortcuts')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('shortcut-reset-all-button')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('shortcut-close-button')),
    );
    await tester.pumpAndSettle();

    await tester.sendKeyEvent(LogicalKeyboardKey.period);
    await tester.pumpAndSettle();
    expect(counterText(tester), '3');
  });
}
