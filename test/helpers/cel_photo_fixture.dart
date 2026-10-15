import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cel_photo.dart';
import 'package:anicel/src/models/media_reference.dart';
import 'package:anicel/src/models/transform_pose.dart';

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
