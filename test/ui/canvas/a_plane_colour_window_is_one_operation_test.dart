import 'package:anicel/src/models/project_background.dart';
import 'package:anicel/src/ui/brush/brush_canvas_panel.dart';
import 'package:anicel/src/ui/brush/canvas_floor_insets.dart';
import 'package:anicel/src/ui/playback/camera_shot.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/cel_text_tool_harness.dart';

/// 🚨A PLANE'S COLOUR WINDOW IS ONE OPERATION (F-620-Q1, 유저 2026-11-19
/// 「레인에서 색 바꿀때 컬러휠 드래그할때 등」) — the real app, the real wheel.
///
/// The paper's, the backdrop's and the pasteboard's windows wrote every
/// colour the wheel passed as it came: a step of history each (🔬60 colours,
/// 60 steps) and every picture of the cut made again for each. Now each
/// colour is SHOWN, wherever a plane shows, and the window closing writes
/// the one it rests on — one undo — as a lane's colour window does.
void main() {
  /// The wheel, in its middle: a move there turns its colour every step.
  Future<TestGesture> grabTheWheel(WidgetTester tester) => tester.startGesture(
    tester.getCenter(find.byKey(const ValueKey<String>('color-picker-wheel'))),
  );

  /// A plane's swatch, pressed where it stands: on the canvas's view pill,
  /// which in the app's window has the room to carry it.
  Future<void> openTheSwatch(WidgetTester tester, String keyValue) async {
    await tester.tap(find.byKey(ValueKey<String>(keyValue)));
    await tester.pumpAndSettle();
  }

  Future<void> closeTheWindow(WidgetTester tester) async {
    await tester.tap(
      find.byKey(const ValueKey<String>('color-picker-popup-dismiss-field')),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('🚨the PAPER follows the wheel on the canvas while it turns, '
      'nothing is written, and the window closing writes the colour it '
      'rests on — one undo', (tester) async {
    await pumpTextToolApp(tester);
    final session = sessionOf(tester);
    ProjectBackground written() =>
        session.repository.requireProject().background;
    ProjectBackground shown() =>
        tester.widget<CameraShot>(find.byType(CameraShot).first).background;
    final before = written();
    final steps = session.historyManager.undoCount;
    expect(shown(), before, reason: 'the premise');

    await openTheSwatch(tester, 'canvas-paper-color-button');
    final hand = await grabTheWheel(tester);
    final passed = <ProjectBackground>{};
    for (var step = 0; step < 4; step += 1) {
      await hand.moveBy(const Offset(12, 8));
      await tester.pump();
      passed.add(shown());
    }
    await hand.up();
    await tester.pump();

    expect(passed.length, greaterThan(1), reason: 'the canvas follows it');
    expect(passed, isNot(contains(before)));
    expect(written(), before, reason: 'nothing is written while it is open');
    expect(session.historyManager.undoCount, steps);

    final rested = shown();
    await closeTheWindow(tester);

    expect(session.dragPreview.value, isNull);
    expect(written(), rested, reason: 'the close writes it');
    expect(shown(), rested);
    expect(
      session.historyManager.undoCount,
      steps + 1,
      reason: '⛔ONE step — every colour the wheel passed was one each',
    );

    session.historyManager.undo();
    await tester.pumpAndSettle();
    expect(written(), before);
  });

  testWidgets('the BACKDROP\'s 「없음」 is shown to every panel under the '
      'stage colours while the window is open, and written as it closes', (
    tester,
  ) async {
    await pumpTextToolApp(tester);
    final session = sessionOf(tester);
    bool writtenNone() => session.repository.requireProject().backdropNone;
    bool shownNone() => CanvasStageColors.maybeOf(
      tester.element(find.byType(BrushCanvasPanel).first),
    )!.backdropNone;
    final steps = session.historyManager.undoCount;
    expect(shownNone(), isFalse, reason: 'the premise');

    await openTheSwatch(tester, 'canvas-backdrop-color-button');
    await tester.tap(find.byKey(const ValueKey<String>('color-picker-none')));
    await tester.pumpAndSettle();

    expect(shownNone(), isTrue, reason: 'the panels show it');
    expect(writtenNone(), isFalse, reason: 'nothing is written yet');

    await closeTheWindow(tester);

    expect(writtenNone(), isTrue);
    expect(shownNone(), isTrue);
    expect(session.historyManager.undoCount, steps + 1);
  });
}
