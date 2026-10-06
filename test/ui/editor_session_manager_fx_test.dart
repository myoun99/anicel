import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/camera_pose.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/property_track.dart';
import 'package:anicel/src/models/transform_track.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';

void main() {
  group('layer fx switches (persisted, R8)', () {
    late EditorSessionManager session;

    setUp(() {
      session = EditorSessionManager(initialProject: createDefaultProject());
      addTearDown(session.dispose);
    });

    test('toggleLayerFx flips the switch and notifies', () {
      final layerId = session.activeLayer!.id;
      var notified = 0;
      session.addListener(() => notified += 1);

      expect(session.effectsAndFx.isLayerFxEnabled(layerId), isTrue);
      expect(session.effectsAndFx.layerFxState(layerId), LayerFxState.on);
      session.effectsAndFx.toggleLayerFx(layerId);
      expect(session.effectsAndFx.isLayerFxEnabled(layerId), isFalse);
      // R8: PERSISTED on the row, not a session set — and undoable.
      expect(session.effectsAndFx.layerFxState(layerId), LayerFxState.off);
      expect(session.activeLayer!.transformEnabled, isFalse);
      session.effectsAndFx.toggleLayerFx(layerId);
      expect(session.effectsAndFx.isLayerFxEnabled(layerId), isTrue);
      expect(session.activeLayer!.transformEnabled, isTrue);
      expect(notified, greaterThanOrEqualTo(2));
    });

    test('layerCanvasPoseSample: the active layer shows its pose '
        '(always-applied rule), bypass returns identity', () {
      final layer = session.activeLayer!;
      expect(
        session.frameVerbs.layerCanvasPoseSample(layer.id),
        isNull,
        reason: 'no transform work = identity, no wrap',
      );

      session.laneVerbs.updateLayerTransformTrack(
        layer.id,
        TransformTrack.empty().copyWith(
          position: PropertyTrack<CanvasPoint>().withKey(
            0,
            CanvasPoint(x: 100, y: 60),
          ),
          anchorPoint: PropertyTrack<CanvasPoint>().withKey(
            0,
            CanvasPoint(x: 10, y: 20),
          ),
        ),
      );

      final placement = session.frameVerbs.layerCanvasPoseSample(layer.id)!;
      expect(
        placement.apply(CanvasPoint(x: 10, y: 20)),
        CanvasPoint(x: 100, y: 60),
        reason: 'the anchor is the point of the artwork the position takes',
      );

      session.effectsAndFx.toggleLayerFx(layer.id);
      expect(session.frameVerbs.layerCanvasPoseSample(layer.id), isNull);
      session.effectsAndFx.toggleLayerFx(layer.id);
      expect(session.frameVerbs.layerCanvasPoseSample(layer.id), isNotNull);
    });

    test('the editing canvas stack: the active layer display opacity carries the '
        'animated Opacity sample; bypass restores the static value', () {
      final layer = session.activeLayer!;
      session.opacityVerbs.setLayerOpacity(layerId: layer.id, opacity: 0.8);
      session.laneVerbs.updateLayerTransformTrack(
        layer.id,
        TransformTrack.empty().copyWith(
          opacity: PropertyTrack<double>().withKey(0, 0.5),
        ),
      );

      expect(session.editingCanvas.stack.activeLayerOpacity, closeTo(0.4, 1e-9));

      session.effectsAndFx.toggleLayerFx(layer.id);
      expect(session.editingCanvas.stack.activeLayerOpacity, closeTo(0.8, 1e-9));
    });

    test('camera fx bypass: cameraPoseForCut returns the identity pose on '
        'the render routes while the camera row is bypassed', () {
      final cut = session.requireActiveCut;
      final cameraLayer = cut.layers.firstWhere(
        (layer) => layer.kind == LayerKind.camera,
      );
      session.camera.setCameraKeyframeAtCurrentFrame(
        CameraPose(center: CanvasPoint(x: 100, y: 80), zoom: 2),
      );

      expect(session.camera.cameraPoseForCut(session.requireActiveCut, 0).zoom, 2);

      session.effectsAndFx.toggleLayerFx(cameraLayer.id);
      final bypassed = session.camera.cameraPoseForCut(session.requireActiveCut, 0);
      expect(bypassed.zoom, 1);
      expect(bypassed.rotationDegrees, 0);
      expect(bypassed.center.x, session.requireActiveCut.canvasSize.width / 2);
      expect(bypassed.center.y, session.requireActiveCut.canvasSize.height / 2);

      session.effectsAndFx.toggleLayerFx(cameraLayer.id);
      expect(session.camera.cameraPoseForCut(session.requireActiveCut, 0).zoom, 2);
    });

    test('lane value resolvers: anchor defaults to the canvas center and '
        'opacity to 1 while unkeyed', () {
      final layer = session.activeLayer!;
      final canvasSize = session.requireActiveCut.canvasSize;

      final anchor = session.layerAnchorPointAtFrame(layer, 0);
      expect(anchor.x, canvasSize.width / 2);
      expect(anchor.y, canvasSize.height / 2);
      expect(resolveOpacityTrackAt(layer.transformTrack.opacity, 0), 1);

      session.laneVerbs.updateLayerTransformTrack(
        layer.id,
        TransformTrack.empty().copyWith(
          opacity: PropertyTrack<double>().withKey(0, 1).withKey(8, 0),
        ),
      );
      final updated = session.activeLayer!;
      expect(
        resolveOpacityTrackAt(updated.transformTrack.opacity, 4),
        closeTo(0.5, 1e-9),
      );
    });
  });

  group('a lane key freezes the value the row shows there', () {
    // AE's rule (`transformTrackWithLaneKeyToggled`): keying a property
    // freezes its CURRENT value. The model is handed the value; what hands
    // it over is `LaneVerbs`, and that is what these pin.
    late EditorSessionManager session;

    setUp(() {
      session = EditorSessionManager(initialProject: createDefaultProject());
      addTearDown(session.dispose);
    });

    test('opacity, between two keys', () {
      final layer = session.activeLayer!;
      session.laneVerbs.updateLayerTransformTrack(
        layer.id,
        TransformTrack.empty().copyWith(
          opacity: PropertyTrack<double>().withKey(0, 1).withKey(8, 0),
        ),
      );
      session.laneVerbs.toggleLaneKeyAt(
        layer.id,
        'opacity',
        4,
        frameIsGlobal: false,
        description: 'Key opacity',
      );
      expect(
        session.activeLayer!.transformTrack.opacity.keyAt(4)?.value,
        closeTo(0.5, 1e-9),
      );
    });

    test('the anchor point, between two keys', () {
      final layer = session.activeLayer!;
      session.laneVerbs.updateLayerTransformTrack(
        layer.id,
        TransformTrack.empty().copyWith(
          anchorPoint: PropertyTrack<CanvasPoint>()
              .withKey(0, CanvasPoint(x: 100, y: 100))
              .withKey(8, CanvasPoint(x: 200, y: 300)),
        ),
      );
      session.laneVerbs.toggleLaneKeyAt(
        layer.id,
        'anchor-point',
        4,
        frameIsGlobal: false,
        description: 'Key anchor point',
      );
      final key = session.activeLayer!.transformTrack.anchorPoint.keyAt(4);
      expect(key?.value.x, closeTo(150, 1e-9));
      expect(key?.value.y, closeTo(200, 1e-9));
    });
  });

  test('a layer transform write is announced — the rails and the canvas '
      'rebuild off the session, and nothing else says the track moved', () {
    final session = EditorSessionManager(
      initialProject: createDefaultProject(),
    );
    addTearDown(session.dispose);
    final layer = session.activeLayer!;
    var announced = 0;
    session.addListener(() => announced += 1);
    session.laneVerbs.updateLayerTransformTrack(
      layer.id,
      TransformTrack.empty().copyWith(
        opacity: PropertyTrack<double>().withKey(0, 0.5),
      ),
    );
    expect(announced, greaterThan(0));
  });
}
