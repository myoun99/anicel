import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/media_reference.dart';
import 'package:anicel/src/models/transform_pose.dart';

/// A reference to [path] for a test that is NOT about where its picture
/// stands (I-68): a 1×1 picture at the canvas's origin, 1:1. A test about
/// the pose spells its own.
MediaReference referenceTo(String path, {int frameOffset = 0}) =>
    MediaReference(
      assetPath: path,
      frameOffset: frameOffset,
      pose: TransformPose(center: CanvasPoint(x: 0, y: 0)),
      pictureSize: const CanvasSize(width: 1, height: 1),
    );
