import 'dart:collection';
import 'dart:math' as math;

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
/// or be taken away: no edit of the cuts leaves one past the end
/// ([cameraFollowingItsEnd]), but a file can bring one in, and a camera
/// that refused every write while it stood would have no way back in.
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

/// [camera] as its cut's last drawn frame moves from [previousLastFrame] to
/// [lastFrame] — every key it has on the frames it was drawn for kept on
/// the frames it is drawn for (I-73-camera-row-Q2: 「밖엔 애초에
/// 존재못하게」), its pose, type and name its own.
///
/// - **Grown**: the key on [previousLastFrame] moves to [lastFrame], on
///   every lane that keys it and has nothing there yet. 🗣️Q4 (유저
///   2026-10-09): 「끝 칸의 키는 늘릴때나 줄일때 컷 끝에 붙어있기만 하면되.
///   위치만 이동되도록」. The key on the FIRST frame needs nothing: frame 0
///   is where the cut begins however it is trimmed.
/// - **Shrunk**: every key on the frames that went comes in by as many
///   frames as went, the end key with them. 🗣️Q7 (유저 2026-10-09):
///   「OL삭제한다거나 하면 키를 컷 길이 줄이는거랑 동일하게 그 사라진
///   코마만큼 컷길이 움직인거랑 동일한 규칙으로 키를 앞당긴다」. A shrink the
///   hand drives stops short of every key but the end's
///   ([cameraDrawnFrameFloor]), so there the end key is the one that comes
///   in; a shrink that comes at once — an O.L taken away, a cut moved off
///   its O.L — brings in all it went past. A key coming in onto another
///   takes its frame (I-73-camera-row-Q8, `moved`, the answer
///   recommended).
///
/// ⚠️The step back is not this move the other way: what came in stays in
/// as the cut grows again, so the commands that take a のりしろ away put
/// their cameras back on the way back (`CamerasFollowTheirEnds`) — and,
/// passing through layouts on the way, settle them from where they found
/// them.
///
/// ⚠️A cut of one frame has its key on both ends at once: it stays on the
/// first as the cut grows.
CutCamera cameraFollowingItsEnd(
  CutCamera camera, {
  required int lastFrame,
  required int previousLastFrame,
}) {
  if (lastFrame < 0 || lastFrame == previousLastFrame) {
    return camera;
  }
  if (lastFrame > previousLastFrame) {
    return previousLastFrame <= 0
        ? camera
        : _cameraWithEachLane(
            camera,
            <T>(lane) => _laneWithEndKeyOut(
              lane,
              lastFrame: lastFrame,
              previousLastFrame: previousLastFrame,
            ),
          );
  }
  return _cameraWithEachLane(
    camera,
    <T>(lane) => _laneWithGoneFramesIn(
      lane,
      lastFrame: lastFrame,
      previousLastFrame: previousLastFrame,
    ),
  );
}

/// [lane] with its key on [previousLastFrame] on [lastFrame], unless
/// [lastFrame] is keyed already.
PropertyTrack<T> _laneWithEndKeyOut<T>(
  PropertyTrack<T> lane, {
  required int lastFrame,
  required int previousLastFrame,
}) {
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

/// [lane] with every key past [lastFrame], up to [previousLastFrame], in
/// by the frames that went — written after the keys that stay, so one
/// coming in onto another takes its frame. A key that was past
/// [previousLastFrame] already is not this write's to move.
PropertyTrack<T> _laneWithGoneFramesIn<T>(
  PropertyTrack<T> lane, {
  required int lastFrame,
  required int previousLastFrame,
}) {
  bool went(int frame) => frame > lastFrame && frame <= previousLastFrame;
  if (!lane.keys.keys.any(went)) {
    return lane;
  }
  final gone = previousLastFrame - lastFrame;
  return PropertyTrack(
    keys: {
      for (final entry in lane.keys.entries)
        if (!went(entry.key)) entry.key: entry.value,
      for (final entry in lane.keys.entries)
        if (went(entry.key)) math.max(0, entry.key - gone): entry.value,
    },
  );
}

/// [camera] with [edit] applied to each of its lanes — the very camera
/// when it changed none.
CutCamera _cameraWithEachLane(
  CutCamera camera,
  PropertyTrack<T> Function<T>(PropertyTrack<T> lane) edit,
) {
  final track = camera.track;
  final next = TransformTrack.properties(
    anchorPoint: edit(track.anchorPoint),
    position: edit(track.position),
    scale: edit(track.scale),
    rotation: edit(track.rotation),
    opacity: edit(track.opacity),
  );
  return next == track ? camera : CutCamera.fromTrack(next);
}

/// The fewest frames a cut drawn for [drawnFrameCount] frames may be drawn
/// for and keep [camera]'s keys on them: the key on its last frame comes in
/// with the end ([cameraFollowingItsEnd]), and every other key stays where
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
