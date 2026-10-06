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
/// 🚧THE ROUND IS STAGED, and this is its first stage: the VALUE has two
/// scales, and nothing lets them differ yet. Where a layer is PLACED is
/// still worked out as a similarity in several places — the folder chain's
/// fold (`composeLayerPoseSamples`), the selection's way into and out of a
/// posed row (`selection_placement.dart`), the row box and its corner
/// (`row_transform_box.dart`), the guides carried through a pose — and a
/// pose whose scales differed would be drawn right in one of them and
/// wrong in another. The ones that take a number take [zoom], which is how
/// they are found; they become a matrix next.
class TransformPose {
  TransformPose({
    required this.center,
    this.scaleX = 1.0,
    this.scaleY = 1.0,
    this.rotationDegrees = 0.0,
  }) {
    for (final (name, scale) in [('scaleX', scaleX), ('scaleY', scaleY)]) {
      if (!scale.isFinite || scale == 0) {
        throw ArgumentError.value(
          scale,
          name,
          'A transform scale must be finite and not zero.',
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
