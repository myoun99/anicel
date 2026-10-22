import 'dart:convert';

import 'package:anicel/src/models/brush_frame_key.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cel_photo.dart';
import 'package:anicel/src/models/media_reference.dart';
import 'package:anicel/src/models/transform_pose.dart';

/// Where the head of a cel stream of [key]'s ends: its version, the five
/// names of its key, its canvas and its tile size — and where the photos
/// stand, ahead of every tile (v4, I-97).
int celStreamHeadEnd(BrushFrameKey key) =>
    1 +
    [
      key.projectId.value,
      key.trackId.value,
      key.cutId.value,
      key.layerId.value,
      key.frameId.value,
    ].fold<int>(0, (sum, name) => sum + 2 + utf8.encode(name).length) +
    10;

/// A photo of the pool file [path] (I-97) with its centre at [center] on
/// the picture's grid — unturned, a [size] picture of its own laid at
/// [scale] (1:1 unless said).
CelPhoto photoOf(
  int id, {
  String path = 'C:/pool/photo.png',
  CanvasPoint? center,
  CanvasSize size = const CanvasSize(width: 20, height: 10),
  double scale = 1,
}) => CelPhoto(
  id: id,
  reference: MediaReference(
    assetPath: path,
    pose: TransformPose(
      center: center ?? CanvasPoint(x: 10, y: 6),
      scaleX: scale,
      scaleY: scale,
    ),
    pictureSize: size,
  ),
);
