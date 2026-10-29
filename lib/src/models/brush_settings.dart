import 'brush_anti_alias.dart';
import 'brush_blend_mode.dart';
import 'brush_correction.dart';
import 'separable_blend_mode.dart';
import 'brush_input_source.dart';
import 'brush_mixing_method.dart';
import 'brush_pressure_curve.dart';
import 'brush_settings_row.dart';
import 'brush_shape.dart';
import 'brush_tip_mask.dart';
import 'brush_tip_order.dart';
import 'brush_texture_mode.dart';
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
    SeparableBlendMode dualCompositeMode = SeparableBlendMode.multiply,
    double dualDensity = 1.0,
    double dualSpacing = 0.1,
    double dualRoundness = 1.0,
    double dualAngleDegrees = 0.0,
    BrushTipRotationMode dualRotationMode = BrushTipRotationMode.fixed,
    double dualAngleJitter = 0.0,
    double dualScatterRadiusRatio = 0.0,
    int dualScatterCount = 1,
    bool dualScatterBothAxes = true,
    BrushTipMask? textureMaskSource,
    bool textureInvert = false,
    double textureBrightness = 0.0,
    double textureContrast = 0.0,
    double textureScale = 1.0,
    double textureDensity = 1.0,
    BrushTextureMode textureMode = BrushTextureMode.multiply,
    BrushBlendMode blendMode = BrushBlendMode.color,
    BrushAntiAlias antiAlias = BrushAntiAlias.high,
    bool mixesGroundColor = false,
    BrushMixingMethod mixingMethod = BrushMixingMethod.mix,
    double paintAmount = 1.0,
    double paintDensity = 1.0,
    double colorStretch = 0.0,
    BrushCorrection correction = const BrushCorrection(),
    this.shown = BrushSettingsRow.shownByDefault,
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
         dualCompositeMode: dualCompositeMode,
         dualDensity: dualDensity,
         dualSpacing: dualSpacing,
         dualRoundness: dualRoundness,
         dualAngleDegrees: dualAngleDegrees,
         dualRotationMode: dualRotationMode,
         dualAngleJitter: dualAngleJitter,
         dualScatterRadiusRatio: dualScatterRadiusRatio,
         dualScatterCount: dualScatterCount,
         dualScatterBothAxes: dualScatterBothAxes,
         textureMaskSource: textureMaskSource,
         textureInvert: textureInvert,
         textureBrightness: textureBrightness,
         textureContrast: textureContrast,
         textureScale: textureScale,
         textureDensity: textureDensity,
         textureMode: textureMode,
         blendMode: blendMode,
         antiAlias: antiAlias,
         mixesGroundColor: mixesGroundColor,
         mixingMethod: mixingMethod,
         paintAmount: paintAmount,
         paintDensity: paintDensity,
         colorStretch: colorStretch,
         correction: correction,
       ) {
    _validateShape(shape);
  }

  /// Wraps an already-legal [BrushShape] as a preset payload without going
  /// back through the flat parameter list — the wholesale hop the stroke
  /// chain's converters take (D4). Values are re-validated so an illegal
  /// shape still throws here rather than downstream.
  BrushSettings.fromShape(
    this.shape, {
    this.shown = BrushSettingsRow.shownByDefault,
  }) {
    _validateShape(shape);
  }

  /// The shared 26-parameter spine; every field below forwards to it, and the
  /// stroke chain moves presets across as a whole [shape] (see [BrushShape]).
  final BrushShape shape;

  /// The rows of this brush's settings the tool settings panel shows (I-141,
  /// [BrushSettingsRow]) — the one thing a brush keeps that is not how it
  /// paints, so it stands beside [shape] rather than in it, as the folded
  /// groups it replaced did (F-418-Q10).
  final Set<BrushSettingsRow> shown;

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
  SeparableBlendMode get dualCompositeMode => shape.dualCompositeMode;

  /// See [BrushShape.dualDensity].
  double get dualDensity => shape.dualDensity;

  /// See [BrushShape.dualSpacing] — the second tip's way along the path.
  double get dualSpacing => shape.dualSpacing;
  double get dualRoundness => shape.dualRoundness;
  double get dualAngleDegrees => shape.dualAngleDegrees;
  BrushTipRotationMode get dualRotationMode => shape.dualRotationMode;
  double get dualAngleJitter => shape.dualAngleJitter;
  double get dualScatterRadiusRatio => shape.dualScatterRadiusRatio;
  int get dualScatterCount => shape.dualScatterCount;
  bool get dualScatterBothAxes => shape.dualScatterBothAxes;
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
  BrushTextureMode get textureMode => shape.textureMode;


  /// How this brush composites — see [BrushShape.blendMode].
  BrushBlendMode get blendMode => shape.blendMode;

  /// How hard this brush's edge lands — see [BrushShape.antiAlias].
  BrushAntiAlias get antiAlias => shape.antiAlias;

  /// The curves the four legacy JSON keys cannot express — read off the map
  /// those four keys are written from ([brushPressureCurves]).
  ///
  /// ↩️It kept every source but pressure, so pressure on any other target —
  /// roundness, spacing, the texture's density (F-451, the pencil pressing
  /// into the tooth) — was written nowhere and lost on the next save.
  Map<BrushDynamicsKey, BrushPressureCurve> get _curvesNoLegacyKeyHolds {
    final legacy = brushPressureCurves(
      size: sizePressureCurve,
      opacity: opacityPressureCurve,
      flow: flowPressureCurve,
      hardness: hardnessPressureCurve,
    );
    return {
      for (final entry in shape.curves.entries)
        if (!legacy.containsKey(entry.key)) entry.key: entry.value,
    };
  }

  /// Ground-colour mixing — see [BrushShape.mixesGroundColor].
  bool get mixesGroundColor => shape.mixesGroundColor;
  BrushMixingMethod get mixingMethod => shape.mixingMethod;
  double get paintAmount => shape.paintAmount;
  double get paintDensity => shape.paintDensity;
  double get colorStretch => shape.colorStretch;

  /// The line's correction — see [BrushShape.correction].
  BrushCorrection get correction => shape.correction;

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
    SeparableBlendMode? dualCompositeMode,
    double? dualDensity,
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
    BrushBlendMode? blendMode,
    BrushAntiAlias? antiAlias,
    bool? mixesGroundColor,
    BrushMixingMethod? mixingMethod,
    double? paintAmount,
    double? paintDensity,
    double? colorStretch,
    BrushCorrection? correction,
    Set<BrushSettingsRow>? shown,
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
      dualCompositeMode: dualCompositeMode ?? this.dualCompositeMode,
      dualDensity: dualDensity ?? this.dualDensity,
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
      shown: shown ?? this.shown,
    );
  }

  /// [withMasks] false leaves the masks out — for comparing two
  /// brushes' settings without writing every tip's pixels out as base64,
  /// which the hand bank does on every slider frame (H25-again). Every file
  /// writer takes the default.
  Map<String, dynamic> toJson({bool withMasks = true}) => {
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
    ..._curvesToJson(_curvesNoLegacyKeyHolds),
    'roundness': roundness,
    'angleDegrees': angleDegrees,
    if (withMasks && tips.isNotEmpty) 'tipMask': tips.first.toJson(),
    // ⛔THE TIPS AFTER THE FIRST RIDE A KEY OF THEIR OWN, not one list of
    // every tip: a file written while a brush had one tip keeps it at
    // 'tipMask', and so reads unchanged with no code of its own — 유저
    // 2026-09-24 wants no carry-forward code and no version bump, which
    // would eat the library of their own brushes.
    if (withMasks && tips.length > 1)
      'moreTipMasks': [for (final tip in tips.skip(1)) tip.toJson()],
    // 繰り返し and one tip a turn are the defaults, so they write nothing —
    // presets saved before the settings existed round-trip byte-identically.
    if (tipOrder != BrushTipOrder.repeat) 'tipOrder': tipOrder.name,
    if (tipsPerTurn != 1) 'tipsPerTurn': tipsPerTurn,
    'rotationMode': rotationMode.toJson(),
    'angleJitter': angleJitter,
    // 通常 is the default, so it writes nothing — presets saved before every
    // brush carried a blend round-trip byte-identically.
    if (blendMode != BrushBlendMode.color) 'blendMode': blendMode.name,
    // Same rule, same reason: [BrushAntiAlias.high] IS the ramp every brush
    // drew before the setting existed.
    if (antiAlias != BrushAntiAlias.high) 'antiAlias': antiAlias.name,
    'scatterRadiusRatio': scatterRadiusRatio,
    'scatterCount': scatterCount,
    'scatterBothAxes': scatterBothAxes,
    if (withMasks && dualMask != null) 'dualMask': dualMask!.toJson(),
    'dualMaskScale': dualMaskScale,
    'dualDensity': dualDensity,
    // ⚠️The mode had no key from v33 until the second tip became a stroke
    // of its own: a saved brush came back multiplying.
    if (dualCompositeMode != SeparableBlendMode.multiply)
      'dualCompositeMode': dualCompositeMode.name,
    'dualSpacing': dualSpacing,
    'dualRoundness': dualRoundness,
    'dualAngleDegrees': dualAngleDegrees,
    'dualRotationMode': dualRotationMode.toJson(),
    'dualAngleJitter': dualAngleJitter,
    'dualScatterRadiusRatio': dualScatterRadiusRatio,
    'dualScatterCount': dualScatterCount,
    'dualScatterBothAxes': dualScatterBothAxes,
    if (withMasks && textureMaskSource != null)
      'textureMaskSource': textureMaskSource!.toJson(),
    if (textureInvert) 'textureInvert': true,
    if (textureBrightness != 0.0) 'textureBrightness': textureBrightness,
    if (textureContrast != 0.0) 'textureContrast': textureContrast,
    'textureScale': textureScale,
    'textureDensity': textureDensity,
    if (textureMode != BrushTextureMode.multiply)
      'textureMode': textureMode.name,
    // Ground-colour mixing writes only when ON, so presets saved before it
    // existed round-trip byte-identically.
    if (mixesGroundColor) ...{
      'mixesGroundColor': true,
      // Off its default only, by the same rule — I-75 added it.
      if (mixingMethod != BrushMixingMethod.mix)
        'mixingMethod': mixingMethod.name,
      'paintAmount': paintAmount,
      'paintDensity': paintDensity,
      'colorStretch': colorStretch,
    },
    // Written only off its default, as the tip order is — a preset saved
    // before the brush held its correction round-trips byte-identically.
    if (correction != const BrushCorrection())
      'correction': correction.toJson(),
    // Written only off the three every brush shows, for the same reason —
    // and so a brush handed back to them leaves no key for the hand's
    // overlay to keep. An EMPTY list is written: it is a brush showing
    // nothing, not one that never said.
    if (!_sameRows(shown, BrushSettingsRow.shownByDefault))
      'shown': [
        for (final row in BrushSettingsRow.values)
          if (shown.contains(row)) row.name,
      ],
  };

  factory BrushSettings.fromJson(Map<String, dynamic> json) {
    // Legacy pressure toggles (pre-BB-3) migrate to their equivalent
    // straight-line curves: size ON was `min + (1 - min) * p` (the
    // minimumSizeRatio floor), opacity ON was plain `p`.
    BrushPressureCurve? curveOf(String key) => json[key] == null
        ? null
        : BrushPressureCurve.fromJson(json[key]);
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
      tips: [
        if (json['tipMask'] case final Map<String, dynamic> first)
          BrushTipMask.fromJson(first),
        for (final more in json['moreTipMasks'] as List<dynamic>? ?? const [])
          BrushTipMask.fromJson(more as Map<String, dynamic>),
      ],
      tipOrder:
          BrushTipOrder.values.asNameMap()[json['tipOrder']] ??
          BrushTipOrder.repeat,
      tipsPerTurn: json['tipsPerTurn'] as int? ?? 1,
      rotationMode: BrushTipRotationMode.fromJson(json['rotationMode']),
      angleJitter: (json['angleJitter'] as num?)?.toDouble() ?? 0.0,
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
      dualCompositeMode:
          SeparableBlendMode.forName(
            json['dualCompositeMode'] as String? ?? '',
          ) ??
          SeparableBlendMode.multiply,
      dualSpacing: (json['dualSpacing'] as num?)?.toDouble() ?? 0.1,
      dualRoundness: (json['dualRoundness'] as num?)?.toDouble() ?? 1.0,
      dualAngleDegrees: (json['dualAngleDegrees'] as num?)?.toDouble() ?? 0.0,
      dualRotationMode: BrushTipRotationMode.fromJson(
        json['dualRotationMode'],
      ),
      dualAngleJitter: (json['dualAngleJitter'] as num?)?.toDouble() ?? 0.0,
      dualScatterRadiusRatio:
          (json['dualScatterRadiusRatio'] as num?)?.toDouble() ?? 0.0,
      dualScatterCount: json['dualScatterCount'] as int? ?? 1,
      dualScatterBothAxes: json['dualScatterBothAxes'] as bool? ?? true,
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
      textureMode: BrushTextureMode.fromName(json['textureMode']),
      mixesGroundColor: json['mixesGroundColor'] as bool? ?? false,
      mixingMethod: BrushMixingMethod.fromName(json['mixingMethod']),
      paintAmount: (json['paintAmount'] as num?)?.toDouble() ?? 1.0,
      paintDensity: (json['paintDensity'] as num?)?.toDouble() ?? 1.0,
      colorStretch: (json['colorStretch'] as num?)?.toDouble() ?? 0.0,
      correction: BrushCorrection.fromJson(json['correction']),
      shown: switch (json['shown']) {
        final List<dynamic> names => {
          for (final name in names)
            ?BrushSettingsRow.values.asNameMap()[name],
        },
        _ => BrushSettingsRow.shownByDefault,
      },
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BrushSettings &&
          other.shape == shape &&
          _sameRows(other.shown, shown);

  @override
  int get hashCode => Object.hash(
    shape,
    Object.hashAllUnordered(shown),
  );

  @override
  String toString() => 'BrushSettings(shape: $shape, shown: $shown)';
}

bool _sameRows(Set<BrushSettingsRow> a, Set<BrushSettingsRow> b) =>
    a.length == b.length && a.containsAll(b);

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
  _validateCorrection(
    shape.correction.stabilization,
    'stabilization',
    BrushCorrection.maxStabilization,
  );
  _validateCorrection(
    shape.correction.postStrength,
    'postStrength',
    BrushCorrection.maxPostStrength,
  );
  _validatePositive(shape.size, 'size');
  _validateUnitInterval(shape.opacity, 'opacity');
  _validateUnitInterval(shape.flow, 'flow');
  _validateUnitInterval(shape.hardness, 'hardness');
  _validatePositive(shape.spacing, 'spacing');
  _validateRoundness(shape.roundness, 'roundness');
  _validateFinite(shape.angleDegrees, 'angleDegrees');
  _validateUnitInterval(shape.angleJitter, 'angleJitter');
  _validateNonNegativeFinite(shape.scatterRadiusRatio, 'scatterRadiusRatio');
  _validateAtLeastOne(shape.scatterCount, 'scatterCount');
  // The second tip's placement keeps the first tip's ranges: the same code
  // reads both (`BrushShape.secondTip`).
  _validatePositive(shape.dualSpacing, 'dualSpacing');
  _validateRoundness(shape.dualRoundness, 'dualRoundness');
  _validateFinite(shape.dualAngleDegrees, 'dualAngleDegrees');
  _validateUnitInterval(shape.dualAngleJitter, 'dualAngleJitter');
  _validateNonNegativeFinite(
    shape.dualScatterRadiusRatio,
    'dualScatterRadiusRatio',
  );
  _validateAtLeastOne(shape.dualScatterCount, 'dualScatterCount');
  _validateAtLeastOne(shape.tipsPerTurn, 'tipsPerTurn');
}

void _validateAtLeastOne(int value, String fieldName) {
  if (value < 1) {
    throw ArgumentError.value(
      value,
      fieldName,
      'BrushSettings.$fieldName must be at least 1.',
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

/// A correction value [name] on its 0..[max] scale.
void _validateCorrection(double value, String name, double max) {
  if (!value.isFinite || value < 0.0 || value > max) {
    throw ArgumentError.value(
      value,
      name,
      'BrushSettings.correction.$name must be between 0 and $max inclusive.',
    );
  }
}

void _validateRoundness(double value, String fieldName) {
  if (!value.isFinite || value <= 0.0 || value > 1.0) {
    throw ArgumentError.value(
      value,
      fieldName,
      'BrushSettings.$fieldName must be finite and in (0.0, 1.0].',
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
/// ⚠️The four legacy pressure entries stay in their keys and are NOT repeated
/// here; pressure on any other target has no key of its own and is.
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
    if (parts.length != 2 || (entry.value is! List && entry.value is! Map)) {
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
    out[(target, source)] = BrushPressureCurve.fromJson(entry.value);
  }
  return out;
}
