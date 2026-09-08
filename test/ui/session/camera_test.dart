import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/camera_pose.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/timeline_frame_range.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/session/camera.dart';

/// CREATE CAMERA KEYS OVER A RANGE — the AE behaviour: keys appear, the
/// picture does not move.
///
/// [Camera.cameraKeysCommandForRange] is the one verb of the camera
/// collaborator that nothing in the suite named at all. It freezes the
/// RESOLVED pose at every unkeyed frame the sweep covers, leaves the keys
/// that are already there alone, and answers null when there is nothing to
/// add — the last part is what keeps a sweep over an already-keyed run
/// from spending an undo step on a write that changes nothing.
///
/// 🚨Reached through [Camera] by name so `tool/mutation_run.dart` can aim
/// at the file: it picks the tests that witness a mutation by asking which
/// tests IMPORT it, and every camera pin arrived through the session.
void main() {
  Camera cameraOf(EditorSessionManager s) => s.camera;

  /// A session whose active cut ramps the camera from zoom 1 at frame 0 to
  /// zoom 3 at frame 8 — so every frame between them resolves to a
  /// DIFFERENT pose, and a freeze that read the wrong frame would show.
  EditorSessionManager sessionWithARamp() {
    final s = EditorSessionManager(initialProject: createDefaultProject());
    addTearDown(s.dispose);
    final size = s.requireActiveCut.canvasSize;
    final centre = CanvasPoint(x: size.width / 2, y: size.height / 2);
    s.selectFrameIndex(0);
    cameraOf(
      s,
    ).setCameraKeyframeAtCurrentFrame(CameraPose(center: centre, zoom: 1));
    s.selectFrameIndex(8);
    cameraOf(
      s,
    ).setCameraKeyframeAtCurrentFrame(CameraPose(center: centre, zoom: 3));
    s.selectFrameIndex(0);
    return s;
  }

  TimelineFrameRangeSelection range(
    EditorSessionManager s,
    int start,
    int endExclusive,
  ) => TimelineFrameRangeSelection(
    layerId: s.activeLayer!.id,
    startIndex: start,
    endIndexExclusive: endExclusive,
  );

  List<int> keyFrames(EditorSessionManager s) =>
      s.requireActiveCut.camera.keyframes.keys.toList();

  test('the keys appear where the sweep passed, and the picture does not '
      'move', () {
    final s = sessionWithARamp();
    final before = [
      for (var frame = 0; frame < 6; frame += 1)
        cameraOf(s).cameraPoseAtFrame(frame).zoom,
    ];

    final command = cameraOf(s).cameraKeysCommandForRange(range(s, 0, 6));
    expect(command, isNotNull);
    s.historyManager.execute(command!);

    expect(
      keyFrames(s),
      [0, 1, 2, 3, 4, 5, 8],
      reason:
          'every frame the sweep covered is keyed, and the ramp\'s far '
          'end is untouched',
    );
    for (var frame = 0; frame < 6; frame += 1) {
      expect(
        cameraOf(s).cameraPoseAtFrame(frame).zoom,
        closeTo(before[frame], 1e-9),
        reason:
            'AE behaviour — the RESOLVED pose is what is frozen, so '
            'nothing on screen moves when the keys land',
      );
    }
  });

  test('a sweep with nothing to add is null, not a command that writes the '
      'same thing back', () {
    final s = sessionWithARamp();
    s.historyManager.execute(
      cameraOf(s).cameraKeysCommandForRange(range(s, 0, 6))!,
    );

    expect(
      cameraOf(s).cameraKeysCommandForRange(range(s, 0, 6)),
      isNull,
      reason:
          'every frame is keyed now — a command here would cost an '
          'undo step for a no-op',
    );
  });

  test('a key already standing in the range keeps its own value', () {
    final s = sessionWithARamp();
    final size = s.requireActiveCut.canvasSize;
    s.selectFrameIndex(3);
    // A key well off the ramp: if the sweep overwrote it with the resolved
    // pose, this is the value that would vanish.
    cameraOf(s).setCameraKeyframeAtCurrentFrame(
      CameraPose(center: CanvasPoint(x: 0, y: size.height / 2), zoom: 9),
    );

    s.historyManager.execute(
      cameraOf(s).cameraKeysCommandForRange(range(s, 0, 6))!,
    );

    expect(cameraOf(s).cameraPoseAtFrame(3).zoom, 9);
    expect(cameraOf(s).cameraPoseAtFrame(3).center.x, 0);
  });

  test('a range that reaches back before the first frame keys only the '
      'frames that exist', () {
    final s = sessionWithARamp();

    final command = cameraOf(s).cameraKeysCommandForRange(range(s, -3, 3));
    expect(command, isNotNull);
    s.historyManager.execute(command!);

    expect(
      keyFrames(s),
      [0, 1, 2, 8],
      reason:
          'a negative frame is not a frame — the ruler can sweep left '
          'of zero and the camera track has no room there',
    );
  });
}
