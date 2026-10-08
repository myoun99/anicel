import 'dart:collection';

import 'camera_pose.dart';
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
