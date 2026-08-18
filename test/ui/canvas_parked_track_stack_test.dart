import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/ui/brush/brush_tool_state.dart';
import 'package:anicel/src/ui/camera/camera_frame_overlay.dart';
import 'package:anicel/src/ui/editor_canvas_area.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/playback/canvas_track_stack_view.dart';

/// The multitrack display path's canvas mount (parked state): a gap
/// parking swaps the canvas content to the track stack — a parked frame
/// ON a cut shows that cut's composite instead of the old unconditional void,
/// while a frame no track covers keeps the void.
///
/// 📐 And it shows it UNCROPPED. The crop is playback's (user 2026-08-11); a
/// preview draws the whole canvas with the camera frame over it, which is what
/// the editing canvas beside it has always done.
void main() {
  const stackKey = ValueKey<String>('canvas-track-stack-view');
  const framesKey = ValueKey<String>('canvas-track-stack-frames');
  const voidKey = ValueKey<String>('canvas-track-stack-void');

  /// Two default-track cuts with a 4-frame gap before the second.
  (EditorSessionManager, CutId, int) gappedSession() {
    final s = EditorSessionManager(initialProject: createDefaultProject());
    s.createCut();
    final track = s.repository.requireProject().tracks.first;
    final first = track.cuts[0].id;
    final second = track.cuts[1].id;
    s.repository.updateCutLeadingGap(cutId: second, leadingGapFrames: 4);
    return (s, first, track.cuts[0].duration);
  }

  /// Drains the prerender scheduler's debounced warming (the established
  /// EditorCanvasArea test epilogue — its Future.delayed timers cannot be
  /// cancelled by dispose).
  Future<void> drainWarming(WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
  }

  Future<void> pumpArea(
    WidgetTester tester,
    EditorSessionManager session, {
    bool cameraViewEnabled = false,
  }) async {
    final brushTool = ValueNotifier<BrushToolState>(BrushToolState.defaults);
    final cameraView = ValueNotifier<bool>(cameraViewEnabled);
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
  }

  testWidgets('a parking ON a covered frame shows the track stack (the '
      'SE-row press contract, feedback #7): that cut\'s composite, not '
      'the void', (tester) async {
    final (s, first, _) = gappedSession();
    addTearDown(s.dispose);
    s.selectCut(first);
    await pumpArea(tester, s);
    expect(find.byKey(stackKey), findsNothing, reason: 'cut active = editing');

    s.parkGlobalFrame(1); // ON cut 1 — the SE-row press parks in place.
    await tester.pump();

    expect(s.activeCutId, isNull);
    expect(find.byKey(stackKey), findsOneWidget);
    expect(
      find.byKey(framesKey),
      findsOneWidget,
      reason: 'the covered frame paints a projection, not the void',
    );
    expect(tester.takeException(), isNull);
    await drainWarming(tester);
  });

  testWidgets('a parking in a REAL gap keeps the void (no track covers '
      'the frame)', (tester) async {
    final (s, first, aEnd) = gappedSession();
    addTearDown(s.dispose);
    s.selectCut(first);
    await pumpArea(tester, s);

    s.selectGlobalFrame(aEnd + 1); // the gap between the cuts
    await tester.pump();

    expect(s.activeCutId, isNull);
    expect(find.byKey(stackKey), findsOneWidget);
    expect(find.byKey(voidKey), findsOneWidget);
    expect(find.byKey(framesKey), findsNothing);
    await drainWarming(tester);
  });

  testWidgets('camera view enabled + gap parking builds without the '
      'authoring overlay (regression: cameraPoseAtCurrentFrame used to '
      'throw requireActiveCut through the overlay build)', (tester) async {
    final (s, first, _) = gappedSession();
    addTearDown(s.dispose);
    s.selectCut(first);
    await pumpArea(tester, s, cameraViewEnabled: true);
    expect(find.byType(CameraFrameOverlay), findsOneWidget);

    s.parkGlobalFrame(1);
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(
      find.byType(CameraFrameOverlay),
      findsNothing,
      reason: 'no active cut = no pose to author, so nothing to draw',
    );
    expect(find.byKey(stackKey), findsOneWidget);

    // Selecting the cut again restores the authoring overlay.
    s.selectCut(first);
    await tester.pump();
    expect(find.byType(CameraFrameOverlay), findsOneWidget);
    expect(find.byKey(stackKey), findsNothing);
    await drainWarming(tester);
  });

  /// 🚨The storyboard RULER DRAG (user 2026-08-11).
  ///
  /// `scrubGlobalFrame` parks the moment the frame belongs to another cut, so
  /// dragging the ruler across cuts is this stack — and it used to CROP to the
  /// camera while the state the drag started from showed the whole canvas with
  /// the frame drawn over it. Same picture, two framings, one gesture apart.
  ///
  /// The rule now: the crop is PLAYBACK's. A preview is canvas + overlay.
  bool stackCrops(WidgetTester tester) => tester
      .widget<CanvasTrackStackView>(find.byKey(stackKey))
      .cameraViewEnabled;

  testWidgets('a ruler drag across cuts shows the WHOLE canvas, camera view '
      'on or off — the crop does not appear one gesture into a drag', (
    tester,
  ) async {
    final (s, first, aEnd) = gappedSession();
    addTearDown(s.dispose);
    s.selectCut(first);
    await pumpArea(tester, s, cameraViewEnabled: true);
    expect(find.byKey(stackKey), findsNothing, reason: 'cut active = editing');

    // Two out-of-territory moves: the preview engages on the SECOND, never on
    // the pointer-down alone — the real drag, not a tap.
    s.scrubGlobalFrame(aEnd + 1);
    s.scrubGlobalFrame(aEnd + 2);
    await tester.pump();

    expect(s.frameScrubActive.value, isTrue, reason: 'a drag, not a tap');
    expect(find.byKey(stackKey), findsOneWidget);
    expect(
      stackCrops(tester),
      isFalse,
      reason: 'the ruler drag shows what the eye already had',
    );
    await drainWarming(tester);
  });

  testWidgets('D6: a drag that STARTED inside the cut crosses the boundary '
      'and the canvas follows — the previous cut\'s picture does not '
      'linger until release', (tester) async {
    final (s, first, aEnd) = gappedSession();
    addTearDown(s.dispose);
    s.selectCut(first);
    await pumpArea(tester, s);

    // The drag starts IN territory: engages the scrub without ever
    // taking the out-of-territory path (the exact shape the old code
    // left invisible — frameScrubActive was already true, so the later
    // crossing had no rebuild trigger).
    s.scrubGlobalFrame(1);
    await tester.pump();
    expect(s.frameScrubActive.value, isTrue);
    expect(find.byKey(stackKey), findsNothing);

    // Cross onto the SECOND cut's frames: the multitrack preview must
    // mount NOW, not on release.
    s.scrubGlobalFrame(aEnd + 5);
    await tester.pump();
    expect(
      find.byKey(stackKey),
      findsOneWidget,
      reason: 'the crossing is the edge — before D6 the canvas kept the '
          'previous cut\'s picture for the rest of the drag',
    );
    expect(
      find.byKey(framesKey),
      findsOneWidget,
      reason: 'the crossed-onto cut paints its composite',
    );

    // Scrub back in: the interactive canvas returns mid-gesture too.
    s.scrubGlobalFrame(1);
    await tester.pump();
    expect(find.byKey(stackKey), findsNothing);

    s.commitFrameScrub();
    await drainWarming(tester);
  });

  test('D6: the territory flag fires per EDGE, not per move — and a tap '
      'never sets it (the no-flash rule)', () {
    final (s, first, aEnd) = gappedSession();
    s.selectCut(first);
    var fires = 0;
    s.scrubOutOfTerritory.addListener(() => fires += 1);

    // A TAP over the gap: pointer-down parks, no move follows.
    s.scrubGlobalFrame(aEnd + 1);
    expect(fires, 0, reason: 'a tap must not flash the track stack');
    s.commitFrameScrub();
    expect(fires, 0);

    // A real drag: in-territory start, cross out, wander, come back.
    s.selectCut(first);
    s.scrubGlobalFrame(1);
    expect(fires, 0);
    s.scrubGlobalFrame(aEnd + 1);
    expect(fires, 1, reason: 'the exit edge fires once');
    s.scrubGlobalFrame(aEnd + 2);
    s.scrubGlobalFrame(aEnd + 3);
    expect(fires, 1, reason: 'per-move parking stays notify-quiet');
    s.scrubGlobalFrame(2);
    expect(fires, 2, reason: 're-entry is the other edge');
    s.commitFrameScrub();
    expect(fires, 2);
    expect(s.scrubOutOfTerritory.value, isFalse);
    s.dispose();
  });

  testWidgets('and the toggle does not move that answer: a parked preview is '
      'uncropped either way', (tester) async {
    for (final toggle in [false, true]) {
      final (s, first, _) = gappedSession();
      s.selectCut(first);
      await pumpArea(tester, s, cameraViewEnabled: toggle);
      s.parkGlobalFrame(1);
      await tester.pump();

      expect(find.byKey(stackKey), findsOneWidget);
      expect(
        stackCrops(tester),
        isFalse,
        reason: 'camera view $toggle — the preview framing is not the toggle\'s',
      );
      await drainWarming(tester);
      s.dispose();
    }
  });
}
