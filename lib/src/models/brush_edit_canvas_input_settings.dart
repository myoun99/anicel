import 'brush_anti_alias.dart';
import 'brush_blend_mode.dart';
import 'brush_correction.dart';
import 'separable_blend_mode.dart';
import 'brush_pressure_curve.dart';
import 'brush_shape.dart';
import 'brush_tip_mask.dart';
import 'brush_tip_order.dart';
import 'brush_texture_mode.dart';
import 'brush_tip_rotation_mode.dart';

class BrushEditCanvasInputSettings {
  factory BrushEditCanvasInputSettings({
    int color = 0xFF000000,
    double size = 1.0,
    double opacity = 1.0,
    double flow = 1.0,
    double hardness = 1.0,
    double spacing = 0.25,
    BrushPressureCurve? sizePressureCurve,
    BrushPressureCurve? opacityPressureCurve,
    BrushPressureCurve? flowPressureCurve,
    BrushPressureCurve? hardnessPressureCurve,
    // The general form; the four names above are sugar for its PRESSURE
    // entries. Anything given here wins, because it is the only way to say
    // "tilt".
    Map<BrushDynamicsKey, BrushPressureCurve> curves = const {},
    double roundness = 1.0,
    double angleDegrees = 0.0,
    List<BrushTipMask> tips = const [],
    BrushTipOrder tipOrder = BrushTipOrder.repeat,
    int tipsPerTurn = 1,
    BrushTipRotationMode rotationMode = BrushTipRotationMode.fixed,
    double angleJitter = 0.0,
    double scatterRadiusRatio = 0.0,
    int scatterCount = 1,
    bool scatterBothAxes = true,
    BrushTipMask? dualMask,
    double dualMaskScale = 1.0,
    double dualDensity = 1.0,
    SeparableBlendMode dualCompositeMode = SeparableBlendMode.multiply,
    BrushTipMask? textureMaskSource,
    bool textureInvert = false,
    double textureBrightness = 0.0,
    double textureContrast = 0.0,
    double textureScale = 1.0,
    double textureDensity = 1.0,
    BrushTextureMode textureMode = BrushTextureMode.multiply,
    bool erase = false,
    BrushBlendMode blendMode = BrushBlendMode.color,
    BrushAntiAlias antiAlias = BrushAntiAlias.high,
    BrushCorrection correction = const BrushCorrection(),
  }) {
    assert(size > 0.0, 'BrushEditCanvasInputSettings.size must be > 0.');
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
        tips: tips,
        tipOrder: tipOrder,
        tipsPerTurn: tipsPerTurn,
        rotationMode: rotationMode,
        angleJitter: angleJitter,
        scatterRadiusRatio: scatterRadiusRatio,
        scatterCount: scatterCount,
        scatterBothAxes: scatterBothAxes,
        dualMask: dualMask,
        dualMaskScale: dualMaskScale,
        dualDensity: dualDensity,
        dualCompositeMode: dualCompositeMode,
        textureMaskSource: textureMaskSource,
        textureInvert: textureInvert,
        textureBrightness: textureBrightness,
        textureContrast: textureContrast,
        textureScale: textureScale,
        textureDensity: textureDensity,
        textureMode: textureMode,
        antiAlias: antiAlias,
        correction: correction,
      ),
      erase: erase,
      blendMode: blendMode,
    );
  }

  const BrushEditCanvasInputSettings._raw({
    required this.shape,
    required this.erase,
    required this.blendMode,
  });

  /// Builds canvas input from an already-legal [BrushShape], carrying the whole
  /// shape across in one hop (the D4 wholesale converter path — a shared brush
  /// parameter cannot be dropped between the tool state and the canvas).
  factory BrushEditCanvasInputSettings.fromShape(
    BrushShape shape, {
    bool erase = false,
    BrushBlendMode blendMode = BrushBlendMode.color,
  }) {
    return BrushEditCanvasInputSettings._raw(
      shape: shape,
      erase: erase,
      blendMode: blendMode,
    );
  }

  /// The all-defaults instance, kept const so it can back a default parameter
  /// value now that the public constructor is a (non-const) factory.
  static const BrushEditCanvasInputSettings defaults =
      BrushEditCanvasInputSettings._raw(
        shape: BrushShape(size: 1.0, spacing: 0.25),
        erase: false,
        blendMode: BrushBlendMode.color,
      );

  /// The shared 26-parameter spine; the fields below forward to it. See
  /// [BrushShape].
  final BrushShape shape;

  int get color => shape.color;
  double get size => shape.size;
  double get opacity => shape.opacity;
  double get flow => shape.flow;
  double get hardness => shape.hardness;
  double get spacing => shape.spacing;

  /// BB-3 (R26 #11): per-setting pressure response curves; `null` = the
  /// setting ignores pressure. See `BrushSettings` for the model story.
  BrushPressureCurve? get sizePressureCurve => shape.sizePressureCurve;
  BrushPressureCurve? get opacityPressureCurve => shape.opacityPressureCurve;
  BrushPressureCurve? get flowPressureCurve => shape.flowPressureCurve;
  BrushPressureCurve? get hardnessPressureCurve => shape.hardnessPressureCurve;

  /// Whether any pressure curve is active (the no-pressure hot path skips
  /// the per-dab dynamics pass entirely).
  /// Whether ANY input drives ANY setting on this brush.
  ///
  /// ⛔It used to name the four PRESSURE curves one by one, which quietly
  /// became a second copy of the emptiness law and answered "no" for a
  /// tilt-only brush — so the pen stroke skipped its dynamics while the
  /// preview and the committed stroke applied them, one brush drawing two
  /// ways (adversarial review, 2026-09-09). It reads the whole map now, and
  /// `applyBrushInputDynamics` owns the same question for the paths that do
  /// not gate at all.
  bool get hasPressureDynamics => shape.curves.isNotEmpty;

  double get roundness => shape.roundness;
  double get angleDegrees => shape.angleDegrees;
  /// See [BrushShape.tips] — and [tipMask], the first of them.
  List<BrushTipMask> get tips => shape.tips;
  BrushTipOrder get tipOrder => shape.tipOrder;
  int get tipsPerTurn => shape.tipsPerTurn;
  BrushTipMask? get tipMask => shape.tipMask;
  BrushTipRotationMode get rotationMode => shape.rotationMode;
  double get angleJitter => shape.angleJitter;
  double get scatterRadiusRatio => shape.scatterRadiusRatio;
  int get scatterCount => shape.scatterCount;
  bool get scatterBothAxes => shape.scatterBothAxes;
  BrushTipMask? get dualMask => shape.dualMask;
  double get dualMaskScale => shape.dualMaskScale;

  /// See [BrushShape.dualDensity].
  double get dualDensity => shape.dualDensity;

  /// See [BrushShape.dualCompositeMode].
  SeparableBlendMode get dualCompositeMode => shape.dualCompositeMode;
  /// The texture as PICKED — see [BrushShape.textureMaskSource].
  BrushTipMask? get textureMaskSource => shape.textureMaskSource;
  bool get textureInvert => shape.textureInvert;
  double get textureBrightness => shape.textureBrightness;
  double get textureContrast => shape.textureContrast;

  /// The texture a DAB carries, levels baked in — see [BrushShape.textureMask].
  BrushTipMask? get textureMask => shape.textureMask;
  double get textureScale => shape.textureScale;
  double get textureDensity => shape.textureDensity;
  BrushTextureMode get textureMode => shape.textureMode;

  /// How hard the edge lands — see [BrushShape.antiAlias].
  BrushAntiAlias get antiAlias => shape.antiAlias;

  /// How the line is corrected — see [BrushShape.correction].
  BrushCorrection get correction => shape.correction;

  /// Eraser mode: dabs remove destination alpha (destination-out) instead
  /// of painting color.
  final bool erase;

  /// Whether this stroke's dabs blur rather than paint ([BrushDab.blurs]).
  ///
  /// 🤔The eraser wins (I-75 설계, 10-27: 「지우개 도구에서 고르면 지우개의
  /// 법대로 지운다」): a blur brush taken up as the eraser, or pressed with
  /// the pen's eraser end, erases.
  bool get blurs => shape.blurs && !erase;

  /// The stroke's BRUSH blend (BB-1, R26 #9): how the finished stroke
  /// composites onto the cel at pen-up. [BrushBlendMode.erase] rides the
  /// [erase] flag instead (same kernels as the eraser tool).
  final BrushBlendMode blendMode;

  BrushEditCanvasInputSettings copyWith({
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
    List<BrushTipMask>? tips,
    BrushTipOrder? tipOrder,
    int? tipsPerTurn,
    BrushTipRotationMode? rotationMode,
    double? angleJitter,
    double? scatterRadiusRatio,
    int? scatterCount,
    bool? scatterBothAxes,
    BrushTipMask? dualMask,
    double? dualMaskScale,
    double? dualDensity,
    SeparableBlendMode? dualCompositeMode,
    BrushTipMask? textureMaskSource,
    bool? textureInvert,
    double? textureBrightness,
    double? textureContrast,
    double? textureScale,
    double? textureDensity,
    BrushTextureMode? textureMode,
    bool? erase,
    BrushBlendMode? blendMode,
    BrushAntiAlias? antiAlias,
    BrushCorrection? correction,
  }) {
    // 🚨MERGE, DO NOT REBUILD. The live stroke path goes through here: a
    // mapped-erase press snapshots the settings with `copyWith(erase:
    // true)`. Rebuilt through the factory, which names only part of the
    // shape, it dropped whatever the factory did not name — found one at a
    // time: the tilt curves (see `BrushSettings.copyWith`), the edge step
    // (↩️a 없음 brush back at 3단계 until 2026-10-01), the line's correction
    // (no longer steadied), and the second tip's way along the path
    // (2026-10-29). Merged into the shape, a field this list does not name
    // is carried as it was.
    return BrushEditCanvasInputSettings._raw(
      shape: shape.copyWith(
        color: color,
        size: size,
        opacity: opacity,
        flow: flow,
        hardness: hardness,
        spacing: spacing,
        curves: brushCurvesWithPressure(
          shape.curves,
          size: sizePressureCurve,
          opacity: opacityPressureCurve,
          flow: flowPressureCurve,
          hardness: hardnessPressureCurve,
        ),
        roundness: roundness,
        angleDegrees: angleDegrees,
        tips: tips,
        tipOrder: tipOrder,
        tipsPerTurn: tipsPerTurn,
        rotationMode: rotationMode,
        angleJitter: angleJitter,
        scatterRadiusRatio: scatterRadiusRatio,
        scatterCount: scatterCount,
        scatterBothAxes: scatterBothAxes,
        dualMask: dualMask,
        dualMaskScale: dualMaskScale,
        dualDensity: dualDensity,
        dualCompositeMode: dualCompositeMode,
        textureMaskSource: textureMaskSource,
        textureInvert: textureInvert,
        textureBrightness: textureBrightness,
        textureContrast: textureContrast,
        textureScale: textureScale,
        textureDensity: textureDensity,
        textureMode: textureMode,
        antiAlias: antiAlias,
        correction: correction,
      ),
      erase: erase ?? this.erase,
      blendMode: blendMode ?? this.blendMode,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BrushEditCanvasInputSettings &&
          other.shape == shape &&
          other.erase == erase &&
          other.blendMode == blendMode;

  @override
  int get hashCode => Object.hash(shape, erase, blendMode);

  @override
  String toString() =>
      'BrushEditCanvasInputSettings(shape: $shape, erase: $erase, '
      'blendMode: $blendMode)';
}
