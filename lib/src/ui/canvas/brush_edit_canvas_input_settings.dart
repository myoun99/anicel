import '../../models/brush_blend_mode.dart';
import '../../models/brush_pressure_curve.dart';
import '../../models/brush_shape.dart';
import '../../models/brush_tip_mask.dart';
import '../../models/brush_tip_rotation_mode.dart';
import '../../models/brush_tip_shape.dart';

class BrushEditCanvasInputSettings {
  factory BrushEditCanvasInputSettings({
    int color = 0xFF000000,
    double size = 1.0,
    double opacity = 1.0,
    double flow = 1.0,
    double hardness = 1.0,
    BrushTipShape tipShape = BrushTipShape.round,
    double spacing = 0.25,
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
    double roundnessJitter = 0.0,
    double spacingJitter = 0.0,
    double scatterRadiusRatio = 0.0,
    int scatterCount = 1,
    bool scatterBothAxes = true,
    BrushTipMask? dualMask,
    double dualMaskScale = 1.0,
    BrushTipMask? textureMask,
    double textureScale = 1.0,
    double textureDensity = 1.0,
    bool erase = false,
    BrushBlendMode blendMode = BrushBlendMode.color,
    double stabilizerStrength = 0.0,
  }) {
    assert(size > 0.0, 'BrushEditCanvasInputSettings.size must be > 0.');
    assert(
      stabilizerStrength >= 0.0 && stabilizerStrength <= 100.0,
      'BrushEditCanvasInputSettings.stabilizerStrength must be in [0, 100].',
    );
    assert(
      textureScale > 0.0,
      'BrushEditCanvasInputSettings.textureScale must be > 0.',
    );
    assert(
      textureDensity >= 0.0 && textureDensity <= 1.0,
      'BrushEditCanvasInputSettings.textureDensity must be in [0, 1].',
    );
    assert(
      dualMaskScale > 0.0,
      'BrushEditCanvasInputSettings.dualMaskScale must be > 0.',
    );
    assert(
      scatterRadiusRatio >= 0.0,
      'BrushEditCanvasInputSettings.scatterRadiusRatio must be >= 0.',
    );
    assert(
      scatterCount >= 1,
      'BrushEditCanvasInputSettings.scatterCount must be at least 1.',
    );
    assert(
      roundness > 0.0 && roundness <= 1.0,
      'BrushEditCanvasInputSettings.roundness must be in (0, 1].',
    );
    assert(
      opacity >= 0.0 && opacity <= 1.0,
      'BrushEditCanvasInputSettings.opacity must be between 0 and 1.',
    );
    assert(
      flow >= 0.0 && flow <= 1.0,
      'BrushEditCanvasInputSettings.flow must be between 0 and 1.',
    );
    assert(
      hardness >= 0.0 && hardness <= 1.0,
      'BrushEditCanvasInputSettings.hardness must be between 0 and 1.',
    );
    assert(spacing > 0.0, 'BrushEditCanvasInputSettings.spacing must be > 0.');
    return BrushEditCanvasInputSettings._raw(
      shape: BrushShape(
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
        roundnessJitter: roundnessJitter,
        spacingJitter: spacingJitter,
        scatterRadiusRatio: scatterRadiusRatio,
        scatterCount: scatterCount,
        scatterBothAxes: scatterBothAxes,
        dualMask: dualMask,
        dualMaskScale: dualMaskScale,
        textureMask: textureMask,
        textureScale: textureScale,
        textureDensity: textureDensity,
      ),
      erase: erase,
      blendMode: blendMode,
      stabilizerStrength: stabilizerStrength,
    );
  }

  const BrushEditCanvasInputSettings._raw({
    required this.shape,
    required this.erase,
    required this.blendMode,
    required this.stabilizerStrength,
  });

  /// Builds canvas input from an already-legal [BrushShape], carrying the whole
  /// shape across in one hop (the D4 wholesale converter path — a shared brush
  /// parameter cannot be dropped between the tool state and the canvas).
  factory BrushEditCanvasInputSettings.fromShape(
    BrushShape shape, {
    bool erase = false,
    BrushBlendMode blendMode = BrushBlendMode.color,
    double stabilizerStrength = 0.0,
  }) {
    assert(
      stabilizerStrength >= 0.0 && stabilizerStrength <= 100.0,
      'BrushEditCanvasInputSettings.stabilizerStrength must be in [0, 100].',
    );
    return BrushEditCanvasInputSettings._raw(
      shape: shape,
      erase: erase,
      blendMode: blendMode,
      stabilizerStrength: stabilizerStrength,
    );
  }

  /// The all-defaults instance, kept const so it can back a default parameter
  /// value now that the public constructor is a (non-const) factory.
  static const BrushEditCanvasInputSettings defaults =
      BrushEditCanvasInputSettings._raw(
        shape: BrushShape(size: 1.0, spacing: 0.25),
        erase: false,
        blendMode: BrushBlendMode.color,
        stabilizerStrength: 0.0,
      );

  /// The shared 26-parameter spine; the fields below forward to it. See
  /// [BrushShape].
  final BrushShape shape;

  int get color => shape.color;
  double get size => shape.size;
  double get opacity => shape.opacity;
  double get flow => shape.flow;
  double get hardness => shape.hardness;
  BrushTipShape get tipShape => shape.tipShape;
  double get spacing => shape.spacing;

  /// BB-3 (R26 #11): per-setting pressure response curves; `null` = the
  /// setting ignores pressure. See `BrushSettings` for the model story.
  BrushPressureCurve? get sizePressureCurve => shape.sizePressureCurve;
  BrushPressureCurve? get opacityPressureCurve => shape.opacityPressureCurve;
  BrushPressureCurve? get flowPressureCurve => shape.flowPressureCurve;
  BrushPressureCurve? get hardnessPressureCurve => shape.hardnessPressureCurve;

  /// Whether any pressure curve is active (the no-pressure hot path skips
  /// the per-dab dynamics pass entirely).
  bool get hasPressureDynamics =>
      sizePressureCurve != null ||
      opacityPressureCurve != null ||
      flowPressureCurve != null ||
      hardnessPressureCurve != null;

  double get roundness => shape.roundness;
  double get angleDegrees => shape.angleDegrees;
  BrushTipMask? get tipMask => shape.tipMask;
  BrushTipRotationMode get rotationMode => shape.rotationMode;
  double get sizeJitter => shape.sizeJitter;
  double get opacityJitter => shape.opacityJitter;
  double get angleJitter => shape.angleJitter;
  double get roundnessJitter => shape.roundnessJitter;
  double get spacingJitter => shape.spacingJitter;
  double get scatterRadiusRatio => shape.scatterRadiusRatio;
  int get scatterCount => shape.scatterCount;
  bool get scatterBothAxes => shape.scatterBothAxes;
  BrushTipMask? get dualMask => shape.dualMask;
  double get dualMaskScale => shape.dualMaskScale;
  BrushTipMask? get textureMask => shape.textureMask;
  double get textureScale => shape.textureScale;
  double get textureDensity => shape.textureDensity;

  /// Eraser mode: dabs remove destination alpha (destination-out) instead
  /// of painting color.
  final bool erase;

  /// The stroke's BRUSH blend (BB-1, R26 #9): how the finished stroke
  /// composites onto the cel at pen-up. [BrushBlendMode.erase] rides the
  /// [erase] flag instead (same kernels as the eraser tool).
  final BrushBlendMode blendMode;

  /// Pull-string stabilization strength (P7): the rope length in SCREEN
  /// pixels (0 = off), frozen per stroke as canvas px = strength / zoom.
  /// A hand-feel setting, deliberately not part of brush presets.
  final double stabilizerStrength;

  BrushEditCanvasInputSettings copyWith({
    int? color,
    double? size,
    double? opacity,
    double? flow,
    double? hardness,
    BrushTipShape? tipShape,
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
    double? roundnessJitter,
    double? spacingJitter,
    double? scatterRadiusRatio,
    int? scatterCount,
    bool? scatterBothAxes,
    BrushTipMask? dualMask,
    double? dualMaskScale,
    BrushTipMask? textureMask,
    double? textureScale,
    double? textureDensity,
    bool? erase,
    BrushBlendMode? blendMode,
    double? stabilizerStrength,
  }) {
    return BrushEditCanvasInputSettings(
      color: color ?? this.color,
      size: size ?? this.size,
      opacity: opacity ?? this.opacity,
      flow: flow ?? this.flow,
      hardness: hardness ?? this.hardness,
      tipShape: tipShape ?? this.tipShape,
      spacing: spacing ?? this.spacing,
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
      roundnessJitter: roundnessJitter ?? this.roundnessJitter,
      spacingJitter: spacingJitter ?? this.spacingJitter,
      scatterRadiusRatio: scatterRadiusRatio ?? this.scatterRadiusRatio,
      scatterCount: scatterCount ?? this.scatterCount,
      scatterBothAxes: scatterBothAxes ?? this.scatterBothAxes,
      dualMask: dualMask ?? this.dualMask,
      dualMaskScale: dualMaskScale ?? this.dualMaskScale,
      textureMask: textureMask ?? this.textureMask,
      textureScale: textureScale ?? this.textureScale,
      textureDensity: textureDensity ?? this.textureDensity,
      erase: erase ?? this.erase,
      blendMode: blendMode ?? this.blendMode,
      stabilizerStrength: stabilizerStrength ?? this.stabilizerStrength,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BrushEditCanvasInputSettings &&
          other.shape == shape &&
          other.erase == erase &&
          other.blendMode == blendMode &&
          other.stabilizerStrength == stabilizerStrength;

  @override
  int get hashCode => Object.hash(shape, erase, blendMode, stabilizerStrength);

  @override
  String toString() =>
      'BrushEditCanvasInputSettings(shape: $shape, erase: $erase, '
      'blendMode: $blendMode, stabilizerStrength: $stabilizerStrength)';
}
