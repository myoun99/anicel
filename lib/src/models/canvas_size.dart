import 'dart:math' as math;

class CanvasSize {
  const CanvasSize({required this.width, required this.height});

  final int width;
  final int height;

  /// This size's ASPECT, laid out at [toWidth] — the output size a render
  /// at a fixed width asks for (thumbnails, conte cell pictures, the PDF's
  /// pictures).
  ///
  /// ⛔THE HEIGHT NEVER REACHES ZERO. A one-pixel-tall render is a
  /// picture; a zero-tall one is a raster the backends refuse. Every
  /// caller used to clamp this itself, which is one forgotten `max` from
  /// an export that throws on a very wide, very short camera.
  CanvasSize scaledToWidth(int toWidth) => CanvasSize(
    width: toWidth,
    height: math.max(1, (toWidth * height / width).round()),
  );

  CanvasSize copyWith({int? width, int? height}) {
    return CanvasSize(
      width: width ?? this.width,
      height: height ?? this.height,
    );
  }

  Map<String, dynamic> toJson() => {'width': width, 'height': height};

  factory CanvasSize.fromJson(Map<String, dynamic> json) {
    return CanvasSize(
      width: json['width'] as int,
      height: json['height'] as int,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CanvasSize && other.width == width && other.height == height;

  @override
  int get hashCode => Object.hash(width, height);

  @override
  String toString() => 'CanvasSize(width: $width, height: $height)';
}
