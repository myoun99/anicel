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
import 'package:anicel/src/ui/theme/app_theme.dart' show AppColors;

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

  /// A cut whose camera turns a corner at frame 5, smooth there, stood on
  /// at frame 0 on its camera row. Its keys are smooth as they are made
  /// (I-89-Q10 B) — the ends are made corners again, so the key at 5 alone
  /// wears a handle of any length.
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
        position: track.position.withKeyPaths(frames: {0, 10}, curved: false),
      ),
    );
    s.selectFrameIndex(0);
    final row = s.requireActiveCut.layers
        .firstWhere((layer) => layer.kind == LayerKind.camera)
        .id;
    s.standOnRow(LayerRowAddress(row));
    return (s, row);
  }

  Future<void> pumpArea(
    WidgetTester tester,
    EditorSessionManager s, {
    CanvasTool tool = CanvasTool.brush,
  }) async {
    final brushTool = ValueNotifier<BrushToolState>(
      BrushToolState.defaults.copyWith(tool: tool),
    );
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

  /// The box's own paint: its chrome, and its paths' handles under it.
  Finder chrome() => find
      .descendant(
        of: find.byType(RowTransformBox),
        matching: find.byType(CustomPaint),
      )
      .first;

  CustomPainter painter(WidgetTester tester) =>
      tester.widget<CustomPaint>(chrome()).painter!;

  /// Where [at] on the canvas is on the tester's screen.
  Offset onScreen(WidgetTester tester, CanvasPoint at) =>
      tester.getTopLeft(find.byType(RowTransformBox)) +
      box(tester).viewport.canvasToViewportOffset(at);

  /// [screen] pixels of the screen, on the canvas.
  CanvasPoint onCanvas(WidgetTester tester, Offset screen) => box(
    tester,
  ).viewport.viewportDeltaToCanvasDelta(dx: screen.dx, dy: screen.dy);

  KeyPath pathAt(EditorSessionManager s, int frame) =>
      s.requireActiveCut.camera.track.position.keyAt(frame)!.path;

  KeyPath pathAt5(EditorSessionManager s) => pathAt(s, 5);

  /// The camera's keys at [frames] made smooth as well.
  void curve(EditorSessionManager s, Set<int> frames) {
    final track = s.camera.activeCutCameraTrack!;
    s.camera.updateActiveCutCameraTrack(
      track.copyWith(
        position: track.position.withKeyPaths(frames: frames, curved: true),
      ),
    );
  }

  /// Carries the knob at [from] by [travel] on the screen, and lets go.
  Future<void> carry(
    WidgetTester tester,
    CanvasPoint from,
    Offset travel,
  ) async {
    final gesture = await tester.startGesture(
      onScreen(tester, from),
      kind: PointerDeviceKind.mouse,
    );
    await gesture.moveBy(travel / 2);
    await gesture.moveBy(travel / 2);
    await gesture.up();
    await tester.pump();
  }

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

    // Drawn as the mock draws it: the grey line through the key, the passive
    // end behind (r 4, white, edged in the grey), the knob ahead (r 6.5,
    // white, edged in the accent).
    const grey = Color(0xFF7C8184);
    final view = box(tester).viewport;
    final knob = view.canvasToViewportOffset(shown.single.at);
    final end = view.canvasToViewportOffset(shown.single.behind);
    expect(
      chrome(),
      paints
        ..line(p1: end, p2: knob, color: grey)
        ..circle(x: end.dx, y: end.dy, radius: 4, color: Colors.white)
        ..circle(x: end.dx, y: end.dy, radius: 4, color: grey)
        ..circle(x: knob.dx, y: knob.dy, radius: 6.5, color: Colors.white)
        ..circle(
          x: knob.dx,
          y: knob.dy,
          radius: 6.5,
          color: AppColors.accent,
          strokeWidth: 2,
        ),
    );

    await drain(tester);
  });

  testWidgets('its tangent carried bends the key — shown while it moves, '
      'written where it is let go, its mirror behind, one undo', (
    tester,
  ) async {
    final (s, _) = turning();
    addTearDown(s.dispose);
    // The first key smooth too: its handle, of no length, stands on it —
    // and is the first of two.
    curve(s, {0});
    await pumpArea(tester, s);
    expect(tangents(tester), hasLength(2), reason: '⛔전제');
    expectNear(tangents(tester).first.at, c0, 'the end key\'s, on it');
    final from = tangents(tester).last.at;
    final trailBefore = tester
        .widget<CameraPathOverlay>(find.byType(CameraPathOverlay))
        .path
        .cornerTrailsBetween(0, 10)
        .toList();
    final paintedBefore = painter(tester);
    final cornersBefore = box(tester).corners;

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
    expectNear(tangents(tester).last.at, reached, 'the knob follows');
    expect(
      box(tester).corners,
      cornersBefore,
      reason: '⛔전제: the frame stood still',
    );
    expect(
      painter(tester).shouldRepaint(paintedBefore),
      isTrue,
      reason: 'the knob is drawn where it went',
    );
    expect(
      tester
          .widget<CameraPathOverlay>(find.byType(CameraPathOverlay))
          .path
          .cornerTrailsBetween(0, 10)
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
      tangents(tester).last.behind,
      CanvasPoint(x: c5.x - tangent.x, y: c5.y - tangent.y),
      'the mirror',
    );
    final key = s.requireActiveCut.camera.track.position.keyAt(5)!;
    expect(key.value, c5, reason: 'the key stays where it is');
    expect(pathAt(s, 0), KeyPath.auto, reason: 'the other key is as it was');

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

  testWidgets('under a tool that draws an area on the empty canvas the knob '
      'is still the box\'s, as its cross and its corners are', (tester) async {
    final (s, _) = turning();
    addTearDown(s.dispose);
    await pumpArea(tester, s, tool: CanvasTool.select);
    expect(tangents(tester), hasLength(1), reason: '⛔전제');

    await carry(tester, tangents(tester).single.at, const Offset(30, -20));
    expect(pathAt5(s), isA<HandledPath>());

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

    // Wherever the frame is worked, its path's handles are (유저 2026-10-12:
    // 「카메라 사각형 조작 가능한것처럼 거기 서야만 핸들이나 이런거
    // 조작하도록」) — on the camera's scale lane too.
    s.standOnRow(LaneRowAddress(row, 'scale'));
    await tester.pump();
    expect(tangents(tester), hasLength(1), reason: 'its scale lane');

    // Every key where the first is: the camera moves nothing, and no path
    // is drawn for the smooth key at 5 to wear its handle on.
    final track = s.camera.activeCutCameraTrack!;
    var still = track.position;
    for (final frame in [5, 10]) {
      still = still.withKey(frame, c0);
    }
    s.camera.updateActiveCutCameraTrack(track.copyWith(position: still));
    await tester.pump();
    expect(pathAt5(s), KeyPath.auto, reason: '⛔전제: still smooth');
    expect(tangents(tester), isEmpty, reason: 'no path drawn');

    await drain(tester);
  });
}
