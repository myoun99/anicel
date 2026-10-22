import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/property_track.dart';
import 'package:anicel/src/models/transform_track.dart';
import 'package:anicel/src/ui/timeline/transform_lane_editing.dart';

/// I-89 ② — a path's knob carried on the canvas bends the key it stands
/// at, on the lane it walks (`transformTrackWithPathHandle`): the handle
/// ahead or the one behind, as the box hands it, and nothing where no key
/// stands.
void main() {
  CanvasPoint p(double x, double y) => CanvasPoint(x: x, y: y);

  final lane = PropertyTrack<CanvasPoint>(
    keys: {
      0: PropertyKey(p(0, 0)),
      10: PropertyKey(
        p(100, 0),
        path: SplitPath(ahead: p(10, 0), behind: p(-5, 0)),
        name: 'A',
      ),
      20: PropertyKey(p(100, 60)),
    },
  );
  final track = TransformTrack.empty().copyWith(
    position: lane,
    anchorPoint: lane,
  );

  PropertyKey<CanvasPoint> keyOn(
    TransformTrack track,
    TransformPropertyId property,
  ) => transformPathLaneOf(track, property)!.keyAt(10)!;

  for (final (property, other) in [
    (TransformPropertyId.position, TransformPropertyId.anchorPoint),
    (TransformPropertyId.anchorPoint, TransformPropertyId.position),
  ]) {
    test('on the ${property.name} lane, the handle the box hands is the one '
        'carried — ahead or behind — and the rest of the key stays', () {
      TransformTrack carried({required bool ahead}) =>
          transformTrackWithPathHandle(
            track,
            property: property,
            frameIndex: 10,
            handle: (ahead: ahead, reach: p(0, 7)),
          );

      final ahead = carried(ahead: true);
      expect(
        keyOn(ahead, property).path,
        SplitPath(ahead: p(0, 7), behind: p(-5, 0)),
      );
      expect(
        keyOn(carried(ahead: false), property).path,
        SplitPath(ahead: p(10, 0), behind: p(0, 7)),
      );
      expect(keyOn(ahead, property).value, p(100, 0));
      expect(keyOn(ahead, property).name, 'A');
      expect(
        keyOn(ahead, other),
        lane.keyAt(10),
        reason: 'the other lane as it was',
      );
    });
  }

  test('where no key stands, nothing changes', () {
    TransformTrack carried() => transformTrackWithPathHandle(
      track,
      property: TransformPropertyId.position,
      frameIndex: 5,
      handle: (ahead: true, reach: p(3, 3)),
    );
    expect(carried, returnsNormally);
    expect(carried(), same(track));
  });
}
