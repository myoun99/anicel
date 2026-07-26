import 'brush_pressure_curve.dart';
import 'brush_shape.dart';
import 'brush_tip_mask.dart';
import 'brush_tip_rotation_mode.dart';
import 'brush_tip_shape.dart';

class BrushSettings {
  BrushSettings({
    int color = 0xFF000000,
    double size = 4.0,
    double opacity = 1.0,
    double flow = 1.0,
    double hardness = 1.0,
    double spacing = 0.1,
    BrushTipShape tipShape = BrushTipShape.round,
    BrushPressureCurve? sizePressureCurve,
    BrushPressureCurve? opacityPressureCurve,
    BrushPressureCurve? flowPressureCurve,
    BrushPressureCurve? hardnessPressureCurve,
    double roundness = 1.0,
    double angleDegrees = 0.0,
    BrushTipMask? tipMask,
    BrushTipRotationMode rotationMode = BrushTipRotationMode.fixed,
    double sizeJitter = 0.0,
    double opacityJitter = 0.0,
    double angleJitter = 0.0,
    double scatterRadiusRatio = 0.0,
    int scatterCount = 1,
    bool scatterBothAxes = true,
    BrushTipMask? dualMask,
    double dualMaskScale = 1.0,
    BrushTipMask? textureMask,
    double textureScale = 1.0,
    double textureDensity = 1.0,
    double roundnessJitter = 0.0,
    bool mixesGroundColor = false,
    double paintAmount = 1.0,
    double paintDensity = 1.0,
    double colorStretch = 0.0,
  }) : shape = BrushShape(
         color: color,
         size: size,
         opacity: opacity,
         flow: flow,
         hardness: hardness,
         spacing: spacing,
         tipShape: tipShape,
         sizePressureCurve: sizePressureCurve,
         opacityPressureCurve: opacityPressureCurve,
         flowPressureCurve: flowPressureCurve,
         hardnessPressureCurve: hardnessPressureCurve,
         roundness: roundness,
         angleDegrees: angleDegrees,
         tipMask: tipMask,
         rotationMode: rotationMode,
         sizeJitter: sizeJitter,
         opacityJitter: opacityJitter,
         angleJitter: angleJitter,
         scatterRadiusRatio: scatterRadiusRatio,
         scatterCount: scatterCount,
         scatterBothAxes: scatterBothAxes,
         dualMask: dualMask,
         dualMaskScale: dualMaskScale,
         textureMask: textureMask,
         textureScale: textureScale,
         textureDensity: textureDensity,
         roundnessJitter: roundnessJitter,
         mixesGroundColor: mixesGroundColor,
         paintAmount: paintAmount,
         paintDensity: paintDensity,
         colorStretch: colorStretch,
       ) {
    _validateShape(shape);
  }

  /// Wraps an already-legal [BrushShape] as a preset payload without going
  /// back through the flat parameter list — the wholesale hop the stroke
  /// chain's converters take (D4). Values are re-validated so an illegal
  /// shape still throws here rather than downstream.
  BrushSettings.fromShape(this.shape) {
    _validateShape(shape);
  }

  /// The shared 26-parameter spine; every field below forwards to it, and the
  /// stroke chain moves presets across as a whole [shape] (see [BrushShape]).
  final BrushShape shape;

  int get color => shape.color;
  double get size => shape.size;
  double get opacity => shape.opacity;
  double get flow => shape.flow;
  double get hardness => shape.hardness;
  double get spacing => shape.spacing;
  BrushTipShape get tipShape => shape.tipShape;

  /// BB-3 (R26 #11): per-setting pen-pressure response — `null` means the
  /// setting ignores pressure. These replaced the pressureSize /
  /// pressureOpacity booleans and the minimumSizeRatio floor (the floor is
  /// now the size curve's left endpoint); [fromJson] migrates the legacy
  /// keys to the equivalent straight-line curves.
  BrushPressureCurve? get sizePressureCurve => shape.sizePressureCurve;
  BrushPressureCurve? get opacityPressureCurve => shape.opacityPressureCurve;
  BrushPressureCurve? get flowPressureCurve => shape.flowPressureCurve;
  BrushPressureCurve? get hardnessPressureCurve => shape.hardnessPressureCurve;

  double get roundness => shape.roundness;
  double get angleDegrees => shape.angleDegrees;
  BrushTipMask? get tipMask => shape.tipMask;
  BrushTipRotationMode get rotationMode => shape.rotationMode;
  double get sizeJitter => shape.sizeJitter;
  double get opacityJitter => shape.opacityJitter;
  double get angleJitter => shape.angleJitter;
  double get scatterRadiusRatio => shape.scatterRadiusRatio;
  int get scatterCount => shape.scatterCount;
  bool get scatterBothAxes => shape.scatterBothAxes;
  BrushTipMask? get dualMask => shape.dualMask;
  double get dualMaskScale => shape.dualMaskScale;
  BrushTipMask? get textureMask => shape.textureMask;
  double get textureScale => shape.textureScale;
  double get textureDensity => shape.textureDensity;

  double get roundnessJitter => shape.roundnessJitter;

  /// Ground-colour mixing — see [BrushShape.mixesGroundColor].
  bool get mixesGroundColor => shape.mixesGroundColor;
  double get paintAmount => shape.paintAmount;
  double get paintDensity => shape.paintDensity;
  double get colorStretch => shape.colorStretch;

  /// The pressure curve driving [target], if any.
  BrushPressureCurve? pressureCurveFor(BrushPressureTarget target) =>
      shape.pressureCurveFor(target);

  BrushSettings copyWith({
    int? color,
    double? size,
    double? opacity,
    double? flow,
    double? hardness,
    double? spacing,
    BrushTipShape? tipShape,
    BrushPressureCurve? sizePressureCurve,
    BrushPressureCurve? opacityPressureCurve,
    BrushPressureCurve? flowPressureCurve,
    BrushPressureCurve? hardnessPressureCurve,
    double? roundness,
    double? angleDegrees,
    BrushTipMask? tipMask,
    BrushTipRotationMode? rotationMode,
    double? sizeJitter,
    double? opacityJitter,
    double? angleJitter,
    double? scatterRadiusRatio,
    int? scatterCount,
    bool? scatterBothAxes,
    BrushTipMask? dualMask,
    double? dualMaskScale,
    BrushTipMask? textureMask,
    double? textureScale,
    double? textureDensity,
    double? roundnessJitter,
    bool? mixesGroundColor,
    double? paintAmount,
    double? paintDensity,
    double? colorStretch,
  }) {
    return BrushSettings(
      color: color ?? this.color,
      size: size ?? this.size,
      opacity: opacity ?? this.opacity,
      flow: flow ?? this.flow,
      hardness: hardness ?? this.hardness,
      spacing: spacing ?? this.spacing,
      tipShape: tipShape ?? this.tipShape,
      sizePressureCurve: sizePressureCurve ?? this.sizePressureCurve,
      opacityPressureCurve: opacityPressureCurve ?? this.opacityPressureCurve,
      flowPressureCurve: flowPressureCurve ?? this.flowPressureCurve,
      hardnessPressureCurve:
          hardnessPressureCurve ?? this.hardnessPressureCurve,
      roundness: roundness ?? this.roundness,
      angleDegrees: angleDegrees ?? this.angleDegrees,
      tipMask: tipMask ?? this.tipMask,
      rotationMode: rotationMode ?? this.rotationMode,
      sizeJitter: sizeJitter ?? this.sizeJitter,
      opacityJitter: opacityJitter ?? this.opacityJitter,
      angleJitter: angleJitter ?? this.angleJitter,
      scatterRadiusRatio: scatterRadiusRatio ?? this.scatterRadiusRatio,
      scatterCount: scatterCount ?? this.scatterCount,
      scatterBothAxes: scatterBothAxes ?? this.scatterBothAxes,
      dualMask: dualMask ?? this.dualMask,
      dualMaskScale: dualMaskScale ?? this.dualMaskScale,
      textureMask: textureMask ?? this.textureMask,
      textureScale: textureScale ?? this.textureScale,
      textureDensity: textureDensity ?? this.textureDensity,
      roundnessJitter: roundnessJitter ?? this.roundnessJitter,
      mixesGroundColor: mixesGroundColor ?? this.mixesGroundColor,
      paintAmount: paintAmount ?? this.paintAmount,
      paintDensity: paintDensity ?? this.paintDensity,
      colorStretch: colorStretch ?? this.colorStretch,
    );
  }

  Map<String, dynamic> toJson() => {
    'color': color,
    'size': size,
    'opacity': opacity,
    'flow': flow,
    'hardness': hardness,
    'spacing': spacing,
    'tipShape': tipShape.toJson(),
    if (sizePressureCurve != null)
      'sizePressureCurve': sizePressureCurve!.toJson(),
    if (opacityPressureCurve != null)
      'opacityPressureCurve': opacityPressureCurve!.toJson(),
    if (flowPressureCurve != null)
      'flowPressureCurve': flowPressureCurve!.toJson(),
    if (hardnessPressureCurve != null)
      'hardnessPressureCurve': hardnessPressureCurve!.toJson(),
    'roundness': roundness,
    'angleDegrees': angleDegrees,
    if (tipMask != null) 'tipMask': tipMask!.toJson(),
    'rotationMode': rotationMode.toJson(),
    'sizeJitter': sizeJitter,
    'opacityJitter': opacityJitter,
    'angleJitter': angleJitter,
    if (roundnessJitter > 0.0) 'roundnessJitter': roundnessJitter,
    'scatterRadiusRatio': scatterRadiusRatio,
    'scatterCount': scatterCount,
    'scatterBothAxes': scatterBothAxes,
    if (dualMask != null) 'dualMask': dualMask!.toJson(),
    'dualMaskScale': dualMaskScale,
    if (textureMask != null) 'textureMask': textureMask!.toJson(),
    'textureScale': textureScale,
    'textureDensity': textureDensity,
    // Ground-colour mixing writes only when ON, so presets saved before it
    // existed round-trip byte-identically.
    if (mixesGroundColor) ...{
      'mixesGroundColor': true,
      'paintAmount': paintAmount,
      'paintDensity': paintDensity,
      'colorStretch': colorStretch,
    },
  };

  factory BrushSettings.fromJson(Map<String, dynamic> json) {
    // Legacy pressure toggles (pre-BB-3) migrate to their equivalent
    // straight-line curves: size ON was `min + (1 - min) * p` (the
    // minimumSizeRatio floor), opacity ON was plain `p`.
    BrushPressureCurve? curveOf(String key) => json[key] == null
        ? null
        : BrushPressureCurve.fromJson(json[key] as List<dynamic>);
    var sizeCurve = curveOf('sizePressureCurve');
    if (sizeCurve == null && json['pressureSize'] == true) {
      sizeCurve = BrushPressureCurve.linearFrom(
        (json['minimumSizeRatio'] as num?)?.toDouble() ?? 0.0,
      );
    }
    var opacityCurve = curveOf('opacityPressureCurve');
    if (opacityCurve == null && json['pressureOpacity'] == true) {
      opacityCurve = BrushPressureCurve.identity();
    }
    return BrushSettings(
      color: json['color'] as int,
      size: (json['size'] as num).toDouble(),
      opacity: (json['opacity'] as num).toDouble(),
      flow: (json['flow'] as num?)?.toDouble() ?? 1.0,
      hardness: (json['hardness'] as num?)?.toDouble() ?? 1.0,
      spacing: (json['spacing'] as num?)?.toDouble() ?? 0.1,
      tipShape: json.containsKey('tipShape')
          ? BrushTipShape.fromJson(json['tipShape'])
          : BrushTipShape.round,
      sizePressureCurve: sizeCurve,
      opacityPressureCurve: opacityCurve,
      flowPressureCurve: curveOf('flowPressureCurve'),
      hardnessPressureCurve: curveOf('hardnessPressureCurve'),
      roundness: (json['roundness'] as num?)?.toDouble() ?? 1.0,
      angleDegrees: (json['angleDegrees'] as num?)?.toDouble() ?? 0.0,
      tipMask: json['tipMask'] == null
          ? null
          : BrushTipMask.fromJson(json['tipMask'] as Map<String, dynamic>),
      rotationMode: BrushTipRotationMode.fromJson(json['rotationMode']),
      sizeJitter: (json['sizeJitter'] as num?)?.toDouble() ?? 0.0,
      opacityJitter: (json['opacityJitter'] as num?)?.toDouble() ?? 0.0,
      angleJitter: (json['angleJitter'] as num?)?.toDouble() ?? 0.0,
      roundnessJitter: (json['roundnessJitter'] as num?)?.toDouble() ?? 0.0,
      scatterRadiusRatio:
          (json['scatterRadiusRatio'] as num?)?.toDouble() ?? 0.0,
      scatterCount: json['scatterCount'] as int? ?? 1,
      scatterBothAxes: json['scatterBothAxes'] as bool? ?? true,
      dualMask: json['dualMask'] == null
          ? null
          : BrushTipMask.fromJson(json['dualMask'] as Map<String, dynamic>),
      dualMaskScale: (json['dualMaskScale'] as num?)?.toDouble() ?? 1.0,
      textureMask: json['textureMask'] == null
          ? null
          : BrushTipMask.fromJson(json['textureMask'] as Map<String, dynamic>),
      textureScale: (json['textureScale'] as num?)?.toDouble() ?? 1.0,
      textureDensity: (json['textureDensity'] as num?)?.toDouble() ?? 1.0,
      mixesGroundColor: json['mixesGroundColor'] as bool? ?? false,
      paintAmount: (json['paintAmount'] as num?)?.toDouble() ?? 1.0,
      paintDensity: (json['paintDensity'] as num?)?.toDouble() ?? 1.0,
      colorStretch: (json['colorStretch'] as num?)?.toDouble() ?? 0.0,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is BrushSettings && other.shape == shape;

  @override
  int get hashCode => shape.hashCode;

  @override
  String toString() => 'BrushSettings(shape: $shape)';
}

/// Throws [ArgumentError] if any parameter in [shape] is outside the model's
/// legal range. Shared by both constructors so the preset payload validates
/// identically whether it is built from flat args or wrapped from a shape.
void _validateShape(BrushShape shape) {
  if (!shape.dualMaskScale.isFinite || shape.dualMaskScale <= 0.0) {
    throw ArgumentError.value(
      shape.dualMaskScale,
      'dualMaskScale',
      'BrushSettings.dualMaskScale must be finite and greater than 0.',
    );
  }
  if (!shape.textureScale.isFinite || shape.textureScale <= 0.0) {
    throw ArgumentError.value(
      shape.textureScale,
      'textureScale',
      'BrushSettings.textureScale must be finite and greater than 0.',
    );
  }
  _validateUnitInterval(shape.textureDensity, 'textureDensity');
  _validateUnitInterval(shape.paintAmount, 'paintAmount');
  _validateUnitInterval(shape.paintDensity, 'paintDensity');
  _validateUnitInterval(shape.colorStretch, 'colorStretch');
  _validatePositive(shape.size, 'size');
  _validateUnitInterval(shape.opacity, 'opacity');
  _validateUnitInterval(shape.flow, 'flow');
  _validateUnitInterval(shape.hardness, 'hardness');
  _validatePositive(shape.spacing, 'spacing');
  _validateRoundness(shape.roundness);
  _validateFinite(shape.angleDegrees, 'angleDegrees');
  _validateUnitInterval(shape.sizeJitter, 'sizeJitter');
  _validateUnitInterval(shape.opacityJitter, 'opacityJitter');
  _validateUnitInterval(shape.angleJitter, 'angleJitter');
  _validateUnitInterval(shape.roundnessJitter, 'roundnessJitter');
  _validateNonNegativeFinite(shape.scatterRadiusRatio, 'scatterRadiusRatio');
  if (shape.scatterCount < 1) {
    throw ArgumentError.value(
      shape.scatterCount,
      'scatterCount',
      'BrushSettings.scatterCount must be at least 1.',
    );
  }
}

void _validatePositive(double value, String fieldName) {
  if (value <= 0) {
    throw ArgumentError.value(
      value,
      fieldName,
      'BrushSettings.$fieldName must be greater than 0.',
    );
  }
}

void _validateUnitInterval(double value, String fieldName) {
  if (value < 0.0 || value > 1.0) {
    throw ArgumentError.value(
      value,
      fieldName,
      'BrushSettings.$fieldName must be between 0.0 and 1.0 inclusive.',
    );
  }
}

void _validateRoundness(double value) {
  if (!value.isFinite || value <= 0.0 || value > 1.0) {
    throw ArgumentError.value(
      value,
      'roundness',
      'BrushSettings.roundness must be finite and in (0.0, 1.0].',
    );
  }
}

void _validateFinite(double value, String fieldName) {
  if (!value.isFinite) {
    throw ArgumentError.value(
      value,
      fieldName,
      'BrushSettings.$fieldName must be finite.',
    );
  }
}

void _validateNonNegativeFinite(double value, String fieldName) {
  if (!value.isFinite || value < 0.0) {
    throw ArgumentError.value(
      value,
      fieldName,
      'BrushSettings.$fieldName must be finite and non-negative.',
    );
  }
}
