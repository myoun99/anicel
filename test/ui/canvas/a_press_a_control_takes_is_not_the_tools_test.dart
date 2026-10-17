import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/timeline_row_address.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/editing/default_cut_helpers.dart';
import 'package:anicel/src/ui/brush/brush_canvas_panel.dart';
import 'package:anicel/src/ui/brush/brush_tool_state.dart';
import 'package:anicel/src/ui/camera/camera_frame_overlay.dart';
import 'package:anicel/src/ui/canvas/camera_adjust_layer.dart';
import 'package:anicel/src/ui/canvas/canvas_viewport_offset.dart';
import 'package:anicel/src/ui/canvas/row_transform_box.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/editor_workspace.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/session/canvas_adjust.dart';
import 'package:anicel/src/ui/text/app_strings.dart';
import 'package:anicel/src/ui/timeline/transform_lane_policy.dart'
    show transformGroupHeaderLane;

import '../../helpers/named_finders.dart';

/// 🗣️F-377 (유저 2026-10-17): 「카메라 레이어에서 카메라 옮길때도 브러시 커서
/// 뜬다거나 드로잉 허용안된 레이어라고 뜨는데 이거 몇번을 말하는지 모르겠는데
/// 안뜨도록. 커서도 브러시커서 뜨는거 이상하고. 게다가 카메라 사이즈를 프로젝트
/// 설정에서 캔버스에서 조정버튼통해 바꿀때도 뜸.」 — then 「그런 누름 관련, 입구
/// 확실하게 나눠서 근본/구조적으로 해결해줬으면」, and for the cursor (F-285):
/// 「카메라 레이어에선 그냥 기본커서로. 이런식으로 도구가 연관이 없는 곳에선
/// 기본커서. 트랜스폼fx든 뭐 그런거 전부」.
///
/// The real app, a real mouse and the BRUSH in hand: the camera's box and the
/// camera size's handles are controls, and a press one takes is never the
/// brush's.
void main() {
  const row = LayerId('pc-row');
  const cel = FrameId('pc-cel');
  const cutId = CutId('pc-cut');
  final camera = cameraLayerIdForCut(cutId);
  // Its middle lands where the canvas is on top at 100% (between the docks,
  // above the timeline) — a real pointer can only press what is on screen.
  const canvasSize = CanvasSize(width: 1300, height: 500);

  Project project() => Project(
    id: const ProjectId('pc-project'),
    name: 'Controls',
    createdAt: DateTime.utc(2026),
    tracks: [
      Track(
        id: const TrackId('pc-track'),
        name: 'Video Track',
        cuts: [
          Cut(
            id: cutId,
            name: 'pc-cut',
            duration: defaultCutDuration,
            canvasSize: canvasSize,
            layers: [
              Layer(
                id: row,
                name: 'A',
                frames: [
                  Frame(id: cel, name: 'c', duration: 1, strokes: const []),
                ],
                timeline: const {0: TimelineExposure.drawing(cel, length: 1)},
              ),
              createCameraLayer(cutId: cutId),
            ],
          ),
        ],
      ),
    ],
  );

  Future<void> pumpFrames(WidgetTester tester) async {
    for (var i = 0; i < 6; i += 1) {
      await tester.pump(const Duration(milliseconds: 16));
    }
  }

  Future<EditorSessionManager> open(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(home: HomePage(initialProject: project())),
    );
    await tester.pumpAndSettle();
    final session = tester
        .widget<EditorWorkspace>(find.byType(EditorWorkspace))
        .session;
    return session;
  }

  BrushCanvasPanel canvas(WidgetTester tester) => tester.widget(
    find.byKey(const ValueKey<String>('main-canvas-brush-host')),
  );

  /// Whether the cursor says the row takes no drawing — read by hand, not
  /// settled: the notice is transient.
  bool toldNotDrawable() => find
      .text(AppText.strings.noticeLayerNotDrawable)
      .evaluate()
      .isNotEmpty;

  /// Where [point] on the canvas shows on the screen, through [box]'s view.
  Offset onScreen(WidgetTester tester, Finder box, CanvasPoint point) =>
      tester.getTopLeft(box) +
      tester.widget<RowTransformBox>(box).viewport.canvasToViewportOffset(
        point,
      );

  testWidgets('standing on the camera row with the brush, a drag of the '
      'camera moves it and says nothing', (tester) async {
    final session = await open(tester);
    session.selectLayer(camera);
    await pumpFrames(tester);
    expect(
      canvas(tester).brushToolState?.value.tool,
      CanvasTool.brush,
      reason: 'the premise: the brush in hand',
    );
    final box = find.descendant(
      of: find.byType(CameraFrameBox),
      matching: find.byType(RowTransformBox),
    );
    final before = session.camera.cameraPoseAtCurrentFrame.center;

    final drag = await tester.startGesture(
      onScreen(tester, box, tester.widget<RowTransformBox>(box).pose.center),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    expect(toldNotDrawable(), isFalse, reason: '「… 안뜨도록」');
    for (var step = 0; step < 4; step += 1) {
      await drag.moveBy(const Offset(12, 6));
      await tester.pump();
    }
    expect(toldNotDrawable(), isFalse);
    await drag.up();
    await tester.pumpAndSettle();

    expect(
      session.requireActiveCut.camera.keyframeAt(0)!.center.x,
      greaterThan(before.x + 1),
      reason: '⛔CONTROL: the box took the drag',
    );
    session.playbackRig.prerenderScheduler.cancel();
  });

  testWidgets('the camera size\'s handles take their drag and say nothing; '
      'a paint press beside them on the camera row is still told why', (
    tester,
  ) async {
    final session = await open(tester);
    // Small enough that its corners lie on screen too.
    session.camera.setProjectCameraSize(
      const CanvasSize(width: 200, height: 150),
    );
    session.selectLayer(camera);
    await pumpFrames(tester);
    // What the canvas adjust button of the project's camera size opens
    // (`ProjectSettingsMenu._editCameraSize`).
    session.canvasAdjust.begin(
      CameraSizeDraft(size: session.camera.cameraFrameSize),
    );
    await pumpFrames(tester);
    final box = find.descendant(
      of: find.byType(CameraAdjustLayer),
      matching: find.byType(RowTransformBox),
    );
    final adjust = tester.widget<RowTransformBox>(box);

    final drag = await tester.startGesture(
      onScreen(tester, box, adjust.corners[2]),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    expect(toldNotDrawable(), isFalse, reason: '「… 조정버튼통해 바꿀때도 뜸」');
    for (var step = 0; step < 2; step += 1) {
      await drag.moveBy(const Offset(20, 15));
      await tester.pump();
    }
    expect(toldNotDrawable(), isFalse);
    await drag.up();
    await tester.pumpAndSettle();
    expect(
      (session.canvasAdjust.draft! as CameraSizeDraft).size.width,
      greaterThan(200),
      reason: '⛔CONTROL: the handle took the drag',
    );

    // The frame's middle is no handle: the canvas there is the tool's
    // (I-79), and the camera row takes no stroke (R26 #35).
    final press = await tester.startGesture(
      onScreen(tester, box, tester.widget<RowTransformBox>(box).pose.center),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    expect(
      toldNotDrawable(),
      isTrue,
      reason: '⛔CONTROL: the notice is there to be seen in this harness',
    );
    await press.up();
    await tester.pumpAndSettle();
    session.playbackRig.prerenderScheduler.cancel();
  });

  testWidgets('the brush wears no cursor of its own on a row that is no '
      'drawing surface — the camera\'s, a property lane — and wears it on a '
      'drawing row, hidden or not', (tester) async {
    final session = await open(tester);
    bool cursors() => canvas(tester).toolCursorsEnabled;

    session.selectLayer(row);
    await pumpFrames(tester);
    expect(cursors(), isTrue, reason: '⛔CONTROL: a drawing row');

    session.layerSwitches.toggleLayerVisibility(row);
    await pumpFrames(tester);
    expect(cursors(), isTrue, reason: 'a hidden row is still the tool\'s');
    session.layerSwitches.toggleLayerVisibility(row);
    await pumpFrames(tester);

    session.selectLayer(camera);
    await pumpFrames(tester);
    expect(cursors(), isFalse, reason: '「카메라 레이어에선 그냥 기본커서로」');

    session.selectLayer(row);
    await pumpFrames(tester);
    for (final toggle in [
      'timeline-lane-toggle-${row.value}',
      'timeline-lane-group-toggle-${row.value}-'
          '${transformGroupHeaderLane.laneId}',
    ]) {
      await tester.ensureVisible(find.named(toggle));
      await tester.pumpAndSettle();
      await tester.tap(find.named(toggle));
      await tester.pumpAndSettle();
    }
    session.standOnRow(const LaneRowAddress(row, 'position'));
    await pumpFrames(tester);
    expect(cursors(), isFalse, reason: '「트랜스폼fx든 뭐 그런거 전부」');
    session.playbackRig.prerenderScheduler.cancel();
  });
}
