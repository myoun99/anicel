import 'dart:typed_data';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/brush_frame_key.dart';
import 'package:anicel/src/models/camera_pose.dart';
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
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/timeline_row_address.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/camera_frame_corners.dart';
import 'package:anicel/src/services/camera_projection_matrix.dart'
    show shotPlacement;
import 'package:anicel/src/ui/brush/brush_tool_state.dart';
import 'package:anicel/src/ui/canvas/canvas_viewport_offset.dart';
import 'package:anicel/src/ui/canvas/row_transform_box.dart';
import 'package:anicel/src/ui/editor_canvas_area.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';

/// F-387 (유저 2026-10-17): 「그림이나 소재(se행의 se블록이 없는상태)가
/// 없을때 변형에 서면 움직여지는데 기준점은 움직이는게 안보인다던가 하는
/// 문제 해결. 위치 변형하듯 무언가 변형되는 박스를 임시로 만들어서
/// 조작중임을 표시하도록 … 특히 지금 se행 네임태그 se블록없는곳에서 변형
/// 조작되는데 화면엔 안보임」 — a row that shows nothing at the playhead
/// stands a box in its picture's place, the whole of the space it is posed
/// in, and a drag on its transform moves that box as it moves a picture.
void main() {
  const row = LayerId('nb-row');
  const cel = FrameId('nb-cel');
  const canvas = CanvasSize(width: 1280, height: 720);
  final canvasCorners = [
    CanvasPoint(x: 0, y: 0),
    CanvasPoint(x: 1280, y: 0),
    CanvasPoint(x: 1280, y: 720),
    CanvasPoint(x: 0, y: 720),
  ];

  /// One drawing row over [canvas] — its cel exposed at every frame, or
  /// none at all where the row is [blank].
  EditorSessionManager sessionOn({required bool blank}) {
    final project = Project(
      id: const ProjectId('nb-project'),
      name: 'Nothing',
      createdAt: DateTime.utc(2026),
      tracks: [
        Track(
          id: const TrackId('nb-track'),
          name: 'Video Track',
          cuts: [
            Cut(
              id: const CutId('nb-cut'),
              name: 'nb-cut',
              duration: 12,
              canvasSize: canvas,
              layers: [
                Layer(
                  id: row,
                  name: 'A',
                  frames: blank
                      ? const []
                      : [
                          Frame(
                            id: cel,
                            name: 'c',
                            duration: 1,
                            strokes: const [],
                          ),
                        ],
                  timeline: blank
                      ? const {}
                      : const {0: TimelineExposure.drawing(cel, length: 12)},
                ),
              ],
            ),
          ],
        ),
      ],
    );
    final s = EditorSessionManager(initialProject: project);
    s.selectLayer(row);
    s.selectFrameIndex(0);
    return s;
  }

  /// Ink on [s]'s cel: one opaque tile, 64..80 across and 32..48 down.
  void ink(EditorSessionManager s) {
    const tileSize = 16;
    s.renderCaches.brushFrameStore.storeBakedSurface(
      const BrushFrameKey(
        projectId: ProjectId('nb-project'),
        trackId: TrackId('nb-track'),
        cutId: CutId('nb-cut'),
        layerId: row,
        frameId: cel,
      ),
      BitmapSurface(
        canvasSize: canvas,
        tileSize: tileSize,
        tiles: {
          TileCoord(x: 4, y: 2): BitmapTile(
            size: tileSize,
            pixels: Uint8List(tileSize * tileSize * 4)..fillRange(
              0,
              tileSize * tileSize * 4,
              0xFF,
            ),
          ),
        },
      ),
    );
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

  RowTransformBox boxOf(WidgetTester tester) =>
      tester.widget<RowTransformBox>(find.byType(RowTransformBox));

  /// Where [by] on the screen takes [from] of [box]'s viewport, on the
  /// canvas.
  CanvasPoint travelOf(RowTransformBox box, Offset from, Offset by) {
    final start = box.viewport.viewportOffsetToCanvas(from);
    final end = box.viewport.viewportOffsetToCanvas(from + by);
    return CanvasPoint(x: end.x - start.x, y: end.y - start.y);
  }

  /// A mouse drag from [from] of the box's viewport by [by], in four
  /// moves — answering the box as it stood before the hand let go.
  Future<RowTransformBox> dragged(
    WidgetTester tester,
    Offset from,
    Offset by,
  ) async {
    final origin = tester.getTopLeft(find.byType(RowTransformBox));
    final gesture = await tester.startGesture(
      origin + from,
      kind: PointerDeviceKind.mouse,
    );
    for (var step = 0; step < 4; step += 1) {
      await gesture.moveBy(by / 4);
      await tester.pump();
    }
    final midway = boxOf(tester);
    await gesture.up();
    await tester.pump();
    return midway;
  }

  void expectCorners(
    List<CanvasPoint> actual,
    List<CanvasPoint> expected,
    String why, {
    double within = 1e-6,
  }) {
    expect(actual, hasLength(expected.length), reason: why);
    for (var i = 0; i < expected.length; i += 1) {
      expect(actual[i].x, closeTo(expected[i].x, within), reason: '$why ($i)');
      expect(actual[i].y, closeTo(expected[i].y, within), reason: '$why ($i)');
    }
  }

  CanvasPoint moved(CanvasPoint point, CanvasPoint by, {double sign = 1}) =>
      CanvasPoint(x: point.x + by.x * sign, y: point.y + by.y * sign);

  testWidgets('a cel that shows nothing stands the canvas in its picture\'s '
      'place under the cross alone too — and the anchor\'s drag moves it the '
      'way it moves a picture', (tester) async {
    final s = sessionOn(blank: true);
    s.standOnRow(const LaneRowAddress(row, 'anchor-point'));
    await pumpArea(tester, s);

    final box = boxOf(tester);
    expect(box.move, isNull, reason: '⛔premise: the lane declares the cross');
    expect(box.cross, isNotNull, reason: '⛔premise: … and the cross alone');
    expectCorners(box.corners, canvasCorners, 'the canvas stands in for it');

    final grabbed = box.viewport.canvasToViewportOffset(box.cross!.at);
    const by = Offset(40, 0);
    final travel = travelOf(box, grabbed, by);
    final midway = await dragged(tester, grabbed, by);
    // The cross carries the anchor's value and stands where it lands, so
    // the picture — here its stand-in — goes the other way under it
    // (F-222-box-Q3).
    final shifted = [
      for (final corner in canvasCorners) moved(corner, travel, sign: -1),
    ];
    expectCorners(
      midway.corners,
      shifted,
      'what the drag does shows while it is dragged',
      within: 1,
    );

    final anchor = s.requireActiveCut.layers
        .byId(row)!
        .transformTrack
        .anchorPoint
        .keyAt(0)!
        .value;
    expect(anchor.x, closeTo(640 + travel.x, 1), reason: 'it keys the anchor');
    expect(anchor.y, closeTo(360, 1e-6), reason: 'it keys the anchor');
    expectCorners(
      boxOf(tester).corners,
      shifted,
      'and the box stays where the hand let go',
      within: 1,
    );
    await drain(tester);
  });

  testWidgets('a cel with a picture shows it moving itself — under the cross '
      'alone no box is drawn over it', (tester) async {
    final s = sessionOn(blank: false);
    ink(s);
    s.standOnRow(const LaneRowAddress(row, 'position'));
    await pumpArea(tester, s);
    expectCorners(boxOf(tester).corners, [
      CanvasPoint(x: 64, y: 32),
      CanvasPoint(x: 80, y: 32),
      CanvasPoint(x: 80, y: 48),
      CanvasPoint(x: 64, y: 48),
    ], '⛔premise: the box frames the ink — the cel shows something');

    s.standOnRow(const LaneRowAddress(row, 'anchor-point'));
    await tester.pump();
    final box = boxOf(tester);
    expect(box.cross, isNotNull, reason: '⛔premise: the cross stands');
    expect(box.corners, isEmpty, reason: 'the picture is what moves');
    await drain(tester);
  });

  testWidgets('an SE row with no block under the playhead stands the shot in '
      'its tag\'s place — where its position puts a tag — and a drag carries '
      'it there', (tester) async {
    final s = EditorSessionManager(initialProject: createDefaultProject());
    final cut = s.requireActiveCut;
    final se = s.activeTrack.seLayers.first;
    s.selectLayer(se.id);
    s.selectFrameIndex(0);
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
    s.standOnRow(LaneRowAddress(se.id, 'position'));
    await pumpArea(tester, s);
    expect(
      s.seEntries.seNameTagsForCutFrame(s.requireActiveCut, 0),
      isEmpty,
      reason: '⛔premise: no block, so no tag',
    );

    final frame = s.camera.cameraFrameSize;
    // An unmoved row's tag stands in the shot's middle, so the stand-in is
    // the shot itself: the panned camera's frame.
    final shot = [
      for (final corner in cameraFrameCornersInCanvas(
        pose: panned,
        cameraFrameSize: frame,
      ))
        CanvasPoint(x: corner.dx, y: corner.dy),
    ];
    final box = boxOf(tester);
    expectCorners(box.corners, shot, 'the shot stands in for the tag');

    final grabbed = box.viewport.canvasToViewportOffset(box.pose.center);
    const by = Offset(40, 0);
    final travel = travelOf(box, grabbed, by);
    final midway = await dragged(tester, grabbed, by);
    final carried = [for (final corner in shot) moved(corner, travel)];
    expectCorners(
      midway.corners,
      carried,
      'it follows the hand, as a tag would',
      within: 1,
    );

    final written = s.activeTrack.seLayers.first.transformTrack.position
        .keyAt(0)!
        .value;
    final landed = shotPlacement(panned, frame).apply(written);
    const why = 'it keys the position, in the shot';
    expect(landed.x, closeTo(box.pose.center.x + travel.x, 1), reason: why);
    expect(landed.y, closeTo(box.pose.center.y, 1), reason: why);
    expectCorners(
      boxOf(tester).corners,
      carried,
      'and it stays where the hand let go',
      within: 1,
    );
    await drain(tester);
  });

  testWidgets('another SE row\'s tag under the playhead is not this row\'s — '
      'with no block of its own the row still stands the shot', (
    tester,
  ) async {
    final s = EditorSessionManager(initialProject: createDefaultProject());
    final cut = s.requireActiveCut;
    final tagged = s.activeTrack.seLayers.first;
    final bare = s.activeTrack.seLayers.last;
    s.selectLayer(tagged.id);
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
    s.selectLayer(bare.id);
    s.standOnRow(LaneRowAddress(bare.id, 'position'));
    await pumpArea(tester, s);
    expect(
      [
        for (final tag in s.seEntries.seNameTagsForCutFrame(
          s.requireActiveCut,
          0,
        ))
          tag.layerId,
      ],
      [tagged.id.value],
      reason: '⛔premise: the one tag under the playhead is the other row\'s',
    );

    final shot = [
      for (final corner in cameraFrameCornersInCanvas(
        pose: panned,
        cameraFrameSize: s.camera.cameraFrameSize,
      ))
        CanvasPoint(x: corner.dx, y: corner.dy),
    ];
    expectCorners(
      boxOf(tester).corners,
      shot,
      'the stand-in is where this row\'s own tag would stand',
    );
    await drain(tester);
  });
}
