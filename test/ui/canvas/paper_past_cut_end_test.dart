import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/ui/canvas/canvas_layer_stack_view.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/editor_workspace.dart';
import 'package:anicel/src/ui/home_page.dart';

/// 🚨T12 (유저 2026-08-13): 「**캔버스패널의 캔버스가 용지나 그림이 사라짐**」
/// past the cut's end line — 「컷길이 넘어서도 공간은 항상 존재하고 항상
/// 보인다고. 스토리보드에서만 그걸 컷길이로 클램핑해서 보여줄 뿐인거고」.
///
/// The SESSION already answers correctly there (measured:
/// `past_cut_end_is_ordinary_test.dart` — not a gap, stack not empty, drawing
/// works, 尺 unmoved). So if paper still goes missing it is the DRAWING path,
/// and this is where that gets measured: what the stack view is actually
/// handed.
void main() {
  Future<EditorSessionManager> pump(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(home: HomePage(initialProject: createDefaultProject())),
    );
    await tester.pumpAndSettle();
    return tester
        .widget<EditorWorkspace>(find.byType(EditorWorkspace))
        .session;
  }

  CanvasLayerStackView stackView(WidgetTester tester) =>
      tester.widget<CanvasLayerStackView>(
        find.byType(CanvasLayerStackView).first,
      );

  testWidgets('the canvas keeps its PAPER past the cut end line', (
    tester,
  ) async {
    final session = await pump(tester);
    session.selectFrameIndex(0);
    session.createDrawingAtCurrentFrame();
    await tester.pumpAndSettle();

    expect(
      stackView(tester).paintPaper,
      isTrue,
      reason: 'inside the cut, for the comparison to mean anything',
    );

    session.selectFrameIndex(session.requireActiveCut.duration + 5);
    await tester.pumpAndSettle();

    expect(
      session.editingPlayheadInGap,
      isFalse,
      reason: 'already measured; restated here so a failure below cannot be '
          'blamed on the session',
    );
    expect(
      stackView(tester).paintPaper,
      isTrue,
      reason: 'past the end line is ordinary space — the paper is the thing '
          'the user says disappears',
    );
    expect(stackView(tester).nodes, isNotEmpty);
  });
}
