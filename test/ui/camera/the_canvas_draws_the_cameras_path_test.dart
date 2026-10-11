import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/camera_path_settings.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/sheet_marks.dart';
import 'package:anicel/src/models/timeline_row_address.dart';
import 'package:anicel/src/ui/brush/brush_tool_state.dart';
import 'package:anicel/src/ui/camera/camera_path_overlay.dart';
import 'package:anicel/src/ui/editor_canvas_area.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/playback/canvas_playback_controller.dart'
    show PlaybackScope;
import 'package:anicel/src/ui/session/camera.dart';

import '../../helpers/canvas_pill.dart';

/// I-89 ④ — the camera's path on the canvas: drawn while one stands on the
/// camera row or its position lane (the confirmed spec of 2026-10-10:
/// 「카메라 행이나 그 위치 레인에 서 있을 때」), as the canvas's camera path
/// settings say — and those are in the canvas's ⚙ list (④-Q1, A while it
/// is asked).
void main() {
  void reset() =>
      CameraPathSettings.settings.value = const CameraPathSettings();
  setUp(reset);
  tearDown(reset);

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

  testWidgets('the canvas\'s ⚙ list holds how the path shows, and what is '
      'chosen there is the app\'s setting', (tester) async {
    final (s, _) = panning();
    addTearDown(s.dispose);
    await pumpArea(tester, s);

    await openViewSettings(tester);
    await tester.tap(find.byKey(const ValueKey('camera-path-show-space')));
    await tester.pump();
    await tester.tap(
      find.byKey(const ValueKey('camera-path-range-aroundPlayhead')),
    );
    await tester.pump();
    await tester.tap(
      find.byKey(const ValueKey('camera-path-tick-every-step-up')),
    );
    await tester.pump();
    await tester.tap(
      find.byKey(const ValueKey('camera-path-around-step-down')),
    );
    await tester.pump();
    expect(
      CameraPathSettings.settings.value,
      const CameraPathSettings(
        show: CameraPathShow.space,
        range: CameraPathRange.aroundPlayhead,
        tickEvery: 2,
        around: 11,
      ),
    );

    await tester.tapAt(Offset.zero);
    await drain(tester);
  });

  test('the path is built again for another track, and kept while the track '
      'is the same', () {
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
}

/// The collaborator that holds the path's memo, under its own name.
Camera cameraOf(EditorSessionManager session) => session.camera;
