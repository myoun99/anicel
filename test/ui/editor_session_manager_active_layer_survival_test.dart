import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/camera_pose.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';

/// UI-R20 #1: cut commands must not steal the layer selection — adding a
/// camera keyframe used to rebuild the controllers with a null preferred
/// layer, throwing the selection to the bottom row.
void main() {
  test('setting a camera keyframe keeps the ACTIVE layer', () {
    final s = EditorSessionManager(initialProject: createDefaultProject());
    addTearDown(s.dispose);
    final cameraLayer = s.layers.firstWhere(
      (layer) => layer.kind == LayerKind.camera,
    );
    s.selectLayer(cameraLayer.id);
    expect(s.activeLayerId, cameraLayer.id);

    s.setCameraKeyframeAtCurrentFrame(
      CameraPose(
        center: CanvasPoint(x: 100, y: 100),
        zoom: 1.2,
        rotationDegrees: 0,
      ),
    );

    expect(
      s.activeLayerId,
      cameraLayer.id,
      reason: 'the camera row must stay selected after keying',
    );

    s.removeCameraKeyframeAtCurrentFrame();
    expect(s.activeLayerId, cameraLayer.id);
  });

  test('a TRACK-SE selection survives cut commands too', () {
    final s = EditorSessionManager(initialProject: createDefaultProject());
    addTearDown(s.dispose);
    final seLayer = s.activeTrack.seLayers.first;
    s.selectLayer(seLayer.id);
    expect(s.activeLayerId, seLayer.id);

    s.setCameraKeyframeAtCurrentFrame(
      CameraPose(
        center: CanvasPoint(x: 10, y: 10),
        zoom: 1.0,
        rotationDegrees: 0,
      ),
    );

    expect(s.activeLayerId, seLayer.id);
  });
}
