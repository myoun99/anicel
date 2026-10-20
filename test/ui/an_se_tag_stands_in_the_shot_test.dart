// AN SE ROW'S NAME TAG STANDS IN THE SHOT (I-67).
//
// 🗣️유저 2026-10-04: 「이 보이는 이름표는 카메라의 위치를 기준으로
// 자리잡게하고싶음 … 근본적인 구조적으로 해결하고싶음. 프로들이 하는
// 방식대로?」 · I-67-Q1 (10-10): 「이름표를 카메라 화면 기준으로 읽는다」.
//
// The SE row's transform is the shot's, and every tag carries where its
// shot lies on the canvas at its frame: the camera moves, zooms and turns,
// and the tag stays where it stands in the frame.
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math_64.dart' show Vector3;

import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/camera_pose.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/property_track.dart';
import 'package:anicel/src/models/se_name_tag.dart';
import 'package:anicel/src/models/text_cel_style.dart';
import 'package:anicel/src/models/transform_track.dart';
import 'package:anicel/src/services/layer_pose_matrix.dart'
    show LayerPlacement;
import 'package:anicel/src/services/camera_frame_corners.dart';
import 'package:anicel/src/services/camera_projection_matrix.dart';
import 'package:anicel/src/services/se_name_tag_plan.dart';
import 'package:anicel/src/ui/canvas/canvas_viewport_offset.dart';
import 'package:anicel/src/ui/canvas/row_transform_box.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/editor_workspace.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/text/se_name_tag_paint.dart';
import 'package:anicel/src/ui/timeline/property_lane_model.dart'
    show laneGroupKey;
import 'package:anicel/src/ui/timeline/timeline_lane_provider.dart'
    show timelineLanesForLayer;
import 'package:anicel/src/ui/timeline/transform_lane_policy.dart'
    show formatTransformLaneValue, transformGroupHeaderLane;

import '../helpers/named_finders.dart';

void main() {
  const frame = CanvasSize(width: 1920, height: 1080);

  void expectPoint(CanvasPoint actual, CanvasPoint expected, String why) {
    expect(actual.x, closeTo(expected.x, 1e-6), reason: '$why (x)');
    expect(actual.y, closeTo(expected.y, 1e-6), reason: '$why (y)');
  }

  /// Where [point] of the canvas shows in [pose]'s frame.
  CanvasPoint inTheFrame(CameraPose pose, CanvasPoint point) {
    final shown = cameraProjectionMatrix(
      pose,
      frame,
    ).transform3(Vector3(point.x, point.y, 0));
    return CanvasPoint(x: shown.x, y: shown.y);
  }

  test('the shot lies on the canvas where the camera\'s frame does — at '
      'rest, panned, zoomed and turned', () {
    for (final pose in [
      CameraPose(center: CanvasPoint(x: 1170, y: 827)),
      CameraPose(center: CanvasPoint(x: 1470, y: 707)),
      CameraPose(center: CanvasPoint(x: 1170, y: 827), zoom: 2),
      CameraPose(center: CanvasPoint(x: 900, y: 600), rotationDegrees: 30),
      CameraPose(
        center: CanvasPoint(x: 1300, y: 700),
        zoom: 0.75,
        rotationDegrees: -12,
      ),
    ]) {
      final shot = shotPlacement(pose, frame);
      final corners = cameraFrameCornersInCanvas(
        pose: pose,
        cameraFrameSize: frame,
      );
      final shotCorners = [
        CanvasPoint(x: 0, y: 0),
        CanvasPoint(x: frame.width.toDouble(), y: 0),
        CanvasPoint(x: frame.width.toDouble(), y: frame.height.toDouble()),
        CanvasPoint(x: 0, y: frame.height.toDouble()),
      ];
      for (var i = 0; i < 4; i += 1) {
        expectPoint(
          shot.apply(shotCorners[i]),
          CanvasPoint(x: corners[i].dx, y: corners[i].dy),
          '$pose',
        );
      }
    }
  });

  test('the painter lays each tag through its shot before it draws', () async {
    const size = CanvasSize(width: 600, height: 200);
    const tag = ResolvedSeNameTag(
      layerId: 's1',
      widthBudget: 400,
      shot: LayerPlacement(1, 0, 0, 1, 300, 0),
      content: TextCelContent(
        text: 'A',
        style: SeNameTag.defaultStyle,
        position: Offset(100, 100),
      ),
    );
    final recorder = ui.PictureRecorder();
    paintSeNameTags(
      ui.Canvas(recorder),
      tags: [tag],
      canvasSize: size,
      rasterScale: 1,
    );
    final picture = recorder.endRecording();
    final image = picture.toImageSync(size.width, size.height);
    picture.dispose();
    final rgba = (await image.toByteData())!;
    image.dispose();
    int alphaAt(int x, int y) => rgba.getUint8((y * size.width + x) * 4 + 3);

    expect(alphaAt(400, 100), 255, reason: 'the box, 300 along — the shot');
    expect(alphaAt(100, 100), 0, reason: 'nothing where the shot\'s point is');
  });

  test('a camera move alone is a repaint — the tags\' signature reads their '
      'shot', () {
    ResolvedSeNameTag at(double x) => ResolvedSeNameTag(
      layerId: 's1',
      widthBudget: 400,
      shot: LayerPlacement(1, 0, 0, 1, x, 0),
      content: const TextCelContent(
        text: 'A',
        style: SeNameTag.defaultStyle,
        position: Offset(100, 100),
      ),
    );
    expect(seNameTagSignature([at(0)]), seNameTagSignature([at(0)]));
    expect(seNameTagSignature([at(0)]), isNot(seNameTagSignature([at(300)])));
  });

  /// A session on the default project, its first SE row speaking at frame
  /// 0 — the row stood on.
  EditorSessionManager speaking() {
    final s = EditorSessionManager(initialProject: createDefaultProject());
    addTearDown(s.dispose);
    final se = s.activeTrack.seLayers.first;
    s.selectLayer(se.id);
    s.selectFrameIndex(0);
    s.seEntries.createSeEntryAtCurrentFrame(name: 'おはよう', seName: 'タモツ');
    return s;
  }

  ResolvedSeNameTag tagOf(EditorSessionManager s) =>
      s.seEntries.seNameTagsForCutFrame(s.requireActiveCut, 0).single;

  /// Where [tag]'s anchor lies on the canvas.
  CanvasPoint onTheCanvas(ResolvedSeNameTag tag) => tag.placement.apply(
    CanvasPoint(x: tag.content.position!.dx, y: tag.content.position!.dy),
  );

  /// Where [tag]'s anchor lies in its shot — where its row lays it.
  CanvasPoint inTheShot(ResolvedSeNameTag tag) => tag.inShot.apply(
    CanvasPoint(x: tag.content.position!.dx, y: tag.content.position!.dy),
  );

  final centreOfTheFrame = CanvasPoint(
    x: frame.width / 2,
    y: frame.height / 2,
  );

  test('a camera that moves, zooms and turns leaves the tag where it stands '
      'in the frame', () {
    final s = speaking();
    final cut = s.requireActiveCut;
    final rest = CameraPose(
      center: CanvasPoint(
        x: cut.canvasSize.width / 2,
        y: cut.canvasSize.height / 2,
      ),
    );
    expectPoint(
      onTheCanvas(tagOf(s)),
      rest.center,
      '⛔전제: a camera at rest lays the shot\'s centre on the canvas centre',
    );

    final moved = CameraPose(
      center: CanvasPoint(x: rest.center.x + 300, y: rest.center.y - 120),
      zoom: 1.5,
      rotationDegrees: 20,
    );
    s.cutCommandCoordinator.setCutCameraKeyframe(
      cutId: cut.id,
      frameIndex: 0,
      pose: moved,
    );

    final tag = tagOf(s);
    expect(tag.shot, shotPlacement(moved, frame));
    expectPoint(
      inTheFrame(moved, onTheCanvas(tag)),
      centreOfTheFrame,
      'the frame\'s centre, as before the camera moved',
    );
  });

  test('a camera edit in flight carries the tag with it', () {
    final s = speaking();
    final cut = s.requireActiveCut;
    final panned = CameraPose(
      center: CanvasPoint(
        x: cut.canvasSize.width / 2 + 400,
        y: cut.canvasSize.height / 2,
      ),
    );
    s.camera.showCameraKeysDragPreview(
      TransformTrack.empty().copyWith(
        position: PropertyTrack<CanvasPoint>().withKey(0, panned.center),
      ),
    );
    addTearDown(() => s.camera.showCameraKeysDragPreview(null));

    expectPoint(
      onTheCanvas(tagOf(s)),
      panned.center,
      'where the camera is being dragged, not where it was',
    );
  });

  test('the timeline\'s lanes read an S row unkeyed in the shot\'s middle — '
      'as the storyboard\'s rail always did', () {
    final s = speaking();
    final se = s.activeTrack.seLayers.first;
    final lanes = timelineLanesForLayer(
      layer: s.layerById(se.id)!,
      session: s,
      expandedGroupKeys: {
        laneGroupKey(se.id, transformGroupHeaderLane.laneId),
      },
    );
    final position = lanes.singleWhere((lane) => lane.laneId == 'position');
    expect(
      position.valueLabel!(0),
      formatTransformLaneValue('position', layerIdentityPose(frame)),
    );
    expect(
      s.layerAnchorPointAtFrame(se, 0),
      centreOfTheFrame,
      reason: 'its anchor too',
    );
  });

  test('resetting an S row\'s transform puts its tag back in the shot\'s '
      'middle', () {
    final s = speaking();
    final se = s.activeTrack.seLayers.first;
    s.laneVerbs.setLaneValueAt(
      se.id,
      'position',
      0,
      '100, 200',
      frameIsGlobal: false,
      scaleLinked: false,
      description: 'Set Position',
    );
    expect(
      inTheShot(tagOf(s)),
      CanvasPoint(x: 100, y: 200),
      reason: '⛔전제: the row moved it',
    );

    expect(
      s.laneVerbs.resetLaneGroup(se.id, transformGroupHeaderLane.laneId),
      isTrue,
    );

    expect(
      inTheShot(tagOf(s)),
      centreOfTheFrame,
    );
  });

  // ---- the canvas's handle on the tag (F-222 ②) ----

  EditorSessionManager sessionOf(WidgetTester tester) =>
      tester.widget<EditorWorkspace>(find.byType(EditorWorkspace)).session;

  Future<void> tapNamed(WidgetTester tester, String name) async {
    final target = find.named(name);
    await tester.ensureVisible(target);
    await tester.pumpAndSettle();
    await tester.tap(target);
    await tester.pumpAndSettle();
  }

  RowTransformBox boxOf(WidgetTester tester) =>
      tester.widget<RowTransformBox>(find.byType(RowTransformBox));

  testWidgets('the handle stands where the camera lays the tag, and a drag '
      'comes back through the camera into the shot', (tester) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(home: HomePage(initialProject: createDefaultProject())),
    );
    await tester.pumpAndSettle();
    final s = sessionOf(tester);
    final cut = s.requireActiveCut;
    final se = s.activeTrack.seLayers.first;
    s.selectLayer(se.id);
    s.selectFrameIndex(0);
    s.seEntries.createSeEntryAtCurrentFrame(name: '쿵', seName: 'A');
    final panned = CameraPose(
      center: CanvasPoint(
        x: cut.canvasSize.width / 2 + 300,
        y: cut.canvasSize.height / 2,
      ),
    );
    s.cutCommandCoordinator.setCutCameraKeyframe(
      cutId: cut.id,
      frameIndex: 0,
      pose: panned,
    );
    await tester.pumpAndSettle();
    await tapNamed(tester, 'timeline-lane-toggle-${se.id.value}');
    // The header's NAME: the chevron twirls and the value cell edits, so
    // the label's text is what means 「stand here」.
    final header = find.byKey(
      ValueKey<String>(
        'timeline-lane-label-${se.id.value}-'
        '${transformGroupHeaderLane.laneId}',
      ),
    );
    await tester.ensureVisible(header);
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(of: header, matching: find.text('Transform')),
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();

    final box = boxOf(tester);
    expectPoint(
      box.pose.center,
      panned.center,
      'the tag stands at the shot\'s centre — the panned camera\'s',
    );
    final tag = tagOf(s);
    final corners = [
      for (final corner in box.corners) inTheFrame(panned, corner),
    ];
    expect(
      (corners[0].x + corners[2].x) / 2,
      closeTo(tag.content.position!.dx, 1e-6),
      reason: 'the box frames the tag where the shot holds it',
    );
    // And it is the TAG's box — the stand-in a row with no block shows
    // (F-387) stands at the same centre, the whole shot wide.
    final tagBox = seNameTagBoxBounds(tag, canvasSize: cut.canvasSize);
    expect(
      [corners[2].x - corners[0].x, corners[2].y - corners[0].y],
      [closeTo(tagBox.width, 1e-6), closeTo(tagBox.height, 1e-6)],
      reason: 'the box is the tag\'s own, not the shot it stands in',
    );

    // Inside the tag, a quarter across it — off the cross at its centre,
    // which is the anchor's and is grabbed first, as a layer's is (F-262).
    final edge = box.corners;
    final inside = CanvasPoint(
      x: edge[0].x * 0.75 + edge[1].x * 0.25,
      y: (edge[0].y + edge[3].y) / 2,
    );
    final grabbed = box.viewport.canvasToViewportOffset(inside);
    final letGo = grabbed + const Offset(40, 0);
    final dropped = box.viewport.viewportOffsetToCanvas(letGo);
    final travel = CanvasPoint(
      x: dropped.x - inside.x,
      y: dropped.y - inside.y,
    );
    final origin = tester.getTopLeft(find.byType(RowTransformBox));
    final gesture = await tester.startGesture(
      origin + grabbed,
      kind: PointerDeviceKind.mouse,
    );
    for (var step = 0; step < 4; step += 1) {
      await gesture.moveBy(const Offset(10, 0));
      await tester.pump();
    }
    await gesture.up();
    await tester.pumpAndSettle();

    final written = s.activeTrack.seLayers.first.transformTrack.position
        .keyAt(0)!
        .value;
    final landed = shotPlacement(panned, frame).apply(written);
    const why =
        'what is written is the shot\'s — through the camera it lands as far '
        'as the hand went';
    expect(landed.x, closeTo(box.pose.center.x + travel.x, 1), reason: why);
    expect(landed.y, closeTo(box.pose.center.y + travel.y, 1), reason: why);
  });
}
