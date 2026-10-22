import 'package:anicel/src/models/cut_camera.dart';

/// [camera] with the key at [frame] called [position], [scale] and
/// [rotation] on those lanes — a null leaves that lane's key unnamed, and
/// lanes called apart are a key whose header reads 「...」.
CutCamera cameraKeyNamed(
  CutCamera camera,
  int frame, {
  String? position,
  String? scale,
  String? rotation,
}) {
  final track = camera.track;
  return CutCamera.fromTrack(
    track.copyWith(
      position: track.position.withKeyName(frame, position),
      scale: track.scale.withKeyName(frame, scale),
      rotation: track.rotation.withKeyName(frame, rotation),
    ),
  );
}
