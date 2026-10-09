import 'dart:collection';

import 'camera_pose.dart';
import 'property_track.dart';
import 'transform_track.dart';

/// Per-cut camera animation: camera poses keyframed by playback frame index.
///
/// A thin cut-level wrapper over the shared [TransformTrack] mechanics (the
/// same track type layer transforms use). An empty track means the cut has
/// no camera work; consumers fall back to the default pose (canvas centered,
/// zoom 1, no rotation).
///
/// ⚠️WHERE A CAMERA'S POSE GOES IN AND COMES OUT. The track keys a scale an
/// axis and speaks [TransformPose]; a camera has one zoom (F-256-Q1, the
/// option 유저 chose on 2026-10-06 says so in its own terms: 「카메라는 줌
/// 하나 그대로」), which this writes to both axes and reads back as the one
/// it is.
class CutCamera {
  CutCamera({Map<int, CameraPose>? keyframes})
    : track = TransformTrack(
        keyframes: keyframes == null
            ? null
            : {
                for (final entry in keyframes.entries)
                  entry.key: TransformPose.ofCamera(entry.value),
              },
      );

  const CutCamera.fromTrack(this.track);

  factory CutCamera.empty() => CutCamera();

  final TransformTrack track;

  SplayTreeMap<int, CameraPose> get keyframes => SplayTreeMap.of({
    for (final entry in track.keyframes.entries)
      entry.key: entry.value.toCameraPose(),
  });

  bool get isEmpty => track.isEmpty;
  bool get isNotEmpty => track.isNotEmpty;

  CameraPose? keyframeAt(int frameIndex) =>
      track.keyframeAt(frameIndex)?.toCameraPose();

  CutCamera withKeyframe(int frameIndex, CameraPose pose) {
    return CutCamera.fromTrack(
      track.withKeyframe(frameIndex, TransformPose.ofCamera(pose)),
    );
  }

  CutCamera withoutKeyframe(int frameIndex) {
    return CutCamera.fromTrack(track.withoutKeyframe(frameIndex));
  }

  Map<String, dynamic> toJson() => track.toJson();

  factory CutCamera.fromJson(Map<String, dynamic> json) {
    return CutCamera.fromTrack(TransformTrack.fromJson(json));
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is CutCamera && other.track == track;

  @override
  int get hashCode => track.hashCode;

  @override
  String toString() => 'CutCamera(keyframes: $keyframes)';
}

/// Whether a camera key can stand on [frame] of a cut drawn for
/// [drawnFrameCount] frames — its own frames, the のりしろ an O.L asks
/// included. 🗣️I-73-camera-row-Q2 (유저 2026-10-09: 「콘티처럼 컷밖으로
/// 못나가게 클리핑」 → `own-frames`): a camera key lives there and nowhere
/// else, so the verbs that make one ask this first.
bool cameraKeyFits(int frame, {required int drawnFrameCount}) =>
    frame >= 0 && frame < drawnFrameCount;

/// Whether writing [after] over [before] puts no camera key out of a cut
/// drawn for [drawnFrameCount] frames ([cameraKeyFits]): none made there,
/// none moved there — the verbs that make a key at a frame, move a range
/// of them or drag the frame on the canvas all ask it of what they would
/// write.
///
/// A key already out there is not put out by this write, so it may stay
/// or be taken away: an O.L edit can still leave one past the end
/// (I-73's ② lane), and a camera that refused every write while it stood
/// would have no way back in.
bool cameraWriteKeepsKeysIn(
  TransformTrack before,
  TransformTrack after, {
  required int drawnFrameCount,
}) {
  final had = before.keyedFrames;
  return after.keyedFrames.every(
    (frame) =>
        had.contains(frame) ||
        cameraKeyFits(frame, drawnFrameCount: drawnFrameCount),
  );
}

/// [camera] with the key on [previousLastFrame] — the last frame its cut
/// was drawn for — moved to [lastFrame], the last one it is drawn for now:
/// on every lane that keys it and has nothing on [lastFrame] yet.
///
/// 🗣️I-73-camera-row-Q4 (유저 2026-10-09): 「끝 칸의 키는 늘릴때나
/// 줄일때 컷 끝에 붙어있기만 하면되. 위치만 이동되도록. 밖엔 애초에
/// 존재못하게하는게 지금구조잖아」 — the key on the end stays on the end
/// whether the cut grows or shrinks, its pose, type and name its own. The
/// key on the FIRST frame needs nothing: frame 0 is where the cut begins
/// however it is trimmed. Nothing is dropped, so the step back is the same
/// move the other way.
///
/// ⚠️A cut of one frame has its key on both ends at once: it stays on the
/// first.
CutCamera cameraWithItsEndKeyAt(
  CutCamera camera, {
  required int lastFrame,
  required int previousLastFrame,
}) {
  if (previousLastFrame <= 0 ||
      lastFrame < 0 ||
      lastFrame == previousLastFrame) {
    return camera;
  }
  PropertyTrack<T> moved<T>(PropertyTrack<T> lane) {
    final key = lane.keys[previousLastFrame];
    if (key == null || lane.keys.containsKey(lastFrame)) {
      return lane;
    }
    return PropertyTrack(
      keys: {
        for (final entry in lane.keys.entries)
          if (entry.key != previousLastFrame) entry.key: entry.value,
        lastFrame: key,
      },
    );
  }

  final track = camera.track;
  final next = TransformTrack.properties(
    anchorPoint: moved(track.anchorPoint),
    position: moved(track.position),
    scale: moved(track.scale),
    rotation: moved(track.rotation),
    opacity: moved(track.opacity),
  );
  return next == track ? camera : CutCamera.fromTrack(next);
}

/// The fewest frames a cut drawn for [drawnFrameCount] frames may be drawn
/// for and keep [camera]'s keys on them: the key on its last frame comes in
/// with the end ([cameraWithItsEndKeyAt]), and every other key stays where
/// it is — so up to the frame after the last of those. The camera lives
/// inside its cut, as the conte does (`minimumCutDurationFor`, 유저
/// 2026-07-27): a shrink stops short of a key rather than putting one out.
int cameraDrawnFrameFloor(CutCamera camera, {required int drawnFrameCount}) {
  final last = drawnFrameCount - 1;
  var floor = 1;
  var keysTheEnd = false;
  for (final frame in camera.track.keyedFrames) {
    if (frame == last) {
      keysTheEnd = true;
    } else if (frame + 1 > floor) {
      floor = frame + 1;
    }
  }
  // The key on the end needs a frame of its own past the others.
  return keysTheEnd && camera.track.keyedFrames.length > 1 ? floor + 1 : floor;
}
