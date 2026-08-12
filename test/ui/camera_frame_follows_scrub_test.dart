import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/ui/brush/brush_tool_state.dart';
import 'package:anicel/src/ui/camera/camera_frame_overlay.dart';
import 'package:anicel/src/ui/editor_canvas_area.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';

/// ㊲ — the camera frame follows the SCRUB, not the active cut.
///
/// A global scrub crosses cut boundaries QUIETLY on purpose: switching the
/// active cut per move rebuilt every panel, so the crossing parks instead
/// (`scrubGlobalFrame`). The camera overlay read `cameraPoseAtCurrentFrame`
/// through that — the cut being LEFT — so a T.U that ended zoomed kept
/// framing the next cut's pictures at the size the last cut finished on,
/// and dragging the other way showed no camera work at all.
///
/// Two kinds of test, because this is a law AND a wiring: the session tests
/// pin which cut answers, and the widget test pins that the overlay watches
/// the ONE listenable that moves during a crossing. Delete the parking
/// subscription and only the widget test dies — which is exactly why it is
/// here.
void main() {
  /// cut ONE zoomed 2× by a T.U · a 4-frame gap · cut TWO animating 1× → 3×,
  /// so "which cut" and "where inside it" both read off a single number.
  (EditorSessionManager, int, int) scrubSession() {
    final s = EditorSessionManager(initialProject: createDefaultProject());
    s.createCut();
    final track = s.repository.requireProject().tracks.first;
    final second = track.cuts[1].id;
    s.repository.updateCutLeadingGap(cutId: second, leadingGapFrames: 4);

    s.selectCut(second);
    s.selectFrameIndex(0);
    s.setCameraKeyframeAtCurrentFrame(
      s.cameraPoseAtCurrentFrame.copyWith(zoom: 1),
    );
    s.selectFrameIndex(5);
    s.setCameraKeyframeAtCurrentFrame(
      s.cameraPoseAtCurrentFrame.copyWith(zoom: 3),
    );

    s.selectCut(track.cuts[0].id);
    s.selectFrameIndex(0);
    s.setCameraKeyframeAtCurrentFrame(
      s.cameraPoseAtCurrentFrame.copyWith(zoom: 2),
    );

    final layout = s.projectTimelineLayout();
    final secondStart = layout
        .firstWhere((entry) => entry.cutId == second)
        .startFrame;
    final gapFrame = track.cuts[0].duration + 1;
    return (s, secondStart, gapFrame);
  }

  /// A drag takes TWO out-of-territory moves to engage the preview (the
  /// no-flash rule: a plain tap over another cut must not flash it).
  void dragTo(EditorSessionManager s, int from, int to) {
    s.scrubGlobalFrame(from);
    s.scrubGlobalFrame(to);
  }

  Future<void> drainWarming(WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
  }

  Future<void> pumpArea(WidgetTester tester, EditorSessionManager s) async {
    final brushTool = ValueNotifier<BrushToolState>(BrushToolState.defaults);
    final cameraView = ValueNotifier<bool>(true);
    final cameraDim = ValueNotifier<double>(0.5);
    addTearDown(brushTool.dispose);
    addTearDown(cameraView.dispose);
    addTearDown(cameraDim.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: EditorCanvasArea(
            session: s,
            brushToolState: brushTool,
            cameraViewEnabled: cameraView,
            cameraDimOpacity: cameraDim,
          ),
        ),
      ),
    );
  }

  test('scrubbing over the NEXT cut frames THAT cut, not the one being left', () {
    final (s, secondStart, _) = scrubSession();
    addTearDown(s.dispose);

    expect(s.cameraPoseAtCurrentFrame.zoom, 2, reason: 'cut one is the T.U');

    dragTo(s, secondStart, secondStart + 5);

    expect(s.frameScrubActive.value, isTrue);
    expect(
      s.cameraPoseAtCurrentFrame.zoom,
      2,
      reason: 'the ACTIVE cut is left untouched by the crossing, by design',
    );
    expect(
      s.displayedCameraPose!.zoom,
      closeTo(3, 1e-6),
      reason: 'the DISPLAY frames the cut under the cursor',
    );
  });

  test('scrubbing over a GAP frames nothing — there is no cut to frame', () {
    final (s, _, gapFrame) = scrubSession();
    addTearDown(s.dispose);

    dragTo(s, gapFrame, gapFrame + 1);

    expect(s.frameScrubActive.value, isTrue);
    expect(s.displayedCameraPose, isNull);
  });

  test('the release lands what the drag was showing — commit and preview '
      'answer with the same cut', () {
    final (s, secondStart, _) = scrubSession();
    addTearDown(s.dispose);

    dragTo(s, secondStart, secondStart + 5);
    final shownDuringDrag = s.displayedCameraPose!.zoom;
    s.commitFrameScrub();

    expect(s.frameScrubActive.value, isFalse);
    expect(s.currentFrameIndex, 5);
    expect(s.cameraPoseAtCurrentFrame.zoom, closeTo(shownDuringDrag, 1e-6));
    expect(s.displayedCameraPose!.zoom, closeTo(shownDuringDrag, 1e-6));
  });

  test('a committed parking frames nothing even where a cut covers it — only '
      'a LIVE scrub asks the parked question', () {
    final (s, _, gapFrame) = scrubSession();
    addTearDown(s.dispose);

    // The V-row eye's hidden-picture state parks ON a covered frame; it means
    // "no cut here", so there is nothing to frame.
    s.parkGlobalFrame(gapFrame);

    expect(s.frameScrubActive.value, isFalse);
    expect(s.displayedCameraPose, isNull);
  });

  testWidgets('the overlay FOLLOWS the crossing per move: the parking is the '
      'only listenable that fires, so it is the one to watch', (tester) async {
    final (s, secondStart, _) = scrubSession();
    addTearDown(s.dispose);
    await pumpArea(tester, s);

    double overlayZoom() => tester
        .widget<CameraFrameOverlay>(find.byType(CameraFrameOverlay))
        .pose
        .zoom;

    expect(overlayZoom(), 2, reason: 'standing in cut one, on its T.U');

    // Engage the drag over cut two, then keep moving INSIDE it — from here
    // the cursor never fires again, only the parking does.
    dragTo(s, secondStart, secondStart + 1);
    await tester.pump();
    expect(overlayZoom(), lessThan(2), reason: 'cut two starts at 1×');

    s.scrubGlobalFrame(secondStart + 5);
    await tester.pump();
    expect(
      overlayZoom(),
      closeTo(3, 1e-6),
      reason: 'the frame rides cut two\'s own curve as the drag moves',
    );

    await drainWarming(tester);
  });

  testWidgets('scrubbing into a gap takes the frame away, and coming back '
      'brings it — the overlay never draws a cut that is not there',
      (tester) async {
    final (s, secondStart, gapFrame) = scrubSession();
    addTearDown(s.dispose);
    await pumpArea(tester, s);

    expect(find.byType(CameraFrameOverlay), findsOneWidget);

    dragTo(s, gapFrame, gapFrame + 1);
    await tester.pump();
    expect(find.byType(CameraFrameOverlay), findsNothing);

    s.scrubGlobalFrame(secondStart + 5);
    await tester.pump();
    expect(find.byType(CameraFrameOverlay), findsOneWidget);

    await drainWarming(tester);
  });
}
