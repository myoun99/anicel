import 'camera_pose.dart';
import 'canvas_point.dart';

/// ONE scale along both axes, as the Scale lane keys it — a camera's zoom,
/// or a layer scaled evenly.
CanvasPoint uniformScale(double zoom) => CanvasPoint(x: zoom, y: zoom);

/// A LAYER's transform at one frame, as After Effects holds one: where its
/// anchor lands ([center] — Position), how it is scaled along each of its
/// own axes ([scaleX] · [scaleY] — Scale), and how it is turned
/// ([rotationDegrees], clockwise — Rotation).
///
/// 🗣️F-256-Q1 (유저 2026-10-06): 「**가른다 — AE 처럼 Scale X · Y(마이너스 =
/// 반전)**」. The transform TOOL's values had the two scales since F-256 ·
/// F-265 (`TransformValues`); this is the layer's own fx catching up, so
/// that a flip and a one-axis stretch are things a layer can keep without
/// its pixels being rewritten.
///
/// ↩️It was `CameraPose` by another name — `typedef TransformPose =
/// CameraPose` — one zoom, greater than zero. The camera keeps that shape
/// (the chosen option's own terms: 「카메라는 줌 하나 그대로」); a transform
/// track resolves to THIS and the camera reads its own out of it
/// ([toCameraPose]).
///
/// 🚧THE ROUND IS STAGED. The VALUE has two scales (stage one), and where a
/// row LIES is one affine — its pose under its folders', folded as their
/// product (`LayerPlacement`, stage two) — so the painter, the pick, the
/// fill, a region and a stamp each take a stretched, a flipped or a
/// sheared row as it is — and so does everything a guide measures, which
/// is measured on the canvas and read through the placement
/// (`GuideSpace`) and a conte picture's pen, laid through it as the main
/// canvas's is. Nothing lets the two scales differ YET, because two
/// readers still work a row out as a similarity: the row's box (one
/// scale a corner, and a turn measured on the canvas) and the Scale
/// lane's one number. The ones that take a number take [zoom], which is
/// how they are found.
class TransformPose {
  TransformPose({
    required this.center,
    this.scaleX = 1.0,
    this.scaleY = 1.0,
    this.rotationDegrees = 0.0,
  }) {
    for (final (name, scale) in [('scaleX', scaleX), ('scaleY', scaleY)]) {
      if (!scale.isFinite) {
        throw ArgumentError.value(
          scale,
          name,
          'A transform scale must be finite.',
        );
      }
    }
    if (!rotationDegrees.isFinite) {
      throw ArgumentError.value(
        rotationDegrees,
        'rotationDegrees',
        'TransformPose.rotationDegrees must be finite.',
      );
    }
  }

  /// The same scale along both axes — every pose there is, until the lanes
  /// can say two.
  TransformPose.uniform({
    required CanvasPoint center,
    double zoom = 1.0,
    double rotationDegrees = 0.0,
  }) : this(
         center: center,
         scaleX: zoom,
         scaleY: zoom,
         rotationDegrees: rotationDegrees,
       );

  /// A camera's pose, as the track that keys it holds one.
  TransformPose.ofCamera(CameraPose camera)
    : this.uniform(
        center: camera.center,
        zoom: camera.zoom,
        rotationDegrees: camera.rotationDegrees,
      );

  final CanvasPoint center;

  /// The scale along each of the layer's own axes, 1 being the size it has.
  /// A NEGATIVE scale is that axis mirrored (`TransformValues.sx` — a flip
  /// is a number, not a flag beside one).
  ///
  /// ZERO is the layer shown as NOTHING, as After Effects shows one: keyed
  /// from 100 to −100, the frame halfway between is this. A placement made
  /// of it has no way back to the artwork (`canvasToArtwork` — null), and
  /// every reader of a placement answers that the one way: the row is not
  /// there to be drawn, picked from, filled against, selected in or drawn
  /// on.
  /// ↩️Zero was refused here, which held while nothing could key a minus —
  /// and a pose that cannot be zero cannot be resolved on the frame a flip
  /// passes through.
  final double scaleX;
  final double scaleY;

  final double rotationDegrees;

  /// The two scales as the track keys them: one two-number value, like
  /// Position and Anchor Point (x across, y down).
  CanvasPoint get scale => CanvasPoint(x: scaleX, y: scaleY);

  /// 🚧THE ONE SCALE of a pose whose two are equal — what a reader that
  /// still works a placement out as a similarity takes (the class note).
  ///
  /// ⛔Not a way to 「get the scale」 of a pose: it asserts the two are one,
  /// and it goes when the last of those readers does.
  double get zoom {
    assert(
      scaleX == scaleY,
      'A similarity reader was handed a pose with two scales '
      '($scaleX × $scaleY): it must read the matrix.',
    );
    return scaleX;
  }

  /// The camera's pose out of a track's: its one zoom is [zoom].
  CameraPose toCameraPose() => CameraPose(
    center: center,
    zoom: zoom,
    rotationDegrees: rotationDegrees,
  );

  TransformPose copyWith({
    CanvasPoint? center,
    double? scaleX,
    double? scaleY,
    double? rotationDegrees,
  }) {
    return TransformPose(
      center: center ?? this.center,
      scaleX: scaleX ?? this.scaleX,
      scaleY: scaleY ?? this.scaleY,
      rotationDegrees: rotationDegrees ?? this.rotationDegrees,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TransformPose &&
          other.center == center &&
          other.scaleX == scaleX &&
          other.scaleY == scaleY &&
          other.rotationDegrees == rotationDegrees;

  @override
  int get hashCode => Object.hash(center, scaleX, scaleY, rotationDegrees);

  @override
  String toString() =>
      'TransformPose(center: $center, scaleX: $scaleX, scaleY: $scaleY, '
      'rotationDegrees: $rotationDegrees)';
}
