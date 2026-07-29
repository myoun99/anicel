import 'dart:math' as math;

import '../models/canvas_point.dart';
import '../models/canvas_size.dart';
import '../models/property_track.dart';
import '../models/transform_track.dart';
import '../services/cut_frame_composite_plan.dart' show layerIdentityPose;

/// The V track's effects as OPACITY/POSE KEYS on the TRACK's GLOBAL frame
/// axis (R4 — "the transform is not the block's": cut trims and reorders
/// never move these keys, keys exist with no cut under them, and the fade
/// handles simply write a canonical shape into the CUT'S WINDOW of the
/// one track lane).
///
/// Canonical fade shape, stated in a window [start, start+duration):
/// - fade-in over N frames: key start = 0.0, key start+N = 1.0;
/// - fade-out over M frames: key (end − M) = 1.0, key end = 0.0 — the
///   fade bottoms out ON the window's final frame (end = start +
///   duration − 1).

/// Fade lengths parsed from [track]'s opacity lane within the window;
/// (0, 0) when unkeyed there or when the window carries a non-canonical
/// (hand-keyed) shape the handles cannot represent — the lane still plays
/// back, only the handles stand down.
({int fadeInFrames, int fadeOutFrames}) trackFadeLengthsInWindow(
  TransformTrack track, {
  required int startFrame,
  required int duration,
}) {
  final opacity = track.opacity;
  if (opacity.isEmpty) {
    return (fadeInFrames: 0, fadeOutFrames: 0);
  }
  final last = startFrame + (duration <= 1 ? 0 : duration - 1);
  var fadeIn = 0;
  var fadeOut = 0;
  final startKey = opacity.keyAt(startFrame);
  if (startKey != null && startKey.value == 0.0) {
    // The first 1.0 key after the window start ends the fade-in.
    for (final entry in opacity.keys.entries) {
      if (entry.key > startFrame && entry.key <= last) {
        if (entry.value.value == 1.0) {
          fadeIn = entry.key - startFrame;
          break;
        }
      }
    }
  }
  final endKey = opacity.keyAt(last);
  if (last > startFrame && endKey != null && endKey.value == 0.0) {
    // The last 1.0 key before the window end starts the fade-out.
    for (final entry in opacity.keys.entries.toList().reversed) {
      if (entry.key >= startFrame && entry.key < last) {
        if (entry.value.value == 1.0) {
          fadeOut = last - entry.key;
          break;
        }
      }
    }
    if (fadeOut == 0) {
      // No 1.0 shoulder (fade spans the whole window): the ramp starts at
      // the fade-in end or the window start.
      fadeOut = (last - startFrame) - fadeIn;
    }
  }
  return (fadeInFrames: fadeIn, fadeOutFrames: fadeOut);
}

/// Whether [track]'s GEOMETRIC pose lanes carry any keys — the display
/// routes skip the transform entirely otherwise, so opacity-only tracks
/// (the classic fade) stay on the zero-cost path.
bool trackPoseIsActive(TransformTrack track) {
  return track.anchorPoint.isNotEmpty ||
      track.position.isNotEmpty ||
      track.scale.isNotEmpty ||
      track.rotation.isNotEmpty;
}

/// The track-level pose at GLOBAL [frameIndex] over the DISPLAY space
/// [displaySize] (the camera's output frame — the space the lanes author
/// in and the MP4 bake renders in) — AE precomp semantics: the finished
/// picture moves on the screen, above the camera projection. Identity =
/// display center / zoom 1 / rotation 0. The canvas-view preview must NOT
/// pass the canvas here — see [trackPoseForCanvasPreview].
TransformPose trackPoseAt(
  TransformTrack track,
  int frameIndex,
  CanvasSize displaySize,
) {
  return track.resolveAt(
    frameIndex: frameIndex,
    orElse: () => layerIdentityPose(displaySize),
  );
}

/// The track pose's anchor at GLOBAL [frameIndex]; null = display center.
CanvasPoint? trackAnchorPointAt(TransformTrack track, int frameIndex) =>
    resolveAnchorTrackAt(track.anchorPoint, frameIndex);

/// The composed frame's opacity at GLOBAL [frameIndex] (the fade), 1 when
/// the opacity lane is unkeyed.
double trackFadeOpacityAt(TransformTrack track, int frameIndex) {
  return track.opacity
      .resolveAt(
        frameIndex: frameIndex,
        orElse: () => 1.0,
        lerp: (a, b, t) => a + (b - a) * t,
      )
      .clamp(0.0, 1.0);
}

/// The track pose remapped for the CANVAS-VIEW preview (R8-③ fix): pose
/// keys are AUTHORED over the camera's output frame (the lanes' display
/// space), so the canvas route resolves them THERE and re-centers the
/// motion on the canvas. Resolving over the canvas instead read every key
/// in the wrong space — an untouched key (camera-frame center) sat up-left
/// of the canvas center, snapping the picture into the top-left corner.
///
/// The remap is the translation conjugation T(d)·M·T(−d) with
/// d = canvas center − frame center, which folds into a plain center +
/// anchor shift (layerPoseMatrix = T(center)·R·S·T(−anchor)). Identity
/// keys stay identity; position deltas match the camera view 1:1 in
/// canvas pixels.
({TransformPose pose, CanvasPoint anchorPoint}) trackPoseForCanvasPreview(
  TransformTrack track,
  int frameIndex, {
  required CanvasSize cameraFrameSize,
  required CanvasSize canvasSize,
}) {
  final pose = trackPoseAt(track, frameIndex, cameraFrameSize);
  final anchor =
      trackAnchorPointAt(track, frameIndex) ??
      CanvasPoint(x: cameraFrameSize.width / 2, y: cameraFrameSize.height / 2);
  final dx = (canvasSize.width - cameraFrameSize.width) / 2;
  final dy = (canvasSize.height - cameraFrameSize.height) / 2;
  return (
    pose: pose.copyWith(
      center: CanvasPoint(x: pose.center.x + dx, y: pose.center.y + dy),
    ),
    anchorPoint: CanvasPoint(x: anchor.x + dx, y: anchor.y + dy),
  );
}

/// The cut's WINDOW of [track], rebased to LOCAL frames — the per-cut
/// lane strips' display/edit projection (R4a: the strips still speak
/// cut-local; the data is the track's, on the global axis). Keys outside
/// the window vanish from the projection, exactly like the SE display
/// clone.
TransformTrack trackTransformCutWindow(
  TransformTrack track, {
  required int startFrame,
  required int duration,
}) {
  PropertyTrack<T> window<T>(PropertyTrack<T> lane) {
    var next = PropertyTrack<T>.empty();
    lane.keys.forEach((frame, key) {
      if (frame >= startFrame && frame < startFrame + duration) {
        next = next.withKey(
          frame - startFrame,
          key.value,
          interpolation: key.interpolation,
        );
      }
    });
    return next;
  }

  return TransformTrack.properties(
    anchorPoint: window(track.anchorPoint),
    position: window(track.position),
    scale: window(track.scale),
    rotation: window(track.rotation),
    opacity: window(track.opacity),
  );
}

/// [track] with the WINDOW's keys replaced by [window]'s (local frames,
/// rebased back by +[startFrame]) — the projection's write-back. Keys
/// outside the window stay untouched: they are other cuts' effects, or
/// free-standing keys on the axis.
TransformTrack trackTransformWithCutWindow(
  TransformTrack track,
  TransformTrack window, {
  required int startFrame,
  required int duration,
}) {
  PropertyTrack<T> merge<T>(PropertyTrack<T> lane, PropertyTrack<T> edited) {
    var next = lane;
    for (final frame in lane.keys.keys.toList()) {
      if (frame >= startFrame && frame < startFrame + duration) {
        next = next.withoutKey(frame);
      }
    }
    edited.keys.forEach((frame, key) {
      if (frame >= 0 && frame < duration) {
        next = next.withKey(
          startFrame + frame,
          key.value,
          interpolation: key.interpolation,
        );
      }
    });
    return next;
  }

  return TransformTrack.properties(
    anchorPoint: merge(track.anchorPoint, window.anchorPoint),
    position: merge(track.position, window.position),
    scale: merge(track.scale, window.scale),
    rotation: merge(track.rotation, window.rotation),
    opacity: merge(track.opacity, window.opacity),
  );
}

/// [track] with the WINDOW's opacity keys rebuilt to the canonical fade
/// shape — keys outside [startFrame, startFrame+duration) stay untouched
/// (they are other cuts' fades, or free-standing keys on the axis). Zero
/// lengths clear the window.
TransformTrack trackTransformWithCutFade(
  TransformTrack track, {
  required int startFrame,
  required int duration,
  required int fadeInFrames,
  required int fadeOutFrames,
}) {
  final last = math.max(0, duration - 1);
  final fadeIn = fadeInFrames.clamp(0, last).toInt();
  // The two ramps may meet but never cross (their keys would clobber each
  // other): the fade-out shortens to whatever the fade-in leaves.
  final fadeOut = fadeOutFrames.clamp(0, last - fadeIn).toInt();
  var opacity = track.opacity;
  for (final frame in track.opacity.keys.keys.toList()) {
    if (frame >= startFrame && frame < startFrame + duration) {
      opacity = opacity.withoutKey(frame);
    }
  }
  if (fadeIn > 0) {
    opacity = opacity
        .withKey(startFrame, 0.0)
        .withKey(startFrame + fadeIn, 1.0);
  }
  if (fadeOut > 0) {
    opacity = opacity
        .withKey(startFrame + last - fadeOut, 1.0)
        .withKey(startFrame + last, 0.0);
  }
  return track.copyWith(opacity: opacity);
}
