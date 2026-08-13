import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/ui/canvas/canvas_layer_stack_view.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/editor_workspace.dart';
import 'package:anicel/src/ui/home_page.dart';

/// 🚨T12, one floor down from `past_cut_end_is_ordinary_test`.
///
/// That one measured the SESSION and found it right: past the end line
/// `editingPlayheadInGap` is false, the stack is not empty and the duration
/// does not move. The user still reports 「캔버스패널의 캔버스가 용지나
/// 그림이 사라짐」, so the disagreement is between what the session answers
/// and what reaches the screen — and a session test cannot say which side
/// moved.
///
/// This asks the WIDGET: does the view that draws the paper actually receive
/// `paintPaper: true` and a non-empty tree while standing past the end line?
/// If it does, the fault is below it, in the painting. If it does not, the
/// wiring between the session and the view drops the answer on the way.
///
/// ⛔The vocabulary is part of the law (유저): the frames past the end line
/// are not a 「런웨이」 or a 「노리시로」. The end line is a line and both
/// sides of it are the same space.
EditorSessionManager _sessionOf(WidgetTester tester) =>
    tester.widget<EditorWorkspace>(find.byType(EditorWorkspace)).session;

/// The stack view that paints the editing canvas — the merged underlay.
CanvasLayerStackView _stackView(WidgetTester tester) =>
    tester.widgetList<CanvasLayerStackView>(
      find.byType(CanvasLayerStackView),
    ).first;

Future<void> _pump(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(1280, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(home: HomePage(initialProject: createDefaultProject())),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the canvas view is told to paint the paper past the end line', (
    tester,
  ) async {
    await _pump(tester);
    final session = _sessionOf(tester);
    final duration = session.requireActiveCut.duration;

    session.selectFrameIndex(0);
    session.createDrawingAtCurrentFrame();
    await tester.pumpAndSettle();

    // Inside the cut first, so the assertions below have a known-good
    // reading to differ from rather than an absolute nobody has checked.
    expect(
      _stackView(tester).paintPaper,
      isTrue,
      reason: 'baseline: inside the cut the paper is painted',
    );

    session.selectFrameIndex(duration + 5);
    await tester.pumpAndSettle();

    expect(
      session.currentFrameIndex,
      duration + 5,
      reason: 'the playhead really moved past the end line',
    );
    expect(
      _stackView(tester).paintPaper,
      isTrue,
      reason: 'past the end line is ordinary space, so the paper is painted '
          'there exactly like it is inside the cut',
    );
    expect(
      _stackView(tester).nodes,
      isNotEmpty,
      reason: 'and the tree it composites is not the void',
    );
  });

  testWidgets('the LAST cut is not a special case', (tester) async {
    await _pump(tester);
    final session = _sessionOf(tester);

    // The default project's cut is the last one, so this is the arrangement
    // where the global axis has nothing after the end line at all — the case
    // an axis-level clamp treats differently from a cut with a neighbour.
    final duration = session.requireActiveCut.duration;
    session.selectFrameIndex(duration * 2);
    await tester.pumpAndSettle();

    expect(_stackView(tester).paintPaper, isTrue);
    expect(_stackView(tester).nodes, isNotEmpty);
  });
}
