import 'package:flutter/widgets.dart' show Matrix4;
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/property_track.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/models/track_transform_migration.dart';
import 'package:anicel/src/models/transform_track.dart';
import 'package:anicel/src/ui/canvas/layer_pose_paint.dart';
import 'package:anicel/src/ui/storyboard_cut_fade_policy.dart';

Cut _cut({String id = 'cut', int duration = 10, int leadingGapFrames = 0}) =>
    Cut(
      id: CutId(id),
      name: 'CUT $id',
      layers: const [],
      duration: duration,
      canvasSize: const CanvasSize(width: 640, height: 360),
      leadingGapFrames: leadingGapFrames,
    );

Track _track({List<Cut>? cuts, TransformTrack? transformTrack}) => Track(
  id: const TrackId('track'),
  name: 'V1',
  cuts: cuts ?? [_cut()],
  transformTrack: transformTrack,
);

TransformTrack _fadeShape() => TransformTrack.empty().copyWith(
  opacity: PropertyTrack<double>.empty().withKey(0, 0.0).withKey(4, 1.0),
);

void main() {
  group('Track.transformTrack (R4 — the track owns the V effects)', () {
    test('serializes only when keyed and round-trips', () {
      final bare = _track();
      expect(bare.toJson().containsKey('transform'), isFalse);
      final restoredBare = Track.fromJson(bare.toJson());
      expect(restoredBare.transformTrack.isEmpty, isTrue);

      final keyed = _track(transformTrack: _fadeShape());
      // Track-only comparison: Cut.fromJson backfills the S1·S2/CAM
      // fixture layers onto the empty-layers fixture, so whole-track
      // equality would compare different layer lists.
      final restored = Track.fromJson(keyed.toJson());
      expect(restored.transformTrack, keyed.transformTrack);
    });

    test('fromJson lifts legacy cut-level transform entries onto the '
        'global axis (shape-based migration)', () {
      final trackJson = _track(
        cuts: [_cut(id: 'a', duration: 10), _cut(id: 'b', duration: 6)],
      ).toJson();
      final cutsJson = (trackJson['cuts'] as List<dynamic>)
          .cast<Map<String, dynamic>>();
      cutsJson[0]['transform'] = _fadeShape().toJson();
      cutsJson[1]['transform'] = TransformTrack.empty()
          .copyWith(
            scale: PropertyTrack<double>.empty().withKey(2, 2.0),
          )
          .toJson();

      final restored = Track.fromJson(trackJson);
      expect(restored.transformTrack.opacity.keyAt(0)?.value, 0.0);
      expect(restored.transformTrack.opacity.keyAt(4)?.value, 1.0);
      // Cut B starts at global 10; its local key 2 lands at 12.
      expect(restored.transformTrack.scale.keyAt(12)?.value, 2.0);
      expect(restored.transformTrack.scale.keys.length, 1);
    });

    test('a track-level transform key wins over the legacy lift', () {
      final trackJson = _track(transformTrack: _fadeShape()).toJson();
      final cutsJson = (trackJson['cuts'] as List<dynamic>)
          .cast<Map<String, dynamic>>();
      cutsJson[0]['transform'] = TransformTrack.empty()
          .copyWith(
            scale: PropertyTrack<double>.empty().withKey(0, 9.0),
          )
          .toJson();

      final restored = Track.fromJson(trackJson);
      expect(restored.transformTrack, _fadeShape());
      expect(restored.transformTrack.scale.isEmpty, isTrue);
    });

    test('Cut.fromJson ignores a legacy transform entry', () {
      final cutJson = _cut().toJson()..['transform'] = _fadeShape().toJson();
      final restored = Cut.fromJson(cutJson);
      expect(restored.toJson().containsKey('transform'), isFalse);
    });
  });

  group('liftCutTransformsToTrack', () {
    test('offsets each cut by its cumulative global start — leading gaps '
        'included, matching the storyboard layout axis', () {
      final cutA = _cut(id: 'a', duration: 10).toJson()
        ..['transform'] = _fadeShape().toJson();
      // 3 empty frames precede cut B: global start = 10 + 3 = 13.
      final cutB = _cut(id: 'b', duration: 5, leadingGapFrames: 3).toJson()
        ..['transform'] = TransformTrack.empty()
            .copyWith(
              opacity: PropertyTrack<double>.empty()
                  .withKey(0, 1.0)
                  .withKey(4, 0.0),
            )
            .toJson();

      final lifted = liftCutTransformsToTrack([cutA, cutB]);
      expect(lifted.opacity.keyAt(0)?.value, 0.0);
      expect(lifted.opacity.keyAt(4)?.value, 1.0);
      expect(lifted.opacity.keyAt(13)?.value, 1.0);
      expect(lifted.opacity.keyAt(17)?.value, 0.0);
      expect(lifted.opacity.keys.length, 4);
    });

    test('drops keys at or past the cut\'s played window — they never '
        'showed (resolveAt clamps at the window ends)', () {
      final cutJson = _cut(duration: 4).toJson()
        ..['transform'] = TransformTrack.empty()
            .copyWith(
              scale: PropertyTrack<double>.empty()
                  .withKey(1, 1.5)
                  .withKey(4, 3.0)
                  .withKey(9, 9.0),
            )
            .toJson();

      final lifted = liftCutTransformsToTrack([cutJson]);
      expect(lifted.scale.keys.keys.toList(), [1]);
    });

    test('returns the empty track when no cut carries a transform', () {
      expect(
        liftCutTransformsToTrack([
          _cut(id: 'a').toJson(),
          _cut(id: 'b').toJson(),
        ]).isEmpty,
        isTrue,
      );
    });
  });

  group('track fade policy (canonical shape in the cut window)', () {
    test('trackTransformWithCutFade writes the canonical shape both ways '
        'at a global offset', () {
      final track = trackTransformWithCutFade(
        TransformTrack.empty(),
        startFrame: 12,
        duration: 10,
        fadeInFrames: 4,
        fadeOutFrames: 3,
      );

      expect(
        trackFadeLengthsInWindow(track, startFrame: 12, duration: 10),
        (fadeInFrames: 4, fadeOutFrames: 3),
      );
      expect(trackFadeOpacityAt(track, 12), 0.0);
      expect(trackFadeOpacityAt(track, 16), 1.0);
      expect(trackFadeOpacityAt(track, 18), 1.0);
      expect(trackFadeOpacityAt(track, 21), 0.0);
    });

    test('zero lengths clear ONLY the window; keys outside it and other '
        'lanes survive', () {
      var track = TransformTrack.empty().copyWith(
        // A free-standing key BEFORE the window — another cut's fade, or a
        // hand-set key on the open axis.
        opacity: PropertyTrack<double>.empty().withKey(5, 0.25),
        scale: PropertyTrack<double>.empty().withKey(14, 1.2),
      );
      track = trackTransformWithCutFade(
        track,
        startFrame: 12,
        duration: 10,
        fadeInFrames: 2,
        fadeOutFrames: 0,
      );
      expect(track.opacity.keyAt(12)?.value, 0.0);

      final cleared = trackTransformWithCutFade(
        track,
        startFrame: 12,
        duration: 10,
        fadeInFrames: 0,
        fadeOutFrames: 0,
      );
      expect(cleared.opacity.keys.keys.toList(), [5]);
      expect(cleared.scale.keyAt(14)?.value, 1.2);
    });

    test('overlapping ramps clamp instead of clobbering each other', () {
      final track = trackTransformWithCutFade(
        TransformTrack.empty(),
        startFrame: 0,
        duration: 10,
        fadeInFrames: 7,
        fadeOutFrames: 7,
      );
      expect(
        trackFadeLengthsInWindow(track, startFrame: 0, duration: 10),
        (fadeInFrames: 7, fadeOutFrames: 2),
      );
      expect(trackFadeOpacityAt(track, 0), 0.0);
      expect(trackFadeOpacityAt(track, 7), 1.0);
      expect(trackFadeOpacityAt(track, 9), 0.0);
    });

    test('hand-keyed non-canonical shapes stand the handles down', () {
      final custom = TransformTrack.empty().copyWith(
        opacity: PropertyTrack<double>.empty().withKey(5, 0.5),
      );
      expect(
        trackFadeLengthsInWindow(custom, startFrame: 0, duration: 10),
        (fadeInFrames: 0, fadeOutFrames: 0),
      );
    });

    test('a fade in ANOTHER window reads as unfaded here', () {
      final track = trackTransformWithCutFade(
        TransformTrack.empty(),
        startFrame: 0,
        duration: 10,
        fadeInFrames: 4,
        fadeOutFrames: 0,
      );
      expect(
        trackFadeLengthsInWindow(track, startFrame: 10, duration: 6),
        (fadeInFrames: 0, fadeOutFrames: 0),
      );
    });
  });

  group('cut-window projection (the per-cut strips\' display/edit lens)', () {
    TransformTrack global() => TransformTrack.empty().copyWith(
      opacity: PropertyTrack<double>.empty()
          .withKey(5, 0.25) // before the window
          .withKey(12, 0.0)
          .withKey(16, 1.0)
          .withKey(30, 0.75), // past the window
      scale: PropertyTrack<double>.empty().withKey(14, 2.0),
    );

    test('trackTransformCutWindow rebases to local frames and drops '
        'outside keys', () {
      final window = trackTransformCutWindow(
        global(),
        startFrame: 12,
        duration: 10,
      );
      expect(window.opacity.keys.keys.toList(), [0, 4]);
      expect(window.opacity.keyAt(0)?.value, 0.0);
      expect(window.scale.keys.keys.toList(), [2]);
    });

    test('trackTransformWithCutWindow writes local edits back at the '
        'offset and preserves outside keys', () {
      final edited = TransformTrack.empty().copyWith(
        opacity: PropertyTrack<double>.empty().withKey(1, 0.5),
        // Out-of-window local keys never leak back onto the axis.
        scale: PropertyTrack<double>.empty().withKey(2, 3.0).withKey(11, 9.0),
      );
      final merged = trackTransformWithCutWindow(
        global(),
        edited,
        startFrame: 12,
        duration: 10,
      );
      expect(merged.opacity.keys.keys.toList(), [5, 13, 30]);
      expect(merged.opacity.keyAt(13)?.value, 0.5);
      expect(merged.scale.keys.keys.toList(), [14]);
      expect(merged.scale.keyAt(14)?.value, 3.0);
    });

    test('an unchanged window round-trips the track exactly', () {
      final track = global();
      final roundTripped = trackTransformWithCutWindow(
        track,
        trackTransformCutWindow(track, startFrame: 12, duration: 10),
        startFrame: 12,
        duration: 10,
      );
      expect(roundTripped, track);
    });
  });

  group('track pose policy (V track full transform)', () {
    const displaySize = CanvasSize(width: 1920, height: 1080);

    test('trackPoseIsActive fires only on GEOMETRIC keys — opacity-only '
        '(the classic fade) stays on the zero-cost path', () {
      expect(trackPoseIsActive(TransformTrack.empty()), isFalse);
      expect(
        trackPoseIsActive(
          trackTransformWithCutFade(
            TransformTrack.empty(),
            startFrame: 0,
            duration: 10,
            fadeInFrames: 3,
            fadeOutFrames: 0,
          ),
        ),
        isFalse,
      );

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
        expect(trackPoseIsActive(track), isTrue);
      }
    });

    test('trackPoseAt resolves per lane over the DISPLAY space, identity '
        'while unkeyed', () {
      final identity = trackPoseAt(TransformTrack.empty(), 0, displaySize);
      expect(identity.center, CanvasPoint(x: 960, y: 540));
      expect(identity.zoom, 1);
      expect(identity.rotationDegrees, 0);

      final posed = TransformTrack.empty().copyWith(
        position: PropertyTrack<CanvasPoint>.empty()
            .withKey(0, CanvasPoint(x: 0, y: 0))
            .withKey(4, CanvasPoint(x: 100, y: 200)),
        scale: PropertyTrack<double>.empty().withKey(0, 2.0),
      );
      final mid = trackPoseAt(posed, 2, displaySize);
      expect(mid.center, CanvasPoint(x: 50, y: 100));
      expect(mid.zoom, 2.0);
      // Unkeyed rotation stays the display identity.
      expect(mid.rotationDegrees, 0);
    });

    test('trackAnchorPointAt samples the anchor lane, null while unkeyed '
        '(consumers default to the display center)', () {
      expect(trackAnchorPointAt(TransformTrack.empty(), 0), isNull);
      final anchored = TransformTrack.empty().copyWith(
        anchorPoint: PropertyTrack<CanvasPoint>.empty().withKey(
          0,
          CanvasPoint(x: 10, y: 20),
        ),
      );
      expect(trackAnchorPointAt(anchored, 5), CanvasPoint(x: 10, y: 20));
    });
  });

  group('trackPoseForCanvasPreview (R8-③ canvas-view space remap)', () {
    const frame = CanvasSize(width: 1920, height: 1080);
    const canvas = CanvasSize(width: 5000, height: 3000);

    test('an UNTOUCHED key (camera-frame identity) stays identity on the '
        'canvas — the top-left snap regression', () {
      // Keying Position without touching the value stores the camera
      // frame's center (the lanes author in camera space).
      final posed = TransformTrack.empty().copyWith(
        position: PropertyTrack<CanvasPoint>.empty().withKey(
          0,
          CanvasPoint(x: 960, y: 540),
        ),
      );
      final preview = trackPoseForCanvasPreview(
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
      final posed = TransformTrack.empty().copyWith(
        position: PropertyTrack<CanvasPoint>.empty().withKey(
          0,
          CanvasPoint(x: 960 + 100, y: 540 + 50),
        ),
      );
      final preview = trackPoseForCanvasPreview(
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
      final posed = TransformTrack.empty().copyWith(
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
      );
      final preview = trackPoseForCanvasPreview(
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
            trackPoseAt(posed, 0, frame),
            frame,
            anchorPoint: trackAnchorPointAt(posed, 0),
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
