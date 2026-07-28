import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/camera_pose.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/property_track.dart';
import 'package:anicel/src/models/transform_track.dart';
import 'package:anicel/src/ui/timeline/camera_key_edit.dart';

final _pose = CameraPose(center: CanvasPoint(x: 320, y: 180));

void main() {
  test('lane states read keyed/hold from the track and values from the '
      'resolved pose', () {
    final track = TransformTrack.empty().copyWith(
      position: PropertyTrack<CanvasPoint>.empty().withKey(
        4,
        CanvasPoint(x: 10, y: 20),
        interpolation: PropertyKeyInterpolation.hold,
      ),
    );

    final states = cameraKeyLaneStatesAt(
      track,
      frameIndex: 4,
      resolvedPose: CameraPose(center: CanvasPoint(x: 10, y: 20)),
    );

    expect(states.map((s) => s.laneId), ['position', 'scale', 'rotation']);
    expect(states[0].keyed, isTrue);
    expect(states[0].hold, isTrue);
    expect(states[0].valueText, '10, 20');
    expect(states[1].keyed, isFalse);
    expect(states[1].valueText, '100%');
    expect(states[2].valueText, '0°');
  });

  test('checking a lane keys the typed value; unchecking removes; no '
      'effective change returns null', () {
    final track = TransformTrack.empty();
    final before = cameraKeyLaneStatesAt(
      track,
      frameIndex: 2,
      resolvedPose: _pose,
    );

    // Key position with an edited value.
    final keyed = transformTrackWithKeyDialogApplied(
      track,
      frameIndex: 2,
      before: before,
      after: [
        before[0].copyWith(keyed: true, valueText: '10, 20'),
        before[1],
        before[2],
      ],
    );
    expect(keyed, isNotNull);
    expect(keyed!.position.keyAt(2)!.value, CanvasPoint(x: 10, y: 20));
    expect(keyed.scale.keyAt(2), isNull);

    // Removing it again.
    final beforeRemoval = cameraKeyLaneStatesAt(
      keyed,
      frameIndex: 2,
      resolvedPose: _pose,
    );
    final removed = transformTrackWithKeyDialogApplied(
      keyed,
      frameIndex: 2,
      before: beforeRemoval,
      after: [
        beforeRemoval[0].copyWith(keyed: false),
        beforeRemoval[1],
        beforeRemoval[2],
      ],
    );
    expect(removed, isNotNull);
    expect(removed!.position.keyAt(2), isNull);

    // No change at all → null (no undo step).
    expect(
      transformTrackWithKeyDialogApplied(
        track,
        frameIndex: 2,
        before: before,
        after: before,
      ),
      isNull,
    );
  });

  test('hold flag flips the key interpolation and value edits preserve '
      'it', () {
    final track = TransformTrack.empty().copyWith(
      scale: PropertyTrack<double>.empty().withKey(3, 1.5),
    );
    final before = cameraKeyLaneStatesAt(
      track,
      frameIndex: 3,
      resolvedPose: CameraPose(center: CanvasPoint(x: 320, y: 180), zoom: 1.5),
    );
    expect(before[1].keyed, isTrue);
    expect(before[1].hold, isFalse);
    expect(before[1].valueText, '150%');

    final held = transformTrackWithKeyDialogApplied(
      track,
      frameIndex: 3,
      before: before,
      after: [
        before[0],
        before[1].copyWith(hold: true, valueText: '200%'),
        before[2],
      ],
    );
    expect(held, isNotNull);
    expect(held!.scale.keyAt(3)!.value, 2.0);
    expect(held.scale.keyAt(3)!.interpolation, PropertyKeyInterpolation.hold);

    // Garbage value on an unkeyed lane adds nothing.
    final garbage = transformTrackWithKeyDialogApplied(
      track,
      frameIndex: 3,
      before: before,
      after: [
        before[0].copyWith(keyed: true, valueText: 'not a point'),
        before[1],
        before[2],
      ],
    );
    expect(garbage, isNull);
  });
}
