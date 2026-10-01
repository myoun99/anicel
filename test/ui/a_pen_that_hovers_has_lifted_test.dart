import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/menu/editor_top_strip.dart';

import '../helpers/panel_finders.dart';

/// 🗣️F-232 (유저 2026-10-02): 「언두 안먹는다는거, 그 뒤로 2번 발생했어.
/// 둘 다 해결은 동일하게 프로젝트설정 버튼 누르는 식으로 해결」.
///
/// The rules are pinned where they live (`contact_census_test`); this asks
/// the one thing they are for, in the app: a press whose lift was lost no
/// longer holds every undo door shut once the pen comes back.
void main() {
  late EditorSessionManager session;

  Future<void> pressUndo(WidgetTester tester) async {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
  }

  testWidgets('🚨the pen HOVERING back — a new pointer — lets go of the '
      'press whose lift was lost, and undo works', (tester) async {
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
    final edits = session.historyManager.undoCount;
    final canvas = tester.getCenter(mainCanvasView());

    // A pen down on the canvas whose lift never comes.
    final pen = await tester.startGesture(
      canvas,
      kind: PointerDeviceKind.stylus,
    );
    await pen.moveBy(const Offset(20, 10));
    await tester.pump();
    await pressUndo(tester);
    expect(
      session.historyManager.undoCount,
      edits,
      reason: 'the premise: a press still down refuses every undo',
    );

    // The pen back over the canvas, in the air — a new pointer of a new
    // device, the way the platform hands a pen back after it left the
    // tablet's range.
    final back = TestPointer(41, PointerDeviceKind.stylus, 7);
    await tester.sendEventToBinding(
      back.addPointer(location: canvas + const Offset(60, 40)),
    );
    await tester.sendEventToBinding(back.hover(canvas + const Offset(70, 45)));
    await tester.pump();
    await pressUndo(tester);

    expect(session.historyManager.undoCount, edits - 1);
    // The lift, arriving after all: nothing is left for it to end.
    await pen.up();
    await tester.pumpAndSettle();
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));
}
