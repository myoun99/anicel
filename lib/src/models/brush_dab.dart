import 'brush_anti_alias.dart';
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
    this.tipShape = BrushTipShape.round,
    required this.pressure,
    required this.sequence,
    this.tiltAzimuthDegrees = 0.0,
    this.tiltAltitude = 1.0,
    this.speed = 0.0,
    this.roundness = 1.0,
    this.angleDegrees = 0.0,
    this.tipMask,
    this.dualMask,
    this.dualMaskScale = 1.0,
    this.dualDensity = 1.0,
    this.dualOffsetU = 0.0,
    this.dualOffsetV = 0.0,
    this.textureMask,
    this.textureScale = 1.0,
    this.textureDensity = 1.0,
    this.antiAlias = BrushAntiAlias.high,
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
    _validateUnitIntervalFinite(dualDensity, 'dualDensity');
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
    _validateFinite(tiltAzimuthDegrees, 'tiltAzimuthDegrees');
    _validateUnitIntervalFinite(tiltAltitude, 'tiltAltitude');
    _validateUnitIntervalFinite(speed, 'speed');
    _validateRoundness(roundness);
    _validateFinite(angleDegrees, 'angleDegrees');
    _validateSquareIsAxisAligned(tipShape, roundness, angleDegrees);
    _validateSequence(sequence);
  }

  /// A dab carrying the settings' BASE values and this sample's input
  /// readings — before any curve has scaled it.
  ///
  /// 🚨THE CURVES ARE NOT APPLIED HERE. They were, inline, and the same four
  /// multiplications lived in `applyBrushInputDynamics` and in the preview
  /// cache as well — one algorithm written three times, each with different
  /// accretions (this one clamped nothing, the dynamics clamp to 0..1, the
  /// preview floors at 0.05). Callers run [applyBrushInputDynamics] and
  /// keep whatever floor is theirs.
  ///
  /// ⚠️F-12 lives in the base, not in the curve: a dab's opacity starts at
  /// 1.0 because the TOOL's opacity is the accumulated stroke's ceiling and
  /// rides `BrushDabSequence.opacity` — on the dab it would cap nothing,
  /// since dabs pile up source-over and any factor below 1 still converges
  /// on opaque.
  factory BrushDab.fromInputSample({
    required BrushInputSample sample,
    required BrushSettings settings,
    required int sequence,
  }) {
    return BrushDab(
      center: CanvasPoint(x: sample.x, y: sample.y),
      color: settings.color,
      size: settings.size,
      opacity: 1.0,
      flow: settings.flow,
      hardness: settings.hardness,
      pressure: sample.pressure,
      sequence: sequence,
      // ⛔"Rides along unread" is no longer true: `applyBrushInputDynamics`
      // evaluates 傾き curves against [tiltAltitude]. It travels on the dab
      // for the reason it always did — a dab that does not carry its own
      // input value could never be replayed (P17).
      tiltAzimuthDegrees: sample.tiltAzimuthDegrees,
      tiltAltitude: sample.tiltAltitude,
      speed: sample.speed,
      roundness: settings.roundness,
      angleDegrees: settings.angleDegrees,
      tipMask: settings.tipMask,
      dualMask: settings.dualMask,
      dualMaskScale: settings.dualMaskScale,
      dualDensity: settings.dualDensity,
      textureMask: settings.textureMask,
      textureScale: settings.textureScale,
      textureDensity: settings.textureDensity,
      antiAlias: settings.antiAlias,
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

  /// How fast the pen was travelling when this dab was laid, normalized to
  /// 0..1 by the pen door — see `BrushInputSample.speed`, which explains why
  /// the raw px/s never travels.
  final double speed;

  /// Which way the pen leaned, in degrees (0 = along +x). Meaningless while
  /// [tiltAltitude] is 1.0 — an upright pen leans nowhere.
  final double tiltAzimuthDegrees;

  /// How upright the pen was: 1.0 vertical, 0.0 flat on the surface.
  final double tiltAltitude;

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

  /// How hard the dual mask bites: `coverage *= (1 - d) + d * sample`, the
  /// same shape [textureDensity] has had all along. 1.0 is the plain
  /// multiply the dual mask used to do unconditionally.
  final double dualDensity;
  final double dualOffsetU;
  final double dualOffsetV;

  /// Paper texture: a mask tiled in CANVAS space (anchored to the canvas,
  /// no per-dab phase) whose sample darkens coverage by [textureDensity]:
  /// `coverage *= (1 - density) + density * sample`. Tile period =
  /// `textureMask.size * textureScale` canvas pixels.
  final BrushTipMask? textureMask;
  final double textureScale;
  final double textureDensity;

  /// How hard this dab's edge lands — see [BrushAntiAlias]. Resolved at
  /// placement from the brush, so the rasterizers never look it up.
  final BrushAntiAlias antiAlias;

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
    double? tiltAzimuthDegrees,
    double? tiltAltitude,
    double? speed,
    double? roundness,
    double? angleDegrees,
    BrushTipMask? tipMask,
    BrushTipMask? dualMask,
    double? dualMaskScale,
    double? dualDensity,
    double? dualOffsetU,
    double? dualOffsetV,
    BrushTipMask? textureMask,
    double? textureScale,
    double? textureDensity,
    BrushAntiAlias? antiAlias,
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
      tiltAzimuthDegrees: tiltAzimuthDegrees ?? this.tiltAzimuthDegrees,
      tiltAltitude: tiltAltitude ?? this.tiltAltitude,
      speed: speed ?? this.speed,
      roundness: roundness ?? this.roundness,
      angleDegrees: angleDegrees ?? this.angleDegrees,
      tipMask: tipMask ?? this.tipMask,
      dualMask: dualMask ?? this.dualMask,
      dualMaskScale: dualMaskScale ?? this.dualMaskScale,
      dualDensity: dualDensity ?? this.dualDensity,
      dualOffsetU: dualOffsetU ?? this.dualOffsetU,
      dualOffsetV: dualOffsetV ?? this.dualOffsetV,
      textureMask: textureMask ?? this.textureMask,
      textureScale: textureScale ?? this.textureScale,
      textureDensity: textureDensity ?? this.textureDensity,
      antiAlias: antiAlias ?? this.antiAlias,
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
    // ⛔Omitted at the resting value: a brush dab is never square now, so
    // every stroke a brush records is byte-identical without this key. The
    // FILL, selection-lift and cut-stamp verbs still write it.
    if (tipShape != BrushTipShape.round) 'tipShape': tipShape.toJson(),
    'pressure': pressure,
    'sequence': sequence,
    // ⚠️Omitted at the resting value so a stroke recorded before tilt
    // existed round-trips byte-identical to one drawn with an upright pen.
    if (tiltAltitude != 1.0) 'tiltAltitude': tiltAltitude,
    if (tiltAzimuthDegrees != 0.0) 'tiltAzimuthDegrees': tiltAzimuthDegrees,
    if (speed != 0.0) 'speed': speed,
    'roundness': roundness,
    'angleDegrees': angleDegrees,
    if (tipMask != null) 'tipMask': tipMask!.toJson(),
    if (dualMask != null) 'dualMask': dualMask!.toJson(),
    'dualMaskScale': dualMaskScale,
    'dualDensity': dualDensity,
    'dualOffsetU': dualOffsetU,
    'dualOffsetV': dualOffsetV,
    if (textureMask != null) 'textureMask': textureMask!.toJson(),
    'textureScale': textureScale,
    'textureDensity': textureDensity,
    if (antiAlias != BrushAntiAlias.high) 'antiAlias': antiAlias.name,
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
      tipShape: json['tipShape'] == null
          ? BrushTipShape.round
          : BrushTipShape.fromJson(json['tipShape']),
      pressure: (json['pressure'] as num).toDouble(),
      sequence: json['sequence'] as int,
      tiltAzimuthDegrees:
          (json['tiltAzimuthDegrees'] as num?)?.toDouble() ?? 0.0,
      tiltAltitude: (json['tiltAltitude'] as num?)?.toDouble() ?? 1.0,
      speed: (json['speed'] as num?)?.toDouble() ?? 0.0,
      roundness: (json['roundness'] as num?)?.toDouble() ?? 1.0,
      angleDegrees: (json['angleDegrees'] as num?)?.toDouble() ?? 0.0,
      tipMask: json['tipMask'] == null
          ? null
          : BrushTipMask.fromJson(json['tipMask'] as Map<String, dynamic>),
      dualMask: json['dualMask'] == null
          ? null
          : BrushTipMask.fromJson(json['dualMask'] as Map<String, dynamic>),
      dualMaskScale: (json['dualMaskScale'] as num?)?.toDouble() ?? 1.0,
      dualDensity: (json['dualDensity'] as num?)?.toDouble() ?? 1.0,
      dualOffsetU: (json['dualOffsetU'] as num?)?.toDouble() ?? 0.0,
      dualOffsetV: (json['dualOffsetV'] as num?)?.toDouble() ?? 0.0,
      textureMask: json['textureMask'] == null
          ? null
          : BrushTipMask.fromJson(json['textureMask'] as Map<String, dynamic>),
      textureScale: (json['textureScale'] as num?)?.toDouble() ?? 1.0,
      textureDensity: (json['textureDensity'] as num?)?.toDouble() ?? 1.0,
      antiAlias:
          BrushAntiAlias.named(json['antiAlias'] as String?) ??
          BrushAntiAlias.high,
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
          other.tiltAzimuthDegrees == tiltAzimuthDegrees &&
          other.tiltAltitude == tiltAltitude &&
          other.speed == speed &&
          other.roundness == roundness &&
          other.angleDegrees == angleDegrees &&
          other.tipMask == tipMask &&
          other.dualMask == dualMask &&
          other.dualMaskScale == dualMaskScale &&
          other.dualDensity == dualDensity &&
          other.dualOffsetU == dualOffsetU &&
          other.dualOffsetV == dualOffsetV &&
          other.textureMask == textureMask &&
          other.textureScale == textureScale &&
          other.textureDensity == textureDensity &&
          other.antiAlias == antiAlias &&
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
    tiltAzimuthDegrees,
    tiltAltitude,
    speed,
    roundness,
    angleDegrees,
    tipMask,
    dualMask,
    dualMaskScale,
    dualDensity,
    dualOffsetU,
    dualOffsetV,
    textureMask,
    textureScale,
    textureDensity,
    antiAlias,
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

/// A SQUARE dab is always axis-aligned, and this is what makes that true
/// rather than merely observed.
///
/// 🚨A square dab is not a brush mark any more (유저 2026-09-09: 「포토샵이나
/// 클튜처럼 가자. 원이나 이미지」) — the only things that build one are the
/// FILL, the selection lift and the cut stamp, and each means "cover exactly
/// this rect". None of them squashes or rotates, and none goes through
/// `BrushStrokeDynamics`, so none can pick up roundness or angle jitter.
///
/// ⇒ The rotated-rect coverage path had no way to be reached. It existed in
/// THREE transcriptions — the Dart reference, the Dart kernel and the C
/// kernel's `QA_DAB_FLAG_ROTATED_RECT` — with a parity case keeping them in
/// step, which is a lot of machinery for a shape nothing can ask for. This
/// check is what lets it be DELETED rather than left unused: the state is
/// unrepresentable now, so a future caller finds out here instead of finding
/// a silently axis-aligned rectangle.
void _validateSquareIsAxisAligned(
  BrushTipShape tipShape,
  double roundness,
  double angleDegrees,
) {
  if (tipShape == BrushTipShape.round) {
    return;
  }
  if (roundness != 1.0 || angleDegrees != 0.0) {
    throw ArgumentError.value(
      '$roundness/$angleDegrees',
      'roundness/angleDegrees',
      'A square BrushDab is the fill and stamp verbs\' "cover exactly this '
          'rect", so it must stay axis-aligned: roundness 1.0, angle 0.',
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
