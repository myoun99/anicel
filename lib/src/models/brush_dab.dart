import 'brush_anti_alias.dart';
import 'brush_blend_mode.dart';
import 'brush_stamp_image.dart';
import 'brush_texture_mode.dart';
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
    this.twistDegrees,
    this.speed = 0.0,
    this.roundness = 1.0,
    this.angleDegrees = 0.0,
    this.tipMask,
    this.dual,
    this.second = false,
    this.textureMask,
    this.textureScale = 1.0,
    this.textureDensity = 1.0,
    this.textureMode = BrushTextureMode.multiply,
    this.antiAlias = BrushAntiAlias.high,
    this.erase = false,
    this.blurs = false,
    this.stamp,
    this.pathStep,
  }) {
    if (!textureScale.isFinite || textureScale <= 0.0) {
      throw ArgumentError.value(
        textureScale,
        'textureScale',
        'BrushDab.textureScale must be finite and greater than 0.',
      );
    }
    _validateUnitIntervalFinite(textureDensity, 'textureDensity');
    if (dual case final dual?) {
      _validateUnitIntervalFinite(dual.density, 'dual.density');
    }
    if (second && dual == null) {
      throw ArgumentError.value(
        second,
        'second',
        'A second tip\'s dab belongs to a stroke with a second tip — give it '
            'the stroke\'s view.',
      );
    }
    _validateColor(color);
    _validateNonNegativeFinite(size, 'size');
    _validateUnitIntervalFinite(opacity, 'opacity');
    _validateUnitIntervalFinite(flow, 'flow');
    _validateUnitIntervalFinite(hardness, 'hardness');
    _validateUnitIntervalFinite(pressure, 'pressure');
    _validateFinite(tiltAzimuthDegrees, 'tiltAzimuthDegrees');
    _validateTilt(tiltAltitude, tiltAzimuthDegrees);
    _validateTwist(twistDegrees);
    _validateUnitIntervalFinite(speed, 'speed');
    _validateRoundness(roundness);
    _validateFinite(angleDegrees, 'angleDegrees');
    _validateSquareIsAxisAligned(tipShape, tipMask, roundness, angleDegrees);
    _validateSequence(sequence);
    _validatePathStep(pathStep);
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
  /// 0..1 against `AppInputSettings.speedReferencePixelsPerSecond`.
  ///
  /// 🚨**NORMALIZED AT THE DOOR, like pressure and tilt.** The raw px/s never
  /// reaches a dab, because a reader holding raw pixels would have to divide
  /// by the ceiling itself to mean anything — sixteen readers, sixteen
  /// chances to divide by a different one. The pen door divides once
  /// (`AppInput.normalizedSpeed`) and everything downstream reads a plain
  /// 0..1, exactly as it does for the other two.
  ///
  /// ⚠️Speed is a property of the MOVE, not of the point: every dab placed
  /// along one segment carries that segment's speed. 0.0 is a pen that has
  /// just landed and has no move behind it yet.
  /// ↩️This lived on `BrushInputSample.speed` until that model went with the
  /// offline path that built it — nothing in the app ever did.
  final double speed;

  /// Which way the pen's top leaned, in degrees clockwise from +x — the
  /// convention every source is converted into (`PenLean`). Meaningless
  /// while [tiltAltitude] is 1.0 — an upright pen leans nowhere — and
  /// REQUIRED to be 0 when it is null, so "the device said nothing" has
  /// exactly one spelling (the constructor checks).
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
  /// `brushInputFactor` skips a source it cannot answer for — the
  /// contribution is exactly 1.0 and the brush draws at its base.
  final double? tiltAltitude;

  /// How far the pen was turned about its own barrel, in degrees 0..360
  /// clockwise — the roll a Wacom Art Pen reports (F-176-Q9, Clip Studio's
  /// ペン軸の回転) — or NULL when the device reported none, which is every
  /// pen whose barrel does not turn. Null is not 0°, as [tiltAltitude]'s
  /// null is not upright.
  final double? twistDegrees;

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

  /// How the stroke shows its second tip — carried by EVERY dab of a stroke
  /// that has one, the first tip's and the second's alike, null on every
  /// dab of a stroke that has none. The law is beside `qa_dual_view_rows`
  /// (qa_engine.c, ABI 60): the second tip is a second stroke along the
  /// same path, piling on a plane of its own ([second]), and what the
  /// stroke shows is the two planes through this view.
  final BrushDualView? dual;

  /// Whether this is a dab of the second tip's stroke: its [tipMask] is the
  /// second tip, and it piles on the stroke's second plane — over, as any
  /// dab piles over its alpha — and paints no colour of its own.
  final bool second;

  /// Paper texture: a mask tiled in CANVAS space (anchored to the canvas,
  /// no per-dab phase) whose sample darkens coverage by [textureDensity]:
  /// `coverage *= (1 - density) + density * sample`. Tile period =
  /// `textureMask.size * textureScale` canvas pixels.
  final BrushTipMask? textureMask;
  final double textureScale;
  final double textureDensity;

  /// How [textureMask] meets the coverage — the multiply above, or the
  /// paper's height cutting the silhouette (F-451) — see
  /// [BrushTextureMode].
  final BrushTextureMode textureMode;

  /// How hard this dab's edge lands — see [BrushAntiAlias]. Resolved at
  /// placement from the brush, so the rasterizers never look it up.
  final BrushAntiAlias antiAlias;

  /// Erase mode: the dab's coverage REMOVES destination alpha
  /// (destination-out) instead of painting color over it. The color still
  /// supplies the source alpha; RGB is ignored.
  final bool erase;

  /// Blur mode (I-75 흐리기): the dab lays no colour — it moves the picture
  /// under it toward that picture blurred, by what it would have laid as
  /// paint ([color] is ignored). It rides the dab as [erase] does, so a
  /// stroke re-derived from its dabs — the commit after the cel moved, 확정
  /// on another cel — knows what it was. Never set together with [erase]:
  /// the eraser's law wins (`BrushEditCanvasInputSettings.blurs`). The law
  /// is beside `BrushBlurPicture`.
  final bool blurs;

  /// RGBA stamp (R14-④ bitmap lift): when set, the dab draws the stamp's
  /// pixels 1:1 source-over centered on [center] (no resampling; [opacity]
  /// still modulates, [erase] still clears) and every tip and texture field
  /// is ignored. [size] is max(stamp.width, stamp.height) by convention;
  /// the dab's reach is the stamp's landing rect (`dirtyRegionForBrushDab`).
  final BrushStampImage? stamp;

  /// How long a stretch of the stroke this dab stands for, in canvas
  /// pixels — the step the interpolator laid it at. NULL for the dab that
  /// opens a stroke (a tap is only that) and for a dab not laid along a path.
  ///
  /// 🚨★★★EVERY DAB LAYS WHAT THIS STEP IS WORTH (유저 2026-10-01
  /// `one-pixel-steps-change-a-brush-with-its-size` A: 「엔진이 쌓임을 환산 —
  /// 크기와 무관하게(클튜처럼)」, Q2 「환산은 커널에서 — 모든 브러시」): the
  /// steps floor at one pixel, so a big brush lays far more stamps per width
  /// than a small one and piled up darker and harder-edged for it. The
  /// kernels even that out on the laid alpha (`stampShareOf`).
  final double? pathStep;

  /// This dab as a tool set to [blend] lays it.
  ///
  /// 🚨ERASE rides a flag on the DAB, not the blend mode — the materializer
  /// reads [erase] per dab and the erase blend takes the plain path, so a
  /// dab handed over with the mode alone paints where it should clear. A
  /// stamp is built with no opinion about erasing (a fill's pieces, a cut
  /// piece), so every road that lands one asks here: the bucket's tap, an
  /// area ([BrushBlendMode.erase] is what makes 사각형/올가미 지우개 out of
  /// the fill tool) and the stamp tool's door. The trap was hit three
  /// times, a caller each, while each wrote this line for itself.
  BrushDab underBlend(BrushBlendMode blend) =>
      blend == BrushBlendMode.erase ? copyWith(erase: true) : this;

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
    double? twistDegrees,
    double? speed,
    double? roundness,
    double? angleDegrees,
    BrushTipMask? tipMask,
    BrushDualView? dual,
    bool? second,
    BrushTipMask? textureMask,
    double? textureScale,
    double? textureDensity,
    BrushTextureMode? textureMode,
    BrushAntiAlias? antiAlias,
    bool? erase,
    bool? blurs,
    BrushStampImage? stamp,
    double? pathStep,
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
      twistDegrees: twistDegrees ?? this.twistDegrees,
      speed: speed ?? this.speed,
      roundness: roundness ?? this.roundness,
      angleDegrees: angleDegrees ?? this.angleDegrees,
      tipMask: tipMask ?? this.tipMask,
      dual: dual ?? this.dual,
      second: second ?? this.second,
      textureMask: textureMask ?? this.textureMask,
      textureScale: textureScale ?? this.textureScale,
      textureDensity: textureDensity ?? this.textureDensity,
      textureMode: textureMode ?? this.textureMode,
      antiAlias: antiAlias ?? this.antiAlias,
      erase: erase ?? this.erase,
      blurs: blurs ?? this.blurs,
      stamp: stamp ?? this.stamp,
      pathStep: pathStep ?? this.pathStep,
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
    if (twistDegrees != null) 'twistDegrees': twistDegrees,
    if (speed != 0.0) 'speed': speed,
    'roundness': roundness,
    'angleDegrees': angleDegrees,
    if (tipMask != null) 'tipMask': tipMask!.toJson(),
    if (dual != null) 'dual': dual!.toJson(),
    if (second) 'second': true,
    if (textureMask != null) 'textureMask': textureMask!.toJson(),
    'textureScale': textureScale,
    'textureDensity': textureDensity,
    if (textureMode != BrushTextureMode.multiply)
      'textureMode': textureMode.name,
    if (antiAlias != BrushAntiAlias.high) 'antiAlias': antiAlias.name,
    if (erase) 'erase': true,
    if (blurs) 'blurs': true,
    if (stamp != null) 'stamp': stamp!.toJson(),
    if (pathStep != null) 'pathStep': pathStep,
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
      twistDegrees: (json['twistDegrees'] as num?)?.toDouble(),
      speed: (json['speed'] as num?)?.toDouble() ?? 0.0,
      roundness: (json['roundness'] as num?)?.toDouble() ?? 1.0,
      angleDegrees: (json['angleDegrees'] as num?)?.toDouble() ?? 0.0,
      tipMask: json['tipMask'] == null
          ? null
          : BrushTipMask.fromJson(json['tipMask'] as Map<String, dynamic>),
      dual: json['dual'] == null
          ? null
          : BrushDualView.fromJson(json['dual'] as Map<String, dynamic>),
      second: json['second'] as bool? ?? false,
      textureMask: json['textureMask'] == null
          ? null
          : BrushTipMask.fromJson(json['textureMask'] as Map<String, dynamic>),
      textureScale: (json['textureScale'] as num?)?.toDouble() ?? 1.0,
      textureDensity: (json['textureDensity'] as num?)?.toDouble() ?? 1.0,
      textureMode: BrushTextureMode.fromName(json['textureMode']),
      antiAlias:
          BrushAntiAlias.named(json['antiAlias'] as String?) ??
          BrushAntiAlias.high,
      erase: json['erase'] as bool? ?? false,
      blurs: json['blurs'] as bool? ?? false,
      stamp: json['stamp'] == null
          ? null
          : BrushStampImage.fromJson(json['stamp'] as Map<String, dynamic>),
      pathStep: (json['pathStep'] as num?)?.toDouble(),
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
          other.twistDegrees == twistDegrees &&
          other.speed == speed &&
          other.roundness == roundness &&
          other.angleDegrees == angleDegrees &&
          other.tipMask == tipMask &&
          other.dual == dual &&
          other.second == second &&
          other.textureMask == textureMask &&
          other.textureScale == textureScale &&
          other.textureDensity == textureDensity &&
          other.textureMode == textureMode &&
          other.antiAlias == antiAlias &&
          other.erase == erase &&
          other.blurs == blurs &&
          other.stamp == stamp &&
          other.pathStep == pathStep;

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
    twistDegrees,
    speed,
    roundness,
    angleDegrees,
    tipMask,
    dual,
    second,
    textureMask,
    textureScale,
    textureDensity,
    textureMode,
    antiAlias,
    erase,
    blurs,
    stamp,
    pathStep,
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

/// A twist is once round, so it has one spelling of each turn.
void _validateTwist(double? degrees) {
  if (degrees != null &&
      (!degrees.isFinite || degrees < 0.0 || degrees >= 360.0)) {
    throw ArgumentError.value(
      degrees,
      'twistDegrees',
      'BrushDab.twistDegrees must be within [0, 360).',
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

void _validatePathStep(double? value) {
  if (value != null && (!value.isFinite || value <= 0.0)) {
    throw ArgumentError.value(
      value,
      'pathStep',
      'BrushDab.pathStep must be finite and greater than 0, or null.',
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

/// How a stroke with a second tip shows its two planes — the first tip's
/// alpha combined with the second tip's through [compositeMode] at
/// [density] (`qa_dual_view_rows`, and [BrushDab.dual]).
///
/// 🚨Both formats say a second tip has a mode and ours had none. Clip
/// Studio writes `DualBrushCompositeMode` (the 合成モード menu index — 1 and
/// 12 found in the user's own files) and Photoshop writes `dualBrush.BlnM`
/// (eight four-char codes across 765 brushes). We multiplied and only
/// multiplied, so both were cut off at the same place.
///
/// ⛔[SeparableBlendMode], not [BrushBlendMode]: this combines two
/// COVERAGES, and the porter-duff heads (`color`/`behind`/`erase`) answer a
/// question about pixels and alpha that a pair of coverages does not ask.
/// The importers already map their formats to [BrushBlendMode] and take
/// `.separable` from there, so nothing new decodes anything.
///
/// ⚠️[SeparableBlendMode.multiply] is the default AND its own line in every
/// transcription of the view — the general form is the same NUMBER and not
/// the same BYTES.
class BrushDualView {
  const BrushDualView({
    this.compositeMode = SeparableBlendMode.multiply,
    this.density = 1.0,
  });

  factory BrushDualView.fromJson(Map<String, dynamic> json) => BrushDualView(
    compositeMode:
        SeparableBlendMode.forName((json['compositeMode'] as String?) ?? '') ??
        SeparableBlendMode.multiply,
    density: (json['density'] as num?)?.toDouble() ?? 1.0,
  );

  final SeparableBlendMode compositeMode;

  /// How hard the second tip bites: at 0 the stroke shows its first tip
  /// alone, at 1 the combination whole.
  final double density;

  Map<String, dynamic> toJson() => {
    if (compositeMode != SeparableBlendMode.multiply)
      'compositeMode': compositeMode.name,
    if (density != 1.0) 'density': density,
  };

  @override
  bool operator ==(Object other) =>
      other is BrushDualView &&
      other.compositeMode == compositeMode &&
      other.density == density;

  @override
  int get hashCode => Object.hash(compositeMode, density);

  @override
  String toString() => 'BrushDualView($compositeMode, density: $density)';
}
