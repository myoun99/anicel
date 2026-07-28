import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/property_track.dart';
import 'package:anicel/src/models/transform_track.dart';

TransformPose _pose(double x, {double zoom = 1.0, double rotation = 0.0}) {
  return TransformPose(
    center: CanvasPoint(x: x, y: x * 2),
    zoom: zoom,
    rotationDegrees: rotation,
  );
}

void main() {
  group('TransformTrack', () {
    test('rejects negative keyframe indexes', () {
      expect(
        () => TransformTrack(keyframes: {-1: _pose(0)}),
        throwsArgumentError,
      );
    });

    test('withKeyframe and withoutKeyframe return updated copies', () {
      final track = TransformTrack.empty();
      expect(track.isEmpty, isTrue);

      final withKey = track.withKeyframe(3, _pose(10));
      expect(track.isEmpty, isTrue, reason: 'source track is immutable');
      expect(withKey.isNotEmpty, isTrue);
      expect(withKey.keyframeAt(3), _pose(10));

      final removed = withKey.withoutKeyframe(3);
      expect(removed.isEmpty, isTrue);
      expect(withKey.keyframeAt(3), _pose(10));
    });

    test('resolveAt returns orElse for an empty track', () {
      final track = TransformTrack.empty();

      expect(
        track.resolveAt(frameIndex: 5, orElse: () => _pose(99)),
        _pose(99),
      );
    });

    test('resolveAt: exact keyframes win', () {
      final track = TransformTrack(keyframes: {2: _pose(10), 6: _pose(50)});

      expect(track.resolveAt(frameIndex: 2, orElse: () => _pose(0)), _pose(10));
    });

    test('resolveAt holds before the first and after the last keyframe', () {
      final track = TransformTrack(keyframes: {2: _pose(10), 6: _pose(50)});

      expect(track.resolveAt(frameIndex: 0, orElse: () => _pose(0)), _pose(10));
      expect(track.resolveAt(frameIndex: 9, orElse: () => _pose(0)), _pose(50));
    });

    test('resolveAt lerps component-wise between keyframes', () {
      final track = TransformTrack(
        keyframes: {
          0: _pose(0, zoom: 1.0, rotation: 0.0),
          4: _pose(8, zoom: 3.0, rotation: 360.0),
        },
      );

      final mid = track.resolveAt(frameIndex: 2, orElse: () => _pose(0));

      expect(mid.center.x, 4.0);
      expect(mid.center.y, 8.0);
      expect(mid.zoom, 2.0);
      // Rotation lerps as-is (no wrap): 0 → 360 passes through 180.
      expect(mid.rotationDegrees, 180.0);
    });

    test('JSON round-trip preserves keyframes', () {
      final track = TransformTrack(
        keyframes: {0: _pose(1), 7: _pose(2, zoom: 2.5, rotation: -30)},
      );

      expect(TransformTrack.fromJson(track.toJson()), track);
    });

    test('fromJson rejects duplicate keyframe indexes', () {
      final pose = _pose(1).toJson();
      expect(
        () => TransformTrack.fromJson({
          'keyframes': [
            {'index': 3, 'pose': pose},
            {'index': 3, 'pose': pose},
          ],
        }),
        throwsFormatException,
      );
    });

    test('legacy pose-keyed json migrates to synchronized property keys', () {
      final legacy = {
        'keyframes': [
          {'index': 2, 'pose': _pose(10, zoom: 2, rotation: 45).toJson()},
        ],
      };

      final track = TransformTrack.fromJson(legacy);

      expect(track.position.keyAt(2)!.value, CanvasPoint(x: 10, y: 20));
      expect(track.scale.keyAt(2)!.value, 2);
      expect(track.rotation.keyAt(2)!.value, 45);
      expect(track.anchorPoint.isEmpty, isTrue);
      expect(track.opacity.isEmpty, isTrue);
    });
  });

  group('TransformTrack per-property (AE model)', () {
    test('properties key independently of each other', () {
      final track = TransformTrack.empty().copyWith(
        position: PropertyTrack<CanvasPoint>()
            .withKey(0, CanvasPoint(x: 0, y: 0))
            .withKey(10, CanvasPoint(x: 100, y: 0)),
        rotation: PropertyTrack<double>().withKey(4, 90),
      );

      expect(track.scale.isEmpty, isTrue);
      expect(track.keyedFrames, {0, 4, 10});

      final mid = track.resolveAt(
        frameIndex: 5,
        orElse: () => _pose(0, zoom: 3),
      );
      // Position interpolates between ITS keys; scale falls back to the
      // default; rotation holds its single key.
      expect(mid.center.x, 50);
      expect(mid.zoom, 3);
      expect(mid.rotationDegrees, 90);
    });

    test('the pose facade sees the union of keyed frames', () {
      final track = TransformTrack.empty().copyWith(
        position: PropertyTrack<CanvasPoint>().withKey(
          2,
          CanvasPoint(x: 5, y: 5),
        ),
        scale: PropertyTrack<double>().withKey(8, 2),
      );

      expect(track.keyframes.keys, [2, 8]);
      expect(track.keyframeAt(2), isNotNull);
      expect(track.keyframeAt(5), isNull);
      expect(track.keyframeAt(8), isNotNull);
    });

    test('a hold key on one property freezes only that property', () {
      final track = TransformTrack.empty().copyWith(
        position: PropertyTrack<CanvasPoint>()
            .withKey(
              0,
              CanvasPoint(x: 0, y: 0),
              interpolation: PropertyKeyInterpolation.hold,
            )
            .withKey(10, CanvasPoint(x: 100, y: 0)),
        scale: PropertyTrack<double>().withKey(0, 1).withKey(10, 3),
      );

      final mid = track.resolveAt(frameIndex: 5, orElse: () => _pose(0));

      expect(mid.center.x, 0, reason: 'position holds');
      expect(mid.zoom, 2, reason: 'scale still lerps');
    });

    test('per-property json round-trips', () {
      final track = TransformTrack.empty().copyWith(
        anchorPoint: PropertyTrack<CanvasPoint>().withKey(
          0,
          CanvasPoint(x: 1, y: 2),
        ),
        position: PropertyTrack<CanvasPoint>().withKey(
          3,
          CanvasPoint(x: 4, y: 5),
          interpolation: PropertyKeyInterpolation.hold,
        ),
        opacity: PropertyTrack<double>().withKey(6, 0.5),
      );

      final restored = TransformTrack.fromJson(track.toJson());

      expect(restored, track);
      expect(
        restored.position.keyAt(3)!.interpolation,
        PropertyKeyInterpolation.hold,
      );
    });

    test('pose-facade writes stay synchronized (camera compatibility)', () {
      final track = TransformTrack.empty()
          .withKeyframe(4, _pose(10, zoom: 2, rotation: 30))
          .withKeyframe(9, _pose(20));

      expect(track.position.keys.keys, [4, 9]);
      expect(track.scale.keys.keys, [4, 9]);
      expect(track.rotation.keys.keys, [4, 9]);
      // Round-tripping through the pose view is lossless while writes are
      // pose-synchronized (the cut-duplicate path relies on this).
      expect(TransformTrack(keyframes: Map.of(track.keyframes)), track);
    });
  });
}
