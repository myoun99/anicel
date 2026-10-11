import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/camera_path_settings.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/property_track.dart';
import 'package:anicel/src/models/timeline_row_address.dart';
import 'package:anicel/src/ui/brush/brush_tool_state.dart';
import 'package:anicel/src/ui/camera/camera_path_overlay.dart';
import 'package:anicel/src/ui/canvas/canvas_viewport_offset.dart';
import 'package:anicel/src/ui/canvas/row_transform_box.dart';
import 'package:anicel/src/ui/editor_canvas_area.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';

/// I-89 ④ 3b — a curved key's handle on the canvas, the mock's 5판: shown
/// with the camera's path in time, its tangent carried by the hand bends
/// the key through it — the other side its mirror (④-Q4 A: 「캔버스에서 끈
/// 접선 — 반대쪽은 거울」), one undo where it is let go.
void main() {
  void reset() =>
      CameraPathSettings.settings.value = const CameraPathSettings();
  setUp(reset);
  tearDown(reset);

  /// The camera's centre at its keys: 0, then 200 right at frame 5, then
  /// 150 down at frame 10 — the key at 5 smooth.
  late CanvasPoint c0;
  late CanvasPoint c5;
  late CanvasPoint c10;

  /// A cut whose camera turns a corner at frame 5, made smooth there, stood
  /// on at frame 0 on its camera row.
  (EditorSessionManager, LayerId) turning() {
    final s = EditorSessionManager(initialProject: createDefaultProject());
    final camera = s.camera;
    s.selectFrameIndex(0);
    final start = camera.cameraPoseAtCurrentFrame;
    c0 = start.center;
    c5 = CanvasPoint(x: c0.x + 200, y: c0.y);
    c10 = CanvasPoint(x: c0.x + 200, y: c0.y + 150);
    camera.setCameraKeyframeAtCurrentFrame(start);
    for (final (frame, center) in [(5, c5), (10, c10)]) {
      s.selectFrameIndex(frame);
      camera.setCameraKeyframeAtCurrentFrame(start.copyWith(center: center));
    }
    final track = camera.activeCutCameraTrack!;
    camera.updateActiveCutCameraTrack(
      track.copyWith(
        position: track.position.withKeyPaths(frames: {5}, curved: true),
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

  RowTransformBox box(WidgetTester tester) =>
      tester.widget<RowTransformBox>(find.byType(RowTransformBox));

  List<RowBoxTangent> tangents(WidgetTester tester) => box(tester).tangents;

  /// Where [at] on the canvas is on the tester's screen.
  Offset onScreen(WidgetTester tester, CanvasPoint at) =>
      tester.getTopLeft(find.byType(RowTransformBox)) +
      box(tester).viewport.canvasToViewportOffset(at);

  /// [screen] pixels of the screen, on the canvas.
  CanvasPoint onCanvas(WidgetTester tester, Offset screen) => box(
    tester,
  ).viewport.viewportDeltaToCanvasDelta(dx: screen.dx, dy: screen.dy);

  KeyPath pathAt5(EditorSessionManager s) =>
      s.requireActiveCut.camera.track.position.keyAt(5)!.path;

  void expectNear(CanvasPoint actual, CanvasPoint expected, String what) {
    expect(actual.x, closeTo(expected.x, 1e-6), reason: '$what x');
    expect(actual.y, closeTo(expected.y, 1e-6), reason: '$what y');
  }

  testWidgets('a smooth key wears its handle where the path is shown in '
      'time: its tangent a third of the way to the key after, along the '
      'line through its neighbours, its passive end behind', (tester) async {
    final (s, _) = turning();
    addTearDown(s.dispose);
    await pumpArea(tester, s);

    final shown = tangents(tester);
    expect(shown, hasLength(1), reason: 'the corners at 0 and 10 have none');
    // Through its neighbours: (200, 150), 250 long — 150 / 3 ahead,
    // 200 / 3 behind.
    expectNear(
      shown.single.at,
      CanvasPoint(x: c5.x + 40, y: c5.y + 30),
      'at',
    );
    expectNear(
      shown.single.behind,
      CanvasPoint(x: c5.x - 160 / 3, y: c5.y - 40),
      'behind',
    );

    await drain(tester);
  });

  testWidgets('its tangent carried bends the key — shown while it moves, '
      'written where it is let go, its mirror behind, one undo', (
    tester,
  ) async {
    final (s, _) = turning();
    addTearDown(s.dispose);
    await pumpArea(tester, s);
    final from = tangents(tester).single.at;
    final trailBefore = tester
        .widget<CameraPathOverlay>(find.byType(CameraPathOverlay))
        .path
        .trailBetween(0, 10)
        .toList();

    const travel = Offset(30, -20);
    final gesture = await tester.startGesture(
      onScreen(tester, from),
      kind: PointerDeviceKind.mouse,
    );
    await gesture.moveBy(travel / 2);
    await gesture.moveBy(travel / 2);
    await tester.pump();

    final carried = onCanvas(tester, travel);
    final reached = CanvasPoint(x: from.x + carried.x, y: from.y + carried.y);
    expectNear(tangents(tester).single.at, reached, 'the knob follows');
    expect(
      tester
          .widget<CameraPathOverlay>(find.byType(CameraPathOverlay))
          .path
          .trailBetween(0, 10)
          .toList(),
      isNot(trailBefore),
      reason: 'the path follows it',
    );
    expect(pathAt5(s), KeyPath.auto, reason: 'nothing written in flight');

    await gesture.up();
    await tester.pump();
    final bent = pathAt5(s);
    expect(bent, isA<HandledPath>());
    final tangent = (bent as HandledPath).tangent;
    expectNear(
      tangent,
      CanvasPoint(x: reached.x - c5.x, y: reached.y - c5.y),
      'the tangent',
    );
    expectNear(
      tangents(tester).single.behind,
      CanvasPoint(x: c5.x - tangent.x, y: c5.y - tangent.y),
      'the mirror',
    );
    final key = s.requireActiveCut.camera.track.position.keyAt(5)!;
    expect(key.value, c5, reason: 'the key stays where it is');

    s.undo();
    await tester.pump();
    expect(pathAt5(s), KeyPath.auto, reason: 'one undo');

    await drain(tester);
  });

  testWidgets('beside its knob the press is the box\'s own — the knob is '
      'taken on the disc it is drawn as', (tester) async {
    final (s, _) = turning();
    addTearDown(s.dispose);
    await pumpArea(tester, s);
    final before = s.requireActiveCut.camera.track;
    final knob = onScreen(tester, tangents(tester).single.at);

    final gesture = await tester.startGesture(
      knob + const Offset(7, 7),
      kind: PointerDeviceKind.mouse,
    );
    await gesture.moveBy(const Offset(20, 0));
    await gesture.moveBy(const Offset(20, 0));
    await gesture.up();
    await tester.pump();

    expect(pathAt5(s), KeyPath.auto, reason: 'the knob was not taken');
    expect(
      s.requireActiveCut.camera.track,
      isNot(before),
      reason: '⛔전제: the box took the press as its own',
    );

    await drain(tester);
  });

  testWidgets('no handle in space alone, nor off the frames the path is '
      'drawn for, nor where the path is not drawn', (tester) async {
    final (s, row) = turning();
    addTearDown(s.dispose);
    await pumpArea(tester, s);
    expect(tangents(tester), hasLength(1), reason: '⛔전제');

    CameraPathSettings.settings.value = const CameraPathSettings(
      show: CameraPathShow.space,
    );
    await tester.pump();
    expect(tangents(tester), isEmpty, reason: 'in space alone');

    CameraPathSettings.settings.value = const CameraPathSettings(
      range: CameraPathRange.aroundPlayhead,
      around: 2,
    );
    await tester.pump();
    expect(tangents(tester), isEmpty, reason: 'frames 0 to 2');
    s.selectFrameIndex(4);
    await tester.pump();
    expect(tangents(tester), hasLength(1), reason: 'frames 2 to 6');

    s.standOnRow(LaneRowAddress(row, 'scale'));
    await tester.pump();
    expect(box(tester).tangents, isEmpty, reason: 'off the position lane');
    s.standOnRow(LaneRowAddress(row, 'position'));
    await tester.pump();
    expect(tangents(tester), hasLength(1), reason: 'on it');

    await drain(tester);
  });
}
