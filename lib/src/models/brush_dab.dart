import 'brush_input_sample.dart';
import 'brush_settings.dart';
import 'brush_stamp_image.dart';
import 'brush_tip_mask.dart';
import 'brush_tip_shape.dart';
import 'canvas_point.dart';

class BrushDab {
  BrushDab({
    required this.center,
    required this.color,
    required this.size,
    required this.opacity,
    required this.flow,
    required this.hardness,
    required this.tipShape,
    required this.pressure,
    required this.sequence,
    this.roundness = 1.0,
    this.angleDegrees = 0.0,
    this.tipMask,
    this.dualMask,
    this.dualMaskScale = 1.0,
    this.dualOffsetU = 0.0,
    this.dualOffsetV = 0.0,
    this.textureMask,
    this.textureScale = 1.0,
    this.textureDensity = 1.0,
    this.erase = false,
    this.stamp,
  }) {
    if (!textureScale.isFinite || textureScale <= 0.0) {
      throw ArgumentError.value(
        textureScale,
        'textureScale',
        'BrushDab.textureScale must be finite and greater than 0.',
      );
    }
    _validateUnitIntervalFinite(textureDensity, 'textureDensity');
    _validateColor(color);
    if (!dualMaskScale.isFinite || dualMaskScale <= 0.0) {
      throw ArgumentError.value(
        dualMaskScale,
        'dualMaskScale',
        'BrushDab.dualMaskScale must be finite and greater than 0.',
      );
    }
    _validateFinite(dualOffsetU, 'dualOffsetU');
    _validateFinite(dualOffsetV, 'dualOffsetV');
    _validateNonNegativeFinite(size, 'size');
    _validateUnitIntervalFinite(opacity, 'opacity');
    _validateUnitIntervalFinite(flow, 'flow');
    _validateUnitIntervalFinite(hardness, 'hardness');
    _validateUnitIntervalFinite(pressure, 'pressure');
    _validateRoundness(roundness);
    _validateFinite(angleDegrees, 'angleDegrees');
    _validateSequence(sequence);
  }

  factory BrushDab.fromInputSample({
    required BrushInputSample sample,
    required BrushSettings settings,
    required int sequence,
  }) {
    // BB-3: each setting's pressure curve scales its base value (null =
    // the setting ignores pressure). The old minimum-size floor is the
    // size curve's left endpoint, so light strokes still never vanish.
    final pressure = sample.pressure;
    return BrushDab(
      center: CanvasPoint(x: sample.x, y: sample.y),
      color: settings.color,
      size:
          settings.size *
          (settings.sizePressureCurve?.evaluate(pressure) ?? 1.0),
      // F-12: the pressure curve ALONE. A dab's opacity is its own
      // variation; the tool's opacity is the accumulated stroke's ceiling
      // and rides `BrushDabSequence.opacity` (see
      // `brushInputSamplesToBrushDabs`, which builds that sequence).
      opacity: settings.opacityPressureCurve?.evaluate(pressure) ?? 1.0,
      flow:
          settings.flow *
          (settings.flowPressureCurve?.evaluate(pressure) ?? 1.0),
      hardness:
          settings.hardness *
          (settings.hardnessPressureCurve?.evaluate(pressure) ?? 1.0),
      tipShape: settings.tipShape,
      pressure: sample.pressure,
      sequence: sequence,
      roundness: settings.roundness,
      angleDegrees: settings.angleDegrees,
      tipMask: settings.tipMask,
      dualMask: settings.dualMask,
      dualMaskScale: settings.dualMaskScale,
      textureMask: settings.textureMask,
      textureScale: settings.textureScale,
      textureDensity: settings.textureDensity,
    );
  }

  final CanvasPoint center;
  final int color;
  final double size;
  final double opacity;
  final double flow;
  final double hardness;
  final BrushTipShape tipShape;
  final double pressure;
  final int sequence;

  /// Minor-to-major axis ratio of the tip in (0, 1]: 1.0 keeps the classic
  /// circle/square, smaller values flatten it into an ellipse/rectangle.
  final double roundness;

  /// Visual counterclockwise rotation of the tip's major axis from the
  /// horizontal, in degrees. Meaningless for a full-round circle.
  final double angleDegrees;

  /// Sampled (bitmap) tip; when set it overrides [tipShape] and [hardness]
  /// and coverage comes from bilinear-sampling the mask in tip space.
  final BrushTipMask? tipMask;

  /// Dual-brush mask: a second tip texture that MULTIPLIES the dab's
  /// coverage, tiled across the dab at [dualMaskScale] times the dab size
  /// with a per-dab random phase ([dualOffsetU]/[dualOffsetV], 0..1 of the
  /// tile period) chosen at placement time.
  final BrushTipMask? dualMask;
  final double dualMaskScale;
  final double dualOffsetU;
  final double dualOffsetV;

  /// Paper texture: a mask tiled in CANVAS space (anchored to the canvas,
  /// no per-dab phase) whose sample darkens coverage by [textureDensity]:
  /// `coverage *= (1 - density) + density * sample`. Tile period =
  /// `textureMask.size * textureScale` canvas pixels.
  final BrushTipMask? textureMask;
  final double textureScale;
  final double textureDensity;

  /// Erase mode: the dab's coverage REMOVES destination alpha
  /// (destination-out) instead of painting color over it. The color still
  /// supplies the source alpha; RGB is ignored.
  final bool erase;

  /// RGBA stamp (R14-④ bitmap lift): when set, the dab draws the stamp's
  /// pixels 1:1 source-over centered on [center] (no resampling; [opacity]
  /// still modulates) and every tip/texture/erase field is ignored. [size]
  /// should be max(stamp.width, stamp.height) so dirty-region math covers
  /// the rect.
  final BrushStampImage? stamp;

  BrushDab copyWith({
    CanvasPoint? center,
    int? color,
    double? size,
    double? opacity,
    double? flow,
    double? hardness,
    BrushTipShape? tipShape,
    double? pressure,
    int? sequence,
    double? roundness,
    double? angleDegrees,
    BrushTipMask? tipMask,
    BrushTipMask? dualMask,
    double? dualMaskScale,
    double? dualOffsetU,
    double? dualOffsetV,
    BrushTipMask? textureMask,
    double? textureScale,
    double? textureDensity,
    bool? erase,
    BrushStampImage? stamp,
  }) {
    return BrushDab(
      center: center ?? this.center,
      color: color ?? this.color,
      size: size ?? this.size,
      opacity: opacity ?? this.opacity,
      flow: flow ?? this.flow,
      hardness: hardness ?? this.hardness,
      tipShape: tipShape ?? this.tipShape,
      pressure: pressure ?? this.pressure,
      sequence: sequence ?? this.sequence,
      roundness: roundness ?? this.roundness,
      angleDegrees: angleDegrees ?? this.angleDegrees,
      tipMask: tipMask ?? this.tipMask,
      dualMask: dualMask ?? this.dualMask,
      dualMaskScale: dualMaskScale ?? this.dualMaskScale,
      dualOffsetU: dualOffsetU ?? this.dualOffsetU,
      dualOffsetV: dualOffsetV ?? this.dualOffsetV,
      textureMask: textureMask ?? this.textureMask,
      textureScale: textureScale ?? this.textureScale,
      textureDensity: textureDensity ?? this.textureDensity,
      erase: erase ?? this.erase,
      stamp: stamp ?? this.stamp,
    );
  }

  Map<String, dynamic> toJson() => {
    'center': center.toJson(),
    'color': color,
    'size': size,
    'opacity': opacity,
    'flow': flow,
    'hardness': hardness,
    'tipShape': tipShape.toJson(),
    'pressure': pressure,
    'sequence': sequence,
    'roundness': roundness,
    'angleDegrees': angleDegrees,
    if (tipMask != null) 'tipMask': tipMask!.toJson(),
    if (dualMask != null) 'dualMask': dualMask!.toJson(),
    'dualMaskScale': dualMaskScale,
    'dualOffsetU': dualOffsetU,
    'dualOffsetV': dualOffsetV,
    if (textureMask != null) 'textureMask': textureMask!.toJson(),
    'textureScale': textureScale,
    'textureDensity': textureDensity,
    if (erase) 'erase': true,
    if (stamp != null) 'stamp': stamp!.toJson(),
  };

  factory BrushDab.fromJson(Map<String, dynamic> json) {
    return BrushDab(
      center: CanvasPoint.fromJson(json['center'] as Map<String, dynamic>),
      color: json['color'] as int? ?? 0xFF000000,
      size: (json['size'] as num).toDouble(),
      opacity: (json['opacity'] as num).toDouble(),
      flow: (json['flow'] as num).toDouble(),
      hardness: (json['hardness'] as num).toDouble(),
      tipShape: BrushTipShape.fromJson(json['tipShape']),
      pressure: (json['pressure'] as num).toDouble(),
      sequence: json['sequence'] as int,
      roundness: (json['roundness'] as num?)?.toDouble() ?? 1.0,
      angleDegrees: (json['angleDegrees'] as num?)?.toDouble() ?? 0.0,
      tipMask: json['tipMask'] == null
          ? null
          : BrushTipMask.fromJson(json['tipMask'] as Map<String, dynamic>),
      dualMask: json['dualMask'] == null
          ? null
          : BrushTipMask.fromJson(json['dualMask'] as Map<String, dynamic>),
      dualMaskScale: (json['dualMaskScale'] as num?)?.toDouble() ?? 1.0,
      dualOffsetU: (json['dualOffsetU'] as num?)?.toDouble() ?? 0.0,
      dualOffsetV: (json['dualOffsetV'] as num?)?.toDouble() ?? 0.0,
      textureMask: json['textureMask'] == null
          ? null
          : BrushTipMask.fromJson(json['textureMask'] as Map<String, dynamic>),
      textureScale: (json['textureScale'] as num?)?.toDouble() ?? 1.0,
      textureDensity: (json['textureDensity'] as num?)?.toDouble() ?? 1.0,
      erase: json['erase'] as bool? ?? false,
      stamp: json['stamp'] == null
          ? null
          : BrushStampImage.fromJson(json['stamp'] as Map<String, dynamic>),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BrushDab &&
          other.center == center &&
          other.color == color &&
          other.size == size &&
          other.opacity == opacity &&
          other.flow == flow &&
          other.hardness == hardness &&
          other.tipShape == tipShape &&
          other.pressure == pressure &&
          other.sequence == sequence &&
          other.roundness == roundness &&
          other.angleDegrees == angleDegrees &&
          other.tipMask == tipMask &&
          other.dualMask == dualMask &&
          other.dualMaskScale == dualMaskScale &&
          other.dualOffsetU == dualOffsetU &&
          other.dualOffsetV == dualOffsetV &&
          other.textureMask == textureMask &&
          other.textureScale == textureScale &&
          other.textureDensity == textureDensity &&
          other.erase == erase &&
          other.stamp == stamp;

  @override
  int get hashCode => Object.hashAll([
    center,
    color,
    size,
    opacity,
    flow,
    hardness,
    tipShape,
    pressure,
    sequence,
    roundness,
    angleDegrees,
    tipMask,
    dualMask,
    dualMaskScale,
    dualOffsetU,
    dualOffsetV,
    textureMask,
    textureScale,
    textureDensity,
    erase,
    stamp,
  ]);

  @override
  String toString() =>
      'BrushDab(center: $center, color: $color, size: $size, '
      'opacity: $opacity, flow: $flow, hardness: $hardness, '
      'tipShape: $tipShape, pressure: $pressure, sequence: $sequence, '
      'roundness: $roundness, angleDegrees: $angleDegrees, '
      'tipMask: $tipMask)';
}

void _validateColor(int value) {
  if (value < 0 || value > 0xFFFFFFFF) {
    throw ArgumentError.value(
      value,
      'color',
      'BrushDab.color must be between 0 and 0xFFFFFFFF inclusive.',
    );
  }
}

void _validateNonNegativeFinite(double value, String fieldName) {
  if (!value.isFinite || value < 0.0) {
    throw ArgumentError.value(
      value,
      fieldName,
      'BrushDab.$fieldName must be finite and greater than or equal to 0.0.',
    );
  }
}

void _validateUnitIntervalFinite(double value, String fieldName) {
  if (!value.isFinite || value < 0.0 || value > 1.0) {
    throw ArgumentError.value(
      value,
      fieldName,
      'BrushDab.$fieldName must be finite and between 0.0 and 1.0 inclusive.',
    );
  }
}

void _validateRoundness(double value) {
  if (!value.isFinite || value <= 0.0 || value > 1.0) {
    throw ArgumentError.value(
      value,
      'roundness',
      'BrushDab.roundness must be finite and in (0.0, 1.0].',
    );
  }
}

void _validateFinite(double value, String fieldName) {
  if (!value.isFinite) {
    throw ArgumentError.value(
      value,
      fieldName,
      'BrushDab.$fieldName must be finite.',
    );
  }
}

void _validateSequence(int value) {
  if (value < 0) {
    throw ArgumentError.value(
      value,
      'sequence',
      'BrushDab.sequence must be greater than or equal to 0.',
    );
  }
}
