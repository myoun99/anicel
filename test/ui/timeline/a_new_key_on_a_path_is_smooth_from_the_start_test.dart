import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/property_track.dart';
import 'package:anicel/src/models/transform_track.dart';
import 'package:anicel/src/ui/timeline/scale_lane_form.dart';
import 'package:anicel/src/ui/timeline/transform_lane_editing.dart';

/// I-89-Q10 B (유저 2026-10-12: 「AE 처럼 처음부터 곡선」) — a key new on a
/// lane whose keys walk a path is smooth through its neighbours from the
/// start, as After Effects lays a new key on a motion path: a position's,
/// and an anchor point's since its keys walk one too (anchor-walks-a-path,
/// 유저 2026-10-13 「구조는 최대한 AE랑 통일하려고」). A key already there
/// keeps the path it was given, and no other lane's key walks one.
void main() {
  CanvasPoint p(double x, double y) => CanvasPoint(x: x, y: y);

  /// A position lane with a corner at 0 and a placed handle at 10, and an
  /// anchor and a scale keyed at 0 — so a reset writes on all three.
  final track = TransformTrack().copyWith(
    anchorPoint: PropertyTrack(keys: {0: PropertyKey(p(0, 0))}),
    position: PropertyTrack(
      keys: {
        0: PropertyKey(p(0, 0)),
        10: PropertyKey(
          p(100, 0),
          path: const JoinedPath(degrees: 45, ahead: 4, behind: 4),
        ),
      },
    ),
    scale: PropertyTrack(keys: {0: PropertyKey(p(1, 1))}),
  );

  test('a key new on a position lane is smooth — one already there keeps '
      'its corner or its handle', () {
    final lane = track.position;
    expect(pathLaneKeyed(lane, 5, p(50, 50)).keyAt(5)!.path, KeyPath.auto);
    expect(
      pathLaneKeyed(lane, 0, p(1, 1)).keyAt(0)!.path,
      KeyPath.straight,
    );
    expect(
      pathLaneKeyed(lane, 10, p(90, 10)).keyAt(10)!.path,
      const JoinedPath(degrees: 45, ahead: 4, behind: 4),
    );
  });

  test('every verb that keys a position or an anchor point keys it so — '
      'and a key new on another lane walks no path', () {
    final pose = TransformPose(center: p(50, 50));
    TransformTrack? toggled(String laneId) => transformTrackWithLaneKeyToggled(
      track,
      laneId: laneId,
      frameIndex: 5,
      resolvedPose: pose,
      resolvedAnchorPoint: p(50, 50),
    );
    TransformTrack? typed(String laneId) => transformTrackWithLaneValueEdited(
      track,
      laneId: laneId,
      frameIndex: 5,
      input: '50, 50',
      scaleForm: const TwoScales(),
      scaleLinked: false,
    );
    final reset = transformTrackWithGroupReset(
      track,
      frameIndexes: const [5],
      identity: pose,
      defaultAnchorPoint: p(0, 0),
    )!;
    final made = <String, PropertyKey<CanvasPoint>?>{
      'a position dragged on the canvas': transformTrackWithPositionDragged(
        track,
        frameIndex: 5,
        position: p(50, 50),
      ).position.keyAt(5),
      'a position keyed from its navigator': toggled(
        'position',
      )!.position.keyAt(5),
      'a position typed': typed('position')!.position.keyAt(5),
      'a position keyed with the pose': track
          .withKeyframe(5, pose)
          .position
          .keyAt(5),
      'a position reset at the playhead': reset.position.keyAt(5),
      'an anchor dragged on the canvas': transformTrackWithAnchorDragged(
        track,
        frameIndex: 5,
        anchorPoint: p(50, 50),
      ).anchorPoint.keyAt(5),
      'an anchor keyed from its navigator': toggled(
        'anchor-point',
      )!.anchorPoint.keyAt(5),
      'an anchor typed': typed('anchor-point')!.anchorPoint.keyAt(5),
      'an anchor reset at the playhead': reset.anchorPoint.keyAt(5),
    };
    for (final MapEntry(key: how, value: key) in made.entries) {
      expect(key!.path, KeyPath.auto, reason: how);
    }
    expect(reset.scale.keyAt(5)!.path, KeyPath.straight);
  });
}
