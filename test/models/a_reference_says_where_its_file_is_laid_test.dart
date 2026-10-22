import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/media_reference.dart';
import 'package:anicel/src/models/property_track.dart';
import 'package:anicel/src/models/transform_track.dart';

/// F-374 — a reference says where its file's pixels are LAID apart from
/// where it was placed ([MediaReference.laid] beside [MediaReference.pose])
/// only once the two part.
void main() {
  final placedAt = TransformPose(center: CanvasPoint(x: 100, y: 50));
  final elsewhere = TransformPose(
    center: CanvasPoint(x: 140, y: 50),
    scaleX: 2,
    scaleY: 2,
    rotationDegrees: 30,
  );

  MediaReference reference({TransformPose? laid, TransformTrack? fx}) =>
      MediaReference(
        assetPath: '/paper.png',
        pose: placedAt,
        pictureSize: const CanvasSize(width: 100, height: 60),
        laid: laid,
        fx: fx,
      );

  TransformTrack positionKeyed(Map<int, CanvasPoint> keys) =>
      TransformTrack.empty().copyWith(
        position: keys.entries.fold<PropertyTrack<CanvasPoint>>(
          PropertyTrack<CanvasPoint>(),
          (track, key) => track.withKey(key.key, key.value),
        ),
      );

  test('laid where it was placed, it says nothing more — the reference one '
      'never laid elsewhere is', () {
    final unparted = reference(laid: placedAt);

    expect(unparted.laid, placedAt);
    expect(unparted.toJson().containsKey('laid'), isFalse);
    expect(unparted, reference());
  });

  test('laid elsewhere, it says where, and reads back the same — its keys '
      'with it', () {
    final parted = reference(
      laid: elsewhere,
      fx: positionKeyed({0: CanvasPoint(x: 140, y: 50)}),
    );

    final back = MediaReference.fromJson(parted.toJson());

    expect(parted.toJson().containsKey('laid'), isTrue);
    expect(back, parted);
    expect(back.laid, elsewhere);
    expect(back.pose, placedAt, reason: 'where it was placed stays apart');
  });

  test('a copy that moves where it was placed moves an unparted '
      'reference\'s pixels with it — a sheet photo dragged — and leaves a '
      'parted one\'s where they are', () {
    final moved = TransformPose(center: CanvasPoint(x: 10, y: 10));

    expect(reference().copyWith(pose: moved).laid, moved);
    expect(reference(laid: elsewhere).copyWith(pose: moved).laid, elsewhere);
  });
}
