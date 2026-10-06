import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/brush_dab.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/composite_tree.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_effect.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/timeline_row_address.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/models/transform_pose.dart';
import 'package:anicel/src/services/editing/default_cut_helpers.dart';
import 'package:anicel/src/services/se_name_tag_plan.dart';
import 'package:anicel/src/ui/brush/brush_canvas_panel.dart';
import 'package:anicel/src/ui/camera/camera_frame_overlay.dart';
import 'package:anicel/src/ui/canvas/canvas_layer_stack_view.dart';
import 'package:anicel/src/ui/canvas/canvas_viewport_offset.dart';
import 'package:anicel/src/ui/canvas/interactive_brush_edit_canvas_view.dart';
import 'package:anicel/src/ui/canvas/row_transform_box.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/editor_workspace.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/timeline/effect_lane_policy.dart';
import 'package:anicel/src/ui/timeline/timeline_drag_preview.dart';
import 'package:anicel/src/ui/timeline/timeline_lane_rows.dart';
import 'package:anicel/src/ui/timeline/transform_lane_policy.dart'
    show transformGroupHeaderLane;

import '../../helpers/placement_reading.dart';

/// F-195 — 유저 2026-09-27: 「카메라레이어든 트랜스폼이든 fx든 다 편집이
/// 실시간으로 화면에 보이도록. 레이어에서 값편집이든 캔버스에서 편집이든」.
///
/// Every cell of that sentence, driven by a REAL pointer in the real app and
/// read BEFORE the release: {transform, fx, camera} × {a value scrubbed on
/// its lane, a handle dragged on the canvas}. Each cell used to hold its
/// value in the widget under the finger — the picture, the handles and the
/// other copies of the value waited for the release. Now the value in
/// flight is the session's, and every reader follows it; the release is the
/// one write, and nothing is written before it.
void main() {
  const row = LayerId('ld-row');
  const cel = FrameId('ld-cel');
  const cutId = CutId('ld-cut');
  const fx = EffectId('ld-fx');
  final camera = cameraLayerIdForCut(cutId);
  // Its centre lands where the canvas is on top at 100% (between the docks,
  // above the timeline) — a real pointer can only press what is on screen.
  const canvasSize = CanvasSize(width: 1300, height: 500);
  final centre = CanvasPoint(
    x: canvasSize.width / 2,
    y: canvasSize.height / 2,
  );

  Project project() => Project(
    id: const ProjectId('ld-project'),
    name: 'Live',
    createdAt: DateTime.utc(2026),
    tracks: [
      Track(
        id: const TrackId('ld-track'),
        name: 'Video Track',
        cuts: [
          Cut(
            id: cutId,
            name: 'ld-cut',
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
                effects: [
                  LayerEffect(
                    id: fx,
                    kind: EffectKind.brightnessContrast,
                    parameters: {'brightness': EffectParameter(value: 20)},
                  ),
                ],
              ),
              createCameraLayer(cutId: cutId),
            ],
          ),
        ],
      ),
    ],
  );

  EditorSessionManager sessionOf(WidgetTester tester) =>
      tester.widget<EditorWorkspace>(find.byType(EditorWorkspace)).session;

  Future<void> pumpFrames(WidgetTester tester) async {
    for (var i = 0; i < 6; i += 1) {
      await tester.pump(const Duration(milliseconds: 16));
    }
  }

  Future<void> tapKey(WidgetTester tester, String key) async {
    final target = find.byKey(ValueKey<String>(key));
    await tester.ensureVisible(target);
    await tester.pumpAndSettle();
    await tester.tap(target);
    await tester.pumpAndSettle();
  }

  /// The app on the project, [layer]'s lanes twirled open with [openGroups]
  /// unfolded, standing on [standOn]. The camera row has no Transform header
  /// to unfold (㉙ — the row IS its transform group).
  Future<EditorSessionManager> open(
    WidgetTester tester, {
    required LayerId layer,
    required String standOn,
    List<String>? openGroups,
  }) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(home: HomePage(initialProject: project())));
    await tester.pumpAndSettle();
    final session = sessionOf(tester);
    session.selectLayer(row);
    await pumpFrames(tester);
    // Ink, so the box has a picture to frame.
    final landed = session.pixelEditing.coordinator!.commitSourceStroke(
      sourceDabs: [
        BrushDab(
          center: CanvasPoint(x: centre.x + 30, y: centre.y + 20),
          color: 0xFF112233,
          size: 40,
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
    session.selectLayer(layer);
    await pumpFrames(tester);
    await tapKey(tester, 'timeline-lane-toggle-${layer.value}');
    for (final group
        in openGroups ?? [transformGroupHeaderLane.laneId]) {
      await tapKey(
        tester,
        'timeline-lane-group-toggle-${layer.value}-$group',
      );
    }
    session.standOnRow(LaneRowAddress(layer, standOn));
    await pumpFrames(tester);
    return session;
  }

  /// The row being drawn on, as the canvas's composite holds it.
  CanvasActiveLayerRow activeRowIn(EditorSessionManager session) {
    CanvasActiveLayerRow? found;
    void walk(List<CompositeNode<CanvasStackRow>> nodes) {
      for (final node in nodes) {
        switch (node) {
          case CompositeLeaf(:final payload) when payload is CanvasActiveLayerRow:
            found = payload;
          case CompositeGroup(:final children):
            walk(children);
          case CompositeAdjustment(:final children):
            walk(children);
          case CompositeLeaf():
            break;
        }
      }
    }

    walk(session.editingCanvas.stack.nodes);
    return found!;
  }

  CanvasPoint shownCentre(EditorSessionManager session) =>
      activeRowIn(session).placement?.centreOf(canvasSize) ?? centre;

  String valueLabel(WidgetTester tester, LayerId layer, String laneId) =>
      tester
          .widget<Text>(
            find.descendant(
              of: find.byKey(
                ValueKey<String>(
                  'timeline-lane-value-${layer.value}-$laneId',
                ),
              ),
              matching: find.byType(Text),
            ),
          )
          .data!;

  /// The standing row's box (F-222) — the layer's, or the camera frame's.
  RowTransformBox boxOf(WidgetTester tester) =>
      tester.widget<RowTransformBox>(find.byType(RowTransformBox));

  /// Where [point] on the canvas shows on the screen, through the box's view.
  Offset onScreen(WidgetTester tester, CanvasPoint point) =>
      tester.getTopLeft(find.byType(RowTransformBox)) +
      boxOf(tester).viewport.canvasToViewportOffset(point);

  /// The middle of the box — inside it, on no handle: a move.
  CanvasPoint boxMiddle(WidgetTester tester) {
    final corners = boxOf(tester).corners;
    return CanvasPoint(
      x: (corners[0].x + corners[2].x) / 2,
      y: (corners[0].y + corners[2].y) / 2,
    );
  }

  Layer committedRow(EditorSessionManager session) =>
      session.requireActiveCut.layers.byId(row)!;

  void expectPoint(CanvasPoint actual, CanvasPoint expected, String reason) {
    expect(actual.x, closeTo(expected.x, 0.01), reason: reason);
    expect(actual.y, closeTo(expected.y, 0.01), reason: reason);
  }

  testWidgets('TRANSFORM × the canvas: dragging inside the box moves the '
      'picture, the pen\'s space and the Position label before the release — '
      'and writes nothing until it', (tester) async {
    final session = await open(
      tester,
      layer: row,
      standOn: 'position',
    );
    final zoom = boxOf(tester).viewport.zoom;
    final labelBefore = valueLabel(tester, row, 'position');
    final cornerBefore = boxOf(tester).corners.first;

    final gesture = await tester.startGesture(
      onScreen(tester, boxMiddle(tester)),
      kind: PointerDeviceKind.mouse,
    );
    for (var step = 0; step < 4; step += 1) {
      await gesture.moveBy(const Offset(10, 5));
      await tester.pump();
    }
    // What the box shows — handed back by the host (F-195), in whole pixels
    // (09-22 ⑭).
    final dragged = boxOf(tester).pose.center;
    expect(
      dragged.x - centre.x,
      inInclusiveRange(40 / zoom - 1, 40 / zoom + 1),
      reason: 'the box went with the pointer',
    );

    expect(session.dragPreview.value, isA<LaneEditPreview>());
    expectPoint(shownCentre(session), dragged, 'the PICTURE follows the hand');
    expectPoint(
      session.frameVerbs.layerCanvasPoseSample(row)!.centreOf(canvasSize),
      dragged,
      'the PEN\'s space follows it — a stroke mid-drag lands where it shows',
    );
    expect(
      boxOf(tester).corners.first.x - cornerBefore.x,
      closeTo(dragged.x - centre.x, 0.01),
      reason: 'the box is DRAWN at the value it shows — not the value plus an '
          'offset of its own, which would count the drag twice',
    );
    expect(
      valueLabel(tester, row, 'position'),
      isNot(labelBefore),
      reason: 'the rail\'s Position value follows the canvas drag',
    );
    expect(
      committedRow(session).transformTrack.position.isEmpty,
      isTrue,
      reason: 'DISPLAY only — nothing is written before the release',
    );

    await gesture.up();
    await tester.pump();

    expect(session.dragPreview.value, isNull, reason: 'the release drops it');
    final key = committedRow(session).transformTrack.position.keyAt(0);
    expect(key, isNotNull, reason: 'the release is the one write');
    expectPoint(key!.value, dragged, 'and it writes what the drag showed');
    expectPoint(shownCentre(session), dragged, 'no frame jumps back');
  });

  testWidgets('TRANSFORM × the lane: scrubbing Position moves the picture '
      'and the box before the release', (tester) async {
    final session = await open(
      tester,
      layer: row,
      standOn: 'position',
    );
    final value = find.byKey(
      ValueKey<String>('timeline-lane-value-${row.value}-position'),
    );

    final gesture = await tester.startGesture(
      tester.getCenter(value),
      kind: PointerDeviceKind.mouse,
    );
    for (var step = 0; step < 3; step += 1) {
      await gesture.moveBy(const Offset(10, 0));
      await tester.pump();
    }
    final scrubbed = CanvasPoint(x: centre.x + 30, y: centre.y);

    expectPoint(shownCentre(session), scrubbed, 'the PICTURE follows the scrub');
    expectPoint(
      boxOf(tester).pose.center,
      scrubbed,
      'so does the box on the canvas',
    );
    expect(committedRow(session).transformTrack.position.isEmpty, isTrue);

    await gesture.up();
    await tester.pump();

    expect(session.dragPreview.value, isNull);
    expectPoint(
      committedRow(session).transformTrack.position.keyAt(0)!.value,
      scrubbed,
      'the release writes the scrubbed value',
    );
  });

  testWidgets('TRANSFORM × the canvas box: a corner drag scales the picture '
      'and the Scale label before the release', (tester) async {
    final session = await open(
      tester,
      layer: row,
      standOn: 'position',
    );
    final labelBefore = valueLabel(tester, row, 'scale');

    final gesture = await tester.startGesture(
      onScreen(tester, boxOf(tester).corners[2]),
      kind: PointerDeviceKind.mouse,
    );
    for (var step = 0; step < 4; step += 1) {
      await gesture.moveBy(const Offset(15, 15));
      await tester.pump();
    }

    final shownZoom = activeRowIn(session).placement?.evenScale ?? 1;
    expect(shownZoom, greaterThan(1.01), reason: 'the PICTURE grows');
    expect(valueLabel(tester, row, 'scale'), isNot(labelBefore));
    expect(committedRow(session).transformTrack.scale.isEmpty, isTrue);

    await gesture.up();
    await tester.pump();

    final released =
        committedRow(session).transformTrack.scale.keyAt(0)!.value;
    for (final alongAnAxis in [released.x, released.y]) {
      expect(
        alongAnAxis,
        closeTo(shownZoom, 1e-9),
        reason: 'the release writes the zoom the drag showed',
      );
    }
  });

  testWidgets('FX × the lane: scrubbing a parameter re-draws the picture '
      'with it before the release', (tester) async {
    final session = await open(
      tester,
      layer: row,
      standOn: transformGroupHeaderLane.laneId,
      openGroups: [transformGroupHeaderLane.laneId, effectGroupLaneId(fx)],
    );
    final value = find.byKey(
      ValueKey<String>(
        'timeline-lane-value-${row.value}-${effectLaneId(fx, 'brightness')}',
      ),
    );
    double shownBrightness() => activeRowIn(session).effects
        .singleWhere((effect) => effect.kind == EffectKind.brightnessContrast)
        .parameter('brightness');
    expect(shownBrightness(), 20, reason: 'the premise');

    final gesture = await tester.startGesture(
      tester.getCenter(value),
      kind: PointerDeviceKind.mouse,
    );
    for (var step = 0; step < 4; step += 1) {
      await gesture.moveBy(const Offset(10, 0));
      await tester.pump();
    }

    expect(shownBrightness(), 40, reason: 'the PICTURE follows the scrub');
    expect(
      committedRow(session).effects.single.parameterOf('brightness').track.isEmpty,
      isTrue,
      reason: 'nothing is keyed before the release',
    );

    await gesture.up();
    await tester.pump();

    expect(session.dragPreview.value, isNull);
    expect(shownBrightness(), 40, reason: 'and the release keeps it');
  });

  testWidgets('CAMERA × the canvas: dragging the frame moves the camera '
      'lanes with it before the release', (tester) async {
    final session = await open(
      tester,
      layer: camera,
      standOn: 'position',
      openGroups: const [],
    );
    final poseBefore = session.camera.cameraPoseAtCurrentFrame;
    final labelBefore = valueLabel(tester, camera, 'position');

    // The frame's centre — inside it, on no handle (it wears no cross): a
    // move.
    final gesture = await tester.startGesture(
      onScreen(tester, boxOf(tester).pose.center),
      kind: PointerDeviceKind.mouse,
    );
    for (var step = 0; step < 4; step += 1) {
      await gesture.moveBy(const Offset(12, 6));
      await tester.pump();
    }

    final shown = tester.widget<CameraFrameOverlay>(find.byType(CameraFrameOverlay)).pose;
    expect(shown.center.x, greaterThan(poseBefore.center.x + 1));
    expectPoint(
      session.camera.activeCutCameraTrack!.keyframeAt(0)!.center,
      shown.center,
      'the camera track every camera reader takes is the one the frame shows',
    );
    expect(
      valueLabel(tester, camera, 'position'),
      isNot(labelBefore),
      reason: 'the camera row\'s Position follows the canvas drag',
    );
    expect(
      session.requireActiveCut.camera.isEmpty,
      isTrue,
      reason: 'nothing is written before the release',
    );

    await gesture.up();
    await tester.pump();

    expect(session.dragPreview.value, isNull);
    expectPoint(
      session.requireActiveCut.camera.keyframeAt(0)!.center,
      shown.center,
      'the release keys what the drag showed',
    );
    final keyed = session.requireActiveCut.camera.track;
    expect(keyed.scale.isEmpty, isTrue, reason: 'a move keys no zoom');
    expect(keyed.rotation.isEmpty, isTrue, reason: 'nor a turn');
  });

  testWidgets('CAMERA × the canvas: a corner of the frame keys the zoom '
      'ALONE — the turn and the middle key nothing with it', (tester) async {
    // 유저 2026-09-28 camera-frame-keys-what-you-grab-Q1 「잡은 것만 — 레이어
    // 핸들과 같은 법」. The frame used to key position, scale and rotation
    // together whatever it was grabbed by.
    final session = await open(
      tester,
      layer: camera,
      standOn: 'position',
      openGroups: const [],
    );
    // The frame's own gesture → member mapping is pinned by real drags in
    // `camera_frame_overlay_test` (its corners lie off this view: the frame
    // is the 1300-wide page). What changed HERE is the host's wiring, so
    // this drives the very landings the canvas area handed the frame.
    final frame = tester.widget<CameraFrameBox>(find.byType(CameraFrameBox));
    for (final zoom in [1.4, 1.8, 2.0]) {
      frame.zoom!.changed(zoom);
      await tester.pump();
    }
    expect(
      session.requireActiveCut.camera.isEmpty,
      isTrue,
      reason: 'nothing is written before the release',
    );
    frame.zoom!.committed(2.0);
    await tester.pump();

    final track = session.requireActiveCut.camera.track;
    expect(
      track.scale.keyAt(0)?.value,
      uniformScale(2),
      reason: 'the zoom keys',
    );
    expect(track.position.isEmpty, isTrue, reason: 'the centre does not');
    expect(track.rotation.isEmpty, isTrue, reason: 'nor does the turn');
  });

  testWidgets('CAMERA × the lane: scrubbing the camera\'s Position moves the '
      'frame on the canvas before the release', (tester) async {
    final session = await open(
      tester,
      layer: camera,
      standOn: 'position',
      openGroups: const [],
    );
    final value = find.byKey(
      ValueKey<String>('timeline-lane-value-${camera.value}-position'),
    );
    CanvasPoint frameCentre() => tester
        .widget<CameraFrameOverlay>(find.byType(CameraFrameOverlay))
        .pose
        .center;
    final before = frameCentre();

    final gesture = await tester.startGesture(
      tester.getCenter(value),
      kind: PointerDeviceKind.mouse,
    );
    for (var step = 0; step < 3; step += 1) {
      await gesture.moveBy(const Offset(10, 0));
      await tester.pump();
    }

    expectPoint(
      frameCentre(),
      CanvasPoint(x: before.x + 30, y: before.y),
      'the FRAME follows the scrub',
    );
    expect(session.requireActiveCut.camera.isEmpty, isTrue);

    await gesture.up();
    await tester.pump();

    expect(session.dragPreview.value, isNull);
    expect(session.requireActiveCut.camera.keyframeAt(0), isNotNull);
  });

  testWidgets('a handle taken away mid-drag drops what it was showing and '
      'writes nothing', (tester) async {
    final session = await open(
      tester,
      layer: row,
      standOn: 'position',
    );
    final gesture = await tester.startGesture(
      onScreen(tester, boxMiddle(tester)),
      kind: PointerDeviceKind.mouse,
    );
    await gesture.moveBy(const Offset(20, 0));
    await tester.pump();
    await gesture.moveBy(const Offset(20, 0));
    await tester.pump();
    expect(session.dragPreview.value, isA<LaneEditPreview>());

    // Stepping onto a lane that declares no handle takes the box away under
    // the pointer — it never sees its release.
    session.standOnRow(const LaneRowAddress(row, 'opacity'));
    await tester.pump();
    await tester.pump();
    expect(
      find.byType(RowTransformBox),
      findsNothing,
      reason: 'the premise: the box is gone',
    );

    expect(session.dragPreview.value, isNull, reason: 'nothing left showing');
    expectPoint(shownCentre(session), centre, 'the picture is back');

    await gesture.up();
    await tester.pump();
    expect(
      committedRow(session).transformTrack.position.isEmpty,
      isTrue,
      reason: 'a drag with no handle left to release writes nothing',
    );
  });

  testWidgets('SE × the lane: scrubbing an S row\'s Position moves its name '
      'tag on the canvas before the release', (tester) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(home: HomePage(initialProject: createDefaultProject())),
    );
    await tester.pumpAndSettle();
    final session = sessionOf(tester);
    final se = session.activeTrack.seLayers.first;
    session.selectLayer(se.id);
    session.selectFrameIndex(0);
    session.seEntries.createSeEntryAtCurrentFrame(name: '쿵', seName: 'A');
    await pumpFrames(tester);
    await tapKey(tester, 'timeline-lane-toggle-${se.id.value}');
    await tapKey(
      tester,
      'timeline-lane-group-toggle-${se.id.value}-'
      '${transformGroupHeaderLane.laneId}',
    );
    Offset? tagOnTheCanvas() {
      final overlay = tester
          .widgetList<CustomPaint>(find.byType(CustomPaint))
          .map((paint) => paint.painter)
          .firstWhere(
            (painter) =>
                painter.runtimeType.toString() == '_SeNameTagOverlayPainter',
          );
      // The overlay's painter is private; its tags are read through it.
      // ignore: avoid_dynamic_calls
      final tags = (overlay as dynamic).tags as List<ResolvedSeNameTag>;
      return tags.single.content.position;
    }

    final before = tagOnTheCanvas();
    final value = find.byKey(
      ValueKey<String>('timeline-lane-value-${se.id.value}-position'),
    );
    await tester.ensureVisible(value);
    await tester.pumpAndSettle();

    final gesture = await tester.startGesture(
      tester.getCenter(value),
      kind: PointerDeviceKind.mouse,
    );
    for (var step = 0; step < 3; step += 1) {
      await gesture.moveBy(const Offset(10, 0));
      await tester.pump();
    }

    expect(session.dragPreview.value, isA<LaneEditPreview>());
    expect(
      tagOnTheCanvas(),
      isNot(before),
      reason: 'the tag the canvas draws follows the scrub',
    );

    await gesture.up();
    await tester.pump();
    expect(session.dragPreview.value, isNull);
  });

  testWidgets('the drawing surface stays MOUNTED while a drag first poses an '
      'unposed row, and while the drag goes away', (tester) async {
    final session = await open(
      tester,
      layer: row,
      standOn: 'position',
    );
    expect(
      session.frameVerbs.layerCanvasPoseSample(row),
      isNull,
      reason: 'the premise: the row stands unposed',
    );
    State<StatefulWidget> surface() =>
        tester.state(find.byType(InteractiveBrushEditCanvasView));
    final mounted = surface();

    final gesture = await tester.startGesture(
      onScreen(tester, boxMiddle(tester)),
      kind: PointerDeviceKind.mouse,
    );
    for (var step = 0; step < 3; step += 1) {
      await gesture.moveBy(const Offset(10, 0));
      await tester.pump();
    }
    expect(
      session.frameVerbs.layerCanvasPoseSample(row),
      isNotNull,
      reason: 'the premise: the drag posed the row',
    );
    expect(
      identical(surface(), mounted),
      isTrue,
      reason: 'a pose arriving is a matrix, not a remount — the mount is the '
          'expensive half of a flip, and it would land on the first step of '
          'every handle drag on an unposed row',
    );

    session.standOnRow(const LaneRowAddress(row, 'opacity'));
    await tester.pump();
    await tester.pump();
    expect(session.frameVerbs.layerCanvasPoseSample(row), isNull);
    expect(
      identical(surface(), mounted),
      isTrue,
      reason: 'nor is the pose leaving',
    );
    await gesture.up();
    await tester.pump();
  });

  testWidgets('a scrub rebuilds the rows of the lane it edits — not every row '
      'of its layer (the rebuild budget of a step)', (tester) async {
    await open(tester, layer: row, standOn: 'position');
    final value = find.byKey(
      ValueKey<String>('timeline-lane-value-${row.value}-position'),
    );
    final gesture = await tester.startGesture(
      tester.getCenter(value),
      kind: PointerDeviceKind.mouse,
    );
    await gesture.moveBy(const Offset(10, 0));
    await tester.pump();

    final rebuilt = <String>[];
    debugOnRebuildDirtyWidget = (element, _) {
      final widget = element.widget;
      if (widget is TimelineLaneControlsRow) {
        rebuilt.add(widget.lane.laneId);
      }
    };
    addTearDown(() => debugOnRebuildDirtyWidget = null);
    await gesture.moveBy(const Offset(10, 0));
    await tester.pump();
    debugOnRebuildDirtyWidget = null;

    expect(
      rebuilt.toSet(),
      {'position', transformGroupHeaderLane.laneId},
      reason: 'the edited lane and the header whose keys it joins — the '
          'scale, rotation and anchor rows show what they showed, and '
          'rebuilding them was most of a step',
    );
    await gesture.up();
    await tester.pump();
  });

  // canvas-wakes-for-what-it-shows: the canvas AREA is rebuilt for a drag
  // only for what it hands the panel — so those are what these read, on the
  // panel as mounted.
  BrushCanvasPanel mountedPanel(WidgetTester tester) =>
      tester.widget<BrushCanvasPanel>(
        find.byKey(const ValueKey<String>('main-canvas-brush-host')),
      );

  testWidgets('the panel is handed the pose a Position scrub shows — the '
      'wrap the pen draws through, before the release', (tester) async {
    await open(tester, layer: row, standOn: 'position');
    final value = find.byKey(
      ValueKey<String>('timeline-lane-value-${row.value}-position'),
    );
    final gesture = await tester.startGesture(
      tester.getCenter(value),
      kind: PointerDeviceKind.mouse,
    );
    try {
      for (var step = 0; step < 3; step += 1) {
        await gesture.moveBy(const Offset(10, 0));
        await tester.pump();
      }
      expectPoint(
        mountedPanel(tester).interactiveContentPose!.centreOf(canvasSize),
        CanvasPoint(x: centre.x + 30, y: centre.y),
        'the draw-through wrap the panel is handed',
      );
    } finally {
      await gesture.up();
      await tester.pump();
    }
  });

  testWidgets('the panel is handed the opacity an Opacity scrub shows',
      (tester) async {
    await open(tester, layer: row, standOn: 'opacity');
    expect(
      mountedPanel(tester).interactiveContentOpacity,
      1,
      reason: '⛔premise',
    );
    final value = find.byKey(
      ValueKey<String>('timeline-lane-value-${row.value}-opacity'),
    );
    final gesture = await tester.startGesture(
      tester.getCenter(value),
      kind: PointerDeviceKind.mouse,
    );
    try {
      for (var step = 0; step < 3; step += 1) {
        await gesture.moveBy(const Offset(-10, 0));
        await tester.pump();
      }
      expect(mountedPanel(tester).interactiveContentOpacity, lessThan(1));
      expect(
        mountedPanel(tester).interactiveContentOpacity,
        closeTo(sessionOf(tester).editingCanvas.stack.activeLayerOpacity, 1e-9),
        reason: 'the one the stack walk carries out',
      );
    } finally {
      await gesture.up();
      await tester.pump();
    }
  });
}
