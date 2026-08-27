import 'package:flutter/foundation.dart' show immutable;

/// The scale a DRAW's spatial effects need — which is the scale the canvas
/// transform will NOT supply.
///
/// 🚨★★★ONE NAME WAS ANSWERING THREE QUESTIONS, and this is the first of them
/// given a type of its own.
///
/// A blur radius in an effect chain is CANVAS pixels. What a draw needs is
/// something in the space it is about to land in, and there are exactly two
/// cases:
///
/// • [canvas] — the draw happens under a canvas-space CTM. **Skia maps the
///   sigma through that matrix**, so anything multiplied in here would land
///   twice: at 200% zoom a radius of 40 would blur like 160.
/// • [preScaled] — the draw happens into pixels already scaled, with no
///   matrix carrying that scale. The radii have to arrive multiplied, or a
///   Half preview shows a double-strength blur (the playback cache's own
///   note says exactly that).
///
/// ⛔SO IT CANNOT BE DERIVED, and that is why it is a value rather than a
/// computation. Reading the scale off `Canvas.getTransform()` is the obvious
/// next move and it is wrong: the editing stack's CTM already carries the
/// zoom, which is precisely why that route passes [canvas].
///
/// ⚠️THE OTHER TWO QUESTIONS ARE NOT THIS ONE, and they used to share its
/// name:
/// - what scale a SUB-TREE should raster at (`targetScale`) — a request, not
///   a description, and the plan may clamp it;
/// - what resolution an IMAGE the steps run over already has (`imageScale`)
///   — derived from the image, never passed.
///
/// 유저 2026-08-28: 「남은 개선안까지 깔끔하게가자」.
@immutable
class DrawSpace {
  const DrawSpace._(this.scale);

  /// A draw under a canvas-space CTM — Skia maps the sigma, so the chain
  /// resolves at 1.
  static const DrawSpace canvas = DrawSpace._(1);

  /// A draw into pixels already scaled by [scale], with no matrix to map
  /// anything: the chain resolves pre-multiplied.
  const DrawSpace.preScaled(double scale) : this._(scale);

  /// How much the chain's spatial parameters must be multiplied by.
  final double scale;

  /// True when this is the identity — the canvas-space case, and the one a
  /// route can take without thinking about resolution at all.
  bool get isCanvasSpace => scale == 1;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is DrawSpace && other.scale == scale;

  @override
  int get hashCode => scale.hashCode;

  @override
  String toString() =>
      isCanvasSpace ? 'DrawSpace.canvas' : 'DrawSpace.preScaled($scale)';
}
