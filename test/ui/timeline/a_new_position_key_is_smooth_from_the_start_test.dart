import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/property_track.dart';
import 'package:anicel/src/models/transform_track.dart';
import 'package:anicel/src/ui/timeline/scale_lane_form.dart';
import 'package:anicel/src/ui/timeline/transform_lane_editing.dart';

/// I-89-Q10 B (유저 2026-10-12: 「AE 처럼 처음부터 곡선」) — a key new on a
/// position lane is smooth through its neighbours from the start, as After
/// Effects lays a new key on a motion path. A key already there keeps the
/// path it was given, and no other lane's key walks one.
void main() {
  CanvasPoint p(double x, double y) => CanvasPoint(x: x, y: y);

  /// A position lane with a corner at 0 and a placed handle at 10, and an
  /// anchor keyed at 0 — so a reset writes on both.
  final track = TransformTrack().copyWith(
    anchorPoint: PropertyTrack(keys: {0: PropertyKey(p(0, 0))}),
    position: PropertyTrack(
      keys: {
        0: PropertyKey(p(0, 0)),
        10: PropertyKey(p(100, 0), path: HandledPath(p(4, 4))),
      },
    ),
  );

  test('a key new on a position lane is smooth — one already there keeps '
      'its corner or its handle', () {
    final lane = track.position;
    expect(positionLaneKeyed(lane, 5, p(50, 50)).keyAt(5)!.path, KeyPath.auto);
    expect(
      positionLaneKeyed(lane, 0, p(1, 1)).keyAt(0)!.path,
      KeyPath.straight,
    );
    expect(
      positionLaneKeyed(lane, 10, p(90, 10)).keyAt(10)!.path,
      HandledPath(p(4, 4)),
    );
  });

  test('every verb that keys a position keys it so — and a key new on '
      'another lane walks no path', () {
    final pose = TransformPose(center: p(50, 50));
    final made = <String, TransformTrack?>{
      'dragged on the canvas': transformTrackWithPositionDragged(
        track,
        frameIndex: 5,
        position: p(50, 50),
      ),
      'keyed from its navigator': transformTrackWithLaneKeyToggled(
        track,
        laneId: 'position',
        frameIndex: 5,
        resolvedPose: pose,
      ),
      'typed': transformTrackWithLaneValueEdited(
        track,
        laneId: 'position',
        frameIndex: 5,
        input: '50, 50',
        scaleForm: const TwoScales(),
        scaleLinked: false,
      ),
      'keyed with the pose': track.withKeyframe(5, pose),
      'reset at the playhead': transformTrackWithGroupReset(
        track,
        frameIndexes: const [5],
        identity: pose,
        defaultAnchorPoint: p(0, 0),
      ),
    };
    for (final MapEntry(key: how, value: next) in made.entries) {
      expect(next!.position.keyAt(5)!.path, KeyPath.auto, reason: how);
    }
    expect(
      made['reset at the playhead']!.anchorPoint.keyAt(5)!.path,
      KeyPath.straight,
    );
  });
}
