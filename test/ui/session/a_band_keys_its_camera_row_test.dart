import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/camera_pose.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/timeline_row_address.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';

/// ＋ OVER A BAND THAT HOLDS THE CAMERA ROW — the AE behaviour: keys
/// appear, the picture does not move.
///
/// The camera row is its transform header (F-17/F-84, 유저 2026-09-11:
/// 「트랜스폼이나 카메라나 똑같으니까 법 싹 하나로 통일해줘」), so the band's ＋
/// keys it the way it keys every lane row the band swept
/// (`LaneVerbs.createKeysForBandLanes`) — alone in the band or beside a
/// drawing row, one code (one band, 유저 2026-10-25). It freezes the
/// RESOLVED pose at every unkeyed frame the band covers, leaves the keys
/// already there alone, and spends no undo step when there is nothing to
/// add. ↩️A band holding more than the camera keyed it by a verb of the
/// camera's own.
void main() {
  /// A session whose active cut ramps the camera from zoom 1 at frame 0 to
  /// zoom 3 at frame 8 — so every frame between them resolves to a
  /// DIFFERENT pose, and a freeze that read the wrong frame would show —
  /// with an empty drawing row added beside it.
  EditorSessionManager sessionWithARamp() {
    final s = EditorSessionManager(initialProject: createDefaultProject());
    addTearDown(s.dispose);
    final size = s.requireActiveCut.canvasSize;
    final centre = CanvasPoint(x: size.width / 2, y: size.height / 2);
    s.selectFrameIndex(0);
    s.camera.setCameraKeyframeAtCurrentFrame(
      CameraPose(center: centre, zoom: 1),
    );
    s.selectFrameIndex(8);
    s.camera.setCameraKeyframeAtCurrentFrame(
      CameraPose(center: centre, zoom: 3),
    );
    s.selectFrameIndex(0);
    s.layerStack.addLayer();
    return s;
  }

  LayerId cameraOf(EditorSessionManager s) =>
      s.layers.firstWhere((layer) => layer.kind == LayerKind.camera).id;

  /// The empty drawing row [sessionWithARamp] added.
  LayerId drawingOf(EditorSessionManager s) => s.activeLayer!.id;

  /// A band over [rows] from [start] to [last], as a sweep stands it.
  void sweep(
    EditorSessionManager s,
    List<LayerId> rows,
    int start,
    int last,
  ) => s.updateFrameRangeSelectionDrag(
    layerId: rows.first,
    anchorIndex: start,
    headIndex: last,
    spanRows: [for (final id in rows) LayerRowAddress(id)],
  );

  List<int> keyFrames(EditorSessionManager s) =>
      s.requireActiveCut.camera.keyframes.keys.toList();

  int framesOf(EditorSessionManager s, LayerId id) =>
      s.layers.firstWhere((layer) => layer.id == id).frames.length;

  test('a band over the camera row and a drawing row keys the camera where '
      'it passed, the picture unmoved, and fills the drawing row — one '
      'undo', () {
    final s = sessionWithARamp();
    final before = [
      for (var frame = 0; frame < 6; frame += 1)
        s.camera.cameraPoseAtFrame(frame).zoom,
    ];
    final drawn = framesOf(s, drawingOf(s));

    sweep(s, [cameraOf(s), drawingOf(s)], 0, 5);
    s.cellInstances.createInstancesForSelection();

    expect(
      keyFrames(s),
      [0, 1, 2, 3, 4, 5, 8],
      reason:
          'every frame the band covered is keyed, and the ramp\'s far end '
          'is untouched',
    );
    for (var frame = 0; frame < 6; frame += 1) {
      expect(
        s.camera.cameraPoseAtFrame(frame).zoom,
        closeTo(before[frame], 1e-9),
        reason:
            'AE behaviour — the RESOLVED pose is what is frozen, so nothing '
            'on screen moves when the keys land',
      );
    }
    expect(framesOf(s, drawingOf(s)), drawn + 1, reason: 'the gap is filled');

    s.historyManager.undo();
    expect(keyFrames(s), [0, 8], reason: 'one press, one undo');
    expect(framesOf(s, drawingOf(s)), drawn);
  });

  test('a band of the camera row alone keys it the same', () {
    final s = sessionWithARamp();

    sweep(s, [cameraOf(s)], 0, 5);
    s.cellInstances.createInstancesForSelection();

    expect(keyFrames(s), [0, 1, 2, 3, 4, 5, 8]);
  });

  test('a band with nothing to add spends no undo step', () {
    final s = sessionWithARamp();
    sweep(s, [cameraOf(s)], 0, 5);
    s.cellInstances.createInstancesForSelection();
    final steps = s.historyManager.undoCount;

    sweep(s, [cameraOf(s)], 0, 5);
    s.cellInstances.createInstancesForSelection();

    expect(
      s.historyManager.undoCount,
      steps,
      reason:
          'every frame is keyed now — a step here would cost an undo for a '
          'no-op',
    );
  });

  test('a key already standing in the band keeps its own value', () {
    final s = sessionWithARamp();
    final size = s.requireActiveCut.canvasSize;
    s.selectFrameIndex(3);
    // A key well off the ramp: if the band overwrote it with the resolved
    // pose, this is the value that would vanish.
    s.camera.setCameraKeyframeAtCurrentFrame(
      CameraPose(center: CanvasPoint(x: 0, y: size.height / 2), zoom: 9),
    );

    sweep(s, [cameraOf(s), drawingOf(s)], 0, 5);
    s.cellInstances.createInstancesForSelection();

    expect(s.camera.cameraPoseAtFrame(3).zoom, 9);
    expect(s.camera.cameraPoseAtFrame(3).center.x, 0);
  });

  test('a band that reaches back before the first frame keys only the '
      'frames that exist', () {
    final s = sessionWithARamp();

    sweep(s, [cameraOf(s), drawingOf(s)], -3, 2);
    s.cellInstances.createInstancesForSelection();

    expect(
      keyFrames(s),
      [0, 1, 2, 8],
      reason:
          'a negative frame is not a frame — the ruler can sweep left of '
          'zero and the camera track has no room there',
    );
  });
}
