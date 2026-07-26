import 'brush_pressure_curve.dart';
import 'brush_tip_mask.dart';
import 'brush_tip_rotation_mode.dart';
import 'brush_tip_shape.dart';

/// Which of the three sampled-mask slots a write targets.
enum BrushMaskSlot { tip, dual, texture }

/// The 26 brush parameters shared, byte-for-byte, by every settings bag in the
/// stroke chain: the UI's `BrushToolState`, the preset payload `BrushSettings`,
/// and the canvas input `BrushEditCanvasInputSettings`. Each of those HOLDS one
/// of these and exposes the fields through forwarding getters; the converters
/// between them pass the whole `BrushShape` across, so a parameter can never be
/// silently dropped on a hop (the failure the hand-threaded converters used to
/// risk — D4). Adding a shared parameter means adding it here, once.
///
/// This is a pure value carrier: it neither validates nor clamps. Each bag
/// keeps its own policy — `BrushSettings` throws, `BrushToolState` clamps into
/// the panel ranges, `BrushEditCanvasInputSettings` asserts — and builds a
/// shape only from values it has already made legal.
///
/// The per-dab resolved unit (`BrushDab`) is deliberately NOT built on this: it
/// carries a different, smaller set (the pressure curves are baked into scalar
/// values, spacing/scatter/jitter are resolved away) plus its own per-stamp
/// fields, so it is a downstream shape, not another copy of these parameters.
class BrushShape {
  const BrushShape({
    this.color = 0xFF000000,
    this.size = 4.0,
    this.opacity = 1.0,
    this.flow = 1.0,
    this.hardness = 1.0,
    this.spacing = 0.1,
    this.tipShape = BrushTipShape.round,
    this.sizePressureCurve,
    this.opacityPressureCurve,
    this.flowPressureCurve,
    this.hardnessPressureCurve,
    this.roundness = 1.0,
    this.angleDegrees = 0.0,
    this.tipMask,
    this.rotationMode = BrushTipRotationMode.fixed,
    this.sizeJitter = 0.0,
    this.opacityJitter = 0.0,
    this.angleJitter = 0.0,
    this.scatterRadiusRatio = 0.0,
    this.scatterCount = 1,
    this.scatterBothAxes = true,
    this.dualMask,
    this.dualMaskScale = 1.0,
    this.textureMask,
    this.textureScale = 1.0,
    this.textureDensity = 1.0,
    this.roundnessJitter = 0.0,
    this.mixesGroundColor = false,
    this.paintAmount = 1.0,
    this.paintDensity = 1.0,
    this.colorStretch = 0.0,
  });

  final int color;
  final double size;
  final double opacity;
  final double flow;
  final double hardness;
  final double spacing;
  final BrushTipShape tipShape;

  /// BB-3 (R26 #11): per-setting pen-pressure response — `null` means the
  /// setting ignores pressure. These replaced the pressureSize /
  /// pressureOpacity booleans and the minimumSizeRatio floor (the floor is
  /// now the size curve's left endpoint).
  final BrushPressureCurve? sizePressureCurve;
  final BrushPressureCurve? opacityPressureCurve;
  final BrushPressureCurve? flowPressureCurve;
  final BrushPressureCurve? hardnessPressureCurve;

  /// Minor-to-major axis ratio of the tip in (0, 1]; 1.0 is the classic
  /// circle/square.
  final double roundness;

  /// Visual counterclockwise rotation of the tip's major axis from the
  /// horizontal, in degrees.
  final double angleDegrees;

  /// Sampled (bitmap) tip; when set it overrides [tipShape] and [hardness].
  final BrushTipMask? tipMask;

  /// How dab angles are chosen at placement time.
  final BrushTipRotationMode rotationMode;

  /// Random per-dab size reduction, 0..1 of the base size.
  final double sizeJitter;

  /// Random per-dab opacity reduction, 0..1 of the base opacity.
  final double opacityJitter;

  /// Random per-dab tip rotation, 0..1 of a half turn in each direction.
  final double angleJitter;

  /// Scatter radius as a ratio of the dab size; 0 disables scattering.
  final double scatterRadiusRatio;

  /// Dabs stamped per placement step when scattering.
  final int scatterCount;

  /// Whether scatter offsets spread along both axes or only perpendicular
  /// to the stroke direction.
  final bool scatterBothAxes;

  /// Dual-brush mask multiplying every dab's coverage; tiled at
  /// [dualMaskScale] times the dab size with a random per-dab phase.
  final BrushTipMask? dualMask;
  final double dualMaskScale;

  /// Paper texture tiled in canvas space; see the same fields on `BrushDab`.
  final BrushTipMask? textureMask;
  final double textureScale;
  final double textureDensity;

  /// Random per-dab roundness reduction, 0..1 — Clip Studio drives this from
  /// its thickness effector's random input source. The tip squashes by a
  /// different amount on every dab, which is how a textured stamp brush
  /// stops looking stamped.
  final double roundnessJitter;

  /// Whether the brush mixes with the colour already on the cel — Clip
  /// Studio's 밑바탕 혼색, Photoshop's Mixer Brush. The gate: with it off the
  /// three knobs below mean nothing and the brush paints its own colour flat.
  ///
  /// Both apps model this the same way, as a brush carrying a reservoir of
  /// paint: each dab picks colour up from the canvas into the reservoir, then
  /// puts a blend of the two back down. The resolved colour is computed AT
  /// PLACEMENT and baked into the dab, so the rasterizers never learn about
  /// mixing and undo/redo replays byte-identically.
  final bool mixesGroundColor;

  /// How much of the reservoir reaches the canvas, 0..1 — Clip Studio's
  /// 물감량. At 0 the dab leaves the ground untouched.
  final double paintAmount;

  /// Strength of the deposited paint, 0..1 — Clip Studio's 물감 농도.
  final double paintDensity;

  /// How strongly the reservoir takes on the colour under the brush, 0..1 —
  /// Clip Studio's 색 늘이기. This is what smears colour along a stroke.
  final double colorStretch;

  /// The pressure curve driving [target], if any.
  BrushPressureCurve? pressureCurveFor(BrushPressureTarget target) {
    return switch (target) {
      BrushPressureTarget.size => sizePressureCurve,
      BrushPressureTarget.opacity => opacityPressureCurve,
      BrushPressureTarget.flow => flowPressureCurve,
      BrushPressureTarget.hardness => hardnessPressureCurve,
    };
  }

  /// Sets — or, with `null`, CLEARS — the pressure curve for one [target],
  /// leaving the other three channels untouched. [copyWith] deliberately
  /// preserves curves (a `null` argument means "keep"), so clearing one has
  /// to go through here.
  BrushShape withPressureCurve(
    BrushPressureTarget target,
    BrushPressureCurve? curve,
  ) {
    return BrushShape(
      color: color,
      size: size,
      opacity: opacity,
      flow: flow,
      hardness: hardness,
      spacing: spacing,
      tipShape: tipShape,
      sizePressureCurve: target == BrushPressureTarget.size
          ? curve
          : sizePressureCurve,
      opacityPressureCurve: target == BrushPressureTarget.opacity
          ? curve
          : opacityPressureCurve,
      flowPressureCurve: target == BrushPressureTarget.flow
          ? curve
          : flowPressureCurve,
      hardnessPressureCurve: target == BrushPressureTarget.hardness
          ? curve
          : hardnessPressureCurve,
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
    );
  }

  /// Replaces — or CLEARS, with null — one of the three sampled masks.
  ///
  /// [copyWith] deliberately preserves them so a slider tweak never drops a
  /// textured tip, which leaves no way to take one OFF. This is that way.
  BrushShape withMask(BrushMaskSlot slot, BrushTipMask? mask) {
    return BrushShape(
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
      tipMask: slot == BrushMaskSlot.tip ? mask : tipMask,
      roundnessJitter: roundnessJitter,
      mixesGroundColor: mixesGroundColor,
      paintAmount: paintAmount,
      paintDensity: paintDensity,
      colorStretch: colorStretch,
      rotationMode: rotationMode,
      sizeJitter: sizeJitter,
      opacityJitter: opacityJitter,
      angleJitter: angleJitter,
      scatterRadiusRatio: scatterRadiusRatio,
      scatterCount: scatterCount,
      scatterBothAxes: scatterBothAxes,
      dualMask: slot == BrushMaskSlot.dual ? mask : dualMask,
      dualMaskScale: dualMaskScale,
      textureMask: slot == BrushMaskSlot.texture ? mask : textureMask,
      textureScale: textureScale,
      textureDensity: textureDensity,
    );
  }

  BrushShape copyWith({
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
    return BrushShape(
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

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BrushShape &&
          other.color == color &&
          other.size == size &&
          other.opacity == opacity &&
          other.flow == flow &&
          other.hardness == hardness &&
          other.spacing == spacing &&
          other.tipShape == tipShape &&
          other.sizePressureCurve == sizePressureCurve &&
          other.opacityPressureCurve == opacityPressureCurve &&
          other.flowPressureCurve == flowPressureCurve &&
          other.hardnessPressureCurve == hardnessPressureCurve &&
          other.roundness == roundness &&
          other.angleDegrees == angleDegrees &&
          other.tipMask == tipMask &&
          other.rotationMode == rotationMode &&
          other.sizeJitter == sizeJitter &&
          other.opacityJitter == opacityJitter &&
          other.angleJitter == angleJitter &&
          other.scatterRadiusRatio == scatterRadiusRatio &&
          other.scatterCount == scatterCount &&
          other.scatterBothAxes == scatterBothAxes &&
          other.dualMask == dualMask &&
          other.dualMaskScale == dualMaskScale &&
          other.textureMask == textureMask &&
          other.textureScale == textureScale &&
          other.textureDensity == textureDensity &&
          other.roundnessJitter == roundnessJitter &&
          other.mixesGroundColor == mixesGroundColor &&
          other.paintAmount == paintAmount &&
          other.paintDensity == paintDensity &&
          other.colorStretch == colorStretch;

  @override
  int get hashCode => Object.hashAll([
    color,
    size,
    opacity,
    flow,
    hardness,
    spacing,
    tipShape,
    sizePressureCurve,
    opacityPressureCurve,
    flowPressureCurve,
    hardnessPressureCurve,
    roundness,
    angleDegrees,
    tipMask,
    rotationMode,
    sizeJitter,
    opacityJitter,
    angleJitter,
    scatterRadiusRatio,
    scatterCount,
    scatterBothAxes,
    dualMask,
    dualMaskScale,
    textureMask,
    textureScale,
    textureDensity,
    roundnessJitter,
    mixesGroundColor,
    paintAmount,
    paintDensity,
    colorStretch,
  ]);

  @override
  String toString() =>
      'BrushShape(color: $color, size: $size, opacity: $opacity, '
      'flow: $flow, hardness: $hardness, spacing: $spacing, '
      'tipShape: $tipShape, sizePressureCurve: $sizePressureCurve, '
      'opacityPressureCurve: $opacityPressureCurve, '
      'flowPressureCurve: $flowPressureCurve, '
      'hardnessPressureCurve: $hardnessPressureCurve, '
      'roundness: $roundness, angleDegrees: $angleDegrees, tipMask: $tipMask, '
      'rotationMode: $rotationMode, sizeJitter: $sizeJitter, '
      'opacityJitter: $opacityJitter, angleJitter: $angleJitter, '
      'scatterRadiusRatio: $scatterRadiusRatio, scatterCount: $scatterCount, '
      'scatterBothAxes: $scatterBothAxes, dualMask: $dualMask, '
      'dualMaskScale: $dualMaskScale, textureMask: $textureMask, '
      'textureScale: $textureScale, textureDensity: $textureDensity)';
}
