import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/property_track.dart';
import 'package:anicel/src/models/transform_track.dart';

TransformPose _pose(double x, {double zoom = 1.0, double rotation = 0.0}) {
  return TransformPose.uniform(
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
      expect(mid.scale, uniformScale(2));
      // Rotation lerps as-is (no wrap): 0 → 360 passes through 180.
      expect(mid.rotationDegrees, 180.0);
    });

    test('JSON round-trip preserves keyframes', () {
      final track = TransformTrack(
        keyframes: {0: _pose(1), 7: _pose(2, zoom: 2.5, rotation: -30)},
      );

      expect(TransformTrack.fromJson(track.toJson()), track);
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
      expect(mid.scale, uniformScale(3));
      expect(mid.rotationDegrees, 90);
    });

    test('the pose facade sees the union of keyed frames', () {
      final track = TransformTrack.empty().copyWith(
        position: PropertyTrack<CanvasPoint>().withKey(
          2,
          CanvasPoint(x: 5, y: 5),
        ),
        scale: PropertyTrack<CanvasPoint>().withKey(8, uniformScale(2)),
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
        scale: PropertyTrack<CanvasPoint>()
            .withKey(0, uniformScale(1))
            .withKey(10, uniformScale(3)),
      );

      final mid = track.resolveAt(frameIndex: 5, orElse: () => _pose(0));

      expect(mid.center.x, 0, reason: 'position holds');
      expect(mid.scale, uniformScale(2), reason: 'scale still lerps');
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

    // 🗣️F-256-Q1 (유저 2026-10-06): 「가른다 — AE 처럼 Scale X · Y」.
    test('the scale lane keys an axis apiece, and each lerps on its own', () {
      final track = TransformTrack.empty().copyWith(
        scale: PropertyTrack<CanvasPoint>()
            .withKey(0, CanvasPoint(x: 1, y: 4))
            .withKey(10, CanvasPoint(x: 3, y: -2)),
      );

      final mid = track.resolveAt(frameIndex: 5, orElse: () => _pose(0));

      expect(mid.scaleX, 2);
      expect(mid.scaleY, 1);
    });

    test('a Scale keyed from 100 to −100 across resolves the frame between '
        'them: nothing across, the whole way down', () {
      final track = TransformTrack.empty().copyWith(
        scale: PropertyTrack<CanvasPoint>.empty()
            .withKey(0, CanvasPoint(x: 1, y: 1))
            .withKey(2, CanvasPoint(x: -1, y: 1)),
      );

      final halfway = track.resolveAt(frameIndex: 1, orElse: () => _pose(0));
      expect(halfway.scaleX, 0);
      expect(halfway.scaleY, 1);
    });

    test('an unkeyed scale lane takes BOTH of the default pose\'s scales', () {
      final track = TransformTrack.empty().copyWith(
        rotation: PropertyTrack<double>().withKey(0, 90),
      );

      final resolved = track.resolveAt(
        frameIndex: 0,
        orElse: () => TransformPose(
          center: CanvasPoint(x: 0, y: 0),
          scaleX: 2,
          scaleY: -3,
        ),
      );

      expect(resolved.scale, CanvasPoint(x: 2, y: -3));
    });

    test('a pose key writes its two scales and reads them back', () {
      final pose = TransformPose(
        center: CanvasPoint(x: 5, y: 6),
        scaleX: 2,
        scaleY: -1,
        rotationDegrees: 15,
      );

      final track = TransformTrack.empty().withKeyframe(3, pose);

      expect(track.scale.keyAt(3)!.value, CanvasPoint(x: 2, y: -1));
      expect(track.keyframeAt(3), pose);
      expect(track.keyframes, {3: pose});
      expect(TransformTrack(keyframes: {3: pose}), track);
    });

    test('the two scales are saved as ONE two-number value, like Position', () {
      final track = TransformTrack.empty().copyWith(
        scale: PropertyTrack<CanvasPoint>().withKey(
          4,
          CanvasPoint(x: 1.5, y: -0.5),
          interpolation: PropertyKeyInterpolation.hold,
        ),
      );

      final json = track.toJson();

      expect(json['scale'], [
        {
          'index': 4,
          'value': {'x': 1.5, 'y': -0.5},
          'interpolation': 'hold',
        },
      ]);
      expect(TransformTrack.fromJson(json), track);
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
