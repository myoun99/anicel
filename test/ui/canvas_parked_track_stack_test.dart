import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/ui/brush/brush_tool_state.dart';
import 'package:anicel/src/ui/camera/camera_frame_overlay.dart';
import 'package:anicel/src/ui/editor_canvas_area.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/playback/canvas_playback_controller.dart'
    show PlaybackScope;
import 'package:anicel/src/ui/playback/canvas_track_stack_view.dart';
import 'package:anicel/src/ui/playback/frame_picture_view.dart';
import 'package:anicel/src/ui/session/frame_scrub.dart';
import 'package:anicel/src/ui/storyboard_playhead_mapping.dart'
    show commitStoryboardScrub;

import '../helpers/draw_on_current_frame.dart';

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

  /// The scrub under test, held BY ITS OWN TYPE (2026-09-08).
  ///
  /// 🚨`tool/mutation_run.dart` picks a file's witnesses by which tests
  /// IMPORT it. A collaborator only ever spelled `s.frameScrub` is one the
  /// campaign reports UNNAMED and never runs a mutant against — every D6
  /// edge law below lives in that file and had no witness it could see.
  FrameScrub scrub(EditorSessionManager s) => s.frameScrub;

  /// Two default-track cuts with a 4-frame gap before the second.
  (EditorSessionManager, CutId, int) gappedSession() {
    final s = EditorSessionManager(initialProject: createDefaultProject());
    s.cutVerbs.createCut();
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

  /// 유저 2026-10-08, the playback rework: a run has ONE maker of its
  /// pictures — the warmer, which follows it — and a parked frame is still
  /// composed where it is asked for (F-206: 「스크럽하던 뭐던 존재하는게
  /// 보여야함」).
  testWidgets('each mount says whose pictures it shows: a parked stack '
      'makes its own, a run\'s are the warmer\'s', (tester) async {
    final (s, first, _) = gappedSession();
    addTearDown(s.dispose);
    s.selectCut(first);
    await pumpArea(tester, s);
    final landings = s.playbackRig.prerenderScheduler.landings;
    CanvasTrackStackView stack() =>
        tester.widget<CanvasTrackStackView>(find.byKey(stackKey));

    s.parkGlobalFrame(1);
    await tester.pump();
    expect(stack().run, isNull, reason: 'parked: it makes its own');
    expect(
      stack().pictures.pictures,
      same(s.playbackRig.framePictures),
      reason: 'the frames\' one pictures, the canvas\'s own',
    );

    s.playbackRig.playback.play(scope: PlaybackScope.allCuts);
    await tester.pump();
    expect(stack().run, isNotNull, reason: 'a run: the warmer makes them');
    expect(stack().pictures.landings, same(landings));
    s.playbackRig.playback.stop();
    await tester.pump();

    s.selectCut(first);
    await tester.pump();
    s.playbackRig.playback.play(scope: PlaybackScope.activeCut);
    await tester.pump();
    final played = tester.widget<FramePictureView>(
      find.byType(FramePictureView),
    );
    expect(
      played.run.landings,
      same(landings),
      reason: 'a cut played alone plays on the canvas, from the warmer\'s '
          'pictures (playback-plays-the-screen-material)',
    );
    expect(played.run.pictures, same(s.playbackRig.framePictures));
    s.playbackRig.playback.stop();
    await drainWarming(tester);
  });

  /// F-365: the film changes frames by the question its run's clock asks of
  /// a frame — the rig's, the one place both read it from — and the clock
  /// counts a frame it leaves unshown by the same answer (F-365-Q2), so the
  /// count is of the frames the screen did not show.
  testWidgets('the film asks of a frame what the run\'s clock asks', (
    tester,
  ) async {
    final (s, first, _) = gappedSession();
    addTearDown(s.dispose);
    final second = s.repository.requireProject().tracks.first.cuts[1].id;
    s.selectCut(second);
    drawOnCurrentFrame(s);
    s.selectCut(first);
    await pumpArea(tester, s);
    final head = s.rowSpans.trackGlobalFrameOf(second, 0);
    expect(
      s.playbackRig.pictureIsThere(head),
      isNull,
      reason: '⛔premise: the warmer follows no run',
    );
    expect(
      s.playbackRig.frameIsThere(head),
      isTrue,
      reason: 'with nothing making the run\'s pictures, what the cuts hold is '
          'all there will be: every frame goes up as it is asked for',
    );

    s.playbackRig.playback.play(
      scope: PlaybackScope.allCuts,
      startGlobalFrame: 0,
    );
    await tester.pump();
    // What was made of the second cut's head goes: a memory warning's work.
    s.renderCaches.framePictureStore.enforceBudget(
      maxBytes: 0,
      wantedAt: (_) => null,
    );
    expect(
      s.playbackRig.pictureIsThere(head),
      isFalse,
      reason: '⛔premise: the head\'s picture is not there',
    );
    expect(
      tester
          .widget<CanvasTrackStackView>(find.byKey(stackKey))
          .run!
          .frameIsThere(head),
      isFalse,
    );
    expect(
      s.playbackRig.playback.frameIsThere?.call(head),
      isFalse,
      reason: 'the clock counts the frame unshown by the same answer',
    );
    s.playbackRig.playback.stop();
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

  /// 🚨The RULER DRAG through a gap (user 2026-08-11).
  ///
  /// `scrubGlobalFrame` parks per move in a gap, so dragging the ruler
  /// through one is this stack — and it used to CROP to the camera while the
  /// state the drag started from showed the whole canvas with the frame drawn
  /// over it. Same picture, two framings, one gesture apart. (Until I-57 ②
  /// another cut's frames parked the drag here too.)
  ///
  /// The rule now: the crop is PLAYBACK's. A preview is canvas + overlay.
  bool stackCrops(WidgetTester tester) => tester
      .widget<CanvasTrackStackView>(find.byKey(stackKey))
      .cameraViewEnabled;

  testWidgets('a ruler drag through a gap shows the WHOLE canvas, camera '
      'view on or off — the crop does not appear one gesture into a drag', (
    tester,
  ) async {
    final (s, first, aEnd) = gappedSession();
    addTearDown(s.dispose);
    s.selectCut(first);
    await pumpArea(tester, s, cameraViewEnabled: true);
    expect(find.byKey(stackKey), findsNothing, reason: 'cut active = editing');

    // Two moves in the gap: its display engages on the SECOND, never on the
    // pointer-down alone — the real drag, not a tap.
    scrub(s).scrubGlobalFrame(aEnd + 1);
    scrub(s).scrubGlobalFrame(aEnd + 2);
    await tester.pump();

    expect(s.frameScrub.active.value, isTrue, reason: 'a drag, not a tap');
    expect(find.byKey(stackKey), findsOneWidget);
    expect(
      stackCrops(tester),
      isFalse,
      reason: 'the ruler drag shows what the eye already had',
    );
    await drainWarming(tester);
  });

  testWidgets('🗣️I-57 ②: a drag that started in one cut CROSSES into the '
      'next — the canvas is that cut\'s own editing canvas, not a preview '
      'of it, and the cut is the active one before the finger lifts', (
    tester,
  ) async {
    final (s, first, aEnd) = gappedSession();
    addTearDown(s.dispose);
    final second = s.repository.requireProject().tracks.first.cuts[1].id;
    s.selectCut(first);
    await pumpArea(tester, s);

    scrub(s).scrubGlobalFrame(1);
    await tester.pump();
    expect(s.frameScrub.active.value, isTrue);
    expect(find.byKey(stackKey), findsNothing);

    // Onto the SECOND cut's frames, past the gap.
    scrub(s).scrubGlobalFrame(aEnd + 5);
    await tester.pump();
    expect(s.activeCutId, second, reason: 'the scrub crossed into it');
    expect(s.currentFrameIndex, 1, reason: 'its frame under the playhead');
    expect(
      find.byKey(stackKey),
      findsNothing,
      reason: 'a crossing is a cut switch, not the track stack\'s preview',
    );
    expect(
      tester.widget<FramePictureView>(find.byType(FramePictureView)).live,
      isNotNull,
      reason: 'the cut\'s editing canvas: its frame\'s picture with the row '
          'a pen is on live in it',
    );

    // And back: the first cut is the one again, mid-gesture.
    scrub(s).scrubGlobalFrame(1);
    await tester.pump();
    expect(s.activeCutId, first);
    expect(find.byKey(stackKey), findsNothing);

    scrub(s).commitFrameScrub();
    expect(s.activeCutId, first, reason: 'the release lands where it is');
    await drainWarming(tester);
  });

  testWidgets('D6: a drag that STARTED inside the cut walks into a gap and '
      'the canvas follows — the cut\'s picture does not linger until '
      'release', (tester) async {
    final (s, first, aEnd) = gappedSession();
    addTearDown(s.dispose);
    s.selectCut(first);
    await pumpArea(tester, s);

    // The drag starts on the cut: engages the scrub without ever taking
    // the gap's path (the exact shape the old code left invisible —
    // frameScrub.active was already true, so the later crossing had no
    // rebuild trigger).
    scrub(s).scrubGlobalFrame(1);
    await tester.pump();
    expect(s.frameScrub.active.value, isTrue);
    expect(find.byKey(stackKey), findsNothing);

    // Into the gap: its display must mount NOW, not on release.
    scrub(s).scrubGlobalFrame(aEnd + 2);
    await tester.pump();
    expect(
      find.byKey(stackKey),
      findsOneWidget,
      reason:
          'the gap is the edge — before D6 the canvas kept the cut\'s '
          'picture for the rest of the drag',
    );
    expect(find.byKey(voidKey), findsOneWidget, reason: 'no track covers it');
    expect(s.activeCutId, first, reason: 'the release lands a gap, not this');

    // Back onto the cut: the interactive canvas returns mid-gesture too.
    scrub(s).scrubGlobalFrame(1);
    await tester.pump();
    expect(find.byKey(stackKey), findsNothing);

    scrub(s).commitFrameScrub();
    await drainWarming(tester);
  });

  test('D6: the gap flag fires per EDGE, not per move — and a tap '
      'never sets it (the no-flash rule)', () {
    final (s, first, aEnd) = gappedSession();
    s.selectCut(first);
    var fires = 0;
    s.frameScrub.inGap.addListener(() => fires += 1);

    // A TAP over the gap: pointer-down parks, no move follows.
    scrub(s).scrubGlobalFrame(aEnd + 1);
    expect(fires, 0, reason: 'a tap must not flash the track stack');
    scrub(s).commitFrameScrub();
    expect(fires, 0);

    // A real drag: start on the cut, into the gap, wander, come back.
    s.selectCut(first);
    scrub(s).scrubGlobalFrame(1);
    expect(fires, 0);
    scrub(s).scrubGlobalFrame(aEnd + 1);
    expect(fires, 1, reason: 'the gap edge fires once');
    scrub(s).scrubGlobalFrame(aEnd + 2);
    scrub(s).scrubGlobalFrame(aEnd + 3);
    expect(fires, 1, reason: 'per-move parking stays notify-quiet');
    scrub(s).scrubGlobalFrame(2);
    expect(fires, 2, reason: 're-entry is the other edge');
    scrub(s).commitFrameScrub();
    expect(fires, 2);
    expect(s.frameScrub.inGap.value, isFalse);
    s.dispose();
  });

  test('D6: a drag GRABBED on the cursor\'s own frame engages on its FIRST '
      'crossing — the same-frame down never set the scrub flag, and the '
      'old two-event rule read the genuine move as tap-shaped', () {
    final (s, first, aEnd) = gappedSession();
    s.selectCut(first);
    // Grab the playhead: press exactly on the cursor's frame (0).
    scrub(s).scrubGlobalFrame(0);
    expect(s.frameScrub.active.value, isFalse, reason: 'same-frame down');

    // Cross ONE frame out and hold: the preview must engage NOW.
    scrub(s).scrubGlobalFrame(aEnd + 1);
    expect(s.frameScrub.active.value, isTrue);
    expect(
      s.frameScrub.inGap.value,
      isTrue,
      reason:
          'the step into the gap is a real drag move — the down was on '
          'the cut, so the no-flash rule does not apply to it',
    );

    // A bare DOWN in the gap still engages nothing (no-flash).
    scrub(s).commitFrameScrub();
    s.selectCut(first);
    scrub(s).scrubGlobalFrame(aEnd + 1);
    expect(s.frameScrub.active.value, isFalse);
    expect(s.frameScrub.inGap.value, isFalse);
    scrub(s).commitFrameScrub();
    s.dispose();
  });

  test('D6: playback taking the transport mid-drag clears the WHOLE '
      'preview state — a leaked gap flag would swallow the next '
      'drag\'s gap edge', () {
    final (s, first, aEnd) = gappedSession();
    s.selectCut(first);
    scrub(s).scrubGlobalFrame(1);
    scrub(s).scrubGlobalFrame(aEnd + 1);
    expect(s.frameScrub.active.value, isTrue);
    expect(s.frameScrub.inGap.value, isTrue);

    // Space mid-drag: playback engages; the release path has no editing
    // seek to commit and must abandon the preview instead.
    s.playbackRig.playback.play(scope: PlaybackScope.allCuts);
    commitStoryboardScrub(s);
    expect(s.frameScrub.active.value, isFalse);
    expect(s.frameScrub.inGap.value, isFalse);

    s.playbackRig.playback.stop();
    // The NEXT drag's gap edge fires cleanly.
    s.selectCut(first);
    scrub(s).scrubGlobalFrame(1);
    scrub(s).scrubGlobalFrame(aEnd + 1);
    expect(
      s.frameScrub.inGap.value,
      isTrue,
      reason: 'no leak: the edge is alive on the very next drag',
    );
    scrub(s).commitFrameScrub();
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
        reason:
            'camera view $toggle — the preview framing is not the toggle\'s',
      );
      await drainWarming(tester);
      s.dispose();
    }
  });
}
