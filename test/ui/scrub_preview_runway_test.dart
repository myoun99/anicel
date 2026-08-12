import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/ui/brush/brush_tool_state.dart';
import 'package:anicel/src/ui/editor_canvas_area.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/playback/playback_frame_painter.dart';

/// ⑯ — the over-end runway is not a clipped view of the cut.
///
/// The scrub preview clamped an over-end cursor to the cut's last frame, so
/// a ruler drag past the end kept showing a picture and the release — where
/// the editing canvas reads the cursor literally — took it away. The user
/// asked for no difference at all between past the end and inside it: an
/// undrawn frame is blank paper either side of the boundary.
///
/// 🚨Removing the clamp alone would not have done it. The warm walks the
/// CUT, so a runway lookup misses forever, and the held-frame policy reads
/// a miss as "still warming" and goes on painting the last image. That is
/// why this test asserts on the PAINTER's image rather than on an index:
/// the index was never the thing the user could see.
void main() {
  Future<void> drainWarming(WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
  }

  testWidgets('a drag past the cut end paints paper, not the last frame it '
      'could still find in the cache', (tester) async {
    final session = EditorSessionManager(
      initialProject: createDefaultProject(),
    );
    addTearDown(session.dispose);
    final cut = session.activeCutOrNull!;

    // A real composite for an in-cut frame, so "the preview is painting an
    // image" is a fact this test can lose rather than one it never had.
    // Rasterising under the fake clock has to run in runAsync or it hangs.
    await tester.runAsync(
      () => session.cutFrameCompositeCache.prepareComposite(
        cut: cut,
        frameIndex: 0,
        quality: session.playbackQuality,
      ),
    );

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

    // Engage the scrub INSIDE the cut: the cursor has to actually move for
    // the preview to come up (a same-frame tap must not flash it).
    session.selectFrameIndex(3);
    await tester.pump();
    session.scrubFrameIndex(0);
    await tester.pump();

    final previewFinder = find.byKey(
      const ValueKey<String>('canvas-scrub-preview'),
    );
    expect(previewFinder, findsOneWidget, reason: 'the drag is in flight');

    PlaybackFramePainter painter() =>
        tester.widget<CustomPaint>(
              find.descendant(
                of: previewFinder,
                matching: find.byType(CustomPaint),
              ),
            ).painter
            as PlaybackFramePainter;

    expect(
      painter().image,
      isNotNull,
      reason: 'inside the cut the preview paints the cached composite',
    );

    // …and out onto the runway, where the cut composites nothing.
    session.scrubFrameIndex(cut.duration + 3);
    await tester.pump();

    expect(
      painter().image,
      isNull,
      reason: 'past the end there is no frame — the paper is the answer, '
          'and the release will show the same paper',
    );

    // Coming back inside brings the picture back: the runway rule is about
    // where the cursor IS, not a latch the drag falls into.
    session.scrubFrameIndex(0);
    await tester.pump();
    expect(painter().image, isNotNull);

    await drainWarming(tester);
  });

  testWidgets('a drawing OUT on the runway paints while dragging — the paper '
      'is for frames that hold nothing, not for frames past a number',
      (tester) async {
    final session = EditorSessionManager(
      initialProject: createDefaultProject(),
    );
    addTearDown(session.dispose);
    final duration = session.activeCutOrNull!.duration;
    final runwayFrame = duration + 3;

    // ＋ works out here — the runway takes cels like any other frame — so a
    // preview that painted paper by index alone would hide real artwork.
    session.selectFrameIndex(runwayFrame);
    session.createDrawingAtCurrentFrame();
    await tester.runAsync(
      () => session.cutFrameCompositeCache.prepareComposite(
        cut: session.activeCutOrNull!,
        frameIndex: runwayFrame,
        quality: session.playbackQuality,
      ),
    );

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

    session.selectFrameIndex(0);
    await tester.pump();
    session.scrubFrameIndex(runwayFrame);
    await tester.pump();

    final previewFinder = find.byKey(
      const ValueKey<String>('canvas-scrub-preview'),
    );
    expect(previewFinder, findsOneWidget);
    final painter =
        tester.widget<CustomPaint>(
              find.descendant(
                of: previewFinder,
                matching: find.byType(CustomPaint),
              ),
            ).painter
            as PlaybackFramePainter;
    expect(
      painter.image,
      isNotNull,
      reason: 'the drag shows what the release will show — a drawing',
    );

    await drainWarming(tester);
  });
}
