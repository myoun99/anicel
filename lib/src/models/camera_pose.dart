import 'canvas_point.dart';
import 'canvas_size.dart';

/// A camera placement over a cut's canvas.
///
/// [center] is the camera view's center in canvas coordinates. [zoom] scales
/// the view: 1.0 means one output (camera) pixel covers one canvas pixel, 2.0
/// zooms in so the view rect covers half the canvas span per axis.
/// [rotationDegrees] rotates the view clockwise around [center]; values are
/// interpolated as-is (no wrap-around), so keyframing 0 → 360 produces a full
/// turn.
class CameraPose {
  CameraPose({
    required this.center,
    this.zoom = 1.0,
    this.rotationDegrees = 0.0,
  }) {
    if (!zoom.isFinite || zoom <= 0) {
      throw ArgumentError.value(
        zoom,
        'zoom',
        'CameraPose.zoom must be finite and greater than 0.',
      );
    }
    if (!rotationDegrees.isFinite) {
      throw ArgumentError.value(
        rotationDegrees,
        'rotationDegrees',
        'CameraPose.rotationDegrees must be finite.',
      );
    }
  }

  final CanvasPoint center;
  final double zoom;
  final double rotationDegrees;

  CameraPose copyWith({
    CanvasPoint? center,
    double? zoom,
    double? rotationDegrees,
  }) {
    return CameraPose(
      center: center ?? this.center,
      zoom: zoom ?? this.zoom,
      rotationDegrees: rotationDegrees ?? this.rotationDegrees,
    );
  }

  Map<String, dynamic> toJson() => {
    'center': center.toJson(),
    'zoom': zoom,
    'rotationDegrees': rotationDegrees,
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CameraPose &&
          other.center == center &&
          other.zoom == zoom &&
          other.rotationDegrees == rotationDegrees;

  @override
  int get hashCode => Object.hash(center, zoom, rotationDegrees);

  @override
  String toString() =>
      'CameraPose(center: $center, zoom: $zoom, '
      'rotationDegrees: $rotationDegrees)';
}

/// The camera pose used when a cut has no keyframes: centered on the canvas,
/// zoom 1, no rotation. A model's own fact — a canvas resize keys an unkeyed
/// camera where this put it (`translateCutCamera`), and models may not
/// import the resolver that reads it.
CameraPose defaultCameraPoseFor(CanvasSize canvasSize) {
  return CameraPose(
    center: CanvasPoint(x: canvasSize.width / 2, y: canvasSize.height / 2),
  );
}
