import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/ui/canvas/canvas_pan_hold.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/menu/editor_top_strip.dart';

import '../helpers/panel_finders.dart';

/// 🗣️F-232 (유저 2026-09-30): 「클로드 통해서 오는 윈도우 알림이 발생하면
/// 언두가 안먹기시작하는거같음. 아마 윈도우 알림등 다른 앱으로 포커스가
/// 바뀌면? … 그상태에서 환경설정창 열어도 언두 되기시작」.
///
/// What was measured: a plain trip away and back keeps the shortcuts (the
/// framework restores the focus it suspended), and so do a Ctrl or a Space
/// let go elsewhere. What did NOT: a pen down on the canvas when the window
/// lost focus, whose lift went to the other window — the stroke stayed in
/// flight for good, and a stroke in flight refuses every undo. So the
/// window lets go of what is pressed in it the moment it loses the OS's
/// focus.
void main() {
  late EditorSessionManager session;

  Future<void> boot(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1500, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(home: HomePage(initialProject: createDefaultProject())),
    );
    await tester.pumpAndSettle();
    session = tester
        .widget<EditorTopStrip>(find.byType(EditorTopStrip).first)
        .projects
        .sessions
        .first;
    // An edit for the undo to take back.
    final add = find.byKey(const ValueKey<String>('new-frame-button'));
    await tester.ensureVisible(add);
    await tester.pumpAndSettle();
    await tester.tap(add);
    await tester.pumpAndSettle();
  }

  Future<void> awayAndBack(WidgetTester tester) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
  }

  Future<void> pressUndo(WidgetTester tester) async {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
  }

  testWidgets('🚨a pen down when the window loses focus — its lift going to '
      'the other window — does not leave undo dead', (tester) async {
    await boot(tester);
    final edits = session.historyManager.undoCount;
    final pen = await tester.startGesture(
      tester.getCenter(mainCanvasView()),
      kind: PointerDeviceKind.stylus,
    );
    await pen.moveBy(const Offset(20, 10));
    await tester.pump();

    await awayAndBack(tester);
    await pressUndo(tester);

    expect(
      session.historyManager.undoCount,
      edits - 1,
      reason: '🪦the stroke waited for a lift that went elsewhere, and a '
          'stroke in flight refuses every undo',
    );
    // The lift the other window got, arriving after all: nothing is left
    // for it to end.
    await pen.up();
    await tester.pumpAndSettle();
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

  testWidgets('a Space held when the window loses focus lets go of the pan', (
    tester,
  ) async {
    await boot(tester);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.space);
    expect(CanvasPanHold.held.value, isTrue, reason: 'fixture');

    await awayAndBack(tester);

    expect(CanvasPanHold.held.value, isFalse);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.space);
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));
}
