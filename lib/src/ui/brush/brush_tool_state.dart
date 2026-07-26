import '../../models/brush_blend_mode.dart';
import '../../models/brush_pressure_curve.dart';
import '../../models/brush_settings.dart';
import '../../models/brush_shape.dart';
import '../../models/brush_tip_mask.dart';
import '../../models/brush_tip_rotation_mode.dart';
import '../../models/brush_tip_shape.dart';
import '../canvas/brush_edit_canvas_input_settings.dart';

/// Which canvas tool the pointer drives. The eraser reuses every brush
/// option (size, hardness, tip) but its dabs remove alpha instead of
/// painting color; the eyedropper samples the composite (P5), the fill
/// commits one region-mask dab (P6), the selection tools (P9: rect
/// marquee / freehand lasso) drag out a region, and the MOVE tool
/// (R11-⑧: selection ≠ move) drags the selected content — none of them
/// start strokes.
enum CanvasTool { brush, eraser, eyedropper, fill, selectRect, lasso, move }

/// Whether [tool] paints strokes through the interactive canvas (the
/// non-painting tools mount a tool overlay instead).
bool canvasToolPaints(CanvasTool tool) =>
    tool == CanvasTool.brush || tool == CanvasTool.eraser;

/// Whether [tool] mounts the selection interaction layer (the P9
/// marquee/lasso tools and the move tool that drags their region).
bool canvasToolSelects(CanvasTool tool) =>
    tool == CanvasTool.selectRect ||
    tool == CanvasTool.lasso ||
    tool == CanvasTool.move;

/// Editor-session state for the active brush tool options.
///
/// This is UI/tool state owned by the editor session. It is intentionally
/// separate from project, cut, layer, frame, stroke, cache, and save/load
/// data.
///
/// The 26 shared brush parameters live in [shape] ([BrushShape]); the fields
/// below forward to it, and [toBrushSettings]/[toInputSettings]/
/// [fromBrushSettings] carry the whole shape across in one hop so a parameter
/// can never be dropped on a converter boundary (D4). Only [tool],
/// [stabilizerStrength], and [brushBlendMode] are the tool state's own — the
/// three HAND settings that presets deliberately never carry (R26 #10).
class BrushToolState {
  factory BrushToolState({
    double size = defaultSize,
    double opacity = defaultOpacity,
    int color = defaultColor,
    double spacing = defaultSpacing,
    double hardness = defaultHardness,
    double flow = defaultFlow,
    BrushTipShape tipShape = defaultTipShape,
    BrushPressureCurve? sizePressureCurve,
    BrushPressureCurve? opacityPressureCurve,
    BrushPressureCurve? flowPressureCurve,
    BrushPressureCurve? hardnessPressureCurve,
    double roundness = defaultRoundness,
    double angleDegrees = defaultAngleDegrees,
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
    BrushTipMask? textureMask,
    double textureScale = 1.0,
    double textureDensity = 1.0,
    CanvasTool tool = CanvasTool.brush,
    double stabilizerStrength = 0.0,
    BrushBlendMode brushBlendMode = BrushBlendMode.color,
  }) {
    return BrushToolState.clamped(
      size: size,
      opacity: opacity,
      color: color,
      spacing: spacing,
      hardness: hardness,
      flow: flow,
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
      scatterRadiusRatio: scatterRadiusRatio,
      scatterCount: scatterCount,
      scatterBothAxes: scatterBothAxes,
      dualMask: dualMask,
      dualMaskScale: dualMaskScale,
      textureMask: textureMask,
      textureScale: textureScale,
      textureDensity: textureDensity,
      tool: tool,
      stabilizerStrength: stabilizerStrength,
      brushBlendMode: brushBlendMode,
    );
  }

  const BrushToolState._raw({
    required this.shape,
    this.tool = CanvasTool.brush,
    this.stabilizerStrength = 0.0,
    this.brushBlendMode = BrushBlendMode.color,
  });

  /// Builds tool state from a loose [BrushShape] and the three hand settings,
  /// clamping every shared parameter into the panel's ranges (see
  /// [_clampShape]). This is the wholesale hop the preset-load path takes —
  /// [fromBrushSettings] routes through it — so no shared parameter can be
  /// dropped when a preset is applied.
  factory BrushToolState.fromShape(
    BrushShape shape, {
    CanvasTool tool = CanvasTool.brush,
    double stabilizerStrength = 0.0,
    BrushBlendMode brushBlendMode = BrushBlendMode.color,
  }) {
    return BrushToolState._raw(
      shape: _clampShape(shape),
      tool: tool,
      stabilizerStrength: clampStabilizerStrength(stabilizerStrength),
      brushBlendMode: brushBlendMode,
    );
  }

  factory BrushToolState.clamped({
    double? size,
    double? opacity,
    int? color,
    double? spacing,
    double? hardness,
    double? flow,
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
    CanvasTool? tool,
    double? stabilizerStrength,
    BrushBlendMode? brushBlendMode,
  }) {
    return BrushToolState.fromShape(
      BrushShape(
        color: color ?? defaultColor,
        size: size ?? defaultSize,
        opacity: opacity ?? defaultOpacity,
        flow: flow ?? defaultFlow,
        hardness: hardness ?? defaultHardness,
        spacing: spacing ?? defaultSpacing,
        tipShape: tipShape ?? defaultTipShape,
        sizePressureCurve: sizePressureCurve,
        opacityPressureCurve: opacityPressureCurve,
        flowPressureCurve: flowPressureCurve,
        hardnessPressureCurve: hardnessPressureCurve,
        roundness: roundness ?? defaultRoundness,
        angleDegrees: angleDegrees ?? defaultAngleDegrees,
        tipMask: tipMask,
        rotationMode: rotationMode ?? BrushTipRotationMode.fixed,
        sizeJitter: sizeJitter ?? 0.0,
        opacityJitter: opacityJitter ?? 0.0,
        angleJitter: angleJitter ?? 0.0,
        scatterRadiusRatio: scatterRadiusRatio ?? 0.0,
        scatterCount: scatterCount ?? 1,
        scatterBothAxes: scatterBothAxes ?? true,
        dualMask: dualMask,
        dualMaskScale: dualMaskScale ?? 1.0,
        textureMask: textureMask,
        textureScale: textureScale ?? 1.0,
        textureDensity: textureDensity ?? 1.0,
      ),
      tool: tool ?? CanvasTool.brush,
      stabilizerStrength: stabilizerStrength ?? 0.0,
      brushBlendMode: brushBlendMode ?? BrushBlendMode.color,
    );
  }

  /// Clamps the shared parameters that have panel ranges into those ranges,
  /// carrying every other parameter through untouched. Field-adds that are not
  /// clampable ride along automatically; a new clampable one just needs a line
  /// here (and, if omitted, still travels — it is simply not clamped).
  static BrushShape _clampShape(BrushShape s) => s.copyWith(
    size: clampSize(s.size),
    opacity: clampOpacity(s.opacity),
    spacing: clampSpacing(s.spacing),
    hardness: clampUnit(s.hardness),
    flow: clampUnit(s.flow),
    roundness: clampRoundness(s.roundness),
    angleDegrees: clampAngleDegrees(s.angleDegrees),
    sizeJitter: clampZeroToOne(s.sizeJitter),
    opacityJitter: clampZeroToOne(s.opacityJitter),
    angleJitter: clampZeroToOne(s.angleJitter),
    scatterRadiusRatio: clampScatterRadius(s.scatterRadiusRatio),
    scatterCount: clampScatterCount(s.scatterCount),
    dualMaskScale: clampDualMaskScale(s.dualMaskScale),
    textureScale: clampDualMaskScale(s.textureScale),
    textureDensity: clampZeroToOne(s.textureDensity),
  );

  static const double minSize = 1.0;
  // CSP-parity ceiling; the settings slider maps this range exponentially so
  // the small sizes keep their precision.
  static const double maxSize = 2000.0;
  static const double defaultSize = 10.0;
  static const double defaultOpacity = 1.0;
  static const int defaultColor = 0xFF000000;
  static const double minSpacing = 0.05;
  static const double maxSpacing = 4.0;
  static const double defaultSpacing = 0.25;
  static const double defaultHardness = 1.0;
  static const double defaultFlow = 1.0;
  static const BrushTipShape defaultTipShape = BrushTipShape.round;
  static const double minRoundness = 0.05;
  static const double defaultRoundness = 1.0;
  static const double minAngleDegrees = 0.0;
  static const double maxAngleDegrees = 180.0;
  static const double defaultAngleDegrees = 0.0;
  static const BrushToolState defaults = BrushToolState._raw(
    shape: BrushShape(size: defaultSize, spacing: defaultSpacing),
  );

  /// The shared 26-parameter spine; the fields below forward to it, and the
  /// converters carry it across whole. See [BrushShape].
  final BrushShape shape;

  double get size => shape.size;
  double get opacity => shape.opacity;
  int get color => shape.color;
  double get spacing => shape.spacing;

  /// Tip edge falloff: 1.0 paints a hard edge, lower values fade linearly
  /// from `radius * hardness` to the radius (same coverage model as the
  /// commit rasterizer).
  double get hardness => shape.hardness;

  /// Per-dab paint strength; combined multiplicatively with [opacity] when a
  /// dab is sampled.
  double get flow => shape.flow;

  BrushTipShape get tipShape => shape.tipShape;

  /// BB-3 (R26 #11): per-setting pen-pressure response curves; `null` =
  /// the setting ignores pressure. Part of brush presets (they travel
  /// through [toBrushSettings]/[fromBrushSettings] like the sliders).
  /// [copyWith] PRESERVES them (same contract as [tipMask]); clearing one
  /// goes through [withPressureCurve].
  BrushPressureCurve? get sizePressureCurve => shape.sizePressureCurve;
  BrushPressureCurve? get opacityPressureCurve => shape.opacityPressureCurve;
  BrushPressureCurve? get flowPressureCurve => shape.flowPressureCurve;
  BrushPressureCurve? get hardnessPressureCurve => shape.hardnessPressureCurve;

  /// Minor-to-major axis ratio of the tip; 1.0 keeps the classic
  /// circle/square, smaller values flatten it into an ellipse/rectangle.
  double get roundness => shape.roundness;

  /// Visual counterclockwise rotation of the tip's major axis from the
  /// horizontal, in degrees (0-180; an ellipse repeats every 180).
  double get angleDegrees => shape.angleDegrees;

  /// Sampled (bitmap) tip applied by a preset; `null` uses the parametric
  /// [tipShape]. The panel has no direct mask picker yet — masks arrive via
  /// presets (and later ABR import). Cleared only by applying a preset
  /// without one ([BrushToolState.fromBrushSettings]); [copyWith] preserves
  /// it so slider tweaks keep the textured tip.
  BrushTipMask? get tipMask => shape.tipMask;

  /// Placement dynamics carried from presets/imports (no panel controls
  /// yet, pending the unified UI pass): see the same-named fields on
  /// `BrushShape`.
  BrushTipRotationMode get rotationMode => shape.rotationMode;
  double get sizeJitter => shape.sizeJitter;
  double get opacityJitter => shape.opacityJitter;
  double get angleJitter => shape.angleJitter;
  double get scatterRadiusRatio => shape.scatterRadiusRatio;
  int get scatterCount => shape.scatterCount;
  bool get scatterBothAxes => shape.scatterBothAxes;
  BrushTipMask? get dualMask => shape.dualMask;
  double get dualMaskScale => shape.dualMaskScale;
  BrushTipMask? get textureMask => shape.textureMask;
  double get textureScale => shape.textureScale;
  double get textureDensity => shape.textureDensity;

  /// The active canvas tool. Not part of presets ([toBrushSettings] omits
  /// it); applying a preset returns to the brush, CSP-style.
  final CanvasTool tool;

  /// Pull-string stabilization strength (P7), 0..100 screen px of rope.
  /// A HAND-FEEL setting, deliberately outside brush presets — preset
  /// application carries it over unchanged.
  final double stabilizerStrength;

  /// The BRUSH's own composite mode (BB-1, R26 #9). Like the stabilizer
  /// — and like [size] since R26 #10 — a HAND setting outside brush
  /// presets: picking another brush never flips it.
  final BrushBlendMode brushBlendMode;

  /// Builds tool state from a preset's model-layer [BrushSettings], clamping
  /// every value into the panel's ranges.
  factory BrushToolState.fromBrushSettings(BrushSettings settings) =>
      BrushToolState.fromShape(settings.shape);

  /// Snapshot of this tool state as the model-layer [BrushSettings] — the
  /// payload brush presets store.
  BrushSettings toBrushSettings() => BrushSettings.fromShape(shape);

  BrushEditCanvasInputSettings toInputSettings() {
    return BrushEditCanvasInputSettings.fromShape(
      shape,
      // The eraser tool IS the erase blend (locked); a brush whose blend
      // is erase rides the SAME dab flag and kernels.
      erase:
          tool == CanvasTool.eraser || brushBlendMode == BrushBlendMode.erase,
      // A mixing brush has already taken the ground colour into the dab it
      // deposits, so letting the blend mode combine with that ground again
      // would apply it twice — visibly. Mixing therefore forces plain
      // srcOver. Erase still wins: it is the tool, not a blend choice.
      blendMode: tool == CanvasTool.eraser
          ? BrushBlendMode.erase
          : (shape.mixesGroundColor && brushBlendMode != BrushBlendMode.erase
                ? BrushBlendMode.color
                : brushBlendMode),
      stabilizerStrength: stabilizerStrength,
    );
  }

  BrushToolState copyWith({
    double? size,
    double? opacity,
    int? color,
    double? spacing,
    double? hardness,
    double? flow,
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
    CanvasTool? tool,
    double? stabilizerStrength,
    BrushBlendMode? brushBlendMode,
  }) {
    return BrushToolState._raw(
      shape: _clampShape(
        shape.copyWith(
          size: size,
          opacity: opacity,
          color: color,
          spacing: spacing,
          hardness: hardness,
          flow: flow,
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
          scatterRadiusRatio: scatterRadiusRatio,
          scatterCount: scatterCount,
          scatterBothAxes: scatterBothAxes,
          dualMask: dualMask,
          dualMaskScale: dualMaskScale,
          textureMask: textureMask,
          textureScale: textureScale,
          textureDensity: textureDensity,
        ),
      ),
      tool: tool ?? this.tool,
      stabilizerStrength: clampStabilizerStrength(
        stabilizerStrength ?? this.stabilizerStrength,
      ),
      brushBlendMode: brushBlendMode ?? this.brushBlendMode,
    );
  }

  /// The pressure curve driving [target], if any.
  BrushPressureCurve? pressureCurveFor(BrushPressureTarget target) =>
      shape.pressureCurveFor(target);

  /// Replaces (or CLEARS, with null) one of the three sampled masks.
  /// [copyWith] preserves them so a slider tweak keeps a textured tip, which
  /// leaves no way to take one off; this is that way.
  BrushToolState withMask(BrushMaskSlot slot, BrushTipMask? mask) {
    return BrushToolState._raw(
      shape: _clampShape(shape.withMask(slot, mask)),
      tool: tool,
      stabilizerStrength: stabilizerStrength,
      brushBlendMode: brushBlendMode,
    );
  }

  /// Replaces (or CLEARS, with null) one setting's pressure curve —
  /// [copyWith] deliberately preserves curves, so disabling pressure on a
  /// setting comes through here.
  BrushToolState withPressureCurve(
    BrushPressureTarget target,
    BrushPressureCurve? curve,
  ) {
    return BrushToolState._raw(
      shape: _clampShape(shape.withPressureCurve(target, curve)),
      tool: tool,
      stabilizerStrength: stabilizerStrength,
      brushBlendMode: brushBlendMode,
    );
  }

  static double clampSize(double value) {
    if (!value.isFinite) {
      return defaultSize;
    }
    return value.clamp(minSize, maxSize).toDouble();
  }

  static double clampOpacity(double value) {
    if (!value.isFinite) {
      return defaultOpacity;
    }
    return value.clamp(0.0, 1.0).toDouble();
  }

  static double clampSpacing(double value) {
    if (!value.isFinite) {
      return defaultSpacing;
    }
    return value.clamp(minSpacing, maxSpacing).toDouble();
  }

  /// Clamps unit-interval settings (hardness, flow) to [0, 1].
  static double clampUnit(double value) {
    if (!value.isFinite) {
      return 1.0;
    }
    return value.clamp(0.0, 1.0).toDouble();
  }

  /// Clamps roundness to [minRoundness, 1] so the tip never degenerates to
  /// zero width.
  static double clampRoundness(double value) {
    if (!value.isFinite) {
      return defaultRoundness;
    }
    return value.clamp(minRoundness, 1.0).toDouble();
  }

  /// Clamps the tip angle to [0, 180] degrees (an ellipse repeats every 180).
  static double clampAngleDegrees(double value) {
    if (!value.isFinite) {
      return defaultAngleDegrees;
    }
    return value.clamp(minAngleDegrees, maxAngleDegrees).toDouble();
  }

  /// Clamps dynamics ratios (jitters, minimum size) to [0, 1].
  static double clampZeroToOne(double value) {
    if (!value.isFinite) {
      return 0.0;
    }
    return value.clamp(0.0, 1.0).toDouble();
  }

  /// Clamps the scatter radius ratio to a sane non-negative range.
  static double clampScatterRadius(double value) {
    if (!value.isFinite) {
      return 0.0;
    }
    return value.clamp(0.0, 10.0).toDouble();
  }

  /// Clamps the per-step scatter dab count.
  static int clampScatterCount(int value) => value.clamp(1, 16);

  /// Clamps the dual-mask tile scale to a sane positive range.
  static double clampDualMaskScale(double value) {
    if (!value.isFinite || value <= 0.0) {
      return 1.0;
    }
    return value.clamp(0.05, 10.0).toDouble();
  }

  /// Clamps the stabilizer rope to [0, 100] screen pixels.
  static double clampStabilizerStrength(double value) {
    if (!value.isFinite) {
      return 0.0;
    }
    return value.clamp(0.0, 100.0).toDouble();
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BrushToolState &&
          other.shape == shape &&
          other.tool == tool &&
          other.stabilizerStrength == stabilizerStrength &&
          // BB-3 audit fix: brushBlendMode was MISSING from ==/hashCode
          // since BB-1 — two states differing only in blend compared
          // equal, so listeners could skip rebuilding on a blend change.
          other.brushBlendMode == brushBlendMode;

  @override
  int get hashCode =>
      Object.hash(shape, tool, stabilizerStrength, brushBlendMode);
}
