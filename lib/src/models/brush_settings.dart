import 'brush_anti_alias.dart';
import 'brush_blend_mode.dart';
import 'separable_blend_mode.dart';
import 'brush_input_source.dart';
import 'brush_pressure_curve.dart';
import 'brush_shape.dart';
import 'brush_tip_mask.dart';
import 'brush_tip_rotation_mode.dart';

class BrushSettings {
  BrushSettings({
    int color = 0xFF000000,
    double size = 4.0,
    double opacity = 1.0,
    double flow = 1.0,
    double hardness = 1.0,
    double spacing = 0.1,
    BrushPressureCurve? sizePressureCurve,
    BrushPressureCurve? opacityPressureCurve,
    BrushPressureCurve? flowPressureCurve,
    BrushPressureCurve? hardnessPressureCurve,
    // The general form. The four names above are sugar for its PRESSURE
    // entries — the only shape a caller needed before sources were
    // separated, and still the common one. Anything given here wins, because
    // it is the only way to say "tilt".
    Map<BrushDynamicsKey, BrushPressureCurve> curves = const {},
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
    SeparableBlendMode dualCompositeMode = SeparableBlendMode.multiply,
    double dualDensity = 1.0,
    BrushTipMask? textureMaskSource,
    bool textureInvert = false,
    double textureBrightness = 0.0,
    double textureContrast = 0.0,
    double textureScale = 1.0,
    double textureDensity = 1.0,
    double roundnessJitter = 0.0,
    double spacingJitter = 0.0,
    BrushBlendMode blendMode = BrushBlendMode.color,
    BrushAntiAlias antiAlias = BrushAntiAlias.high,
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
         curves: {
           ...brushPressureCurves(
             size: sizePressureCurve,
             opacity: opacityPressureCurve,
             flow: flowPressureCurve,
             hardness: hardnessPressureCurve,
           ),
           ...curves,
         },
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
         dualCompositeMode: dualCompositeMode,
         dualDensity: dualDensity,
         textureMaskSource: textureMaskSource,
         textureInvert: textureInvert,
         textureBrightness: textureBrightness,
         textureContrast: textureContrast,
         textureScale: textureScale,
         textureDensity: textureDensity,
         roundnessJitter: roundnessJitter,
         spacingJitter: spacingJitter,
         blendMode: blendMode,
         antiAlias: antiAlias,
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
  SeparableBlendMode get dualCompositeMode => shape.dualCompositeMode;

  /// See [BrushShape.dualDensity].
  double get dualDensity => shape.dualDensity;
  /// See [BrushShape.textureMaskSource] — the texture as PICKED.
  BrushTipMask? get textureMaskSource => shape.textureMaskSource;
  bool get textureInvert => shape.textureInvert;
  double get textureBrightness => shape.textureBrightness;
  double get textureContrast => shape.textureContrast;

  /// See [BrushShape.textureMask] — the texture with the levels baked in,
  /// which is what a dab carries.
  BrushTipMask? get textureMask => shape.textureMask;
  double get textureScale => shape.textureScale;
  double get textureDensity => shape.textureDensity;

  double get roundnessJitter => shape.roundnessJitter;
  double get spacingJitter => shape.spacingJitter;

  /// How this brush composites — see [BrushShape.blendMode].
  BrushBlendMode get blendMode => shape.blendMode;

  /// How hard this brush's edge lands — see [BrushShape.antiAlias].
  BrushAntiAlias get antiAlias => shape.antiAlias;

  /// The curves the four legacy JSON keys cannot express.
  Map<BrushDynamicsKey, BrushPressureCurve> get _nonPressureCurves => {
    for (final entry in shape.curves.entries)
      if (entry.key.$2 != BrushInputSource.pressure) entry.key: entry.value,
  };

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
    SeparableBlendMode? dualCompositeMode,
    double? dualDensity,
    BrushTipMask? textureMaskSource,
    bool? textureInvert,
    double? textureBrightness,
    double? textureContrast,
    double? textureScale,
    double? textureDensity,
    double? roundnessJitter,
    double? spacingJitter,
    BrushBlendMode? blendMode,
    BrushAntiAlias? antiAlias,
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
      // 🚨MERGE, DO NOT REBUILD. The four names can only address
      // `(target, pressure)`; handing the constructor a map built from them
      // alone would DELETE every tilt and speed curve this brush carries,
      // silently and with no error. `BrushToolState.copyWith` was written
      // with this helper and this one was not — an adversarial review found
      // the gap on 2026-09-09, and the pin below now fails without it.
      curves:
          brushCurvesWithPressure(
            shape.curves,
            size: sizePressureCurve,
            opacity: opacityPressureCurve,
            flow: flowPressureCurve,
            hardness: hardnessPressureCurve,
          ) ??
          shape.curves,
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
      dualCompositeMode: dualCompositeMode ?? this.dualCompositeMode,
      dualDensity: dualDensity ?? this.dualDensity,
      textureMaskSource: textureMaskSource ?? this.textureMaskSource,
      textureInvert: textureInvert ?? this.textureInvert,
      textureBrightness: textureBrightness ?? this.textureBrightness,
      textureContrast: textureContrast ?? this.textureContrast,
      textureScale: textureScale ?? this.textureScale,
      textureDensity: textureDensity ?? this.textureDensity,
      roundnessJitter: roundnessJitter ?? this.roundnessJitter,
      spacingJitter: spacingJitter ?? this.spacingJitter,
      blendMode: blendMode ?? this.blendMode,
      antiAlias: antiAlias ?? this.antiAlias,
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
    if (sizePressureCurve != null)
      'sizePressureCurve': sizePressureCurve!.toJson(),
    if (opacityPressureCurve != null)
      'opacityPressureCurve': opacityPressureCurve!.toJson(),
    if (flowPressureCurve != null)
      'flowPressureCurve': flowPressureCurve!.toJson(),
    if (hardnessPressureCurve != null)
      'hardnessPressureCurve': hardnessPressureCurve!.toJson(),
    // Every OTHER source — see [_curvesToJson].
    ..._curvesToJson(_nonPressureCurves),
    'roundness': roundness,
    'angleDegrees': angleDegrees,
    if (tipMask != null) 'tipMask': tipMask!.toJson(),
    'rotationMode': rotationMode.toJson(),
    'sizeJitter': sizeJitter,
    'opacityJitter': opacityJitter,
    'angleJitter': angleJitter,
    if (roundnessJitter > 0.0) 'roundnessJitter': roundnessJitter,
    if (spacingJitter > 0.0) 'spacingJitter': spacingJitter,
    // 通常 is the default, so it writes nothing — presets saved before every
    // brush carried a blend round-trip byte-identically.
    if (blendMode != BrushBlendMode.color) 'blendMode': blendMode.name,
    // Same rule, same reason: [BrushAntiAlias.high] IS the ramp every brush
    // drew before the setting existed.
    if (antiAlias != BrushAntiAlias.high) 'antiAlias': antiAlias.name,
    'scatterRadiusRatio': scatterRadiusRatio,
    'scatterCount': scatterCount,
    'scatterBothAxes': scatterBothAxes,
    if (dualMask != null) 'dualMask': dualMask!.toJson(),
    'dualMaskScale': dualMaskScale,
    'dualDensity': dualDensity,
    if (textureMaskSource != null)
      'textureMaskSource': textureMaskSource!.toJson(),
    if (textureInvert) 'textureInvert': true,
    if (textureBrightness != 0.0) 'textureBrightness': textureBrightness,
    if (textureContrast != 0.0) 'textureContrast': textureContrast,
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
      sizePressureCurve: sizeCurve,
      opacityPressureCurve: opacityCurve,
      flowPressureCurve: curveOf('flowPressureCurve'),
      hardnessPressureCurve: curveOf('hardnessPressureCurve'),
      curves: _curvesFromJson(json['curves']),
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
      spacingJitter: (json['spacingJitter'] as num?)?.toDouble() ?? 0.0,
      // The legacy `lockedBlendMode` key reads straight in: a preset that
      // PINNED a blend now simply has it.
      blendMode: BrushBlendMode.fromJson(
        json['blendMode'] ?? json['lockedBlendMode'],
      ),
      antiAlias:
          BrushAntiAlias.named(json['antiAlias'] as String?) ??
          BrushAntiAlias.high,
      scatterRadiusRatio:
          (json['scatterRadiusRatio'] as num?)?.toDouble() ?? 0.0,
      scatterCount: json['scatterCount'] as int? ?? 1,
      scatterBothAxes: json['scatterBothAxes'] as bool? ?? true,
      dualMask: json['dualMask'] == null
          ? null
          : BrushTipMask.fromJson(json['dualMask'] as Map<String, dynamic>),
      dualMaskScale: (json['dualMaskScale'] as num?)?.toDouble() ?? 1.0,
      dualDensity: (json['dualDensity'] as num?)?.toDouble() ?? 1.0,
      textureMaskSource: json['textureMaskSource'] == null
          ? null
          : BrushTipMask.fromJson(
              json['textureMaskSource'] as Map<String, dynamic>,
            ),
      textureInvert: json['textureInvert'] as bool? ?? false,
      textureBrightness:
          (json['textureBrightness'] as num?)?.toDouble() ?? 0.0,
      textureContrast: (json['textureContrast'] as num?)?.toDouble() ?? 0.0,
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
  _validateUnitInterval(shape.spacingJitter, 'spacingJitter');
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

/// The `curves` block, or nothing at all when there is none to write — it is
/// SPREAD into [BrushSettings.toJson], so an empty map adds no key and a
/// brush that predates input sources serialises byte-for-byte as before.
///
/// 🚨THIS IS WHERE EVERY NON-PRESSURE CURVE LIVES ON DISK, and it was missing
/// for one commit. The four legacy keys can only spell `(target, pressure)`,
/// so a Clip Studio brush imported WITH its tilt curve lost it on the very
/// next save — the library persists immediately after an import — which is
/// the exact defect that round set out to end. Found by adversarial review
/// 2026-09-09, after the round had already claimed to have fixed it.
///
/// ⚠️Pressure entries stay in the four legacy keys and are NOT repeated here.
///
/// Paired with [_curvesFromJson] on purpose: one place spells the
/// `"<target>.<source>"` key, one place reads it, and they sit together.
Map<String, Object?> _curvesToJson(
  Map<BrushDynamicsKey, BrushPressureCurve> curves,
) {
  if (curves.isEmpty) {
    return const {};
  }
  return {
    'curves': {
      for (final entry in curves.entries)
        '${entry.key.$1.name}.${entry.key.$2.name}': entry.value.toJson(),
    },
  };
}

/// The `curves` block: `"<target>.<source>"` -> curve.
///
/// ⚠️An entry naming a target or a source this build does not know is
/// SKIPPED, not an error — the same rule the blend mode follows. A preset
/// written by a later version has to stay loadable, minus what it says that
/// we cannot yet hear.
Map<BrushDynamicsKey, BrushPressureCurve> _curvesFromJson(Object? json) {
  if (json is! Map) {
    return const {};
  }
  final out = <BrushDynamicsKey, BrushPressureCurve>{};
  for (final entry in json.entries) {
    final parts = '${entry.key}'.split('.');
    if (parts.length != 2 || entry.value is! List) {
      continue;
    }
    final target = BrushPressureTarget.values
        .where((t) => t.name == parts[0])
        .firstOrNull;
    final source = BrushInputSource.values
        .where((s) => s.name == parts[1])
        .firstOrNull;
    if (target == null || source == null) {
      continue;
    }
    out[(target, source)] = BrushPressureCurve.fromJson(
      entry.value as List<dynamic>,
    );
  }
  return out;
}
