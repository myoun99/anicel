import 'dart:math' as math;

import '../models/canvas_point.dart';
import '../models/canvas_size.dart';
import '../models/cut.dart';
import '../models/property_track.dart';
import '../models/transform_track.dart';
import '../services/cut_frame_composite_plan.dart' show layerIdentityPose;

/// Cut fades as OPACITY KEYS ("opacity joins the transform system", user
/// direction): the fade handles write a canonical key shape into the
/// cut-level transform's opacity lane, and the composite consumers just
/// resolve the lane per frame — any future lane editor can key arbitrary
/// shapes on the same track.
///
/// Canonical shape (what the handles read back):
/// - fade-in over N frames: key 0 = 0.0, key N = 1.0 (both linear);
/// - fade-out over M frames: key (last − M) = 1.0, key last = 0.0 — the
///   fade reaches full black ON the cut's final frame.

/// Fade lengths parsed from the opacity lane; (0, 0) when unkeyed or when
/// the lane carries a non-canonical (hand-keyed) shape the handles cannot
/// represent — the lane still plays back, only the handles stand down.
({int fadeInFrames, int fadeOutFrames}) cutFadeLengths(Cut cut) {
  final opacity = cut.transformTrack.opacity;
  if (opacity.isEmpty) {
    return (fadeInFrames: 0, fadeOutFrames: 0);
  }
  final last = math.max(0, cut.duration - 1);
  var fadeIn = 0;
  var fadeOut = 0;
  final startKey = opacity.keyAt(0);
  if (startKey != null && startKey.value == 0.0) {
    // The first 1.0 key after 0 ends the fade-in.
    for (final entry in opacity.keys.entries) {
      if (entry.key > 0 && entry.value.value == 1.0) {
        fadeIn = entry.key;
        break;
      }
    }
  }
  final endKey = opacity.keyAt(last);
  if (last > 0 && endKey != null && endKey.value == 0.0) {
    // The last 1.0 key before the end starts the fade-out.
    for (final entry in opacity.keys.entries.toList().reversed) {
      if (entry.key < last && entry.value.value == 1.0) {
        fadeOut = last - entry.key;
        break;
      }
    }
    if (fadeOut == 0) {
      // No 1.0 shoulder (fade spans the whole cut): the ramp starts at the
      // fade-in end or the cut start.
      fadeOut = last - fadeIn;
    }
  }
  return (fadeInFrames: fadeIn, fadeOutFrames: fadeOut);
}

/// Whether the cut's GEOMETRIC pose lanes carry any keys — the display
/// routes skip the transform entirely otherwise, so opacity-only cuts
/// (the classic fade) stay on the zero-cost path.
bool cutPoseIsActive(Cut cut) {
  final track = cut.transformTrack;
  return track.anchorPoint.isNotEmpty ||
      track.position.isNotEmpty ||
      track.scale.isNotEmpty ||
      track.rotation.isNotEmpty;
}

/// The cut-level pose at [frameIndex] over the DISPLAY space [displaySize]
/// (the camera's output frame — the space the lanes author in and the MP4
/// bake renders in) — AE precomp semantics, user-confirmed: the cut's
/// FINISHED picture moves on the screen, above the camera projection.
/// Identity = display center / zoom 1 / rotation 0. The canvas-view
/// preview must NOT pass the canvas here — see [cutPoseForCanvasPreview].
TransformPose cutPoseAt(Cut cut, int frameIndex, CanvasSize displaySize) {
  return cut.transformTrack.resolveAt(
    frameIndex: frameIndex,
    orElse: () => layerIdentityPose(displaySize),
  );
}

/// The cut pose's anchor at [frameIndex]; null = the display center.
CanvasPoint? cutAnchorPointAt(Cut cut, int frameIndex) =>
    resolveAnchorTrackAt(cut.transformTrack.anchorPoint, frameIndex);

/// The cut pose remapped for the CANVAS-VIEW preview (R8-③ fix): pose keys
/// are AUTHORED over the camera's output frame (the lanes' display space),
/// so the canvas route resolves them THERE and re-centers the motion on
/// the canvas. Resolving over the canvas instead read every key in the
/// wrong space — an untouched key (camera-frame center) sat up-left of the
/// canvas center, snapping the picture into the top-left corner.
///
/// The remap is the translation conjugation T(d)·M·T(−d) with
/// d = canvas center − frame center, which folds into a plain center +
/// anchor shift (layerPoseMatrix = T(center)·R·S·T(−anchor)). Identity
/// keys stay identity; position deltas match the camera view 1:1 in
/// canvas pixels.
({TransformPose pose, CanvasPoint anchorPoint}) cutPoseForCanvasPreview(
  Cut cut,
  int frameIndex, {
  required CanvasSize cameraFrameSize,
  required CanvasSize canvasSize,
}) {
  final pose = cutPoseAt(cut, frameIndex, cameraFrameSize);
  final anchor =
      cutAnchorPointAt(cut, frameIndex) ??
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

/// The cut's transform with its opacity lane rebuilt to the canonical fade
/// shape (other lanes untouched). Zero lengths clear the lane.
TransformTrack cutTransformWithFade(
  Cut cut, {
  required int fadeInFrames,
  required int fadeOutFrames,
}) {
  final last = math.max(0, cut.duration - 1);
  final fadeIn = fadeInFrames.clamp(0, last);
  // The two ramps may meet but never cross (their keys would clobber each
  // other): the fade-out shortens to whatever the fade-in leaves.
  final fadeOut = fadeOutFrames.clamp(0, last - fadeIn);
  var opacity = PropertyTrack<double>.empty();
  if (fadeIn > 0) {
    opacity = opacity.withKey(0, 0.0).withKey(fadeIn, 1.0);
  }
  if (fadeOut > 0) {
    opacity = opacity.withKey(last - fadeOut, 1.0).withKey(last, 0.0);
  }
  return cut.transformTrack.copyWith(opacity: opacity);
}
