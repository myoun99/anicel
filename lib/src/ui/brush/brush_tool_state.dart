import '../../models/brush_blend_mode.dart';
import '../../models/brush_pressure_curve.dart';
import '../../models/brush_settings.dart';
import '../../models/brush_shape.dart';
import '../../models/brush_tip_mask.dart';
import '../../models/brush_tip_rotation_mode.dart';
import '../../models/brush_tip_shape.dart';
import '../../models/canvas_shape_kind.dart';
import '../canvas/brush_edit_canvas_input_settings.dart';

/// The strip's standing hand settings — the group whose members a tool
/// either honours or has no use for (TP2). See [BrushToolState.supports].
enum ToolParameter { blend, size, opacity, pressure }

/// Which canvas tool the pointer drives — the VERB only.
///
/// The eraser reuses every brush option (size, hardness, tip) but its dabs
/// remove alpha instead of painting color; the eyedropper samples the
/// composite (P5), the fill commits one region-mask dab (P6), SELECT (P9)
/// drags out a region, and the MOVE tool (R11-⑧: selection ≠ move) drags
/// the selected content — none of them start strokes.
///
/// The SHAPE a drag-out verb traces is NOT encoded here: it is
/// [CanvasShapeKind], carried beside the tool (see
/// [BrushToolState.selectShape] / [BrushToolState.cutShape]). Select and
/// cut used to spell their rectangle and lasso variants out as tool values
/// — a cross product that doubles every time either axis grows.
enum CanvasTool {
  brush,
  eraser,
  eyedropper,
  fill,

  /// Drags out an outline and fills it with the current colour, whatever
  /// is inside it. Which outline it drags is [BrushToolState.fillShape].
  ///
  /// Separate from [fill], which floods from a tap: they are two verbs, and
  /// the tool library lists them side by side as the bucket and the
  /// shapes. Photoshop and Clip Studio split them the same way — filling
  /// an outline you drew is never the paint bucket in either.
  fillShape,

  /// Drags out a region and folds it into the selection. Which outline it
  /// drags is [BrushToolState.selectShape].
  select,
  move,

  /// Edits the cut's drawing guides (symmetry, perspective). It marks
  /// nothing itself — the guides it edits steer the OTHER tools, and they
  /// keep doing so while this one is not selected.
  guide,

  /// Drags out a region and COPIES the pixels under it into the held
  /// piece; the source is never removed (유저 확정: "잘라내기는 원본 남기는
  /// 복사"). Which outline it drags is [BrushToolState.cutShape].
  cut,

  /// The CUT tool's stamp variant: click to drop the held piece, drag to
  /// draw with it.
  ///
  /// Grab and stamp stay two tools — unlike rectangle/lasso, which are one
  /// tool wearing two shapes. That split is what makes the gesture question
  /// disappear: within the grab tool a drag means exactly one thing and
  /// within the stamp tool it means exactly one other, so no modifier is
  /// needed and both work on a tablet with no keyboard. TVPaint solves the
  /// same problem with two separate tools (Cutting tool / Custom Brush).
  cutStamp,
}

/// Whether [tool] lifts a piece into the cut slot.
bool canvasToolCuts(CanvasTool tool) => tool == CanvasTool.cut;

/// Whether [tool] stamps the held piece onto the cel.
bool canvasToolStamps(CanvasTool tool) => tool == CanvasTool.cutStamp;

/// Whether [tool] is one of the cut tool's variants — what the rail button
/// lights up for, and what the tool library lists tiles for.
bool canvasToolUsesCutPiece(CanvasTool tool) =>
    canvasToolCuts(tool) || canvasToolStamps(tool);

/// Whether [tool] paints strokes through the interactive canvas (the
/// non-painting tools mount a tool overlay instead).
bool canvasToolPaints(CanvasTool tool) =>
    tool == CanvasTool.brush || tool == CanvasTool.eraser;

/// Whether [tool] puts marks on the CEL — the strokes and the fill.
///
/// The question "would this press actually draw?" used to be spelled out at
/// its one call site as `!canvasToolPaints(tool) && tool != CanvasTool.fill`,
/// which quietly meant "and every tool added later draws too". It does not:
/// the guide tool edits the guides, the eyedropper reads a colour, and the
/// selection tools mark nothing.
bool canvasToolMarksCel(CanvasTool tool) =>
    canvasToolPaints(tool) ||
    canvasToolFills(tool) ||
    // The stamp drops pixels on the cel, so a press with it armed has to
    // count as drawing — the empty-cel guard this predicate feeds must not
    // let a stamp land on nothing.
    canvasToolStamps(tool);

/// Whether [tool] mounts the selection interaction layer (the P9
/// marquee/lasso tools and the move tool that drags their region).
///
/// The CUT tool mounts it too — it needs the very same marquee/lasso drag,
/// and rebuilding that geometry beside it would be a second copy of the
/// trickiest input code in the app. What differs is only what a finished
/// drag DOES: select commits a region, cut fills the slot and leaves the
/// region alone (유저 확정: "잘라내기는 잘라내기만이야. 그러니 선택으로 남지
/// 않아"). The stamp variant does not mount it — it paints.
bool canvasToolSelects(CanvasTool tool) =>
    tool == CanvasTool.select ||
    tool == CanvasTool.move ||
    tool == CanvasTool.fillShape ||
    canvasToolCuts(tool);

/// Whether [tool] drags an outline out of the canvas — the verbs that wear
/// a [CanvasShapeKind]. MOVE does not: it drags a region that already
/// exists rather than tracing a new one.
bool canvasToolDragsShape(CanvasTool tool) =>
    tool == CanvasTool.select ||
    tool == CanvasTool.fillShape ||
    canvasToolCuts(tool);

/// Whether [tool] is one of the FILL tool's tiles — what the rail's single
/// Fill button lights up for. The bucket floods from a tap and the shape
/// fill drags an outline; both are the fill.
bool canvasToolFills(CanvasTool tool) =>
    tool == CanvasTool.fill || tool == CanvasTool.fillShape;

/// Whether [tool] is the TRANSFORM tool — the one whose library lists
/// 일반/퍼스/메쉬 and whose settings panel shows the numeric channels.
///
/// Spelled as a predicate rather than `== CanvasTool.move` at each of its
/// call sites for the reason the cut tool learned: the question "is the
/// transform tool armed?" is asked by the rail, the library, the settings
/// panel, the edit gate and the canvas layer, and every one of those had
/// to be found and changed by hand the last time the answer grew.
///
/// The three transform MODES are deliberately not three tool values. A
/// tool change confirms the open session on the way out
/// (`canvas_selection_layer`'s didUpdateWidget), so a mode picked from the
/// library would land the pixels and reopen — which is the opposite of the
/// lossless promotion the modes are built on. The mode rides
/// [TransformToolOptions] instead.
bool canvasToolTransforms(CanvasTool tool) => tool == CanvasTool.move;

/// Which RAIL BUTTON [tool] lives under, named by that group's default tile.
///
/// The rail has fewer buttons than there are tools: the bucket and the shape
/// fill share one, the grab and the stamp share another. Each of those
/// buttons used to spell its own membership test AND its own re-entry rule
/// by hand (`canvasToolFills(tool) ? tool : CanvasTool.fill`), which is two
/// hand-written lists to keep in step and the reason a new tile could be
/// added without either button hearing about it.
///
/// 🚨Spelled as a SWITCH over every value rather than a couple of `if`s, so
/// a tool added tomorrow cannot slip in without saying which button it
/// answers to — the same discipline `supports` uses for the strip (TP2).
CanvasTool canvasToolRailGroup(CanvasTool tool) => switch (tool) {
  CanvasTool.brush => CanvasTool.brush,
  CanvasTool.eraser => CanvasTool.eraser,
  CanvasTool.eyedropper => CanvasTool.eyedropper,
  CanvasTool.fill || CanvasTool.fillShape => CanvasTool.fill,
  CanvasTool.guide => CanvasTool.guide,
  CanvasTool.select => CanvasTool.select,
  // MOVE is its own button even though it drags what SELECT traced: its
  // three modes are settings, not tiles (see [canvasToolTransforms]).
  CanvasTool.move => CanvasTool.move,
  CanvasTool.cut || CanvasTool.cutStamp => CanvasTool.cut,
};

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
    CanvasTool tool = CanvasTool.brush,
    CanvasShapeKind selectShape = CanvasShapeKind.rect,
    CanvasShapeKind cutShape = CanvasShapeKind.rect,
    CanvasShapeKind fillShape = CanvasShapeKind.rect,
    double stabilizerStrength = 0.0,
    BrushBlendMode brushBlendMode = BrushBlendMode.color,
    BrushBlendMode fillBlendMode = BrushBlendMode.color,
    BrushBlendMode? fillBlendLock,
    BrushBlendMode cutStampBlendMode = BrushBlendMode.color,
    double fillOpacity = 1.0,
    double cutStampOpacity = 1.0,
    BrushBlendMode? cutStampBlendLock,
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
      tool: tool,
      selectShape: selectShape,
      cutShape: cutShape,
      fillShape: fillShape,
      stabilizerStrength: stabilizerStrength,
      brushBlendMode: brushBlendMode,
      fillBlendMode: fillBlendMode,
      fillBlendLock: fillBlendLock,
      cutStampBlendMode: cutStampBlendMode,
      cutStampBlendLock: cutStampBlendLock,
      fillOpacity: fillOpacity,
      cutStampOpacity: cutStampOpacity,
    );
  }

  const BrushToolState._raw({
    required this.shape,
    this.tool = CanvasTool.brush,
    this.selectShape = CanvasShapeKind.rect,
    this.cutShape = CanvasShapeKind.rect,
    this.fillShape = CanvasShapeKind.rect,
    this.stabilizerStrength = 0.0,
    this.brushBlendMode = BrushBlendMode.color,
    this.fillBlendMode = BrushBlendMode.color,
    this.fillBlendLock,
    this.cutStampBlendMode = BrushBlendMode.color,
    this.cutStampBlendLock,
    this.fillOpacity = 1.0,
    this.cutStampOpacity = 1.0,
  });

  /// Builds tool state from a loose [BrushShape] and the three hand settings,
  /// clamping every shared parameter into the panel's ranges (see
  /// [_clampShape]). This is the wholesale hop the preset-load path takes —
  /// [fromBrushSettings] routes through it — so no shared parameter can be
  /// dropped when a preset is applied.
  factory BrushToolState.fromShape(
    BrushShape shape, {
    CanvasTool tool = CanvasTool.brush,
    CanvasShapeKind selectShape = CanvasShapeKind.rect,
    CanvasShapeKind cutShape = CanvasShapeKind.rect,
    CanvasShapeKind fillShape = CanvasShapeKind.rect,
    double stabilizerStrength = 0.0,
    BrushBlendMode brushBlendMode = BrushBlendMode.color,
    BrushBlendMode fillBlendMode = BrushBlendMode.color,
    BrushBlendMode? fillBlendLock,
    BrushBlendMode cutStampBlendMode = BrushBlendMode.color,
    BrushBlendMode? cutStampBlendLock,
    double fillOpacity = 1.0,
    double cutStampOpacity = 1.0,
  }) {
    return BrushToolState._raw(
      shape: _clampShape(shape),
      tool: tool,
      selectShape: selectShape,
      cutShape: cutShape,
      fillShape: fillShape,
      stabilizerStrength: clampStabilizerStrength(stabilizerStrength),
      brushBlendMode: brushBlendMode,
      fillBlendMode: fillBlendMode,
      fillBlendLock: fillBlendLock,
      cutStampBlendMode: cutStampBlendMode,
      cutStampBlendLock: cutStampBlendLock,
      fillOpacity: clampOpacity(fillOpacity),
      cutStampOpacity: clampOpacity(cutStampOpacity),
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
    bool? mixesGroundColor,
    double? paintAmount,
    double? paintDensity,
    double? colorStretch,
    CanvasTool? tool,
    CanvasShapeKind? selectShape,
    CanvasShapeKind? cutShape,
    CanvasShapeKind? fillShape,
    double? stabilizerStrength,
    BrushBlendMode? brushBlendMode,
    BrushBlendMode? fillBlendMode,
    BrushBlendMode? fillBlendLock,
    BrushBlendMode? cutStampBlendMode,
    BrushBlendMode? cutStampBlendLock,
    double? fillOpacity,
    double? cutStampOpacity,
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
        roundnessJitter: roundnessJitter ?? 0.0,
        spacingJitter: spacingJitter ?? 0.0,
        scatterRadiusRatio: scatterRadiusRatio ?? 0.0,
        scatterCount: scatterCount ?? 1,
        scatterBothAxes: scatterBothAxes ?? true,
        dualMask: dualMask,
        dualMaskScale: dualMaskScale ?? 1.0,
        textureMask: textureMask,
        textureScale: textureScale ?? 1.0,
        textureDensity: textureDensity ?? 1.0,
        mixesGroundColor: mixesGroundColor ?? false,
        paintAmount: paintAmount ?? 1.0,
        paintDensity: paintDensity ?? 1.0,
        colorStretch: colorStretch ?? 0.0,
      ),
      tool: tool ?? CanvasTool.brush,
      selectShape: selectShape ?? CanvasShapeKind.rect,
      cutShape: cutShape ?? CanvasShapeKind.rect,
      fillShape: fillShape ?? CanvasShapeKind.rect,
      stabilizerStrength: stabilizerStrength ?? 0.0,
      brushBlendMode: brushBlendMode ?? BrushBlendMode.color,
      fillBlendMode: fillBlendMode ?? BrushBlendMode.color,
      fillBlendLock: fillBlendLock,
      cutStampBlendMode: cutStampBlendMode ?? BrushBlendMode.color,
      cutStampBlendLock: cutStampBlendLock,
      fillOpacity: fillOpacity ?? 1.0,
      cutStampOpacity: cutStampOpacity ?? 1.0,
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
    roundnessJitter: clampZeroToOne(s.roundnessJitter),
    spacingJitter: clampZeroToOne(s.spacingJitter),
    paintAmount: clampZeroToOne(s.paintAmount),
    paintDensity: clampZeroToOne(s.paintDensity),
    colorStretch: clampZeroToOne(s.colorStretch),
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
  double get roundnessJitter => shape.roundnessJitter;
  double get spacingJitter => shape.spacingJitter;

  /// The blend this brush pins, or null when it leaves the hand setting be.
  BrushBlendMode? get lockedBlendMode => shape.lockedBlendMode;

  /// What actually composites: the lock when there is one, else the hand.
  BrushBlendMode get effectiveBlendMode =>
      shape.lockedBlendMode ?? brushBlendMode;
  double get scatterRadiusRatio => shape.scatterRadiusRatio;
  int get scatterCount => shape.scatterCount;
  bool get scatterBothAxes => shape.scatterBothAxes;
  BrushTipMask? get dualMask => shape.dualMask;
  double get dualMaskScale => shape.dualMaskScale;
  BrushTipMask? get textureMask => shape.textureMask;
  double get textureScale => shape.textureScale;
  double get textureDensity => shape.textureDensity;
  bool get mixesGroundColor => shape.mixesGroundColor;
  double get paintAmount => shape.paintAmount;
  double get paintDensity => shape.paintDensity;
  double get colorStretch => shape.colorStretch;

  /// The active canvas tool. Not part of presets ([toBrushSettings] omits
  /// it); applying a preset returns to the brush, CSP-style.
  final CanvasTool tool;

  /// The outline SELECT drags out, remembered separately from the one CUT
  /// drags (유저 확정: 도형은 동사별로 기억). "The shape vocabulary is
  /// shared" is not "the shape value is shared" — wanting the lasso for
  /// selecting and the box for cutting is an ordinary combination, and one
  /// field would make picking either one silently retune the other.
  ///
  /// This is also what the rail's single Select button re-activates: with
  /// the shape held here, "restore the variant I last used" is just
  /// `tool: select` — no last-variant bookkeeping beside it.
  final CanvasShapeKind selectShape;

  /// The outline CUT drags out. See [selectShape].
  final CanvasShapeKind cutShape;

  /// The outline SHAPE FILL drags out. See [selectShape].
  final CanvasShapeKind fillShape;

  /// The outline the ACTIVE tool drags, or null for tools that do not drag
  /// one out (every painting tool, plus MOVE — it drags a region that
  /// already exists rather than tracing a new one).
  CanvasShapeKind? get activeShapeKind => switch (tool) {
    CanvasTool.select => selectShape,
    CanvasTool.cut => cutShape,
    CanvasTool.fillShape => fillShape,
    _ => null,
  };

  /// This state with [forTool]'s remembered outline set to [kind], and
  /// [forTool] made active.
  ///
  /// One write, not two: the shape tiles are also how a verb is entered
  /// (tapping "Rectangle Cut" while the stamp is armed means both), and
  /// splitting that into a tool change and a shape change would leave a
  /// state in between where the shape is being written for the wrong verb.
  /// Verbs that trace nothing are returned unchanged rather than silently
  /// storing an outline they will never use.
  BrushToolState withShapeKind(
    CanvasShapeKind kind, {
    required CanvasTool forTool,
  }) => switch (forTool) {
    CanvasTool.select => copyWith(tool: forTool, selectShape: kind),
    CanvasTool.cut => copyWith(tool: forTool, cutShape: kind),
    CanvasTool.fillShape => copyWith(tool: forTool, fillShape: kind),
    _ => this,
  };

  /// Pull-string stabilization strength (P7), 0..100 screen px of rope.
  /// A HAND-FEEL setting, deliberately outside brush presets — preset
  /// application carries it over unchanged.
  final double stabilizerStrength;

  /// The BRUSH's own composite mode (BB-1, R26 #9). Like the stabilizer
  /// — and like [size] since R26 #10 — a HAND setting outside brush
  /// presets: picking another brush never flips it.
  final BrushBlendMode brushBlendMode;

  /// The FILL's composite mode, kept apart from the brush's (유저 확정:
  /// 잠금도 블렌드모드 선택도 툴에 산다).
  ///
  /// One shared field would mean painting shadows on multiply and then
  /// reaching for the bucket fills on multiply too — a setting from
  /// another tool arriving unannounced, which is the leak the cut tool had
  /// to block on opacity. Two fields make it structural instead of
  /// remembered.
  final BrushBlendMode fillBlendMode;

  /// The fill's blend PIN, or null when it is free.
  ///
  /// Same meaning as the brush's pin, different home: a brush pins through
  /// its preset ([BrushShape.lockedBlendMode]) because the pin belongs to
  /// the brush, and the fill has no preset to belong to, so it pins here.
  /// What the padlock says is one thing either way — this tool's blend
  /// does not change until you unlock it.
  final BrushBlendMode? fillBlendLock;

  /// The STAMP's composite mode (TS8), its own field for the same reason
  /// the fill got one: 유저 확정 — 값은 툴별 칸. Painting shadows on
  /// multiply and then dropping a stamp must not drop it on multiply.
  final BrushBlendMode cutStampBlendMode;

  /// The stamp's blend PIN, or null when it is free. Like the fill, the
  /// stamp has no preset for a pin to belong to, so it pins here — without
  /// this field the padlock would read and write the BRUSH's pin, which is
  /// the very leak the per-tool fields exist to stop.
  final BrushBlendMode? cutStampBlendLock;

  /// The FILL's opacity, and the STAMP's (TP1).
  ///
  /// 유저: *"툴마다 기억하게해서 필 툴도 불투명도 설정하면 그거대로 채워지게
  /// … 거기서 브러시툴로 바꾼다고해서 필 툴의 불투명도 남는다거나 없게."*
  ///
  /// Own fields, exactly like the blends beside them, and for the reason the
  /// blends were split: the brush's opacity is the BRUSH's. Shading at 40%
  /// and then reaching for the bucket must not fill at 40%, and the reverse
  /// must not happen either.
  ///
  /// 🚨The stamp's field is also what RETIRES the hard-coded 100% in
  /// `buildCutStampDab` (TP3). That constant was never about wanting 100% —
  /// it was the only way to stop the brush's opacity leaking in when there
  /// was one field for everybody, and 유저's own reasoning at the time said
  /// so ("브러시마다 고르면 다르지 않나"). With a field of its own the leak
  /// cannot happen, so the stamp can have the setting it was denied.
  ///
  /// ⚠️Both fill tiles share ONE value — 유저 확정, the same law the fill's
  /// blend follows: the bucket and the shape fill are one tool wearing two
  /// ways of choosing an area.
  final double fillOpacity;
  final double cutStampOpacity;

  /// The opacity the ACTIVE tool paints with.
  ///
  /// The brush and the eraser keep theirs in [shape] (it is a brush
  /// parameter, and presets carry it); the tools that are not brushes keep
  /// theirs beside it. One reader either way, so the strip's bar never has
  /// to name a tool.
  double get activeOpacity => switch (tool) {
    CanvasTool.fill || CanvasTool.fillShape => fillOpacity,
    CanvasTool.cutStamp => cutStampOpacity,
    _ => opacity,
  };

  /// This state with the ACTIVE tool's opacity set to [value].
  BrushToolState withActiveOpacity(double value) => switch (tool) {
    CanvasTool.fill || CanvasTool.fillShape => copyWith(fillOpacity: value),
    CanvasTool.cutStamp => copyWith(cutStampOpacity: value),
    _ => copyWith(opacity: value),
  };

  /// The blend the ACTIVE tool actually composites with — a pin when there
  /// is one, otherwise the mode that tool was last set to.
  ///
  /// The eraser is not a blend CHOICE: the tool IS the erase blend, and it
  /// wins over both (R26 #9).
  BrushBlendMode get activeBlendMode => switch (tool) {
    CanvasTool.eraser => BrushBlendMode.erase,
    // Both fill tiles share one blend: they are one tool wearing two ways
    // of choosing an area (유저 확정: 채우기 툴 하나로 공유).
    CanvasTool.fill || CanvasTool.fillShape => fillBlendLock ?? fillBlendMode,
    CanvasTool.cutStamp => cutStampBlendLock ?? cutStampBlendMode,
    _ => effectiveBlendMode,
  };

  /// The pin on the ACTIVE tool's blend, or null when it is free (or when
  /// the tool composites nothing at all).
  BrushBlendMode? get activeBlendLock => switch (tool) {
    CanvasTool.fill || CanvasTool.fillShape => fillBlendLock,
    CanvasTool.cutStamp => cutStampBlendLock,
    _ => lockedBlendMode,
  };

  /// Whether the active tool composites at all — whether a blend control
  /// is telling the truth while it is armed.
  ///
  /// This is why the strip's blend button used to lie: it was shown for
  /// every tool, and the fill (and the selection tools, and move) ignored
  /// it outright.
  ///
  /// TS8: the STAMP composites too — 유저 확정, 「블렌드모드가 존재한다면
  /// 다 공통」. It puts pixels on the cel through the same funnel, and the
  /// 위/아래 붙여넣기 pair was already spelling `color`/`behind` by hand.
  bool get toolHasBlendMode => supports(ToolParameter.blend);

  /// Whether [parameter] means anything for the active tool (TP2).
  ///
  /// 🚨ONE table, because the strip's controls are one group and the user's
  /// complaint was about the group: *"뭐가 적용되고 뭐가 적용안되는지 몰라할거
  /// 같으니까 … 적용안되는툴이나 모드면 비활성화시키도록"*. Before this, the
  /// blend asked its own question and size/opacity/pressure asked none at all
  /// — they were shown for the eyedropper and the guide tool, where nothing
  /// downstream reads them.
  ///
  /// A tool added later shows up here as a row of `false`s and has to be
  /// argued into each one, which is the point: a control that lies is worse
  /// than a control that is missing.
  ///
  /// 유저 확정 표 (2026-08-15):
  /// - brush / eraser: everything (the eraser's blend is FIXED to erase, not
  ///   absent — the strip says that with a padlock, not by dimming).
  /// - fills: blend + opacity. Not size — the area comes from the flood or
  ///   from the drawn outline, never from a tip width. Not pressure — one
  ///   tap is not a stroke.
  /// - stamp: blend + opacity. Its SIZE is the tool settings' `%`, kept off
  ///   the strip's slider on purpose (08-12: 크기 슬라이더와 공유 금지).
  /// - grab / select / move / guide / eyedropper: none. They put no pixels
  ///   down at all.
  bool supports(ToolParameter parameter) => switch (tool) {
    CanvasTool.brush || CanvasTool.eraser => true,
    CanvasTool.fill ||
    CanvasTool.fillShape ||
    CanvasTool.cutStamp => parameter == ToolParameter.blend ||
        parameter == ToolParameter.opacity,
    _ => false,
  };

  /// Builds tool state from a preset's model-layer [BrushSettings], clamping
  /// every value into the panel's ranges.
  factory BrushToolState.fromBrushSettings(BrushSettings settings) =>
      BrushToolState.fromShape(settings.shape);

  /// This state after a PRESET's [settings] are applied, on [tool].
  ///
  /// A preset carries a whole brush, but four things are the user's HAND
  /// and never come from it — they are how this person holds the pen right
  /// now, not what the brush is:
  ///
  /// * the stabilizer (P7),
  /// * the SIZE and the brush BLEND (R26 #10 — "브러시 다른거 선택한다고
  ///   사이즈/블렌딩모드가 바뀌지 않음"),
  /// * the COLOUR (R9 #2). A preset stores a colour so it can be saved and
  ///   imported faithfully, and most of the roster's presets carry the
  ///   default black — so before this rule, every brush swap silently
  ///   repainted the palette black.
  ///
  /// The remembered SHAPE KINDS ride along for the same reason: a preset is
  /// a brush, and which outline the select and cut tools drag is not part
  /// of one. Rebuilding from settings alone would quietly snap both back to
  /// the rectangle every time a brush was picked.
  /// This state after a PRESET's [settings] are applied, on [tool].
  ///
  /// This used to REBUILD the state from the preset's shape and then hand-list
  /// eleven fields to carry back across, so survival depended on someone
  /// remembering to add the twelfth.
  ///
  /// 🚨⛔It was ALSO named as T26's culprit (「브러시툴로만 바꾸면 모드
  /// 초기화되」) and it is not. Measured 2026-08-14: restoring the old body as
  /// a mutation kills no test — the eleven entries covered every field this
  /// class holds, so nothing was being dropped. The reported symptom is
  /// elsewhere, and the likeliest place is the one that round already
  /// flagged: the selection's COMBINE mode lives on `CanvasSelectionCommands`,
  /// so this class never had it to lose. ⛔Do not read the shape below as
  /// having fixed that.
  ///
  /// ⇒ A preset owns **the shape**, and everything outside the shape survives
  /// because it is never touched rather than because it was listed. The
  /// remembered shape kinds, the stabilizer and the per-tool blends are all
  /// out there, so a field added tomorrow is safe without anyone knowing this
  /// method exists.
  ///
  /// ⚠️Two exceptions stay, and they are named because they are DECISIONS,
  /// not omissions: **size and colour live inside the shape** and are the
  /// user's hand anyway.
  ///
  /// * size — R26 #10, 「브러시 다른거 선택한다고 사이즈/블렌딩모드가 바뀌지
  ///   않음」
  /// * colour — R9 #2. A preset stores one so it can round-trip through
  ///   export, and most of the roster carries the default black, so without
  ///   this every brush swap silently repainted the palette black.
  ///
  /// The list went from eleven entries to two, and the two that remain are
  /// the only ones a reader has to be able to justify. (The stabilizer and
  /// the brush blend were on the old list for the same reason and no longer
  /// need to be — they are outside the shape, so they are already safe.)
  BrushToolState withPresetSettings(
    BrushSettings settings, {
    required CanvasTool tool,
  }) => copyWith(
    shape: settings.shape,
    tool: tool,
    size: size,
    color: color,
  );

  /// Snapshot of this tool state as the model-layer [BrushSettings] — the
  /// payload brush presets store.
  BrushSettings toBrushSettings() => BrushSettings.fromShape(shape);

  BrushEditCanvasInputSettings toInputSettings() {
    return BrushEditCanvasInputSettings.fromShape(
      shape,
      // The eraser tool IS the erase blend (locked); a brush whose blend
      // is erase rides the SAME dab flag and kernels.
      erase: activeBlendMode == BrushBlendMode.erase,
      // A brush that pins a blend wins over the hand setting while it is
      // selected; the hand setting itself is untouched, so leaving the brush
      // restores it. Erase still wins over both: it is the tool, not a blend
      // choice.
      //
      // Mixing does NOT force plain srcOver. Clip Studio runs 下地混色 and a
      // 乗算 composite together on the same brush — they are different
      // stages, one loading the brush and one laying the stroke down — so
      // suppressing the blend was a deviation, not a safeguard.
      blendMode: activeBlendMode,
      stabilizerStrength: stabilizerStrength,
    );
  }

  BrushToolState copyWith({
    /// Swaps the whole BRUSH out, leaving every setting that is not part of
    /// one alone (T26).
    ///
    /// The state flattens a shape — size, opacity, spacing, the curves, the
    /// masks — so "give me this brush and keep the rest" had no way to be
    /// said before, and callers said it by rebuilding and listing what to
    /// carry back. This is that sentence.
    ///
    /// ⚠️The individual arguments below WIN over it: a caller may lay a
    /// shape down and override one value on top, which is the order
    /// `withPresetSettings` and the sliders both need.
    BrushShape? shape,
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
    bool? mixesGroundColor,
    double? paintAmount,
    double? paintDensity,
    double? colorStretch,
    bool clearBlendLock = false,
    BrushBlendMode? lockedBlendMode,
    CanvasTool? tool,
    CanvasShapeKind? selectShape,
    CanvasShapeKind? cutShape,
    CanvasShapeKind? fillShape,
    double? stabilizerStrength,
    BrushBlendMode? brushBlendMode,
    BrushBlendMode? fillBlendMode,
    bool clearFillBlendLock = false,
    BrushBlendMode? fillBlendLock,
    BrushBlendMode? cutStampBlendMode,
    bool clearCutStampBlendLock = false,
    BrushBlendMode? cutStampBlendLock,
    double? fillOpacity,
    double? cutStampOpacity,
  }) {
    // The base is the caller's shape when it gave one; the named arguments
    // then land on TOP of it, so "this brush, but at my size" is one call.
    final baseShape = shape ?? this.shape;
    return BrushToolState._raw(
      shape: _clampShape(
        baseShape.copyWith(
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
          mixesGroundColor: mixesGroundColor,
          paintAmount: paintAmount,
          paintDensity: paintDensity,
          colorStretch: colorStretch,
          clearBlendLock: clearBlendLock,
          lockedBlendMode: lockedBlendMode,
        ),
      ),
      tool: tool ?? this.tool,
      selectShape: selectShape ?? this.selectShape,
      cutShape: cutShape ?? this.cutShape,
      fillShape: fillShape ?? this.fillShape,
      stabilizerStrength: clampStabilizerStrength(
        stabilizerStrength ?? this.stabilizerStrength,
      ),
      brushBlendMode: brushBlendMode ?? this.brushBlendMode,
      fillBlendMode: fillBlendMode ?? this.fillBlendMode,
      fillBlendLock: clearFillBlendLock
          ? null
          : (fillBlendLock ?? this.fillBlendLock),
      cutStampBlendMode: cutStampBlendMode ?? this.cutStampBlendMode,
      cutStampBlendLock: clearCutStampBlendLock
          ? null
          : (cutStampBlendLock ?? this.cutStampBlendLock),
      fillOpacity: clampOpacity(fillOpacity ?? this.fillOpacity),
      cutStampOpacity: clampOpacity(cutStampOpacity ?? this.cutStampOpacity),
    );
  }

  /// This state with the ACTIVE tool's blend set to [mode].
  ///
  /// One control writes to whichever field the armed tool owns, so the
  /// strip's blend button never has to name a tool — and picking a mode
  /// for one tool can never reach into another's.
  BrushToolState withActiveBlendMode(BrushBlendMode mode) => switch (tool) {
    CanvasTool.fill || CanvasTool.fillShape => copyWith(fillBlendMode: mode),
    CanvasTool.cutStamp => copyWith(cutStampBlendMode: mode),
    _ => copyWith(brushBlendMode: mode),
  };

  /// This state with the ACTIVE tool's blend pinned to [mode], or freed
  /// when [mode] is null.
  ///
  /// The brush pins through its PRESET, which is where a brush's pin has
  /// always belonged (유저: 프리셋 저장된 핀은 그대로 사용하고 싶음); the
  /// fill has no preset, so it pins on the tool state. Same padlock, same
  /// promise, different drawer.
  BrushToolState withActiveBlendLock(BrushBlendMode? mode) => switch (tool) {
    CanvasTool.fill || CanvasTool.fillShape => mode == null
        ? copyWith(clearFillBlendLock: true)
        : copyWith(fillBlendLock: mode),
    CanvasTool.cutStamp => mode == null
        ? copyWith(clearCutStampBlendLock: true)
        : copyWith(cutStampBlendLock: mode),
    _ => mode == null
        ? copyWith(clearBlendLock: true)
        : copyWith(lockedBlendMode: mode),
  };

  /// The pressure curve driving [target], if any.
  BrushPressureCurve? pressureCurveFor(BrushPressureTarget target) =>
      shape.pressureCurveFor(target);

  /// Replaces (or CLEARS, with null) one of the three sampled masks.
  /// [copyWith] preserves them so a slider tweak keeps a textured tip, which
  /// leaves no way to take one off; this is that way.
  ///
  /// ⚠️Every non-shape field is listed: this constructor DEFAULTS the ones
  /// it is not given, so an omission here is not a no-op — it is a silent
  /// reset. Picking a tip used to snap the three remembered outlines back
  /// to the rectangle and the fill's blend back to Color, which is the same
  /// trap [withPresetSettings] carries a comment about.
  BrushToolState withMask(BrushMaskSlot slot, BrushTipMask? mask) {
    return _withShape(shape.withMask(slot, mask));
  }

  /// [shape] replaced, every hand setting carried through untouched.
  BrushToolState _withShape(BrushShape next) => BrushToolState._raw(
    shape: _clampShape(next),
    tool: tool,
    selectShape: selectShape,
    cutShape: cutShape,
    fillShape: fillShape,
    stabilizerStrength: stabilizerStrength,
    brushBlendMode: brushBlendMode,
    fillBlendMode: fillBlendMode,
    fillBlendLock: fillBlendLock,
    cutStampBlendMode: cutStampBlendMode,
    cutStampBlendLock: cutStampBlendLock,
    fillOpacity: fillOpacity,
    cutStampOpacity: cutStampOpacity,
  );

  /// Replaces (or CLEARS, with null) one setting's pressure curve —
  /// [copyWith] deliberately preserves curves, so disabling pressure on a
  /// setting comes through here.
  BrushToolState withPressureCurve(
    BrushPressureTarget target,
    BrushPressureCurve? curve,
  ) {
    return _withShape(shape.withPressureCurve(target, curve));
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
          // The shape kinds ride here for the same reason blend does
          // below: a state differing only in the remembered outline must
          // not compare equal, or the tool library's tiles keep painting
          // the old one as selected.
          other.selectShape == selectShape &&
          other.cutShape == cutShape &&
          other.fillShape == fillShape &&
          other.stabilizerStrength == stabilizerStrength &&
          // BB-3 audit fix: brushBlendMode was MISSING from ==/hashCode
          // since BB-1 — two states differing only in blend compared
          // equal, so listeners could skip rebuilding on a blend change.
          other.brushBlendMode == brushBlendMode &&
          other.fillBlendMode == fillBlendMode &&
          other.fillBlendLock == fillBlendLock &&
          other.cutStampBlendMode == cutStampBlendMode &&
          other.cutStampBlendLock == cutStampBlendLock &&
          other.fillOpacity == fillOpacity &&
          other.cutStampOpacity == cutStampOpacity;

  @override
  int get hashCode => Object.hash(
    shape,
    tool,
    selectShape,
    cutShape,
    fillShape,
    stabilizerStrength,
    brushBlendMode,
    fillBlendMode,
    fillBlendLock,
    cutStampBlendMode,
    cutStampBlendLock,
    fillOpacity,
    cutStampOpacity,
  );
}
