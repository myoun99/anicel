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

      expect(session.isLayerFxEnabled(layerId), isTrue);
      expect(session.layerFxState(layerId), LayerFxState.on);
      session.toggleLayerFx(layerId);
      expect(session.isLayerFxEnabled(layerId), isFalse);
      // R8: PERSISTED on the row, not a session set — and undoable.
      expect(session.layerFxState(layerId), LayerFxState.off);
      expect(session.activeLayer!.transformEnabled, isFalse);
      session.toggleLayerFx(layerId);
      expect(session.isLayerFxEnabled(layerId), isTrue);
      expect(session.activeLayer!.transformEnabled, isTrue);
      expect(notified, greaterThanOrEqualTo(2));
    });

    test('layerCanvasPoseSample: the active layer shows its pose '
        '(always-applied rule), bypass returns identity', () {
      final layer = session.activeLayer!;
      expect(
        session.layerCanvasPoseSample(layer.id),
        isNull,
        reason: 'no transform work = identity, no wrap',
      );

      session.updateLayerTransformTrack(
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

      final sample = session.layerCanvasPoseSample(layer.id)!;
      expect(sample.pose.center.x, 100);
      expect(sample.pose.center.y, 60);
      expect(sample.anchorPoint, CanvasPoint(x: 10, y: 20));

      session.toggleLayerFx(layer.id);
      expect(session.layerCanvasPoseSample(layer.id), isNull);
      session.toggleLayerFx(layer.id);
      expect(session.layerCanvasPoseSample(layer.id), isNotNull);
    });

    test('editingCanvasStack: the active layer display opacity carries the '
        'animated Opacity sample; bypass restores the static value', () {
      final layer = session.activeLayer!;
      session.setLayerOpacity(layerId: layer.id, opacity: 0.8);
      session.updateLayerTransformTrack(
        layer.id,
        TransformTrack.empty().copyWith(
          opacity: PropertyTrack<double>().withKey(0, 0.5),
        ),
      );

      expect(session.editingCanvasStack.activeLayerOpacity, closeTo(0.4, 1e-9));

      session.toggleLayerFx(layer.id);
      expect(session.editingCanvasStack.activeLayerOpacity, closeTo(0.8, 1e-9));
    });

    test('camera fx bypass: cameraPoseForCut returns the identity pose on '
        'the render routes while the camera row is bypassed', () {
      final cut = session.requireActiveCut;
      final cameraLayer = cut.layers.firstWhere(
        (layer) => layer.kind == LayerKind.camera,
      );
      session.setCameraKeyframeAtCurrentFrame(
        CameraPose(center: CanvasPoint(x: 100, y: 80), zoom: 2),
      );

      expect(session.cameraPoseForCut(session.requireActiveCut, 0).zoom, 2);

      session.toggleLayerFx(cameraLayer.id);
      final bypassed = session.cameraPoseForCut(session.requireActiveCut, 0);
      expect(bypassed.zoom, 1);
      expect(bypassed.rotationDegrees, 0);
      expect(bypassed.center.x, session.requireActiveCut.canvasSize.width / 2);
      expect(bypassed.center.y, session.requireActiveCut.canvasSize.height / 2);

      session.toggleLayerFx(cameraLayer.id);
      expect(session.cameraPoseForCut(session.requireActiveCut, 0).zoom, 2);
    });

    test('lane value resolvers: anchor defaults to the canvas center and '
        'opacity to 1 while unkeyed', () {
      final layer = session.activeLayer!;
      final canvasSize = session.requireActiveCut.canvasSize;

      final anchor = session.layerAnchorPointAtFrame(layer, 0);
      expect(anchor.x, canvasSize.width / 2);
      expect(anchor.y, canvasSize.height / 2);
      expect(session.layerOpacityAtFrame(layer, 0), 1);

      session.updateLayerTransformTrack(
        layer.id,
        TransformTrack.empty().copyWith(
          opacity: PropertyTrack<double>().withKey(0, 1).withKey(8, 0),
        ),
      );
      final updated = session.activeLayer!;
      expect(session.layerOpacityAtFrame(updated, 4), closeTo(0.5, 1e-9));
    });
  });
}
