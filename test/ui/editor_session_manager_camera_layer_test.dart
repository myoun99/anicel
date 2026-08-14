import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_cut_helpers.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/camera_pose.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/timeline/timeline_cell_exposure_state.dart';

void main() {
  EditorSessionManager session() =>
      EditorSessionManager(initialProject: createDefaultProject());

  CameraPose pose({double x = 100}) =>
      CameraPose(center: CanvasPoint(x: x, y: 50));

  test('default cut carries one camera layer at the bottom row', () {
    final s = session();

    final layers = s.requireActiveCut.layers;
    expect(layers.last.kind, LayerKind.camera);
    expect(layers.last.name, 'Camera');
    expect(
      layers.where((layer) => layer.kind == LayerKind.camera),
      hasLength(1),
    );
    // The drawing layer stays the default active layer.
    expect(s.activeLayer?.kind, LayerKind.animation);
    expect(s.isCameraLayerActive, isFalse);
  });

  test('new cuts also get a camera layer', () {
    final s = session();

    s.createCut();

    expect(
      s.requireActiveCut.layers.where((layer) => layer.kind == LayerKind.camera),
      hasLength(1),
    );
  });

  test('selecting the camera layer enters camera mode with guards', () {
    final s = session();
    final cameraLayer = s.requireActiveCut.layers.last;

    s.selectLayer(cameraLayer.id);

    expect(s.isCameraLayerActive, isTrue);
    expect(s.canDeleteActiveLayer, isFalse);
    expect(s.canToggleTargetLayerKind, isFalse);
    expect(s.canCreateDrawingAtCurrentFrame, isFalse);
    expect(s.canBlankExposureAtCurrentFrame, isFalse);
    expect(s.canToggleMarkAtCurrentFrame, isFalse);
    expect(s.activeLayerKindLabelText, 'Camera Layer');

    // Copy/duplicate quietly refuse the camera layer.
    s.copyActiveLayer();
    expect(s.hasLayerClipboard, isFalse);
    final layerCount = s.requireActiveCut.layers.length;
    s.duplicateActiveLayer();
    expect(s.requireActiveCut.layers.length, layerCount);
  });

  test('camera layer cells mirror camera keyframes', () {
    final s = session();
    final cameraLayer = s.requireActiveCut.layers.last;
    s.selectLayer(cameraLayer.id);

    s.selectFrameIndex(3);
    s.setCameraKeyframeAtCurrentFrame(pose());

    expect(
      s.exposureStateForLayer(cameraLayer, 3),
      TimelineCellExposureState.drawingStart,
    );
    expect(
      s.exposureStateForLayer(cameraLayer, 4),
      TimelineCellExposureState.uncovered,
    );
    expect(s.hasMarkForLayer(cameraLayer, 3), isFalse);
    expect(s.hasCameraKeyframeAtCurrentFrame, isTrue);

    s.removeCameraKeyframeAtCurrentFrame();
    expect(
      s.exposureStateForLayer(cameraLayer, 3),
      TimelineCellExposureState.uncovered,
    );
  });

  test('R28 #14: the only drawing layer IS deletable — the camera row is '
      'still fixed', () {
    final s = session();

    // Active cut has 1 drawing layer + 1 camera layer.
    expect(s.activeLayer?.kind, LayerKind.animation);
    expect(
      s.canDeleteActiveLayer,
      isTrue,
      reason: 'R28 #14: "액션 레이어가 1개도 없는상황 허용" — the drawing floor '
          'is gone',
    );

    // The CAMERA row keeps its floor: it is a fixture of the cut.
    final cameraLayer = s.layers.firstWhere(
      (layer) => layer.kind == LayerKind.camera,
    );
    s.selectLayer(cameraLayer.id);
    expect(s.canDeleteActiveLayer, isFalse);
  });

  test('camera layer id derives from the cut id', () {
    expect(cameraLayerIdForCut(const CutId('cut-9')).value, 'cut-9-camera');
  });
}
