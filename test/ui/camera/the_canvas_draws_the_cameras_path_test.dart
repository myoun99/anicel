import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/camera_path_settings.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_resize_anchor.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/sheet_marks.dart';
import 'package:anicel/src/models/timeline_row_address.dart';
import 'package:anicel/src/services/camera_frame_corners.dart';
import 'package:anicel/src/ui/brush/brush_tool_state.dart';
import 'package:anicel/src/ui/camera/camera_frame_overlay.dart';
import 'package:anicel/src/ui/camera/camera_path_overlay.dart';
import 'package:anicel/src/ui/canvas/canvas_viewport_offset.dart';
import 'package:anicel/src/ui/editor_canvas_area.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/playback/canvas_playback_controller.dart'
    show PlaybackScope;
import 'package:anicel/src/ui/session/camera.dart';
import 'package:anicel/src/ui/session/canvas_adjust.dart' show CameraSizeDraft;

/// I-89 ④ — the camera's path on the canvas: drawn while one stands on the
/// camera row or its position lane (the confirmed spec of 2026-10-10:
/// 「카메라 행이나 그 위치 레인에 서 있을 때」), where the canvas draws the
/// camera's frame, as the canvas's camera path settings say.
void main() {
  void reset() =>
      CameraPathSettings.settings.value = const CameraPathSettings();
  setUp(reset);
  tearDown(reset);

  /// The spec's grey behind the playhead and blue ahead of it (2026-10-10,
  /// the mock's 5판), and a key between's ink.
  const grey = 0xFF8E9093;
  const blue = 0xFF3A78C8;
  const ink = 0xFF101010;

  /// A cut whose camera pans 200 canvas pixels right from frame 0 to frame
  /// 5, stood on at frame 0 on its camera row.
  (EditorSessionManager, LayerId) panning() {
    final s = EditorSessionManager(initialProject: createDefaultProject());
    final camera = cameraOf(s);
    s.selectFrameIndex(0);
    final start = camera.cameraPoseAtCurrentFrame;
    camera.setCameraKeyframeAtCurrentFrame(start);
    s.selectFrameIndex(5);
    camera.setCameraKeyframeAtCurrentFrame(
      start.copyWith(
        center: CanvasPoint(x: start.center.x + 200, y: start.center.y),
      ),
    );
    s.selectFrameIndex(0);
    final row = s.requireActiveCut.layers
        .firstWhere((layer) => layer.kind == LayerKind.camera)
        .id;
    s.standOnRow(LayerRowAddress(row));
    return (s, row);
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
    await tester.pump();
  }

  /// The warmer's debounced timers cannot be cancelled by a dispose.
  Future<void> drain(WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
  }

  Finder path() => find.byType(CameraPathOverlay);

  List<SheetMark> marks(WidgetTester tester) =>
      tester.widget<CameraPathOverlay>(path()).marks;

  List<String> labels(WidgetTester tester) => [
    for (final mark in marks(tester))
      if (mark is SheetWords) mark.text,
  ];

  /// The two-point strokes — the arms of the keys' and the ticks' crosses.
  int armsOf(WidgetTester tester) => [
    for (final mark in marks(tester))
      if (mark is SheetStroke && !mark.closed && mark.points.length == 2)
        mark,
  ].length;

  /// The frames the path draws, a key each, first to last — on the screen.
  List<List<Offset>> keyFrames(WidgetTester tester) => [
    for (final mark in marks(tester))
      if (mark is SheetStroke && mark.closed) mark.points,
  ];

  /// The camera's frame as the canvas draws it now — on the screen.
  List<Offset> frameDrawn(WidgetTester tester) {
    final frame = tester.widget<CameraFrameOverlay>(
      find.byType(CameraFrameOverlay),
    );
    return [
      for (final corner in cameraFrameCornersInCanvas(
        pose: frame.pose,
        cameraFrameSize: frame.cameraFrameSize,
      ))
        frame.viewport.canvasToViewportOffset(
          CanvasPoint(x: corner.dx, y: corner.dy),
        ),
    ];
  }

  void expectPoints(List<Offset> actual, List<Offset> expected) {
    expect(actual, hasLength(expected.length));
    for (final (index, point) in expected.indexed) {
      expect(actual[index].dx, closeTo(point.dx, 1e-6), reason: 'x $index');
      expect(actual[index].dy, closeTo(point.dy, 1e-6), reason: 'y $index');
    }
  }

  testWidgets('standing on the camera row, the canvas draws its path — on '
      'its position lane too, and on no other row or lane', (tester) async {
    final (s, row) = panning();
    addTearDown(s.dispose);
    await pumpArea(tester, s);
    expect(cameraOf(s).isCameraLayerActive, isTrue, reason: '⛔전제');
    expect(path(), findsOneWidget);

    s.standOnRow(LaneRowAddress(row, 'position'));
    await tester.pump();
    expect(path(), findsOneWidget);

    s.standOnRow(LaneRowAddress(row, 'scale'));
    await tester.pump();
    expect(path(), findsNothing);

    final drawing = s.requireActiveCut.layers
        .firstWhere((layer) => layer.kind != LayerKind.camera)
        .id;
    s.standOnRow(LayerRowAddress(drawing));
    await tester.pump();
    expect(cameraOf(s).isCameraLayerActive, isFalse, reason: '⛔전제');
    expect(path(), findsNothing);

    await drain(tester);
  });

  testWidgets('it writes every key by its frame, and shown in time a cross '
      'at every frame between them; in space alone, the keys\' crosses only '
      '— and off, nothing', (tester) async {
    final (s, _) = panning();
    addTearDown(s.dispose);
    await pumpArea(tester, s);
    expect(labels(tester), ['1f', '6f']);
    expect(armsOf(tester), 4 + 8, reason: 'two keys, and frames 1 to 4');

    CameraPathSettings.settings.value = const CameraPathSettings(
      show: CameraPathShow.space,
    );
    await tester.pump();
    expect(armsOf(tester), 4);

    CameraPathSettings.settings.value = const CameraPathSettings(
      show: CameraPathShow.off,
    );
    await tester.pump();
    expect(path(), findsNothing);

    await drain(tester);
  });

  testWidgets('a key\'s frame lands on the camera\'s frame as the canvas '
      'draws it there — through the view, and at the size the frame is being '
      'adjusted to', (tester) async {
    final (s, _) = panning();
    addTearDown(s.dispose);
    await pumpArea(tester, s);
    final view = tester.widget<CameraPathOverlay>(path()).viewport;
    expect(
      view.canvasToViewportOffset(CanvasPoint(x: 100, y: 50)),
      isNot(const Offset(100, 50)),
      reason: '⛔전제: the screen is not the canvas',
    );
    expectPoints(keyFrames(tester).first, frameDrawn(tester));

    s.selectFrameIndex(5);
    await tester.pump();
    expectPoints(keyFrames(tester).last, frameDrawn(tester));

    final size = cameraOf(s).cameraFrameSize;
    final adjusted = CanvasSize(
      width: size.width ~/ 2,
      height: size.height ~/ 2,
    );
    s.canvasAdjust.begin(CameraSizeDraft(size: adjusted));
    await tester.pump();
    expect(
      tester
          .widget<CameraFrameOverlay>(find.byType(CameraFrameOverlay))
          .cameraFrameSize,
      adjusted,
      reason: '⛔전제: the canvas draws the frame at the size it is given',
    );
    expectPoints(keyFrames(tester).last, frameDrawn(tester));

    s.canvasAdjust.end();
    await drain(tester);
  });

  testWidgets('it follows a camera edit while it is in flight — and writes '
      'nothing', (tester) async {
    final (s, row) = panning();
    addTearDown(s.dispose);
    await pumpArea(tester, s);
    final before = keyFrames(tester).last;
    final end = cameraOf(s).activeCutCameraTrack!.position.keyAt(5)!.value;

    s.laneVerbs.previewLaneValueAt(
      row,
      'position',
      5,
      '${end.x}, ${end.y + 100}',
      frameIsGlobal: false,
      scaleLinked: false,
    );
    await tester.pump();
    final view = tester.widget<CameraPathOverlay>(path()).viewport;
    final down =
        view.canvasToViewportOffset(CanvasPoint(x: 0, y: 100)) -
        view.canvasToViewportOffset(CanvasPoint(x: 0, y: 0));
    expectPoints(keyFrames(tester).last, [
      for (final corner in before) corner + down,
    ]);
    expect(
      s.requireActiveCut.camera.track.position.keyAt(5)!.value,
      end,
      reason: 'nothing is written while it is in flight',
    );

    s.laneVerbs.endLaneEditPreview();
    await drain(tester);
  });

  testWidgets('around the playhead it keeps to so many frames either side, '
      'and goes with the playhead', (tester) async {
    final (s, _) = panning();
    addTearDown(s.dispose);
    CameraPathSettings.settings.value = const CameraPathSettings(
      range: CameraPathRange.aroundPlayhead,
      around: 2,
    );
    await pumpArea(tester, s);
    expect(labels(tester), ['1f']);
    expect(armsOf(tester), 2 + 4, reason: 'the key at 0, frames 1 and 2');

    s.selectFrameIndex(5);
    await tester.pump();
    expect(labels(tester), ['6f']);
    expect(armsOf(tester), 2 + 4, reason: 'frames 3 and 4, the key at 5');

    await drain(tester);
  });

  testWidgets('each of its settings reaches the canvas on its own', (
    tester,
  ) async {
    final (s, _) = panning();
    addTearDown(s.dispose);
    await pumpArea(tester, s);
    Future<void> change(
      CameraPathSettings Function(CameraPathSettings now) to,
    ) async {
      CameraPathSettings.settings.value = to(CameraPathSettings.settings.value);
      await tester.pump();
    }

    expect(armsOf(tester), 4 + 8, reason: '⛔전제: a cross at every frame');
    await change((now) => now.copyWith(tickEvery: 2));
    expect(armsOf(tester), 4 + 4, reason: 'frames 2 and 4');

    await change((now) => now.copyWith(around: 2));
    expect(labels(tester), ['1f', '6f'], reason: 'every key, however near');
    await change((now) => now.copyWith(range: CameraPathRange.aroundPlayhead));
    expect(labels(tester), ['1f']);
    expect(armsOf(tester), 2 + 2, reason: 'the key at 0, frame 2');

    await change((now) => now.copyWith(around: 4));
    expect(armsOf(tester), 2 + 4, reason: 'the key at 0, frames 2 and 4');

    await drain(tester);
  });

  testWidgets('its crosses in time wear where the playhead stands — grey '
      'behind it, blue ahead, ink on it — and are painted again as it '
      'moves', (tester) async {
    final (s, _) = panning();
    addTearDown(s.dispose);
    s.selectFrameIndex(2);
    await pumpArea(tester, s);
    List<int> ticks() => [
      for (final mark in marks(tester))
        if (mark is SheetStroke && mark.width == CameraPathOverlay.tickWidth)
          mark.argb,
    ];
    CustomPainter painter() => tester
        .widget<CustomPaint>(
          find.byKey(const ValueKey<String>('camera-path-overlay')),
        )
        .painter!;

    expect(ticks(), [grey, grey, ink, ink, blue, blue, blue, blue]);
    final before = painter();
    s.selectFrameIndex(3);
    await tester.pump();
    expect(ticks(), [grey, grey, grey, grey, ink, ink, blue, blue]);
    expect(painter().shouldRepaint(before), isTrue);

    await drain(tester);
  });

  testWidgets('a run shows the film: no path while it plays', (tester) async {
    final (s, _) = panning();
    addTearDown(s.dispose);
    await pumpArea(tester, s);
    expect(path(), findsOneWidget, reason: '⛔전제');

    s.playbackRig.playback.play(scope: PlaybackScope.activeCut);
    await tester.pump();
    expect(path(), findsNothing);

    s.playbackRig.playback.stop();
    await drain(tester);
  });

  group('the path is built again', () {
    test('for another track, and kept while the track is the same', () {
      final (s, _) = panning();
      addTearDown(s.dispose);
      final camera = cameraOf(s);
      final size = camera.cameraFrameSize;
      final first = camera.activeCutCameraPath(size);
      expect(first, isNotNull, reason: '⛔전제: the camera moves');
      expect(camera.activeCutCameraPath(size), same(first));

      s.selectFrameIndex(3);
      camera.setCameraKeyframeAtCurrentFrame(camera.cameraPoseAtCurrentFrame);
      final again = camera.activeCutCameraPath(size);
      expect(again, isNot(same(first)));
      expect(again!.keys.map((key) => key.frameIndex), [0, 3, 5]);
    });

    test('for another size of frame, its frames that size', () {
      final (s, _) = panning();
      addTearDown(s.dispose);
      final camera = cameraOf(s);
      final size = camera.cameraFrameSize;
      final whole = camera.activeCutCameraPath(size);
      final half = CanvasSize(width: size.width ~/ 2, height: size.height ~/ 2);
      final halved = camera.activeCutCameraPath(half)!;
      expect(halved, isNot(same(whole)));
      final top = halved.keys.first.corners[1] - halved.keys.first.corners[0];
      expect(
        top.distance,
        closeTo(half.width.toDouble(), 1e-9),
        reason: 'at zoom 1, a frame as wide as it is asked to be',
      );
    });

    test('for its cut\'s canvas resized under the same track', () {
      final s = EditorSessionManager(initialProject: createDefaultProject());
      addTearDown(s.dispose);
      final row = s.requireActiveCut.layers
          .firstWhere((layer) => layer.kind == LayerKind.camera)
          .id;
      for (final (frame, percent) in const [(0, '100'), (5, '200')]) {
        s.laneVerbs.setLaneValueAt(
          row,
          'scale',
          frame,
          percent,
          frameIsGlobal: false,
          description: 'Set Scale',
          scaleLinked: true,
        );
      }
      final camera = cameraOf(s);
      final size = camera.cameraFrameSize;
      expect(
        camera.activeCutCameraPath(size),
        isNotNull,
        reason: '⛔전제: a push-in moves the frame',
      );
      final track = camera.activeCutCameraTrack;
      final canvas = s.requireActiveCut.canvasSize;
      s.cutVerbs.resizeActiveCutCanvas(
        CanvasSize(width: canvas.width + 200, height: canvas.height + 100),
        anchor: CanvasResizeAnchor.topLeft,
      );
      expect(
        camera.activeCutCameraTrack,
        same(track),
        reason: '⛔전제: a canvas grown from its top-left moves no key',
      );
      expect(
        camera.activeCutCameraPath(size)!.keys.first.corners,
        cameraFrameShownAt(s.requireActiveCut, size, 0),
        reason: 'a camera keyed on no place stands at the middle of the '
            'canvas it has now',
      );
    });
  });
}

/// The collaborator that holds the path's memo, under its own name.
Camera cameraOf(EditorSessionManager session) => session.camera;
