import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

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
import 'package:anicel/src/services/editing/default_cut_helpers.dart';
import 'package:anicel/src/ui/camera/camera_frame_overlay.dart';
import 'package:anicel/src/ui/canvas/canvas_layer_stack_view.dart';
import 'package:anicel/src/ui/canvas/canvas_point_gizmo.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/editor_workspace.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/timeline/effect_lane_policy.dart';
import 'package:anicel/src/ui/timeline/timeline_drag_preview.dart';
import 'package:anicel/src/ui/timeline/transform_lane_policy.dart'
    show transformGroupHeaderLane;

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
    final landed = session.pixelEditingCoordinator!.commitSourceStroke(
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
      activeRowIn(session).pose?.center ?? centre;

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

  CanvasPointGizmo crosshairOf(WidgetTester tester) =>
      tester.widget<CanvasPointGizmo>(
        find.byWidgetPredicate(
          (widget) =>
              widget is CanvasPointGizmo && widget.glyph == HandleGlyph.crosshair,
        ),
      );

  Layer committedRow(EditorSessionManager session) =>
      session.requireActiveCut.layers.byId(row)!;

  void expectPoint(CanvasPoint actual, CanvasPoint expected, String reason) {
    expect(actual.x, closeTo(expected.x, 0.01), reason: reason);
    expect(actual.y, closeTo(expected.y, 0.01), reason: reason);
  }

  testWidgets('TRANSFORM × the canvas: dragging the crosshair moves the '
      'picture, the pen\'s space and the Position label before the release — '
      'and writes nothing until it', (tester) async {
    final session = await open(
      tester,
      layer: row,
      standOn: 'position',
    );
    final crosshair = find.byKey(const ValueKey<String>('layer-position-gizmo'));
    final zoom = crosshairOf(tester).viewport.zoom;
    final labelBefore = valueLabel(tester, row, 'position');
    final start = tester.getCenter(crosshair);

    final gesture = await tester.startGesture(
      start,
      kind: PointerDeviceKind.mouse,
    );
    for (var step = 0; step < 4; step += 1) {
      await gesture.moveBy(const Offset(10, 5));
      await tester.pump();
    }
    // What the handle reports — the pan's slop is the recognizer's, so the
    // value is read off the handle rather than off the raw pointer.
    final dragged = crosshairOf(tester).point;
    expect(
      dragged.x - centre.x,
      inInclusiveRange(20 / zoom, 40 / zoom),
      reason: 'the handle went with the pointer (less the pan\'s slop)',
    );

    expect(session.dragPreview.value, isA<LaneEditPreview>());
    expectPoint(shownCentre(session), dragged, 'the PICTURE follows the hand');
    expectPoint(
      session.frameVerbs.layerCanvasPoseSample(row)!.pose.center,
      dragged,
      'the PEN\'s space follows it — a stroke mid-drag lands where it shows',
    );
    final drawnAt = tester.getCenter(crosshair);
    expect(
      drawnAt.dx - start.dx,
      closeTo((dragged.x - centre.x) * zoom, 0.5),
      reason: 'the handle is DRAWN at the value it shows — not the value plus '
          'an offset of its own, which would count the drag twice',
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
      'and the crosshair before the release', (tester) async {
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
      crosshairOf(tester).point,
      scrubbed,
      'so does the handle on the canvas',
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
    final corner = find.byKey(
      const ValueKey<String>('layer-transform-box-corner-2'),
    );
    final labelBefore = valueLabel(tester, row, 'scale');

    final gesture = await tester.startGesture(
      tester.getCenter(corner),
      kind: PointerDeviceKind.mouse,
    );
    for (var step = 0; step < 4; step += 1) {
      await gesture.moveBy(const Offset(15, 15));
      await tester.pump();
    }

    final shownZoom = activeRowIn(session).pose?.zoom ?? 1;
    expect(shownZoom, greaterThan(1.01), reason: 'the PICTURE grows');
    expect(valueLabel(tester, row, 'scale'), isNot(labelBefore));
    expect(committedRow(session).transformTrack.scale.isEmpty, isTrue);

    await gesture.up();
    await tester.pump();

    expect(
      committedRow(session).transformTrack.scale.keyAt(0)!.value,
      closeTo(shownZoom, 1e-9),
      reason: 'the release writes the zoom the drag showed',
    );
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
    final overlay = find.byKey(
      const ValueKey<String>('camera-frame-overlay-gesture'),
    );
    final poseBefore = session.camera.cameraPoseAtCurrentFrame;
    final labelBefore = valueLabel(tester, camera, 'position');
    // The frame's centre — inside it, on no handle: a move.
    final frame = tester.widget<CameraFrameOverlay>(
      find.byType(CameraFrameOverlay),
    );
    final press =
        tester.getTopLeft(overlay) +
        cameraCenterInViewport(pose: frame.pose, viewport: frame.viewport);

    final gesture = await tester.startGesture(
      press,
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
    final crosshair = find.byKey(const ValueKey<String>('layer-position-gizmo'));

    final gesture = await tester.startGesture(
      tester.getCenter(crosshair),
      kind: PointerDeviceKind.mouse,
    );
    await gesture.moveBy(const Offset(20, 0));
    await tester.pump();
    await gesture.moveBy(const Offset(20, 0));
    await tester.pump();
    expect(session.dragPreview.value, isA<LaneEditPreview>());

    // Stepping onto a lane that declares no handle takes the crosshair away
    // under the pointer — it never sees its release.
    session.standOnRow(const LaneRowAddress(row, 'opacity'));
    await tester.pump();
    await tester.pump();
    expect(crosshair, findsNothing, reason: 'the premise: the handle is gone');

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
}
