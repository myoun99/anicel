import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/native/app_kernels_ahead.dart';
import 'package:anicel/src/services/input/pencil_interaction_service.dart';
import 'package:anicel/src/ui/brush/brush_tool_state.dart';
import 'package:anicel/src/ui/canvas/canvas_view_hold.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/editor_workspace.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/media/viewer_page_loading.dart';
import 'package:anicel/src/ui/menu/editor_top_strip.dart';
import 'package:anicel/src/ui/panels/editor_panel_tabs.dart';

/// 🗣️gpu-canonical-store-Q15 (유저 2026-11-11): 「준비가 끝난 뒤에 그림을
/// 띄운다 — 그때까지 고리」 · 「애초에 타임라인같은거도 포함해서 고리띄우고
/// 모든 조작 막음」 — while the app gets its engine ready
/// ([appEngineGetsReady]) every panel's place stands the ring and the
/// editor takes no input: a press that needed a kernel still to be compiled
/// stopped the whole app for as long as its compile took.
void main() {
  final ring = find.byType(ViewerPageLoading);
  final docks = find.byType(EditorPanelTabs);
  final add = find.byKey(const ValueKey<String>('new-frame-button'));

  Future<void> stand(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1500, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    addTearDown(debugLetTheAppGo);
    await tester.pumpWidget(
      MaterialApp(home: HomePage(initialProject: createDefaultProject())),
    );
  }

  /// The frames a held app is given: it never settles, its rings turning.
  Future<void> frames(WidgetTester tester) async {
    for (var frame = 0; frame < 8; frame += 1) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  EditorSessionManager sessionOf(WidgetTester tester) => tester
      .widget<EditorTopStrip>(find.byType(EditorTopStrip).first)
      .projects
      .sessions
      .first;

  CanvasTool toolOf(WidgetTester tester) => tester
      .widget<EditorWorkspace>(find.byType(EditorWorkspace))
      .brushTool!
      .value
      .tool;

  Future<void> pressUndo(WidgetTester tester) async {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
  }

  testWidgets('held from before its first frame, every dock stands one ring '
      '— the floor\'s among them — and none once the app is let go', (
    tester,
  ) async {
    // As a launch says it, before the app is run (`main`).
    holdTheAppForItsEngine();
    await stand(tester);
    await frames(tester);

    expect(docks, findsWidgets, reason: '⛔premise: the app has docks');
    for (final dock in docks.evaluate()) {
      expect(
        find.descendant(of: find.byWidget(dock.widget), matching: ring),
        findsOneWidget,
        reason: '${(dock.widget as EditorPanelTabs).groupId}',
      );
    }
    expect(ring, findsNWidgets(docks.evaluate().length));

    debugLetTheAppGo();
    await tester.pumpAndSettle();

    expect(ring, findsNothing);
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

  testWidgets('held, the editor takes no press, no bound key, no held key '
      'and no pencil tap — and each once the app is let go', (tester) async {
    await stand(tester);
    await tester.pumpAndSettle();
    final session = sessionOf(tester);
    await tester.ensureVisible(add);
    await tester.pumpAndSettle();
    // An edit for the undo to take back.
    await tester.tap(add);
    await tester.pumpAndSettle();
    final edits = session.historyManager.undoCount;
    expect(edits, greaterThan(0), reason: '⛔premise: an edit to take back');
    expect(toolOf(tester), isNot(CanvasTool.eraser), reason: '⛔premise');
    final tap = PencilInteractionService.instance.onPencilTap!;

    holdTheAppForItsEngine();
    await frames(tester);

    await tester.tap(add, warnIfMissed: false);
    await frames(tester);
    expect(session.historyManager.undoCount, edits, reason: 'no press');
    await pressUndo(tester);
    expect(session.historyManager.undoCount, edits, reason: 'no bound key');
    await tester.sendKeyDownEvent(LogicalKeyboardKey.space);
    expect(CanvasViewHold.held.value, isNull, reason: 'no held key');
    await tester.sendKeyUpEvent(LogicalKeyboardKey.space);
    tap(PencilTapAction.switchEraser);
    await frames(tester);
    expect(toolOf(tester), isNot(CanvasTool.eraser), reason: 'no pencil tap');

    debugLetTheAppGo();
    await tester.pumpAndSettle();

    await tester.tap(add);
    await tester.pumpAndSettle();
    expect(session.historyManager.undoCount, edits + 1);
    await pressUndo(tester);
    expect(session.historyManager.undoCount, edits);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.space);
    expect(CanvasViewHold.held.value, ViewHold.pan);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.space);
    tap(PencilTapAction.switchEraser);
    await tester.pumpAndSettle();
    expect(toolOf(tester), CanvasTool.eraser);
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));
}
