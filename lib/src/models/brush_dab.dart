import 'brush_anti_alias.dart';
import 'brush_stamp_image.dart';
import 'brush_tip_mask.dart';
import 'brush_tip_shape.dart';
import 'canvas_point.dart';
import 'separable_blend_mode.dart';

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
    this.tiltAltitude,
    this.speed = 0.0,
    this.roundness = 1.0,
    this.angleDegrees = 0.0,
    this.tipMask,
    this.dualMask,
    this.dualMaskScale = 1.0,
    this.dualDensity = 1.0,
    this.dualCompositeMode = SeparableBlendMode.multiply,
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
    _validateTilt(tiltAltitude, tiltAzimuthDegrees);
    _validateUnitIntervalFinite(speed, 'speed');
    _validateRoundness(roundness);
    _validateFinite(angleDegrees, 'angleDegrees');
    _validateSquareIsAxisAligned(tipShape, tipMask, roundness, angleDegrees);
    _validateSequence(sequence);
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
  /// [tiltAltitude] is 1.0 — an upright pen leans nowhere — and REQUIRED to
  /// be 0 when it is null, so "the device said nothing" has exactly one
  /// spelling (the constructor checks).
  final double tiltAzimuthDegrees;

  /// How upright the pen was: 1.0 vertical, 0.0 flat on the surface — or
  /// NULL when the device reported no tilt at all.
  ///
  /// 🚨NULL IS NOT 1.0, and telling them apart is the whole point (유저
  /// 2026-09-09, `brush-tilt-no-device-Q1` 답 1: 「기울기 못 재는 기기에서는
  /// 傾き 소스를 건너뛴다」, 「1번이 구조적으로 맞아보여서」). A mouse and an
  /// upright pen used to arrive as the same number, so an imported brush with
  /// a 0% tilt minimum drew nothing at all on a mouse and the screen could
  /// not say why. Absence makes `brushInputValue` answer null, and
  /// `_factorFor` skips a source it cannot answer for — the contribution is
  /// exactly 1.0 and the brush draws at its base.
  final double? tiltAltitude;

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

  /// How the dual mask COMBINES with the coverage under it.
  ///
  /// 🚨Both formats say a dual tip has one and ours had none. Clip Studio
  /// writes `DualBrushCompositeMode` (the 合成モード menu index — 1 and 12
  /// found in the user's own files) and Photoshop writes `dualBrush.BlnM`
  /// (eight four-char codes across 765 brushes). We multiplied and only
  /// multiplied, so both were cut off at the same place.
  ///
  /// ⛔[SeparableBlendMode], not [BrushBlendMode]: this combines two
  /// COVERAGES, and the porter-duff heads (`color`/`behind`/`erase`) answer
  /// a question about pixels and alpha that a mask pair does not ask. The
  /// importers already map their formats to [BrushBlendMode] and take
  /// `.separable` from there, so nothing new decodes anything.
  ///
  /// ⚠️[SeparableBlendMode.multiply] is the default AND its own line in both
  /// kernels — the general form is the same NUMBER and not the same BYTES,
  /// and every brush that ever shipped multiplies.
  final SeparableBlendMode dualCompositeMode;

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
    SeparableBlendMode? dualCompositeMode,
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
      dualCompositeMode: dualCompositeMode ?? this.dualCompositeMode,
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
    // ⚠️Absent when the device reported none, which is also how a stroke
    // recorded before tilt existed reads back — the key is simply not there.
    if (tiltAltitude != null) 'tiltAltitude': tiltAltitude,
    if (tiltAzimuthDegrees != 0.0) 'tiltAzimuthDegrees': tiltAzimuthDegrees,
    if (speed != 0.0) 'speed': speed,
    'roundness': roundness,
    'angleDegrees': angleDegrees,
    if (tipMask != null) 'tipMask': tipMask!.toJson(),
    if (dualMask != null) 'dualMask': dualMask!.toJson(),
    'dualMaskScale': dualMaskScale,
    'dualDensity': dualDensity,
    'dualCompositeMode': dualCompositeMode.name,
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
      tiltAltitude: (json['tiltAltitude'] as num?)?.toDouble(),
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
      dualCompositeMode:
          SeparableBlendMode.forName(
            (json['dualCompositeMode'] as String?) ?? '',
          ) ??
          SeparableBlendMode.multiply,
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
          other.dualCompositeMode == dualCompositeMode &&
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
    dualCompositeMode,
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

/// Tilt is ONE reading of two numbers, so it has ONE way to be absent.
///
/// ⛔Without this check a dab could carry an azimuth with no altitude —
/// a lean in a direction the pen never reported — and "the device said
/// nothing" would have two spellings. Two fields sharing one fact is how a
/// mutation walked out of the speed round untouched.
void _validateTilt(double? altitude, double azimuthDegrees) {
  if (altitude == null) {
    if (azimuthDegrees != 0.0) {
      throw ArgumentError.value(
        azimuthDegrees,
        'tiltAzimuthDegrees',
        'BrushDab.tiltAzimuthDegrees must be 0 when no tilt was reported.',
      );
    }
    return;
  }
  _validateUnitIntervalFinite(altitude, 'tiltAltitude');
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
/// ⚠️MASKLESS squares only, which is exactly what the deleted path was gated
/// on (`tipMask == null && !isRound && …`). With a tip MASK the shape flag is
/// ignored entirely — the mask carries the footprint and the sampler squashes
/// and rotates it — so a masked dab may carry any roundness and angle, and a
/// rotated raster tip is a real brush (Graphite Stick is one).
void _validateSquareIsAxisAligned(
  BrushTipShape tipShape,
  BrushTipMask? tipMask,
  double roundness,
  double angleDegrees,
) {
  if (tipShape == BrushTipShape.round || tipMask != null) {
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
