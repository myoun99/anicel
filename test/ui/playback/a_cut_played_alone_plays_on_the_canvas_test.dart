import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/core/tree_nodes.dart';
import 'package:anicel/src/models/brush_frame_key.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/composite_tree.dart';
import 'package:anicel/src/models/drawing_guide.dart';
import 'package:anicel/src/models/playback_mode.dart';
import 'package:anicel/src/ui/brush/brush_tool_state.dart';
import 'package:anicel/src/ui/brush/main_canvas_brush_host.dart';
import 'package:anicel/src/ui/canvas/canvas_layer_stack_view.dart';
import 'package:anicel/src/ui/canvas/guide_overlay.dart';
import 'package:anicel/src/ui/canvas/interactive_brush_edit_canvas_view.dart';
import 'package:anicel/src/ui/editor_canvas_area.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/playback/canvas_playback_controller.dart'
    show PlaybackScope;
import 'package:anicel/src/ui/playback/camera_shot.dart';
import 'package:anicel/src/ui/playback/canvas_track_stack_view.dart';
import 'package:anicel/src/ui/playback/playback_run_layer.dart';
import 'package:anicel/src/ui/session/frame_scrub.dart';

/// playback-plays-the-screen-material ① (10-09) and ② (10-10): a cut played
/// alone plays ON the editing canvas, through the camera or not. The clock
/// moves the playhead the way a scrub does and the canvas draws the frame
/// it stands on, from the images it draws standing still — 유저 F-296-Q6:
/// 「보인다 — 재생과 정지가 같은 그림」 · 「중복소재 안만들고 싶은것」.
///
/// ↩️A run swapped the canvas for a composite view: a second picture of
/// every frame, the cut's own size, made from the very images the canvas
/// draws, with the canvas hidden under it — and the camera view kept that
/// swap a day longer than the rest.
void main() {
  /// The scrub under test, held by its own type so the mutation campaign
  /// finds this file as its witness.
  FrameScrub scrubOf(EditorSessionManager s) => s.frameScrub;

  Future<(EditorSessionManager, ValueNotifier<bool>)> pumpArea(
    WidgetTester tester, {
    bool cameraView = false,
  }) async {
    final session = EditorSessionManager(
      initialProject: createDefaultProject(),
    );
    addTearDown(session.dispose);
    // A cel under the playhead: the row the canvas draws live, standing
    // still.
    session.createDrawingAtCurrentFrame();
    final brushTool = ValueNotifier<BrushToolState>(BrushToolState.defaults);
    final camera = ValueNotifier<bool>(cameraView);
    final dim = ValueNotifier<double>(0.5);
    addTearDown(brushTool.dispose);
    addTearDown(camera.dispose);
    addTearDown(dim.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: EditorCanvasArea(
            session: session,
            brushToolState: brushTool,
            cameraViewEnabled: camera,
            cameraDimOpacity: dim,
          ),
        ),
      ),
    );
    await tester.pump();
    return (session, camera);
  }

  /// The warmer's debounced timers cannot be cancelled by a dispose.
  Future<void> drain(WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
  }

  CanvasLayerStackView stackOf(WidgetTester tester) =>
      tester.widget<CanvasLayerStackView>(find.byType(CanvasLayerStackView));

  /// The cels the rows of [nodes] are images of.
  List<BrushFrameKey> celsOf(List<CompositeNode<CanvasStackRow>> nodes) => [
    for (final node in preorderNodes(nodes))
      if (node is CompositeLeaf<CanvasStackRow> &&
          node.payload is CanvasLayerImageRequest)
        (node.payload as CanvasLayerImageRequest).frameKey,
  ];

  /// Whether a row stands LIVE in the tree the canvas paints.
  bool aRowStandsLive(WidgetTester tester) =>
      preorderNodes(stackOf(tester).nodes).any(
        (node) => node is CompositeLeaf<CanvasStackRow> &&
            node.payload is CanvasActiveLayerRow,
      );

  Finder guideOverlay() => find.byWidgetPredicate(
    (widget) => widget is CustomPaint && widget.painter is GuideOverlayPainter,
  );

  for (final cameraView in [false, true]) {
    final seen = cameraView ? 'through' : 'without';
    testWidgets('🚨a cut played alone, seen $seen the camera, plays ON the '
        'canvas: the canvas stays, under the run\'s layer, and no composite '
        'view is built', (tester) async {
      final (s, _) = await pumpArea(tester, cameraView: cameraView);
      s.playbackRig.playback.play(scope: PlaybackScope.activeCut);
      await tester.pump();

      expect(find.byType(CanvasTrackStackView), findsNothing);
      expect(find.byType(PlaybackRunLayer), findsOneWidget);
      expect(
        stackOf(tester).run?.landings,
        same(s.playbackRig.prerenderScheduler.landings),
        reason: 'the run\'s pictures are the warmer\'s',
      );
      s.playbackRig.playback.stop();
      await drain(tester);
    });
  }

  testWidgets('🚨the playhead follows the run: the canvas stands on the frame '
      'the run shows', (tester) async {
    final (s, _) = await pumpArea(tester);
    final playback = s.playbackRig.playback;
    playback.play(scope: PlaybackScope.activeCut);
    await tester.pump();

    for (final frame in [5, 3, 7]) {
      playback.seekToGlobalFrame(frame);
      await tester.pump();
      expect(s.editingFrameCursor.value, frame);
      expect(s.currentFrameIndex, frame);
    }
    expect(
      scrubOf(s).active.value,
      isFalse,
      reason: 'it moves as a scrub moves; it is no scrub gesture',
    );
    playback.stop();
    await drain(tester);
  });

  testWidgets('🚨a step of the run builds the picture again, not the canvas: '
      'the host stays as the run found it, and the rows shown are the '
      'frame\'s the run stands on', (tester) async {
    final (s, _) = await pumpArea(tester);
    // A second cel five frames on: the rows name the frame they are of.
    s.selectFrameIndex(5);
    s.createDrawingAtCurrentFrame();
    s.selectFrameIndex(0);
    await tester.pump();
    final playback = s.playbackRig.playback;
    playback.play(scope: PlaybackScope.activeCut);
    await tester.pump();
    final host = tester.widget<MainCanvasBrushHost>(
      find.byType(MainCanvasBrushHost),
    );
    final atTheStart = celsOf(stackOf(tester).nodes);

    playback.seekToGlobalFrame(5);
    await tester.pump();

    expect(
      tester.widget(find.byType(MainCanvasBrushHost)),
      same(host),
      reason: 'the canvas is not built again for a step',
    );
    expect(celsOf(stackOf(tester).nodes), isNot(atTheStart));
    expect(
      celsOf(stackOf(tester).nodes),
      celsOf(s.editingCanvas.playingStack.nodes),
      reason: 'the picture is',
    );

    playback.stop();
    await tester.pump();
    expect(
      tester
          .widget<MainCanvasBrushHost>(find.byType(MainCanvasBrushHost))
          .selection
          ?.toBrushFrameKey(),
      allOf(
        isNotNull,
        s.editingCanvas.activeBrushEditorSelection?.toBrushFrameKey(),
        isNot(host.selection?.toBrushFrameKey()),
      ),
      reason: 'the run\'s end builds the canvas again, on the frame it '
          'stopped on',
    );
    await drain(tester);
  });

  testWidgets('the picture standing still is the picture the run plays: its '
      'view is not made again at the run\'s start, nor at its end', (
    tester,
  ) async {
    final (s, _) = await pumpArea(tester);
    final view = tester.state(find.byType(CanvasLayerStackView));

    s.playbackRig.playback.play(scope: PlaybackScope.activeCut);
    await tester.pump();
    expect(tester.state(find.byType(CanvasLayerStackView)), same(view));

    s.playbackRig.playback.stop();
    await tester.pump();
    expect(tester.state(find.byType(CanvasLayerStackView)), same(view));
    await drain(tester);
  });

  testWidgets('🚨seen through the camera, the run is drawn through the '
      'camera\'s view of the frame it stands on — the playhead follows it, '
      'and a canvas that stands again is seen through none', (tester) async {
    final (s, _) = await pumpArea(tester, cameraView: true);
    CameraShot shotOf() => tester.widget<CameraShot>(find.byType(CameraShot));
    expect(
      shotOf().shot,
      isNull,
      reason: '⛔premise: standing still, the camera\'s frame is drawn OVER '
          'the whole canvas — the crop is playback\'s',
    );
    expect(stackOf(tester).viewport, shotOf().view);

    final playback = s.playbackRig.playback;
    playback.play(scope: PlaybackScope.activeCut);
    await tester.pump();
    playback.seekToGlobalFrame(5);
    await tester.pump();

    expect(s.editingFrameCursor.value, 5, reason: 'the playhead follows');
    final shot = shotOf().shot;
    expect(shot, isNotNull);
    expect(shot!.pose, s.camera.cameraPoseForCut(s.requireActiveCut, 5));
    expect(
      stackOf(tester).viewport,
      shot.frameView,
      reason: 'the canvas is seen through the camera at that frame',
    );
    expect(
      s.renderCaches.canvasLook.value.camera?.frameSize,
      s.camera.cameraFrameSize,
      reason: 'and the warmer is told so, for the frames it makes ahead',
    );

    playback.stop();
    await tester.pump();
    await tester.pump();
    expect(shotOf().shot, isNull);
    expect(s.renderCaches.canvasLook.value.camera, isNull);
    await drain(tester);
  });

  testWidgets('🚨a run keeps its clock, and the canvas its picture, when the '
      'camera view is turned on under it, and off again', (tester) async {
    final (s, camera) = await pumpArea(tester);
    final playback = s.playbackRig.playback;
    // A clock that never waits: what moves it is its ticker alone.
    s.playbackRig.setPlaybackMode(PlaybackMode.skipFrames);
    playback.play(scope: PlaybackScope.activeCut);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    final view = tester.state(find.byType(CanvasLayerStackView));

    for (final throughTheCamera in [true, false]) {
      camera.value = throughTheCamera;
      await tester.pump();
      final before = playback.playlistFrame;
      await tester.pump(const Duration(milliseconds: 250));
      final seen = throughTheCamera ? 'seen through it' : 'seen without it';
      expect(
        playback.playlistFrame,
        isNot(before),
        reason: '$seen, the clock still runs',
      );
      expect(
        tester.state(find.byType(CanvasLayerStackView)),
        same(view),
        reason: '$seen, the stack that holds the run\'s images is the same — '
            'not made again, and nothing of it made again',
      );
    }
    expect(find.byType(PlaybackRunLayer), findsOneWidget);
    playback.stop();
    await drain(tester);
  });

  testWidgets('a run draws on nothing: no row stands live while it plays, and '
      'one does again the moment it stops', (tester) async {
    final (s, _) = await pumpArea(tester);
    expect(aRowStandsLive(tester), isTrue, reason: '⛔premise: standing still');

    expect(find.byType(InteractiveBrushEditCanvasView), findsOneWidget);

    s.playbackRig.playback.play(scope: PlaybackScope.activeCut);
    await tester.pump();
    expect(aRowStandsLive(tester), isFalse);
    expect(stackOf(tester).activeSurfacePainter, isNull);
    expect(
      find.byType(InteractiveBrushEditCanvasView),
      findsNothing,
      reason: 'the view a pen draws through is not built under a run',
    );

    s.playbackRig.playback.stop();
    await tester.pump();
    expect(aRowStandsLive(tester), isTrue);
    expect(stackOf(tester).run, isNull);
    expect(find.byType(InteractiveBrushEditCanvasView), findsOneWidget);
    await drain(tester);
  });

  testWidgets('the editing chrome leaves for the run: a guide is drawn '
      'standing still, and not while it plays', (tester) async {
    final (s, _) = await pumpArea(tester);
    s.cutVerbs.setActiveCutGuides(
      CutGuides(
        guides: [
          DrawingGuide(
            id: const GuideId('axis'),
            name: 'Axis',
            shape: SymmetryShape(
              axis: GuideAxis(
                origin: CanvasPoint(x: 10, y: 20),
                angleDegrees: 30,
              ),
            ),
          ),
        ],
      ),
    );
    await tester.pump();
    expect(guideOverlay(), findsOneWidget, reason: '⛔premise');

    s.playbackRig.playback.play(scope: PlaybackScope.activeCut);
    await tester.pump();
    expect(guideOverlay(), findsNothing);

    s.playbackRig.playback.stop();
    await tester.pump();
    expect(guideOverlay(), findsOneWidget);
    await drain(tester);
  });

  testWidgets('the warmer makes the canvas\'s pictures, through the camera or '
      'not — only the whole film is shown from composites', (tester) async {
    final (s, camera) = await pumpArea(tester);
    final rig = s.playbackRig;
    expect(rig.canvasShown, same(rig.canvasPictures));
    expect(rig.shownPictures, same(rig.canvasPictures));

    camera.value = true;
    await tester.pump();
    expect(rig.shownPictures, same(rig.canvasPictures));
    rig.playback.play(scope: PlaybackScope.activeCut);
    await tester.pump();
    expect(
      rig.shownPictures,
      same(rig.canvasPictures),
      reason: 'a cut played alone through the camera is the canvas\'s too',
    );
    rig.playback.stop();
    await tester.pump();

    rig.playback.play(scope: PlaybackScope.allCuts);
    expect(
      rig.canvasShown,
      isNull,
      reason: 'the whole film plays on the track stack yet',
    );
    rig.playback.stop();
    await drain(tester);
  });

  group('the run moves the playhead as a scrub does', () {
    test('the cursor and the plan move together, with no session notify, '
        'no scrub flag and no warm', () {
      final s = EditorSessionManager(initialProject: createDefaultProject());
      addTearDown(s.dispose);
      var notices = 0;
      s.addListener(() => notices += 1);

      scrubOf(s).followTheRun(4);

      expect(s.editingFrameCursor.value, 4);
      expect(s.currentFrameIndex, 4);
      expect(scrubOf(s).active.value, isFalse);
      expect(notices, 0, reason: 'the panels are not rebuilt per frame');
    });

    test('a step is a seek: none moves the playhead under a live stroke', () {
      final s = EditorSessionManager(initialProject: createDefaultProject());
      addTearDown(s.dispose);
      s.brushInputActive.value = true;

      scrubOf(s).followTheRun(4);

      expect(s.editingFrameCursor.value, 0);
      expect(s.currentFrameIndex, 0);
    });
  });
}
