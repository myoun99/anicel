import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/brush_dab.dart';
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
import 'package:anicel/src/ui/brush/brush_tool_state.dart';
import 'package:anicel/src/ui/canvas/canvas_selection_layer.dart';
import 'package:anicel/src/ui/canvas/canvas_viewport_offset.dart';
import 'package:anicel/src/ui/canvas/row_transform_box.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/editor_workspace.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/timeline/transform_lane_policy.dart'
    show transformGroupHeaderLane;

/// 🗣️F-222 (유저 2026-09-28): 「변형툴 사용시 내부 사각형 드래그하면
/// 이동한다던가. 바깥은 회전이라던가. 이런거 싹 fx에 서있을때도 조작할떄
/// 가능하도록. 지금은 브러시도구인상태로 fx서있을때 조작하려하면
/// 프레임없다거나 그런거뜸」 — and F-222-box-Q4 「선택 · 잘라내기만 빼고
/// 모든 도구」.
///
/// Standing on a row's transform, the CANVAS is that row's box under every
/// tool but the two that draw an area on it; under those two the box keeps
/// its corners and its cross, and the empty canvas is the tool's.
void main() {
  const row = LayerId('ro-row');
  const cel = FrameId('ro-cel');
  const cutId = CutId('ro-cut');
  final camera = cameraLayerIdForCut(cutId);
  // Its centre lands where the canvas is on top at 100% (between the docks,
  // above the timeline) — a real pointer can only press what is on screen.
  const canvasSize = CanvasSize(width: 1300, height: 500);
  final centre = CanvasPoint(
    x: canvasSize.width / 2,
    y: canvasSize.height / 2,
  );

  Project project() => Project(
    id: const ProjectId('ro-project'),
    name: 'Owner',
    createdAt: DateTime.utc(2026),
    tracks: [
      Track(
        id: const TrackId('ro-track'),
        name: 'Video Track',
        cuts: [
          Cut(
            id: cutId,
            name: 'ro-cut',
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

  EditorWorkspace workspaceOf(WidgetTester tester) =>
      tester.widget<EditorWorkspace>(find.byType(EditorWorkspace));

  Future<void> pumpFrames(WidgetTester tester) async {
    for (var i = 0; i < 6; i += 1) {
      await tester.pump(const Duration(milliseconds: 16));
    }
  }

  Future<void> useTool(WidgetTester tester, CanvasTool tool) async {
    final brush = workspaceOf(tester).brushTool!;
    brush.value = brush.value.copyWith(tool: tool);
    await pumpFrames(tester);
  }

  /// The app on the project with ink on the row's cel, standing on [standOn]
  /// with [tool] in hand.
  Future<EditorSessionManager> open(
    WidgetTester tester, {
    required RowAddressFor standOn,
    required CanvasTool tool,
  }) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(home: HomePage(initialProject: project())),
    );
    await tester.pumpAndSettle();
    final session = workspaceOf(tester).session;
    session.selectLayer(row);
    await pumpFrames(tester);
    final landed = session.pixelEditing.coordinator!.commitSourceStroke(
      sourceDabs: [
        BrushDab(
          center: CanvasPoint(x: centre.x + 30, y: centre.y + 20),
          color: 0xFF112233,
          size: 300,
          opacity: 1,
          flow: 1,
          hardness: 1,
          pressure: 1,
          sequence: 0,
        ),
      ],
      cacheInvalidationSink: session.renderCaches.cacheInvalidationHub,
    );
    expect(landed, isNotNull, reason: 'LIVENESS — the ink landed');
    await useTool(tester, tool);
    final address = standOn(session);
    session.selectLayer(address.layerId);
    await pumpFrames(tester);
    final toggle = find.byKey(
      ValueKey<String>('timeline-lane-toggle-${address.layerId.value}'),
    );
    await tester.ensureVisible(toggle);
    await tester.pumpAndSettle();
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    session.standOnRow(address);
    await pumpFrames(tester);
    return session;
  }

  RowTransformBox boxOf(WidgetTester tester) =>
      tester.widget<RowTransformBox>(find.byType(RowTransformBox));

  Offset onScreen(WidgetTester tester, CanvasPoint point) =>
      tester.getTopLeft(find.byType(RowTransformBox)) +
      boxOf(tester).viewport.canvasToViewportOffset(point);

  /// Inside the box and well clear of its cross and its corners — the
  /// picture is 300 wide, so seven tenths of the way to the far corner is
  /// over a hundred canvas pixels from each, a press the move takes at any
  /// zoom this view settles on.
  CanvasPoint awayFromTheHandles(List<CanvasPoint> corners) => CanvasPoint(
    x: corners[0].x + (corners[2].x - corners[0].x) * 0.7,
    y: corners[0].y + (corners[2].y - corners[0].y) * 0.7,
  );

  Future<void> drag(WidgetTester tester, Offset from, Offset by) async {
    final gesture = await tester.startGesture(
      from,
      kind: PointerDeviceKind.mouse,
    );
    for (var step = 0; step < 4; step += 1) {
      await gesture.moveBy(by / 4);
      await tester.pump();
    }
    await gesture.up();
    await pumpFrames(tester);
  }

  Layer committedRow(EditorSessionManager session) =>
      session.requireActiveCut.layers.byId(row)!;

  LaneRowAddress onTheTransform(EditorSessionManager session) =>
      LaneRowAddress(row, transformGroupHeaderLane.laneId);

  testWidgets('the BRUSH in hand, a drag inside the box moves the row — and '
      'draws nothing', (tester) async {
    final session = await open(
      tester,
      standOn: onTheTransform,
      tool: CanvasTool.brush,
    );
    final ink = session.renderCaches.layerContentBoundsAt(
      committedRow(session),
      0,
    );

    await drag(
      tester,
      onScreen(tester, awayFromTheHandles(boxOf(tester).corners)),
      const Offset(40, 0),
    );

    expect(
      committedRow(session).transformTrack.position.keyAt(0),
      isNotNull,
      reason: 'the box moved the row',
    );
    expect(
      session.renderCaches.layerContentBoundsAt(committedRow(session), 0),
      ink,
      reason: 'no stroke landed on the cel',
    );
  });

  testWidgets('the TRANSFORM tool in hand, the row\'s box is grabbed — not '
      'the cel\'s pixels', (tester) async {
    final session = await open(
      tester,
      standOn: onTheTransform,
      tool: CanvasTool.move,
    );
    final ink = session.renderCaches.layerContentBoundsAt(
      committedRow(session),
      0,
    );

    await drag(
      tester,
      onScreen(tester, awayFromTheHandles(boxOf(tester).corners)),
      const Offset(40, 0),
    );

    expect(committedRow(session).transformTrack.position.keyAt(0), isNotNull);
    final commands = tester
        .widget<CanvasSelectionLayer>(find.byType(CanvasSelectionLayer).first)
        .selectionCommands!;
    expect(commands.transformActive, isFalse, reason: 'no pixel box opened');
    expect(
      session.renderCaches.layerContentBoundsAt(committedRow(session), 0),
      ink,
    );
  });

  testWidgets('the SELECT tool in hand, the inside of the box is the '
      'marquee\'s — and a corner is still the box\'s', (tester) async {
    final session = await open(
      tester,
      standOn: onTheTransform,
      tool: CanvasTool.select,
    );
    final commands = tester
        .widget<CanvasSelectionLayer>(find.byType(CanvasSelectionLayer).first)
        .selectionCommands!;
    expect(commands.region, isNull, reason: 'the premise');

    await drag(
      tester,
      onScreen(tester, awayFromTheHandles(boxOf(tester).corners)),
      const Offset(40, 30),
    );
    expect(commands.region, isNotNull, reason: 'a marquee was drawn');
    expect(
      committedRow(session).transformTrack.position.isEmpty,
      isTrue,
      reason: 'the row did not move',
    );

    await drag(
      tester,
      onScreen(tester, boxOf(tester).corners[2]),
      const Offset(30, 30),
    );
    expect(
      committedRow(session).transformTrack.scale.keyAt(0),
      isNotNull,
      reason: 'the corner is the box\'s whatever tool is in hand',
    );
  });

  // 🗣️유저 2026-10-01: 「ae랑 똑같으면 문제없어. 애초에 트랜스폼 fx는
  // 똑같도록하는게 목표」 — After Effects draws the anchor where it lands.
  testWidgets('the cross stands where the anchor LANDS — moved with the '
      'position, the centre the box turns about — and a drag on it keys the '
      'anchor alone, the cross staying with the position', (tester) async {
    // Which press takes which grab is the box's own law, pinned with real
    // pointers in `row_transform_box_test`; what is asked HERE is where the
    // canvas stands the cross and what each landing keys.
    final session = await open(
      tester,
      standOn: onTheTransform,
      tool: CanvasTool.brush,
    );
    final box = boxOf(tester);
    box.move!.committed(
      CanvasPoint(x: box.pose.center.x + 60, y: box.pose.center.y),
    );
    await pumpFrames(tester);
    final moved = boxOf(tester);
    expect(
      moved.pose.center.x,
      closeTo(box.pose.center.x + 60, 0.001),
      reason: 'the premise: the row moved',
    );
    expect(
      moved.cross!.at,
      moved.pose.center,
      reason: 'the cross went with the position — AE\'s mark, never apart '
          'from the pivot',
    );

    final positionBefore = committedRow(session).transformTrack.position
        .keyAt(0)!
        .value;
    final value = moved.cross!.value;
    moved.cross!.landing.committed(CanvasPoint(x: value.x, y: value.y + 40));
    await pumpFrames(tester);

    final track = committedRow(session).transformTrack;
    expect(track.anchorPoint.keyAt(0), isNotNull, reason: 'the anchor keyed');
    expect(
      track.position.keyAt(0)!.value,
      positionBefore,
      reason: 'and only the anchor — the position is untouched',
    );
    expect(
      boxOf(tester).cross!.at,
      moved.cross!.at,
      reason: 'so the cross stays where the position is, and the picture '
          'moved under it',
    );
  });

  testWidgets('the CAMERA row, the brush in hand: a drag inside the frame '
      'moves the camera', (tester) async {
    final session = await open(
      tester,
      standOn: (_) => LaneRowAddress(camera, 'position'),
      tool: CanvasTool.brush,
    );

    await drag(
      tester,
      onScreen(tester, boxOf(tester).pose.center),
      const Offset(40, 0),
    );

    expect(session.requireActiveCut.camera.keyframeAt(0), isNotNull);
  });

  testWidgets('an SE row\'s box is its name tag, and it only MOVES — no '
      'corner, no cross, no turn', (tester) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(home: HomePage(initialProject: createDefaultProject())),
    );
    await tester.pumpAndSettle();
    final session = workspaceOf(tester).session;
    final se = session.activeTrack.seLayers.first;
    session.selectLayer(se.id);
    session.selectFrameIndex(0);
    session.seEntries.createSeEntryAtCurrentFrame(name: '쿵', seName: 'A');
    await pumpFrames(tester);
    final toggle = find.byKey(
      ValueKey<String>('timeline-lane-toggle-${se.id.value}'),
    );
    await tester.ensureVisible(toggle);
    await tester.pumpAndSettle();
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    session.standOnRow(LaneRowAddress(se.id, 'position'));
    await pumpFrames(tester);

    final box = boxOf(tester);
    expect(box.scale, isNull);
    expect(box.turn, isNull);
    expect(box.cross, isNull);
    final corners = box.corners;
    expect(
      corners[2].x - corners[0].x,
      lessThan(session.requireActiveCut.canvasSize.width / 2),
      reason: 'the box frames the tag, not the canvas',
    );

    // The press itself is the box's law (`row_transform_box_test`); this
    // asks that the SE row's move lands on the tag.
    final to = CanvasPoint(x: box.pose.center.x + 40, y: box.pose.center.y);
    box.move!.committed(to);
    await pumpFrames(tester);

    final after = boxOf(tester);
    expect(after.pose.center.x, closeTo(to.x, 0.001), reason: 'it moved');
    expect(
      after.corners[0].x - corners[0].x,
      closeTo(40, 0.5),
      reason: 'and the tag\'s box with it',
    );
  });
}

/// Where to stand, asked of the session once it is up.
typedef RowAddressFor = LaneRowAddress Function(EditorSessionManager session);
