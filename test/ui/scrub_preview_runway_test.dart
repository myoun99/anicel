import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/ui/brush/brush_tool_state.dart';
import 'package:anicel/src/ui/canvas/canvas_layer_stack_view.dart';
import 'package:anicel/src/ui/editor_canvas_area.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';

/// ⑯ — a ruler drag shows what letting go will show.
///
/// 🚨🚨★★★THE WHOLE SUBJECT OF THIS FILE CHANGED, and the old version is
/// worth a paragraph because the shape recurs.
///
/// A scrub used to swap the canvas for `CanvasScrubPreview` — the PLAYBACK
/// composite cache, standing in for the editing stack while the cursor
/// moved. Everything this file used to test was a property of that
/// stand-in: it clamped an over-end cursor to the cut's last frame, so a
/// drag past the end kept showing a picture and the release took it away,
/// and the fix was to teach the stand-in the runway.
///
/// 유저 2026-08-15 asked for the general form instead: 「단순히 full만하는게
/// 아니라 페이스트보드도 보이게. **즉 그냥 멈췄을때랑 보이는게 똑같게**」.
/// One substitution had reached them as FOUR faults — filtered artwork,
/// quality following the PLAYBACK setting, no pasteboard, and a layer
/// blinking at the handback — and teaching the stand-in three more things
/// would have left the fourth, because the fourth WAS the substitution.
///
/// ★So there is no stand-in now, and this file pins the property that
/// replaces every one of those: the drag and the release are the same path,
/// therefore the same picture. The over-end runway needs no clamp of its
/// own because the editing canvas already reads the cursor literally
/// (`past_cut_end_is_ordinary_test` holds that end of it).
void main() {
  Future<void> pumpCanvas(WidgetTester tester, EditorSessionManager session)
  async {
    final brushTool = ValueNotifier<BrushToolState>(BrushToolState.defaults);
    final cameraView = ValueNotifier<bool>(false);
    final cameraDim = ValueNotifier<double>(0.5);
    addTearDown(brushTool.dispose);
    addTearDown(cameraView.dispose);
    addTearDown(cameraDim.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: EditorCanvasArea(
            session: session,
            brushToolState: brushTool,
            cameraViewEnabled: cameraView,
            cameraDimOpacity: cameraDim,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// ⛔The stand-in's key. Asserting it is ABSENT is the point: a future
  /// change that brings a second renderer back for scrubs would pass every
  /// index-level test in the suite and fail here.
  final previewFinder = find.byKey(
    const ValueKey<String>('canvas-scrub-preview'),
  );

  testWidgets('a drag past the cut end shows the editing canvas, not a '
      'stand-in that has to be taught the runway', (tester) async {
    final session = EditorSessionManager(
      initialProject: createDefaultProject(),
    );
    addTearDown(session.dispose);
    final cut = session.activeCutOrNull!;

    await pumpCanvas(tester, session);

    session.selectFrameIndex(3);
    await tester.pump();
    session.scrubFrameIndex(0);
    await tester.pump();
    expect(previewFinder, findsNothing, reason: 'the drag is in flight');
    expect(find.byType(CanvasLayerStackView), findsWidgets);

    // Past the end, mid-drag. This is where the stand-in used to clamp.
    session.scrubFrameIndex(cut.duration + 4);
    await tester.pump();
    expect(previewFinder, findsNothing);
    expect(
      find.byType(CanvasLayerStackView),
      findsWidgets,
      reason: 'the runway is ordinary canvas — nothing swaps out there',
    );

    // And the release changes nothing, which is the half the user felt as
    // "the picture jumped when I let go".
    session.commitFrameScrub();
    await tester.pumpAndSettle();
    expect(previewFinder, findsNothing);
    expect(find.byType(CanvasLayerStackView), findsWidgets);
  });

  testWidgets('the cursor is read literally on the runway, during the drag '
      'and after it', (tester) async {
    final session = EditorSessionManager(
      initialProject: createDefaultProject(),
    );
    addTearDown(session.dispose);
    final cut = session.activeCutOrNull!;
    await pumpCanvas(tester, session);

    final past = cut.duration + 7;
    session.selectFrameIndex(2);
    await tester.pump();
    session.scrubFrameIndex(past);
    await tester.pump();

    expect(
      session.editingFrameCursor.value,
      past,
      reason: 'no clamp to the cut length — 「컷 길이는 소재와 관계없다」',
    );

    session.commitFrameScrub();
    await tester.pumpAndSettle();
    expect(
      session.currentFrameIndex,
      past,
      reason: 'and the release lands on the frame the drag was showing',
    );
  });
}
