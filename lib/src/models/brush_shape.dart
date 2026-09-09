import 'brush_anti_alias.dart';
import 'brush_input_source.dart';
import 'brush_blend_mode.dart';
import 'brush_pressure_curve.dart';
import 'brush_tip_mask.dart';
import 'brush_tip_rotation_mode.dart';

/// What a response curve is FOR: the setting it drives, and the input that
/// drives it. A record because it is nothing but those two facts together —
/// giving it a class would add a name nobody needs to learn.
typedef BrushDynamicsKey = (BrushPressureTarget, BrushInputSource);

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
    this.curves = const {},
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
    this.spacingJitter = 0.0,
    this.antiAlias = BrushAntiAlias.high,
    this.blendMode = BrushBlendMode.color,
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
  // ⛔tipShape is GONE from the brush (유저 2026-09-09: 「포토샵이나 클튜처럼
  // 가자. 원이나 이미지」). A brush tip is the analytic ROUND one or a tip
  // IMAGE — the two Clip Studio and Photoshop offer — so a brush can never
  // ask for the square footprint. `BrushDab.tipShape` keeps it, because the
  // fill, selection-lift and cut-stamp verbs build a square dab to mean
  // "cover exactly this rect", which is not a brush mark.

  /// Every response curve this brush carries, keyed by WHAT it drives and
  /// WHAT drives it. An absent key is "that pairing ignores that input".
  ///
  /// ⛔This replaced four named fields (`sizePressureCurve` and siblings),
  /// which could only ever say "pressure". Clip Studio files a curve PER
  /// INPUT SOURCE — one block per enabled source in the effector's tail —
  /// so a brush that answers to both pressure and tilt could not be stored,
  /// and import silently dropped everything that was not pressure.
  ///
  /// The four names survive as GETTERS below. They are projections of this
  /// map, not a second home for the data: they read `(target, pressure)`,
  /// which is what they always meant.
  ///
  /// ⚠️STORED BY REFERENCE — this class is const, so it cannot wrap the map
  /// the way [BrushPressureCurve] wraps its points. Every producer therefore
  /// hands over a FRESH map it does not keep (, ,
  /// the importers), and nobody may mutate one after handing it over: a shape
  /// is a value and a live cache key, so a map that changes underneath it
  /// changes its hashCode after the fact.
  /// ⚠️STORED BY REFERENCE. This class is const, so it cannot wrap the map
  /// the way [BrushPressureCurve] wraps its points. Every producer therefore
  /// hands over a FRESH map it does not keep, and nobody may mutate one
  /// afterwards: a shape is a value AND a live cache key, so a map that
  /// changes underneath it changes its hashCode after the fact.
  final Map<BrushDynamicsKey, BrushPressureCurve> curves;

  /// BB-3 (R26 #11): the pressure response for one setting, or `null` when it
  /// ignores pressure. Kept because the whole stroke chain reads these names.
  BrushPressureCurve? get sizePressureCurve =>
      pressureCurveFor(BrushPressureTarget.size);
  BrushPressureCurve? get opacityPressureCurve =>
      pressureCurveFor(BrushPressureTarget.opacity);
  BrushPressureCurve? get flowPressureCurve =>
      pressureCurveFor(BrushPressureTarget.flow);
  BrushPressureCurve? get hardnessPressureCurve =>
      pressureCurveFor(BrushPressureTarget.hardness);

  /// Minor-to-major axis ratio of the tip in (0, 1]; 1.0 is the classic
  /// circle/square.
  final double roundness;

  /// Visual counterclockwise rotation of the tip's major axis from the
  /// horizontal, in degrees.
  final double angleDegrees;

  /// Sampled (bitmap) tip; when set it overrides the analytic round tip and
  /// [hardness]. This and the round tip are the ONLY two shapes a brush has.
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

  /// How this brush composites. Every brush states one; [BrushBlendMode.color]
  /// IS 通常, so "normal" is a value here rather than an absence.
  ///
  /// ⛔THIS WAS A NULLABLE PIN, and the pin existed for exactly one reason:
  /// R26 #10 said a preset must never move the blend under you, while Clip
  /// Studio files a brush's composite under the sub tool and importing
  /// ウェット水彩 without it lost the 乗算 (`324e4e2a`). Null meant "this brush
  /// does not say", so hand-made brushes kept the old behaviour and only an
  /// imported one overrode the hand.
  ///
  /// 유저 2026-09-08 retired the rule the pin was protecting — 「손설정이든
  /// 정한거 싹 다 내보낼때 나르도록 … 브러시든 지우개든 블렌드 모드를
  /// 나른단거야」 — so the brush simply owns its blend, the way it already
  /// owned its size. Import stops asking whether the file departed from the
  /// default and carries what the file says.
  final BrushBlendMode blendMode;

  /// How hard this brush's own edge lands — see [BrushAntiAlias].
  ///
  /// Defaults to [BrushAntiAlias.high], the ramp the engine drew before this
  /// existed, so a preset that says nothing draws exactly as it always did.
  final BrushAntiAlias antiAlias;

  /// Random per-segment spacing reduction, 0..1 — Clip Studio drives this
  /// from its interval effector's random input source, which breaks up the
  /// even beat of a stamped brush.
  final double spacingJitter;

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

  /// The curve by which [source] drives [target], if any.
  BrushPressureCurve? curveFor(
    BrushPressureTarget target,
    BrushInputSource source,
  ) => curves[(target, source)];

  /// The PRESSURE curve driving [target], if any — the common case, and the
  /// only one that existed before sources were separated.
  BrushPressureCurve? pressureCurveFor(BrushPressureTarget target) =>
      curveFor(target, BrushInputSource.pressure);

  /// Sets — or, with `null`, CLEARS — one (target, source) curve, leaving
  /// every other pairing untouched. [copyWith] deliberately preserves the
  /// whole map (a `null` argument means "keep"), so clearing one has to go
  /// through here.
  BrushShape withCurve(
    BrushPressureTarget target,
    BrushInputSource source,
    BrushPressureCurve? curve,
  ) {
    final next = Map<BrushDynamicsKey, BrushPressureCurve>.of(curves);
    if (curve == null) {
      next.remove((target, source));
    } else {
      next[(target, source)] = curve;
    }
    return copyWith(curves: next);
  }

  /// Replaces EVERY source's curve for one [target] in a single step — a
  /// `null` entry clears that pairing, an absent key leaves it alone.
  ///
  /// 🚨THE CURVE EDITOR HAS TO COMMIT THROUGH THIS, not through three
  /// [withCurve] calls. Its `onChanged` closes over the tool state as it was
  /// when the button was BUILT, and that closure lives for the whole popup —
  /// so committing one source at a time reads a stale base three times and
  /// the second write resurrects what the first cleared. One call, one base.
  BrushShape withTargetCurves(
    BrushPressureTarget target,
    Map<BrushInputSource, BrushPressureCurve?> bySource,
  ) {
    final next = Map<BrushDynamicsKey, BrushPressureCurve>.of(curves);
    for (final entry in bySource.entries) {
      final curve = entry.value;
      if (curve == null) {
        next.remove((target, entry.key));
      } else {
        next[(target, entry.key)] = curve;
      }
    }
    return copyWith(curves: next);
  }

  /// Every source's curve for one [target], as the editor wants to read it —
  /// an absent key means that pairing is off.
  Map<BrushInputSource, BrushPressureCurve?> targetCurves(
    BrushPressureTarget target,
  ) => {
    for (final source in BrushInputSource.values)
      source: curveFor(target, source),
  };

  /// [withCurve] for the pressure source — the call every existing site
  /// meant.
  BrushShape withPressureCurve(
    BrushPressureTarget target,
    BrushPressureCurve? curve,
  ) => withCurve(target, BrushInputSource.pressure, curve);

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
      curves: curves,
      roundness: roundness,
      angleDegrees: angleDegrees,
      tipMask: slot == BrushMaskSlot.tip ? mask : tipMask,
      roundnessJitter: roundnessJitter,
      spacingJitter: spacingJitter,
      blendMode: blendMode,
      antiAlias: antiAlias,
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
    Map<BrushDynamicsKey, BrushPressureCurve>? curves,
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
    double? spacingJitter,
    bool? mixesGroundColor,
    BrushBlendMode? blendMode,
    BrushAntiAlias? antiAlias,
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
      curves: curves ?? this.curves,
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
      spacingJitter: spacingJitter ?? this.spacingJitter,
      blendMode: blendMode ?? this.blendMode,
      antiAlias: antiAlias ?? this.antiAlias,
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
          _sameCurves(other.curves, curves) &&
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
          other.spacingJitter == spacingJitter &&
          other.blendMode == blendMode &&
          other.antiAlias == antiAlias &&
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
    Object.hashAllUnordered([
      for (final entry in curves.entries) Object.hash(entry.key, entry.value),
    ]),
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
    spacingJitter,
    blendMode,
    antiAlias,
    mixesGroundColor,
    paintAmount,
    paintDensity,
    colorStretch,
  ]);

  @override
  String toString() =>
      'BrushShape(color: $color, size: $size, opacity: $opacity, '
      'flow: $flow, hardness: $hardness, spacing: $spacing, '
      'curves: $curves, '
      'roundness: $roundness, angleDegrees: $angleDegrees, tipMask: $tipMask, '
      'rotationMode: $rotationMode, sizeJitter: $sizeJitter, '
      'opacityJitter: $opacityJitter, angleJitter: $angleJitter, '
      'scatterRadiusRatio: $scatterRadiusRatio, scatterCount: $scatterCount, '
      'scatterBothAxes: $scatterBothAxes, dualMask: $dualMask, '
      'dualMaskScale: $dualMaskScale, textureMask: $textureMask, '
      'textureScale: $textureScale, textureDensity: $textureDensity)';
}

/// Whether two curve maps hold the same curves.
///
/// ⚠️`Map ==` is IDENTITY in Dart, so comparing the maps directly would make
/// every rebuilt shape unequal to itself and every listener rebuild forever.
/// The four named fields this replaced were compared one by one and got that
/// for free; a map has to say it.
bool _sameCurves(
  Map<BrushDynamicsKey, BrushPressureCurve> a,
  Map<BrushDynamicsKey, BrushPressureCurve> b,
) {
  if (identical(a, b)) {
    return true;
  }
  if (a.length != b.length) {
    return false;
  }
  for (final entry in a.entries) {
    if (b[entry.key] != entry.value) {
      return false;
    }
  }
  return true;
}

/// The four pressure curves as a [BrushShape.curves] map.
///
/// The settings bags still take `sizePressureCurve:` and friends on their flat
/// constructors — that is the shape of every call site and of the JSON — so the
/// translation lives HERE, once, rather than four times over.
Map<BrushDynamicsKey, BrushPressureCurve> brushPressureCurves({
  BrushPressureCurve? size,
  BrushPressureCurve? opacity,
  BrushPressureCurve? flow,
  BrushPressureCurve? hardness,
}) => {
  (BrushPressureTarget.size, BrushInputSource.pressure): ?size,
  (BrushPressureTarget.opacity, BrushInputSource.pressure): ?opacity,
  (BrushPressureTarget.flow, BrushInputSource.pressure): ?flow,
  (BrushPressureTarget.hardness, BrushInputSource.pressure): ?hardness,
};

/// [base] with any NAMED pressure curve replaced, or `null` when the caller
/// named none — which is `copyWith`'s "keep what is there".
///
/// 🚨⛔NOT [brushPressureCurves]. Building a fresh map from four nulls yields
/// `{}`, and handing that to `copyWith` would DELETE every tilt and speed
/// curve the brush had. The four names can only ever set their own key; they
/// have no way to say anything about the others, so they must not erase them.
Map<BrushDynamicsKey, BrushPressureCurve>? brushCurvesWithPressure(
  Map<BrushDynamicsKey, BrushPressureCurve> base, {
  BrushPressureCurve? size,
  BrushPressureCurve? opacity,
  BrushPressureCurve? flow,
  BrushPressureCurve? hardness,
}) {
  final named = brushPressureCurves(
    size: size,
    opacity: opacity,
    flow: flow,
    hardness: hardness,
  );
  if (named.isEmpty) {
    return null;
  }
  return {...base, ...named};
}
