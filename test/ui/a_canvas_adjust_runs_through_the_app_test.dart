import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/menu/editor_top_strip.dart';

/// I-79 through the app: an adjust opened on the canvas stands its box and
/// pill on the canvas showing the cut, Escape closes it as its ✕ does, and
/// Enter lands it as its ✓ does — 확정 is one verb (`ConfirmVerb`), and the
/// landing waits in the same window a size typed into the window waits in.
void main() {
  Future<EditorSessionManager> pumpApp(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1600, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(home: HomePage(initialProject: createDefaultProject())),
    );
    await tester.pumpAndSettle();
    return tester
        .widget<EditorTopStrip>(find.byType(EditorTopStrip))
        .projects
        .active;
  }

  final pill = find.byKey(const ValueKey<String>('canvas-adjust-pill'));

  /// Through the wait window, which lingers and spins.
  Future<void> pumpPastTheWait(WidgetTester tester) async {
    for (var step = 0; step < 30; step += 1) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  testWidgets('the adjust stands on the canvas, and Escape closes it',
      (tester) async {
    final session = await pumpApp(tester);
    final cut = session.requireActiveCut;
    expect(pill, findsNothing, reason: '⛔전제: nothing open');

    session.canvasAdjust.begin(cut.id, cut.canvasSize);
    await tester.pump();
    expect(pill, findsOneWidget, reason: 'on the canvas showing the cut');

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(session.canvasAdjust.isOpen, isFalse);
    expect(pill, findsNothing);
  });

  testWidgets('🚨Enter lands the edges — the canvas takes their size, and '
      'the adjust closes', (tester) async {
    final session = await pumpApp(tester);
    final cut = session.requireActiveCut;
    final before = cut.canvasSize;
    session.canvasAdjust
      ..begin(cut.id, before)
      ..move(
        Rect.fromLTRB(
          -10,
          0,
          before.width.toDouble(),
          before.height + 20.0,
        ),
      );
    await tester.pump();
    expect(pill, findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await pumpPastTheWait(tester);

    expect(
      session.requireActiveCut.canvasSize,
      CanvasSize(width: before.width + 10, height: before.height + 20),
    );
    expect(session.canvasAdjust.isOpen, isFalse);
    expect(pill, findsNothing);
  });
}
