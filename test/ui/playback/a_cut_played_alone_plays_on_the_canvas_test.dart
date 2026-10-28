import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/core/tree_nodes.dart';
import 'package:anicel/src/models/brush_frame_key.dart';
import 'package:anicel/src/models/camera_instruction.dart' show InstructionEvent;
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/canvas_viewport.dart';
import 'package:anicel/src/models/composite_tree.dart';
import 'package:anicel/src/models/drawing_guide.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/pasteboard_bounds.dart'
    show PasteboardBounds, PasteboardReach;
import 'package:anicel/src/models/playback_mode.dart';
import 'package:anicel/src/ui/brush/brush_tool_state.dart';
import 'package:anicel/src/ui/brush/main_canvas_brush_host.dart';
import 'package:anicel/src/ui/canvas/canvas_layer_stack_view.dart';
import 'package:anicel/src/ui/canvas/guide_overlay.dart';
import 'package:anicel/src/ui/canvas/interactive_brush_edit_canvas_view.dart';
import 'package:anicel/src/ui/canvas/outline_clipper.dart';
import 'package:anicel/src/ui/editor_canvas_area.dart';
import 'package:anicel/src/ui/effective_device_pixel_ratio.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/playback/canvas_playback_controller.dart'
    show PlaybackScope;
import 'package:anicel/src/ui/playback/camera_shot.dart';
import 'package:anicel/src/ui/playback/canvas_track_stack_view.dart';
import 'package:anicel/src/ui/playback/frame_picture_view.dart';
import 'package:anicel/src/ui/playback/playback_run_layer.dart';
import 'package:anicel/src/ui/repaint_props.dart';
import 'package:anicel/src/ui/session/frame_scrub.dart';
import '../../helpers/a_canvas_standing_on_a_frame.dart';

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
    void Function(EditorSessionManager session)? prepare,
  }) async {
    final session = EditorSessionManager(
      initialProject: createDefaultProject(),
    );
    addTearDown(session.dispose);
    // A cel under the playhead: the row the canvas draws live, standing
    // still.
    session.createDrawingAtCurrentFrame();
    prepare?.call(session);
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

  /// The frame the canvas shows — standing still or under a run: its one
  /// picture.
  FramePictureView playedOf(WidgetTester tester) =>
      tester.widget<FramePictureView>(theFramesPicture());

  /// The cels the rows of [nodes] are images of.
  List<BrushFrameKey> celsOf(List<CompositeNode<CanvasStackRow>> nodes) => [
    for (final node in preorderNodes(nodes))
      if (node is CompositeLeaf<CanvasStackRow> &&
          node.payload is CanvasLayerImageRequest)
        (node.payload as CanvasLayerImageRequest).frameKey,
  ];

  /// Whether a row stands LIVE in the tree the canvas paints.
  bool aRowStandsLive(WidgetTester tester) =>
      preorderNodes(playedOf(tester).nodes).any(
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
        playedOf(tester).run.landings,
        same(s.playbackRig.prerenderScheduler.landings),
        reason: 'the run\'s pictures are the warmer\'s',
      );
      expect(playedOf(tester).run.pictures, same(s.playbackRig.framePictures));
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
    final atTheStart = celsOf(playedOf(tester).nodes);

    playback.seekToGlobalFrame(5);
    await tester.pump();

    expect(
      tester.widget(find.byType(MainCanvasBrushHost)),
      same(host),
      reason: 'the canvas is not built again for a step',
    );
    expect(celsOf(playedOf(tester).nodes), isNot(atTheStart));
    expect(playedOf(tester).picture.frameIndex, 5);
    expect(
      celsOf(playedOf(tester).nodes),
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
    final view = tester.state(theFramesPicture());

    s.playbackRig.playback.play(scope: PlaybackScope.activeCut);
    await tester.pump();
    expect(tester.state(theFramesPicture()), same(view));

    s.playbackRig.playback.stop();
    await tester.pump();
    expect(tester.state(theFramesPicture()), same(view));
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
    expect(playedOf(tester).viewport, shotOf().view);

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
      playedOf(tester).viewport,
      shot.frameView,
      reason: 'the canvas is seen through the camera at that frame',
    );
    // ↩️The warmer was told the camera the canvas was seen through
    // (`RenderCaches.canvasLook`), to make each row at the level that view
    // drew it at — until a frame became one picture, made whatever it is
    // seen through (D7-2-Q2).

    playback.stop();
    await tester.pump();
    await tester.pump();
    expect(shotOf().shot, isNull);
    await drain(tester);
  });

  /// What one of the overlay's private painters paints with, read through
  /// the one face they show ([RepaintOnProps.props]) — the order is theirs.
  Object propsOf(WidgetTester tester, String painter) =>
      (tester
                  .widget<CustomPaint>(
                    find.byWidgetPredicate(
                      (widget) =>
                          widget is CustomPaint &&
                          widget.painter.runtimeType.toString() == painter,
                    ),
                  )
                  .painter!
              as RepaintOnProps)
          .props;

  /// The first of two cuts run alone and stood three frames before the end
  /// of it, inside an O.L into the second — with a name tag on its SE row:
  /// everything a run lays over its picture.
  Future<EditorSessionManager> runningIntoAnOl(
    WidgetTester tester, {
    required bool cameraView,
  }) async {
    late int boundary;
    final (s, _) = await pumpArea(
      tester,
      cameraView: cameraView,
      prepare: (s) {
        s.cutVerbs.createCut();
        final cuts = s.repository.requireProject().tracks.first.cuts;
        s.selectCut(cuts[0].id);
        boundary = cuts[0].duration;
        // An O.L across the boundary, six frames each side.
        s.transitions.updateTransitionInstructions({
          boundary - 6: const InstructionEvent(instructionId: 'ol', length: 12),
        });
        // A name tag on the SE row, from the first frame on.
        s.selectLayer(
          s.layers.firstWhere((layer) => layer.kind == LayerKind.se).id,
        );
        s.selectFrameIndex(0);
        s.seEntries.createSeEntryAtCurrentFrame(name: '쿵');
      },
    );
    final playback = s.playbackRig.playback;
    playback.play(scope: PlaybackScope.activeCut);
    await tester.pump();
    playback.seekToGlobalFrame(boundary - 3);
    await tester.pump();
    return s;
  }

  /// The clip over what lies over the picture: the one around the fade's
  /// wash.
  ClipPath clipOverThePicture(WidgetTester tester) => tester.widget<ClipPath>(
    find
        .ancestor(
          of: find.byWidgetPredicate(
            (widget) =>
                widget is CustomPaint &&
                widget.painter.runtimeType.toString() == '_CutFadeWashPainter',
          ),
          matching: find.byType(ClipPath),
        )
        .first,
  );

  testWidgets('🚨seen through no camera, nothing over the picture is cut, '
      'and the fade thins the cut\'s unit as far as its pasteboard — as the '
      'film thins it (conte-playback-hides-the-pasteboard)', (tester) async {
    final s = await runningIntoAnOl(tester, cameraView: false);

    final (_, unit, _, _, _, _) =
        propsOf(tester, '_CutFadeWashPainter')
            as (CanvasViewport, Rect, Object, Object, double, double);
    expect(
      unit,
      s.activeCutOrNull!.canvasSize.pasteboardAt(PasteboardReach.whole).rect,
      reason: 'the pasteboard and what is drawn on it thin with the paper',
    );
    expect(
      clipOverThePicture(tester).clipBehavior,
      Clip.none,
      reason: 'a cut played whole is cut nowhere, over its picture either',
    );
    expect(
      tester
          .widget<CanvasTrackStackView>(
            find.byKey(const ValueKey<String>('canvas-ol-partner')),
          )
          .cameraViewEnabled,
      isFalse,
      reason: 'the O.L\'s other cut is seen as the canvas sees it',
    );

    s.playbackRig.playback.stop();
    await drain(tester);
  });

  testWidgets('🚨seen through the camera, what is over the picture is in the '
      'camera\'s frame with it: the SE tags ride the camera, the fade\'s unit '
      'is the frame, the O.L\'s other cut is seen through the camera too, and '
      'nothing of them shows past the frame', (tester) async {
    final s = await runningIntoAnOl(tester, cameraView: true);
    final playback = s.playbackRig.playback;

    final shotWidget = tester.widget<CameraShot>(find.byType(CameraShot));
    final shot = shotWidget.shot!;
    final (tagsView, _, _, _) =
        propsOf(tester, '_SeNameTagOverlayPainter')
            as (CanvasViewport, CanvasSize, double, Object);
    final (washView, unit, _, _, _, _) =
        propsOf(tester, '_CutFadeWashPainter')
            as (CanvasViewport, Rect, Object, Object, double, double);
    expect(
      tagsView,
      shot.frameView,
      reason: 'the tags ride the camera, as the picture they name does',
    );
    expect(washView, shotWidget.view);
    expect(
      unit,
      s.camera.cameraFrameSize.canvasRect,
      reason: 'the fade thins the camera\'s frame — apron, paper and picture',
    );
    expect(
      tester
          .widget<CanvasTrackStackView>(
            find.byKey(const ValueKey<String>('canvas-ol-partner')),
          )
          .cameraViewEnabled,
      isTrue,
      reason: 'the O.L\'s other cut is seen through the camera too',
    );
    final over = clipOverThePicture(tester);
    final ratio = EffectiveDevicePixelRatio.of(
      tester.element(find.byType(CameraShot)),
    );
    final frame = shotClipOnScreen(
      cameraFrameOnScreen(shotWidget.view, shot.frameSize, ratio),
      ratio,
    );
    expect(over.clipBehavior, frame.behavior);
    expect(
      (over.clipper! as OutlineClipper).corners,
      frame.corners,
      reason: 'nothing over the picture shows past the camera\'s frame — '
          'cut as the picture under it is',
    );

    playback.stop();
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
    final view = tester.state(theFramesPicture());

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
        tester.state(theFramesPicture()),
        same(view),
        reason: '$seen, the view that holds the run\'s picture is the same — '
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
    expect(
      preorderNodes(playedOf(tester).nodes).any(
        (node) => node is CompositeLeaf<CanvasStackRow> &&
            node.payload is CanvasActiveLayerRow,
      ),
      isFalse,
    );
    expect(
      playedOf(tester).live,
      isNull,
      reason: 'the frame is its one picture: nothing in it is drawn live',
    );
    expect(
      find.byType(InteractiveBrushEditCanvasView),
      findsNothing,
      reason: 'the view a pen draws through is not built under a run',
    );

    s.playbackRig.playback.stop();
    await tester.pump();
    expect(aRowStandsLive(tester), isTrue);
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

  testWidgets('the warmer makes the canvas\'s pictures for every run — a cut '
      'through the camera or not, and the whole film; the canvas shows a '
      'cut, the track stack the film', (tester) async {
    final (s, camera) = await pumpArea(tester);
    final rig = s.playbackRig;
    expect(rig.prerenderScheduler.pictures, same(rig.framePictures));
    expect(rig.pictures, same(rig.framePictures));

    camera.value = true;
    await tester.pump();
    rig.playback.play(scope: PlaybackScope.activeCut);
    await tester.pump();
    expect(
      rig.playsOnTheCanvas,
      isTrue,
      reason: 'a cut played alone through the camera plays on the canvas',
    );
    rig.playback.stop();
    await tester.pump();

    rig.playback.play(scope: PlaybackScope.allCuts);
    expect(
      rig.playsOnTheCanvas,
      isFalse,
      reason: 'the whole film plays on the track stack',
    );
    expect(
      rig.prerenderScheduler.pictures,
      same(rig.framePictures),
      reason: 'from the same pictures. ↩️It played from composites until '
          '2026-10-10',
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
