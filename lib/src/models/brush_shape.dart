import 'package:flutter/foundation.dart' show listEquals, mapEquals;

import 'brush_anti_alias.dart';
import 'brush_input_source.dart';
import 'brush_blend_mode.dart';
import 'brush_dab.dart' show BrushDab, BrushDualView;
import 'brush_correction.dart';
import 'brush_mixing_method.dart';
import 'separable_blend_mode.dart';
import 'brush_pressure_curve.dart';
import 'brush_tip_mask.dart';
import 'brush_tip_order.dart';
import 'brush_texture_mode.dart';
import 'brush_tip_rotation_mode.dart';

/// What a response curve is FOR: the setting it drives, and the input that
/// drives it. A record because it is nothing but those two facts together —
/// giving it a class would add a name nobody needs to learn.
typedef BrushDynamicsKey = (BrushPressureTarget, BrushInputSource);

/// Which of the two one-mask slots a write targets.
///
/// ↩️The tip was a third slot until a brush could carry several tips
/// (F-176-Q3); [BrushShape.tips] is written whole, with `copyWith`.
enum BrushMaskSlot { dual, texture }

/// The brush parameters shared, byte-for-byte, by every settings bag in the
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
/// values, spacing/scatter/chance are resolved away) plus its own per-stamp
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
    this.tips = const [],
    this.tipOrder = BrushTipOrder.repeat,
    this.tipsPerTurn = 1,
    this.rotationMode = BrushTipRotationMode.fixed,
    this.angleJitter = 0.0,
    this.scatterRadiusRatio = 0.0,
    this.scatterCount = 1,
    this.scatterBothAxes = true,
    this.dualMask,
    this.dualMaskScale = 1.0,
    this.dualDensity = 1.0,
    this.dualCompositeMode = SeparableBlendMode.multiply,
    this.dualSpacing = 0.1,
    this.dualRoundness = 1.0,
    this.dualAngleDegrees = 0.0,
    this.dualRotationMode = BrushTipRotationMode.fixed,
    this.dualAngleJitter = 0.0,
    this.dualScatterRadiusRatio = 0.0,
    this.dualScatterCount = 1,
    this.dualScatterBothAxes = true,
    this.textureMaskSource,
    this.textureInvert = false,
    this.textureBrightness = 0.0,
    this.textureContrast = 0.0,
    this.textureScale = 1.0,
    this.textureDensity = 1.0,
    this.textureMode = BrushTextureMode.multiply,
    this.antiAlias = BrushAntiAlias.high,
    this.blendMode = BrushBlendMode.color,
    this.mixesGroundColor = false,
    this.mixingMethod = BrushMixingMethod.mix,
    this.paintAmount = 1.0,
    this.paintDensity = 1.0,
    this.colorStretch = 0.0,
    this.correction = const BrushCorrection(),
  });

  /// 🚨The finest [spacing] a brush may have: 1% of its size (유저
  /// 2026-09-24: 「간격 최소치 너무 높지않나? 더 작게 해도 될거같은데 클튜나
  /// 포토샵 참고해서」). Photoshop's brush spacing runs 1%–1000% of the tip,
  /// default 25%; Clip Studio's fixed spacing is the same percent of the tip
  /// (100 = tips touching). 5% stood here, which clamped an imported ABR
  /// brush's 1–4% back up to 5% and left a large tip's edge scalloped. The
  /// dab step never goes below a tenth of the size nor a quarter of a pixel
  /// whatever this is (`finestDabStep`), so a small brush pays nothing for
  /// it.
  static const double minSpacing = 0.01;

  /// The widest [spacing]: four tip sizes between dabs.
  static const double maxSpacing = 4.0;

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

  /// Sampled (bitmap) tips, in the order the dabs take them ([tipOrder]);
  /// any at all override the analytic round tip and [hardness]. These and
  /// the round tip are the ONLY two shapes a brush has.
  ///
  /// 유저 2026-09-22: 「브러시 팁 이미지도 여러개 사용하게해서 여러개
  /// 순차적으로 dab 떨굴지 랜덤하게할지 클튜보니 설정가능하니 도입」 —
  /// Clip Studio's tip list (F-176-Q3).
  ///
  /// ⛔ONE LIST, NOT A TIP AND ITS FOLLOWERS. A first-tip field beside a
  /// list of the rest could hold followers with no first; the list cannot.
  /// [tipMask] reads the first, the way the four pressure-curve names read
  /// [curves].
  ///
  /// ⚠️STORED BY REFERENCE, as [curves] is: every producer hands over a
  /// fresh list it does not keep, and nobody mutates one afterwards.
  final List<BrushTipMask> tips;

  /// Which tip each dab of a stroke takes — see [BrushTipOrder].
  final BrushTipOrder tipOrder;

  /// How many of [tips] each turn of [tipOrder] holds: the order picks the
  /// turn, and a dab throws one of that turn's tips at random. 1, every tip
  /// a turn of its own, is Clip Studio's; more is GIMP's and Krita's image
  /// pipe, a second rank selected at random. The last turn may hold fewer.
  ///
  /// 🗣️F-456-Q4 (유저 2026-10-23): 「기울기가 단계를 고르고, 그 단계 안에서
  /// 여러 장 중 무작위」 — a pencil's lean picks the face its lead wears,
  /// and of the faces worn that way any one lands, so the line's edge
  /// breaks somewhere new every dab.
  final int tipsPerTurn;

  /// The first tip, or `null` for the round one: what a single picture of
  /// the brush shows (its cursor, its tip swatch) and what a dab takes when
  /// nothing turns the tips.
  BrushTipMask? get tipMask => tips.isEmpty ? null : tips.first;

  /// How dab angles are chosen at placement time.
  final BrushTipRotationMode rotationMode;

  /// The random turn of 向き: 0..1 of a half turn either way, thrown per
  /// dab on top of the base the rotation mode picks (F-176-Q1 「기준 +
  /// 랜덤」). Unlike the other settings' ランダム row it ADDS — an angle
  /// has no base to scale.
  final double angleJitter;

  /// Scatter radius as a ratio of the dab size; 0 disables scattering.
  final double scatterRadiusRatio;

  /// Dabs stamped per placement step when scattering.
  final int scatterCount;

  /// Whether scatter offsets spread along both axes or only perpendicular
  /// to the stroke direction.
  final bool scatterBothAxes;

  /// The SECOND tip: a second stroke stamped along the same path at
  /// [dualMaskScale] times the first tip's size (`BrushSecondStroke`), shown
  /// over the first through [dualView] (ABI 60, `qa_dual_view_rows`).
  /// ↩️Until v60 it was a mask tiled over every dab at a random phase.
  final BrushTipMask? dualMask;
  final double dualMaskScale;

  /// How hard the second tip bites, 0..1 — at 0 the stroke shows its first
  /// tip alone ([BrushDualView.density]).
  ///
  /// 🚨1.0 IS THE OLD BEHAVIOUR: the dual mask used to be an unconditional
  /// multiply, all or nothing, while the texture mask beside it has had this
  /// exact knob all along. That asymmetry was the whole reason to add it —
  /// two masks doing the same job, one of them dimmable and one not.
  final double dualDensity;

  /// How the second tip COMBINES with the first — see [BrushDualView]. Both
  /// formats carry one; ours multiplied and only multiplied until v33.
  final SeparableBlendMode dualCompositeMode;

  /// The second tip's own way along the path — the first tip's settings of
  /// the same names, for the second stroke: Photoshop's dual brush has its
  /// own spacing, angle, roundness and scatter, and Clip Studio's `Dual*`
  /// columns are its `Brush*` ones over again. [secondTip] hands them to the
  /// code that reads the first tip's.
  final double dualSpacing;
  final double dualRoundness;
  final double dualAngleDegrees;
  final BrushTipRotationMode dualRotationMode;
  final double dualAngleJitter;
  final double dualScatterRadiusRatio;
  final int dualScatterCount;
  final bool dualScatterBothAxes;

  /// The second tip's placement as a shape of its own, under the first
  /// tip's names — what the second stroke is walked and scattered by
  /// (`BrushSecondStroke`, the interpolator and `BrushStrokeDynamics` the
  /// first stroke uses), or null when there is no second tip.
  BrushShape? get secondTip => dualMask == null
      ? null
      : BrushShape(
          spacing: dualSpacing,
          roundness: dualRoundness,
          angleDegrees: dualAngleDegrees,
          rotationMode: dualRotationMode,
          angleJitter: dualAngleJitter,
          scatterRadiusRatio: dualScatterRadiusRatio,
          scatterCount: dualScatterCount,
          scatterBothAxes: dualScatterBothAxes,
        );

  /// How a stroke of this shape shows its second tip, or null when it has
  /// none — what every dab of its strokes carries ([BrushDab.dual]).
  BrushDualView? get dualView => dualMask == null
      ? null
      : BrushDualView(compositeMode: dualCompositeMode, density: dualDensity);

  /// The paper texture AS PICKED, before the three levels below are applied.
  ///
  /// 🚨SOURCE AND PAINTED ARE DIFFERENT FACTS, and this is the one the user
  /// chose. The importers used to bake invert/brightness/contrast into the
  /// mask on the way in, which made the levels unreachable forever: nothing
  /// held the original to re-bake from, so a slider would have had to work
  /// on its own last output and lose the grain a little each time.
  final BrushTipMask? textureMaskSource;

  /// 濃度反転 — the texture's coverage read the other way up (Clip Studio's
  /// `TextureReverseDensity`, Photoshop's `InvT`).
  final bool textureInvert;

  /// −1..1 each, both neutral at 0. See `brushTipMaskWithLevels` for why
  /// brightness is a lerp toward white rather than an offset.
  final double textureBrightness;
  final double textureContrast;

  /// Paper texture tiled in canvas space, WITH the levels baked in — what a
  /// dab actually carries; see the same field on `BrushDab`.
  ///
  /// ⚠️Derived, not stored, so the levels can never be out of step with the
  /// mask beside them. It costs nothing when the levels are neutral (the
  /// source comes straight back) and one bake per (source, levels)
  /// otherwise.
  BrushTipMask? get textureMask {
    final source = textureMaskSource;
    if (source == null) {
      return null;
    }
    return brushTipMaskWithCachedLevels(
      source,
      invert: textureInvert,
      brightness: textureBrightness,
      contrast: textureContrast,
    );
  }

  final double textureScale;
  final double textureDensity;

  /// How the paper texture meets each dab's coverage — see
  /// [BrushTextureMode].
  final BrushTextureMode textureMode;

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

  /// Whether the brush mixes with the picture already on the cel — Clip
  /// Studio's 混色. The gate: with it off [mixingMethod] and the three knobs
  /// below mean nothing and the brush paints its own colour flat.
  ///
  /// ⚠️Ask [picksUpGround] or [blurs] rather than this: since I-75 the gate
  /// opens onto one of two methods, and either question asked of this alone
  /// answers for both.
  final bool mixesGroundColor;

  /// What the open gate does — see [BrushMixingMethod].
  final BrushMixingMethod mixingMethod;

  /// Whether each dab picks colour up from the cel — Clip Studio's 下地混色,
  /// Photoshop's Mixer Brush.
  ///
  /// Both apps model this the same way, as a brush carrying a reservoir of
  /// paint: each dab picks colour up from the canvas into the reservoir, then
  /// puts a blend of the two back down. The resolved colour is computed AT
  /// PLACEMENT and baked into the dab, so the rasterizers never learn about
  /// mixing and undo/redo replays byte-identically.
  bool get picksUpGround =>
      mixesGroundColor && mixingMethod == BrushMixingMethod.mix;

  /// Whether the brush blurs the picture instead of laying colour (I-75) —
  /// see [BrushMixingMethod.blur].
  bool get blurs => mixesGroundColor && mixingMethod == BrushMixingMethod.blur;

  /// How much drawing colour the brush is loaded with, 0..1 — Clip Studio's
  /// 물감량: how soon it comes back to its own colour after picking another
  /// up. At 0 it is dry and lays only what it picked up
  /// (`BrushGroundColorMixer`).
  final double paintAmount;

  /// Strength of the deposited paint, 0..1 — Clip Studio's 물감 농도.
  final double paintDensity;

  /// How far a colour picked up is drawn out, 0..1 — Clip Studio's 색 늘이기:
  /// the higher, the less a dab lifts of what it crosses, so what the brush
  /// carries lingers. ↩️Until 2026-10-30 it was how much a dab lifted — the
  /// other way round.
  final double colorStretch;

  /// How the line this brush draws is corrected — Clip Studio's 補正, the
  /// brush's own (F-418-Q6).
  final BrushCorrection correction;

  /// The curve by which [source] drives [target], if any.
  BrushPressureCurve? curveFor(
    BrushPressureTarget target,
    BrushInputSource source,
  ) => curves[(target, source)];

  /// Whether [source] drives any setting of this brush — whether a stroke
  /// needs that input read at all.
  bool reads(BrushInputSource source) =>
      curves.keys.any((key) => key.$2 == source);

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

  /// Replaces — or CLEARS, with null — the dual or the texture mask.
  ///
  /// [copyWith] deliberately preserves them so a slider tweak never drops a
  /// textured tip, which leaves no way to take one OFF. This is that way.
  /// (The tips need none: `copyWith(tips: const [])` says "none" outright.)
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
      tips: tips,
      tipOrder: tipOrder,
      tipsPerTurn: tipsPerTurn,
      blendMode: blendMode,
      antiAlias: antiAlias,
      mixesGroundColor: mixesGroundColor,
      mixingMethod: mixingMethod,
      paintAmount: paintAmount,
      paintDensity: paintDensity,
      colorStretch: colorStretch,
      correction: correction,
      rotationMode: rotationMode,
      angleJitter: angleJitter,
      scatterRadiusRatio: scatterRadiusRatio,
      scatterCount: scatterCount,
      scatterBothAxes: scatterBothAxes,
      dualMask: slot == BrushMaskSlot.dual ? mask : dualMask,
      dualMaskScale: dualMaskScale,
      dualDensity: dualDensity,
      dualCompositeMode: dualCompositeMode,
      dualSpacing: dualSpacing,
      dualRoundness: dualRoundness,
      dualAngleDegrees: dualAngleDegrees,
      dualRotationMode: dualRotationMode,
      dualAngleJitter: dualAngleJitter,
      dualScatterRadiusRatio: dualScatterRadiusRatio,
      dualScatterCount: dualScatterCount,
      dualScatterBothAxes: dualScatterBothAxes,
      textureMaskSource: slot == BrushMaskSlot.texture
          ? mask
          : textureMaskSource,
      textureInvert: textureInvert,
      textureBrightness: textureBrightness,
      textureContrast: textureContrast,
      textureScale: textureScale,
      textureDensity: textureDensity,
      textureMode: textureMode,
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
    double? dualSpacing,
    double? dualRoundness,
    double? dualAngleDegrees,
    BrushTipRotationMode? dualRotationMode,
    double? dualAngleJitter,
    double? dualScatterRadiusRatio,
    int? dualScatterCount,
    bool? dualScatterBothAxes,
    BrushTipMask? textureMaskSource,
    bool? textureInvert,
    double? textureBrightness,
    double? textureContrast,
    double? textureScale,
    double? textureDensity,
    BrushTextureMode? textureMode,
    bool? mixesGroundColor,
    BrushMixingMethod? mixingMethod,
    BrushBlendMode? blendMode,
    BrushAntiAlias? antiAlias,
    double? paintAmount,
    double? paintDensity,
    double? colorStretch,
    BrushCorrection? correction,
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
      tips: tips ?? this.tips,
      tipOrder: tipOrder ?? this.tipOrder,
      tipsPerTurn: tipsPerTurn ?? this.tipsPerTurn,
      rotationMode: rotationMode ?? this.rotationMode,
      angleJitter: angleJitter ?? this.angleJitter,
      scatterRadiusRatio: scatterRadiusRatio ?? this.scatterRadiusRatio,
      scatterCount: scatterCount ?? this.scatterCount,
      scatterBothAxes: scatterBothAxes ?? this.scatterBothAxes,
      dualMask: dualMask ?? this.dualMask,
      dualMaskScale: dualMaskScale ?? this.dualMaskScale,
      dualDensity: dualDensity ?? this.dualDensity,
      dualCompositeMode: dualCompositeMode ?? this.dualCompositeMode,
      dualSpacing: dualSpacing ?? this.dualSpacing,
      dualRoundness: dualRoundness ?? this.dualRoundness,
      dualAngleDegrees: dualAngleDegrees ?? this.dualAngleDegrees,
      dualRotationMode: dualRotationMode ?? this.dualRotationMode,
      dualAngleJitter: dualAngleJitter ?? this.dualAngleJitter,
      dualScatterRadiusRatio:
          dualScatterRadiusRatio ?? this.dualScatterRadiusRatio,
      dualScatterCount: dualScatterCount ?? this.dualScatterCount,
      dualScatterBothAxes: dualScatterBothAxes ?? this.dualScatterBothAxes,
      textureMaskSource: textureMaskSource ?? this.textureMaskSource,
      textureInvert: textureInvert ?? this.textureInvert,
      textureBrightness: textureBrightness ?? this.textureBrightness,
      textureContrast: textureContrast ?? this.textureContrast,
      textureScale: textureScale ?? this.textureScale,
      textureDensity: textureDensity ?? this.textureDensity,
      textureMode: textureMode ?? this.textureMode,
      blendMode: blendMode ?? this.blendMode,
      antiAlias: antiAlias ?? this.antiAlias,
      mixesGroundColor: mixesGroundColor ?? this.mixesGroundColor,
      mixingMethod: mixingMethod ?? this.mixingMethod,
      paintAmount: paintAmount ?? this.paintAmount,
      paintDensity: paintDensity ?? this.paintDensity,
      colorStretch: colorStretch ?? this.colorStretch,
      correction: correction ?? this.correction,
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
          // ⚠️`==` on a map or a list is IDENTITY: every rebuilt shape would
          // be unequal to itself and every listener rebuild forever.
          mapEquals(other.curves, curves) &&
          other.roundness == roundness &&
          other.angleDegrees == angleDegrees &&
          listEquals(other.tips, tips) &&
          other.tipOrder == tipOrder &&
          other.tipsPerTurn == tipsPerTurn &&
          other.rotationMode == rotationMode &&
          other.angleJitter == angleJitter &&
          other.scatterRadiusRatio == scatterRadiusRatio &&
          other.scatterCount == scatterCount &&
          other.scatterBothAxes == scatterBothAxes &&
          other.dualMask == dualMask &&
          other.dualMaskScale == dualMaskScale &&
          other.dualDensity == dualDensity &&
          other.dualCompositeMode == dualCompositeMode &&
          other.dualSpacing == dualSpacing &&
          other.dualRoundness == dualRoundness &&
          other.dualAngleDegrees == dualAngleDegrees &&
          other.dualRotationMode == dualRotationMode &&
          other.dualAngleJitter == dualAngleJitter &&
          other.dualScatterRadiusRatio == dualScatterRadiusRatio &&
          other.dualScatterCount == dualScatterCount &&
          other.dualScatterBothAxes == dualScatterBothAxes &&
          other.textureMaskSource == textureMaskSource &&
          other.textureInvert == textureInvert &&
          other.textureBrightness == textureBrightness &&
          other.textureContrast == textureContrast &&
          other.textureScale == textureScale &&
          other.textureDensity == textureDensity &&
          other.textureMode == textureMode &&
          other.blendMode == blendMode &&
          other.antiAlias == antiAlias &&
          other.mixesGroundColor == mixesGroundColor &&
          other.mixingMethod == mixingMethod &&
          other.paintAmount == paintAmount &&
          other.paintDensity == paintDensity &&
          other.colorStretch == colorStretch &&
          other.correction == correction;

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
    Object.hashAll(tips),
    tipOrder,
    tipsPerTurn,
    rotationMode,
    angleJitter,
    scatterRadiusRatio,
    scatterCount,
    scatterBothAxes,
    dualMask,
    dualMaskScale,
    dualDensity,
    dualSpacing,
    dualRoundness,
    dualAngleDegrees,
    dualRotationMode,
    dualAngleJitter,
    dualScatterRadiusRatio,
    dualScatterCount,
    dualScatterBothAxes,
    textureMaskSource,
    textureInvert,
    textureBrightness,
    textureContrast,
    textureScale,
    textureDensity,
    textureMode,
    blendMode,
    antiAlias,
    mixesGroundColor,
    mixingMethod,
    paintAmount,
    paintDensity,
    colorStretch,
    correction,
  ]);

  @override
  String toString() =>
      'BrushShape(color: $color, size: $size, opacity: $opacity, '
      'flow: $flow, hardness: $hardness, spacing: $spacing, '
      'curves: $curves, '
      'roundness: $roundness, angleDegrees: $angleDegrees, tips: $tips, '
      'tipOrder: $tipOrder, tipsPerTurn: $tipsPerTurn, '
      'rotationMode: $rotationMode, angleJitter: $angleJitter, '
      'scatterRadiusRatio: $scatterRadiusRatio, scatterCount: $scatterCount, '
      'scatterBothAxes: $scatterBothAxes, dualMask: $dualMask, '
      'dualMaskScale: $dualMaskScale, '
      'dualSpacing: $dualSpacing, dualRoundness: $dualRoundness, '
      'dualAngleDegrees: $dualAngleDegrees, '
      'dualRotationMode: $dualRotationMode, '
      'dualAngleJitter: $dualAngleJitter, '
      'dualScatterRadiusRatio: $dualScatterRadiusRatio, '
      'dualScatterCount: $dualScatterCount, '
      'dualScatterBothAxes: $dualScatterBothAxes, '
      'textureMaskSource: $textureMaskSource, '
      'textureInvert: $textureInvert, '
      'textureBrightness: $textureBrightness, '
      'textureContrast: $textureContrast, '
      'textureScale: $textureScale, textureDensity: $textureDensity, '
      'textureMode: $textureMode, '
      'correction: $correction)';
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
