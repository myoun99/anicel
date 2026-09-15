import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/app_input_settings.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/ui/canvas/canvas_viewport_gesture_layer.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/editor_workspace.dart';
import 'package:anicel/src/ui/home_page.dart';

import '../helpers/home_page_probes.dart';
import 'timeline/timeline_cell_probe.dart';

/// F-28 — on the X-sheet a flip and an arrow key land where the SHEET says,
/// driven through the real shell.
///
/// 유저 2026-08-31 실기: 「키보드는 위아래는 제대로 반전되있음. 다만 좌우가
/// 방향이 반대임. 그리고 터치는 위아래 터치 조작이 여전히 레이어이동, 심각한건
/// 플립ui는 프레임이동의 ui 보여주고있음 … 터치 좌우 조작도 똑같음」.
///
/// Both halves passed every unit test while broken. The gesture layer and
/// the shell each asked the axis question, which only shows when the two
/// run together; and which way the X-sheet lays its columns out is only
/// visible on screen.
void main() {
  setUp(() {
    AppInput.settings.value = AppInput.settings.value.copyWith(
      touchDragThreeFingers: CanvasTouchDragAction.flip,
    );
  });
  tearDown(() {
    AppInput.settings.value = AppInputSettings.testCorpusBaseline;
  });

  /// The X-sheet, three drawing rows, standing on the MIDDLE one — so both
  /// of its neighbours are drawing columns — at frame 1, with drawings at
  /// frames 1 and 3 on that row.
  Future<(EditorSessionManager, LayerId)> xsheetOnTheMiddleRow(
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1600, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const MaterialApp(home: HomePage()));
    await tester.pumpAndSettle();
    final session = tester
        .widget<EditorWorkspace>(find.byType(EditorWorkspace))
        .session;

    await addLayer(tester);
    await addLayer(tester);
    final drawingRows = [
      for (final layer in session.layers)
        if (layer.kind == LayerKind.animation) layer.id,
    ];
    expect(drawingRows, hasLength(3), reason: 'fixture premise');
    final middle = drawingRows[1];
    session.selectLayer(middle);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey<String>('new-frame-button')));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.period);
    await tester.sendKeyEvent(LogicalKeyboardKey.period);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('new-frame-button')));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.comma);
    await tester.sendKeyEvent(LogicalKeyboardKey.comma);
    await tester.pumpAndSettle();

    await tapToolbarButton(
      tester,
      const ValueKey<String>('timeline-orientation-toggle-button'),
    );
    expect(session.activeLayerId, middle, reason: 'fixture premise');
    expect(session.currentFrameIndex, 0, reason: 'fixture premise');
    return (session, middle);
  }

  testWidgets('a downward flip on the X-sheet walks FRAMES and keeps the '
      'layer', (tester) async {
    final (session, middle) = await xsheetOnTheMiddleRow(tester);

    // The fingers land where the CANVAS answers a touch. Its centre sits
    // under the turned X-sheet on this layout — measured: not hit-testable
    // there, so three fingers on it were the sheet's gesture and the flip
    // never locked, on the old code and the new alike.
    final canvas = find.byType(CanvasViewportGestureLayer).first;
    final at = [
      Alignment.center,
      const Alignment(-0.6, -0.6),
      const Alignment(0.6, -0.6),
      const Alignment(-0.6, 0.6),
      const Alignment(0.6, 0.6),
    ].firstWhere(
      (alignment) => canvas.hitTestable(at: alignment).evaluate().isNotEmpty,
    );
    final origin = at.withinRect(tester.getRect(canvas));
    final fingers = <TestGesture>[
      for (var finger = 0; finger < 3; finger += 1)
        await tester.startGesture(
          origin + Offset(finger * 20.0, 0),
          kind: PointerDeviceKind.touch,
        ),
    ];
    await tester.pump();
    // One step down: past the lock, short of a second step.
    for (final finger in fingers) {
      await finger.moveBy(
        const Offset(0, CanvasViewportGestureLayer.flipStepExtent + 12),
      );
      await tester.pump();
    }
    for (final finger in fingers) {
      await finger.up();
    }
    await tester.pumpAndSettle();

    expect(
      session.activeLayerId,
      middle,
      reason: '유저: 「터치는 위아래 터치 조작이 여전히 레이어이동」',
    );
    // ⚠️ONE COLUMN, not the next drawing. The flip's rule (R10 #13, the
    // user's, `flip_column_step.dart`): a block where there are blocks, a
    // frame where there are none — and frame 1, between the two drawings,
    // is uncovered, so it is the column after frame 0's block. ↓ lands
    // there too; the first draft of this line said 2 and the flip was
    // right.
    expect(
      session.currentFrameIndex,
      1,
      reason: 'down the X-sheet is down the frames: one column',
    );
  });

  testWidgets('→ on the X-sheet lands on the column to the RIGHT', (
    tester,
  ) async {
    final (session, middle) = await xsheetOnTheMiddleRow(tester);
    double columnLeft(LayerId id) =>
        timelineCellGlobalRect(tester, id.value, 0, prefix: 'xsheet').left;

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();

    final landed = session.activeLayerId!;
    expect(landed, isNot(middle), reason: 'a drawing column sits either side');
    expect(
      columnLeft(landed),
      greaterThan(columnLeft(middle)),
      reason: '유저: 「좌우가 방향이 반대임」',
    );
    expect(session.currentFrameIndex, 0, reason: 'across the frames, not along');
  });
}
