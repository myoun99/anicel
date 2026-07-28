import 'package:flutter/widgets.dart' show Matrix4;
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/property_track.dart';
import 'package:anicel/src/models/transform_track.dart';
import 'package:anicel/src/ui/canvas/layer_pose_paint.dart';
import 'package:anicel/src/ui/storyboard_cut_fade_policy.dart';

Cut _cut({int duration = 10, TransformTrack? transformTrack}) => Cut(
  id: const CutId('cut'),
  name: 'CUT 1',
  layers: const [],
  duration: duration,
  canvasSize: const CanvasSize(width: 640, height: 360),
  transformTrack: transformTrack,
);

void main() {
  group('Cut.transformTrack', () {
    test('serializes only when keyed and round-trips', () {
      final bare = _cut();
      expect(bare.toJson().containsKey('transform'), isFalse);
      final restoredBare = Cut.fromJson(bare.toJson());
      expect(restoredBare.transformTrack.isEmpty, isTrue);

      final faded = _cut(
        transformTrack: TransformTrack.empty().copyWith(
          opacity: PropertyTrack<double>.empty()
              .withKey(0, 0.0)
              .withKey(4, 1.0),
        ),
      );
      // Track-only comparison: fromJson backfills the S1·S2/CAM fixture
      // layers onto the empty-layers fixture, so whole-cut equality would
      // compare different layer lists.
      final restored = Cut.fromJson(faded.toJson());
      expect(restored.transformTrack, faded.transformTrack);
    });

    test('fadeOpacityAt resolves the opacity lane, defaulting to 1', () {
      expect(_cut().fadeOpacityAt(0), 1.0);
      expect(_cut().fadeOpacityAt(9), 1.0);

      final faded = _cut(
        transformTrack: TransformTrack.empty().copyWith(
          opacity: PropertyTrack<double>.empty()
              .withKey(0, 0.0)
              .withKey(4, 1.0)
              .withKey(7, 1.0)
              .withKey(9, 0.0),
        ),
      );
      expect(faded.fadeOpacityAt(0), 0.0);
      expect(faded.fadeOpacityAt(2), closeTo(0.5, 1e-9));
      expect(faded.fadeOpacityAt(4), 1.0);
      expect(faded.fadeOpacityAt(6), 1.0);
      expect(faded.fadeOpacityAt(8), closeTo(0.5, 1e-9));
      expect(faded.fadeOpacityAt(9), 0.0);
      // Past-the-end frames hold the last key.
      expect(faded.fadeOpacityAt(20), 0.0);
    });
  });

  group('cut fade policy', () {
    test('cutTransformWithFade writes the canonical shape both ways', () {
      final faded = _cut().copyWith(
        transformTrack: cutTransformWithFade(
          _cut(),
          fadeInFrames: 4,
          fadeOutFrames: 3,
        ),
      );

      expect(cutFadeLengths(faded), (fadeInFrames: 4, fadeOutFrames: 3));
      expect(faded.fadeOpacityAt(0), 0.0);
      expect(faded.fadeOpacityAt(4), 1.0);
      expect(faded.fadeOpacityAt(6), 1.0);
      expect(faded.fadeOpacityAt(9), 0.0);
    });

    test('zero lengths clear the lane; other lanes survive', () {
      final withScale = _cut(
        transformTrack: TransformTrack.empty().copyWith(
          scale: PropertyTrack<double>.empty().withKey(0, 1.2),
        ),
      );
      final faded = withScale.copyWith(
        transformTrack: cutTransformWithFade(
          withScale,
          fadeInFrames: 2,
          fadeOutFrames: 0,
        ),
      );
      expect(faded.transformTrack.scale.isNotEmpty, isTrue);

      final cleared = faded.copyWith(
        transformTrack: cutTransformWithFade(
          faded,
          fadeInFrames: 0,
          fadeOutFrames: 0,
        ),
      );
      expect(cleared.transformTrack.opacity.isEmpty, isTrue);
      expect(cleared.transformTrack.scale.isNotEmpty, isTrue);
    });

    test('overlapping ramps clamp instead of clobbering each other', () {
      final faded = _cut().copyWith(
        transformTrack: cutTransformWithFade(
          _cut(),
          fadeInFrames: 7,
          fadeOutFrames: 7,
        ),
      );
      final lengths = cutFadeLengths(faded);
      expect(lengths.fadeInFrames, 7);
      expect(lengths.fadeOutFrames, 2);
      expect(faded.fadeOpacityAt(0), 0.0);
      expect(faded.fadeOpacityAt(7), 1.0);
      expect(faded.fadeOpacityAt(9), 0.0);
    });

    test('hand-keyed non-canonical shapes stand the handles down', () {
      final custom = _cut(
        transformTrack: TransformTrack.empty().copyWith(
          opacity: PropertyTrack<double>.empty().withKey(5, 0.5),
        ),
      );
      expect(cutFadeLengths(custom), (fadeInFrames: 0, fadeOutFrames: 0));
    });
  });

  group('cut pose policy (V track full transform)', () {
    const displaySize = CanvasSize(width: 1920, height: 1080);

    test('cutPoseIsActive fires only on GEOMETRIC keys — opacity-only '
        '(the classic fade) stays on the zero-cost path', () {
      expect(cutPoseIsActive(_cut()), isFalse);
      final fadeOnly = _cut(
        transformTrack: cutTransformWithFade(
          _cut(),
          fadeInFrames: 3,
          fadeOutFrames: 0,
        ),
      );
      expect(cutPoseIsActive(fadeOnly), isFalse);

      for (final track in [
        TransformTrack.empty().copyWith(
          position: PropertyTrack<CanvasPoint>.empty().withKey(
            0,
            CanvasPoint(x: 1, y: 2),
          ),
        ),
        TransformTrack.empty().copyWith(
          scale: PropertyTrack<double>.empty().withKey(0, 2.0),
        ),
        TransformTrack.empty().copyWith(
          rotation: PropertyTrack<double>.empty().withKey(0, 45.0),
        ),
        TransformTrack.empty().copyWith(
          anchorPoint: PropertyTrack<CanvasPoint>.empty().withKey(
            0,
            CanvasPoint(x: 3, y: 4),
          ),
        ),
      ]) {
        expect(cutPoseIsActive(_cut(transformTrack: track)), isTrue);
      }
    });

    test('cutPoseAt resolves per lane over the DISPLAY space, identity '
        'while unkeyed', () {
      final identity = cutPoseAt(_cut(), 0, displaySize);
      expect(identity.center, CanvasPoint(x: 960, y: 540));
      expect(identity.zoom, 1);
      expect(identity.rotationDegrees, 0);

      final posed = _cut(
        transformTrack: TransformTrack.empty().copyWith(
          position: PropertyTrack<CanvasPoint>.empty()
              .withKey(0, CanvasPoint(x: 0, y: 0))
              .withKey(4, CanvasPoint(x: 100, y: 200)),
          scale: PropertyTrack<double>.empty().withKey(0, 2.0),
        ),
      );
      final mid = cutPoseAt(posed, 2, displaySize);
      expect(mid.center, CanvasPoint(x: 50, y: 100));
      expect(mid.zoom, 2.0);
      // Unkeyed rotation stays the display identity.
      expect(mid.rotationDegrees, 0);
    });

    test('cutAnchorPointAt samples the anchor lane, null while unkeyed '
        '(consumers default to the display center)', () {
      expect(cutAnchorPointAt(_cut(), 0), isNull);
      final anchored = _cut(
        transformTrack: TransformTrack.empty().copyWith(
          anchorPoint: PropertyTrack<CanvasPoint>.empty().withKey(
            0,
            CanvasPoint(x: 10, y: 20),
          ),
        ),
      );
      expect(cutAnchorPointAt(anchored, 5), CanvasPoint(x: 10, y: 20));
    });
  });

  group('cutPoseForCanvasPreview (R8-③ canvas-view space remap)', () {
    const frame = CanvasSize(width: 1920, height: 1080);
    const canvas = CanvasSize(width: 5000, height: 3000);

    test('an UNTOUCHED key (camera-frame identity) stays identity on the '
        'canvas — the top-left snap regression', () {
      // Keying Position without touching the value stores the camera
      // frame's center (the lanes author in camera space).
      final posed = _cut(
        transformTrack: TransformTrack.empty().copyWith(
          position: PropertyTrack<CanvasPoint>.empty().withKey(
            0,
            CanvasPoint(x: 960, y: 540),
          ),
        ),
      );
      final preview = cutPoseForCanvasPreview(
        posed,
        0,
        cameraFrameSize: frame,
        canvasSize: canvas,
      );
      expect(preview.pose.center, CanvasPoint(x: 2500, y: 1500));
      expect(preview.anchorPoint, CanvasPoint(x: 2500, y: 1500));
      expect(
        layerPoseMatrix(preview.pose, canvas, anchorPoint: preview.anchorPoint),
        Matrix4.identity(),
        reason: 'identity in camera space must stay identity on the canvas',
      );
    });

    test('position deltas match the camera view 1:1 in canvas pixels', () {
      final posed = _cut(
        transformTrack: TransformTrack.empty().copyWith(
          position: PropertyTrack<CanvasPoint>.empty().withKey(
            0,
            CanvasPoint(x: 960 + 100, y: 540 + 50),
          ),
        ),
      );
      final preview = cutPoseForCanvasPreview(
        posed,
        0,
        cameraFrameSize: frame,
        canvasSize: canvas,
      );
      expect(preview.pose.center, CanvasPoint(x: 2600, y: 1550));
      expect(preview.anchorPoint, CanvasPoint(x: 2500, y: 1500));
    });

    test('the remap IS the translation conjugation T(d)·M·T(−d) — zoom, '
        'rotation and a keyed anchor all survive exactly', () {
      final posed = _cut(
        transformTrack: TransformTrack.empty().copyWith(
          position: PropertyTrack<CanvasPoint>.empty().withKey(
            0,
            CanvasPoint(x: 300, y: 400),
          ),
          scale: PropertyTrack<double>.empty().withKey(0, 2.0),
          rotation: PropertyTrack<double>.empty().withKey(0, 90.0),
          anchorPoint: PropertyTrack<CanvasPoint>.empty().withKey(
            0,
            CanvasPoint(x: 100, y: 200),
          ),
        ),
      );
      final preview = cutPoseForCanvasPreview(
        posed,
        0,
        cameraFrameSize: frame,
        canvasSize: canvas,
      );
      final remapped = layerPoseMatrix(
        preview.pose,
        canvas,
        anchorPoint: preview.anchorPoint,
      );

      const dx = (5000 - 1920) / 2;
      const dy = (3000 - 1080) / 2;
      final conjugated = Matrix4.translationValues(dx, dy, 0)
        ..multiply(
          layerPoseMatrix(
            cutPoseAt(posed, 0, frame),
            frame,
            anchorPoint: cutAnchorPointAt(posed, 0),
          ),
        )
        ..multiply(Matrix4.translationValues(-dx, -dy, 0));
      for (var index = 0; index < 16; index += 1) {
        expect(
          remapped.storage[index],
          closeTo(conjugated.storage[index], 1e-9),
        );
      }
    });
  });
}
