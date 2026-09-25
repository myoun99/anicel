import '../models/brush_anti_alias.dart';
import '../models/brush_blend_mode.dart';
import '../models/brush_group.dart';
import '../models/brush_group_icon.dart';
import '../models/brush_group_id.dart';
import '../models/brush_input_source.dart';
import '../models/brush_preset.dart';
import '../models/brush_preset_id.dart';
import '../models/brush_pressure_curve.dart';
import '../models/brush_settings.dart';
import '../models/brush_shape.dart';
import '../models/brush_tip_rotation_mode.dart';
import 'brush_tip_mask_defaults.dart';

const BrushGroupId _pencilGroup = BrushGroupId('builtin-pencil-group');
const BrushGroupId _penGroup = BrushGroupId('builtin-ink-group');
const BrushGroupId _dryMediaGroup = BrushGroupId('builtin-dry-media-group');
const BrushGroupId _watercolorGroup = BrushGroupId('builtin-watercolor-group');
const BrushGroupId _oilGroup = BrushGroupId('builtin-paint-group');
const BrushGroupId _airbrushGroup = BrushGroupId('builtin-airbrush-group');
const BrushGroupId _blendGroup = BrushGroupId('builtin-blend-group');
const BrushGroupId _textureGroup = BrushGroupId('builtin-texture-group');
const BrushGroupId _decorationGroup = BrushGroupId('builtin-decoration-group');

/// Built-in library groups seeded alongside [defaultBrushPresets].
///
/// 🚨**THE GROUPS ARE MEDIA; THE ORDER IS THE PIPELINE.** Media is the axis
/// the user named — 「페인트는 그룹 더 나눠서 수채화나 오일이나 이런거
/// 나누게하고싶어」 (2026-09-09) — and it is the one Clip Studio, Photoshop,
/// Procreate and Krita all reach independently. The ORDER then reads
/// left-to-right the way a cel is made (rough → clean-up → shading → finish),
/// which costs nothing because this list is already ordered.
///
/// ⛔A task-first top level is not available even if it were wanted:
/// [BrushGroup] is a FLAT list with no parent, so making the top level a
/// stage would bury watercolour and oil where nobody can see them.
///
/// There is deliberately NO eraser group. 🚨READ ALL THREE PARAGRAPHS BELOW
/// BEFORE ADDING ONE — the first reason expired and the second replaced it.
///
/// ⛔The original reason (2026-07-25) was that "size and blend mode are hand
/// settings a preset never carries", so an eraser brush could only ever be a
/// tip SHAPE, which the roster already has. **That premise is false now.**
/// `BrushShape.blendMode` is a preset field, `BrushShape.size` always was,
/// `withPreset` applies both, and the hand/preset split is GONE as
/// of 2026-09-08: 「손설정이든 정한거 싹 다 내보낼때 나르도록 … 지우개는
/// 그냥 지우개 브러시 내보낼때 블렌드를 내보내면 되는거고」.
///
/// ✅**The standing reason is the user's, 2026-09-09**: 「지우개그룹은 만들
/// 이유를 못느끼겠고. **왜냐하면 툴이 있으니까.** 지우개툴에서 브러시고르면
/// 어차피 블렌드모드 삭제밖에 없으니까」 — the eraser is a TOOL, and picking a
/// brush inside it only forces the blend to erase. A group would be a second
/// copy of what the tool already does. ⇒ No preset here sets
/// `BrushBlendMode.erase`; one that did would be the banned group in disguise.
/// **Blend gets a group for the opposite reading of the same test: there is
/// no smudge TOOL for it to duplicate.**
///
/// ⛔And no PIXEL group, for the same shape of reason (유저 2026-09-09):
/// 「픽셀브러시도 그냥 G펜 우리가 만들어서 넣고 aa off면 픽셀대로 나오게
/// 클튜처럼 하면되는거고」 — a pixel brush is an anti-alias setting, not a
/// family. It ships as Anime Pen inside Pen, where Clip Studio files its
/// ドットペン too.
final List<BrushGroup> defaultBrushGroups = List.unmodifiable(<BrushGroup>[
  const BrushGroup(
    id: _pencilGroup,
    name: 'Pencil',
    icon: BrushGroupIcon.pencil,
  ),
  // ⚠️The ID still says `ink` and that is deliberate: renaming a group is a
  // NAME change, and the id is what presets reference. 유저 2026-09-09:
  // 「잉크가 안에 G펜 들어있는지 뭔지 모르겠는데 이름 펜이 맞지않을까」 —
  // right, and it matches the reference: Clip Studio's tool is ペン and holds
  // Gペン and 丸ペン, with 筆 kept separate. Every other group here is named
  // for a tool; Ink was the one named for a medium.
  const BrushGroup(id: _penGroup, name: 'Pen', icon: BrushGroupIcon.pen),
  const BrushGroup(
    id: _dryMediaGroup,
    name: 'Dry Media',
    icon: BrushGroupIcon.grain,
  ),
  const BrushGroup(
    id: _watercolorGroup,
    name: 'Watercolor',
    icon: BrushGroupIcon.watercolor,
  ),
  // Same id, new name: this group was 'Paint', and the split moved
  // watercolour, airbrush and the soft brush out of it. What is left is oil.
  const BrushGroup(id: _oilGroup, name: 'Oil', icon: BrushGroupIcon.paint),
  const BrushGroup(
    id: _airbrushGroup,
    name: 'Airbrush',
    icon: BrushGroupIcon.airbrush,
  ),
  const BrushGroup(
    id: _blendGroup,
    name: 'Blend',
    icon: BrushGroupIcon.palette,
  ),
  const BrushGroup(
    id: _textureGroup,
    name: 'Texture',
    icon: BrushGroupIcon.texture,
  ),
  // 🚨THE SCATTER GROUP (유저 `brush-roster-Q1` 답 2: the whole roster in one
  // round). It is last because it is the only group that does not paint a
  // MEDIUM — these are marks thrown at a finished drawing, and every one of
  // them needs the kind of mask nothing here had: an ANGULAR one.
  const BrushGroup(
    id: _decorationGroup,
    name: 'Decoration',
    icon: BrushGroupIcon.star,
  ),
]);

/// Built-in brush presets seeded when no user preset library exists yet.
///
/// A working starting set covering the media a drawing tool is expected
/// to ship with, not a curated artist pack. Users can delete or extend them;
/// the library file then persists their choice.
///
/// Every tip and texture here is generated procedurally
/// (`brush_tip_mask_defaults.dart`) — third-party brush files may not be
/// bundled, so the built-ins have to be the engine's own.
///
/// ⛔SIZE IS NOT A HAND SETTING ANY MORE. This used to read "applying a
/// preset deliberately keeps the current brush size (R26 #10)"; H25 asked
/// the opposite and was answered, and `BrushToolState.withPreset`
/// has applied the brush's own size ever since — a brush the hand has never
/// touched wears the size baked into its own file. The comment simply
/// outlived the code.
///
/// So the sizes below are REAL: they are what each brush opens at, as well
/// as what shapes the panel's previews and says what the brush is FOR.
///
/// 🔑**TWO PRESETS MAY NOT DIFFER ONLY BY SOMETHING THE PICKER CANNOT DRAW.**
/// `brush_stroke_preview.dart` normalizes SIZE to the row height, skips
/// scatter and every jitter on purpose, and bakes ALPHA only — the theme
/// tints it. So size, scatter, jitter, blend mode and the whole
/// colour-mixing block are INVISIBLE in this list. What separates two rows is
/// the tip mask, the dual and texture masks, roundness/angle, hardness,
/// spacing, the rotation mode and the shape of a pressure curve. A pair that
/// shares all of those is one brush wearing two names, which is what
/// 「최대한 안겹치도록… 에어브러시 같은게 두개 안생기도록」 (유저) forbids.
///
/// 🚨**A GENERAL BRUSH LAYS ITS DABS AT THE FINEST SPACING** (유저
/// 2026-09-24: 「지금 프리셋 브러시들 간격이 너무 멀어서 일반적인 설정으론
/// 최소치로 두자. 간격이 필요한 특수한거만 둬도되고」). A brush keeps a gap of
/// its own only where its look IS the gap — measured on the sample stroke at
/// an 87 px tip, texture being the neighbour-to-neighbour difference inside
/// the stroke: the decorations (separate marks); the grain and bristle tips,
/// whose texture fell to 16–51% at 1% (Rough Pencil, Dark Pencil 4B,
/// Colored Pencil, Dry Ink, Pastel, Crayon, Graphite Stick, Wet Watercolor,
/// Flat Bristle, Palette Knife, Grit Spray, Blending Stump, Hatching, Rough
/// Edge, Concrete, Chalk); the spacing-jitter ones (Charcoal, Dry Brush),
/// whose jitter needs a gap to move; and the blenders, which pick colour up
/// once per dab. On a general brush the edge got smoother (its wobble fell
/// 30–60%) and nothing else moved — except density, which flow builds per
/// dab: each soft brush took the flow that gives, at its own size, the
/// density it had, `1 − (1 − flow)^(old step / new step)` (Airbrush at 40 px:
/// a 2 px step became 1, and 0.12 became 0.062).
final List<BrushPreset> defaultBrushPresets = List.unmodifiable(<BrushPreset>[
  // ---- Pencil ----------------------------------------------------------
  BrushPreset(
    id: const BrushPresetId('builtin-pencil'),
    name: 'Pencil',
    groupId: _pencilGroup,
    // ⚠️Pressure darkens the line as well as widening it — what a pencil
    // does and ink does not. Only its spacing (15% against the Ink Pen's
    // 10%) set the two rows apart until both went to the finest spacing
    // (2026-09-24), and then they drew the same row.
    settings: BrushSettings(
      size: 4,
      hardness: 1.0,
      spacing: BrushShape.minSpacing,
      sizePressureCurve: BrushPressureCurve.identity(),
      opacityPressureCurve: BrushPressureCurve.identity(),
    ),
  ),
  BrushPreset(
    id: const BrushPresetId('builtin-soft-pencil'),
    name: 'Soft Pencil',
    groupId: _pencilGroup,
    settings: BrushSettings(
      size: 6,
      hardness: 0.8,
      opacity: 0.85,
      flow: 0.8,
      spacing: BrushShape.minSpacing,
      sizePressureCurve: BrushPressureCurve.linearFrom(0.35),
      opacityPressureCurve: BrushPressureCurve.identity(),
    ),
  ),
  BrushPreset(
    id: const BrushPresetId('builtin-mechanical-pencil'),
    name: 'Mechanical Pencil',
    groupId: _pencilGroup,
    settings: BrushSettings(
      size: 2,
      hardness: 1.0,
      spacing: BrushShape.minSpacing,
      // A lead has one width; pressure darkens it rather than widening it.
      sizePressureCurve: BrushPressureCurve.linearFrom(0.8),
      opacityPressureCurve: BrushPressureCurve.linearFrom(0.45),
    ),
  ),
  BrushPreset(
    id: const BrushPresetId('builtin-rough-pencil'),
    name: 'Rough Pencil',
    groupId: _pencilGroup,
    settings: BrushSettings(
      size: 8,
      flow: 0.9,
      spacing: 0.1,
      tipMask: grainBrushTipMask,
      textureMaskSource: paperGrainTextureMask,
      textureDensity: 0.55,
      sizePressureCurve: BrushPressureCurve.linearFrom(0.3),
    ),
  ),
  // 🚨TWO MORE GRADES, because a pencil set IS its grades. 2H is hard and
  // pale, 4B is soft and dark, and the pair is what makes the middle grades
  // already here read as a set rather than as three similar pencils.
  BrushPreset(
    id: const BrushPresetId('builtin-hard-pencil'),
    name: 'Hard Pencil 2H',
    groupId: _pencilGroup,
    settings: BrushSettings(
      size: 3,
      hardness: 0.95,
      flow: 0.55,
      spacing: BrushShape.minSpacing,
      opacity: 0.75,
      textureMaskSource: paperGrainTextureMask,
      textureScale: 1.0,
      textureDensity: 0.35,
      sizePressureCurve: BrushPressureCurve.linearFrom(0.75),
    ),
  ),
  BrushPreset(
    id: const BrushPresetId('builtin-dark-pencil'),
    name: 'Dark Pencil 4B',
    groupId: _pencilGroup,
    settings: BrushSettings(
      size: 8,
      hardness: 0.5,
      flow: 1.0,
      spacing: 0.05,
      tipMask: grainBrushTipMask,
      textureMaskSource: paperGrainTextureMask,
      textureScale: 1.4,
      textureDensity: 0.7,
      sizePressureCurve: BrushPressureCurve.linearFrom(0.35),
    ),
  ),
  BrushPreset(
    id: const BrushPresetId('builtin-colored-pencil'),
    name: 'Colored Pencil',
    groupId: _pencilGroup,
    settings: BrushSettings(
      size: 6,
      flow: 0.55,
      spacing: 0.08,
      tipMask: grainBrushTipMask,
      textureMaskSource: paperGrainTextureMask,
      textureScale: 1.4,
      textureDensity: 0.7,
      opacityPressureCurve: BrushPressureCurve.identity(),
    ),
  ),
  BrushPreset(
    id: const BrushPresetId('builtin-shading-pencil'),
    name: 'Shading Pencil',
    groupId: _pencilGroup,
    settings: BrushSettings(
      size: 6,
      hardness: 0.7,
      flow: 0.8,
      spacing: BrushShape.minSpacing,
      roundness: 0.55,
      angleDegrees: 35,
      rotationMode: BrushTipRotationMode.fixed,
      textureMaskSource: paperGrainTextureMask,
      textureScale: 1.2,
      textureDensity: 0.5,
      // 🚨THE 0.25 FLOOR ON THE TILT CURVE IS LOAD-BEARING, not taste.
      // `BrushPressureCurve.evaluate` returns `clamp(0,1) * maximum`, so the
      // pair (0.25, maximum 4.0) evaluates to exactly 1.0 at lean 0.0 — and
      // lean 0.0 is where a pen held UPRIGHT sits. Lower the floor and this
      // brush draws at a quarter size for anyone who holds the stylus
      // straight.
      // ⛔The reason used to be "that is where a mouse sits, because a device
      // reporting no tilt reads as an upright pen". That premise is gone: a
      // device with no tilt now answers null and the source is SKIPPED, so a
      // mouse never reaches this curve at all. The floor survives on its own
      // merit, which is why it is restated rather than deleted.
      curves: {
        (BrushPressureTarget.size, BrushInputSource.pressure):
            BrushPressureCurve.linearFrom(0.45),
        (BrushPressureTarget.size, BrushInputSource.tilt): BrushPressureCurve(
          const [BrushCurvePoint(0.0, 0.25), BrushCurvePoint(1.0, 1.0)],
          maximum: 4.0,
        ),
        // Leaning the pencil over spreads the same graphite thinner.
        // ⚠️A curve whose y DECREASES is legal; only x must increase.
        (BrushPressureTarget.opacity, BrushInputSource.tilt):
            BrushPressureCurve(const [
              BrushCurvePoint(0.0, 1.0),
              BrushCurvePoint(1.0, 0.55),
            ]),
      },
    ),
  ),

  // ---- Pen -------------------------------------------------------------
  BrushPreset(
    id: const BrushPresetId('builtin-ink-pen'),
    name: 'Ink Pen',
    groupId: _penGroup,
    settings: BrushSettings(
      size: 8,
      hardness: 1.0,
      spacing: BrushShape.minSpacing,
      sizePressureCurve: BrushPressureCurve.identity(),
    ),
  ),
  BrushPreset(
    id: const BrushPresetId('builtin-g-pen'),
    name: 'G-Pen',
    groupId: _penGroup,
    settings: BrushSettings(
      size: 10,
      hardness: 1.0,
      spacing: BrushShape.minSpacing,
      // The nib that snaps open under pressure: little happens early, then
      // the line swells fast.
      sizePressureCurve: BrushPressureCurve(const [
        BrushCurvePoint(0.0, 0.08),
        BrushCurvePoint(0.6, 0.4),
        BrushCurvePoint(1.0, 1.0),
      ]),
    ),
  ),
  BrushPreset(
    id: const BrushPresetId('builtin-maru-pen'),
    name: 'Maru Pen',
    groupId: _penGroup,
    settings: BrushSettings(
      size: 3,
      hardness: 1.0,
      spacing: BrushShape.minSpacing,
      sizePressureCurve: BrushPressureCurve.linearFrom(0.45),
    ),
  ),
  BrushPreset(
    id: const BrushPresetId('builtin-brush-pen'),
    name: 'Brush Pen',
    groupId: _penGroup,
    settings: BrushSettings(
      size: 12,
      hardness: 0.85,
      spacing: BrushShape.minSpacing,
      sizePressureCurve: BrushPressureCurve(const [
        BrushCurvePoint(0.0, 0.05),
        BrushCurvePoint(0.4, 0.22),
        BrushCurvePoint(1.0, 1.0),
      ]),
    ),
  ),
  BrushPreset(
    id: const BrushPresetId('builtin-calligraphy'),
    name: 'Calligraphy',
    groupId: _penGroup,
    settings: BrushSettings(
      size: 14,
      hardness: 0.9,
      spacing: BrushShape.minSpacing,
      roundness: 0.3,
      angleDegrees: 45,
      sizePressureCurve: BrushPressureCurve.identity(),
    ),
  ),
  BrushPreset(
    id: const BrushPresetId('builtin-marker'),
    name: 'Marker',
    groupId: _penGroup,
    settings: BrushSettings(
      size: 16,
      hardness: 0.8,
      opacity: 0.7,
      flow: 0.436,
      spacing: BrushShape.minSpacing,
    ),
  ),
  BrushPreset(
    id: const BrushPresetId('builtin-anime-pen'),
    name: 'Anime Pen',
    groupId: _penGroup,
    settings: BrushSettings(
      size: 6,
      // 🚨HARDNESS 0.85 IS THE WHOLE PRESET, not a style choice. At hardness
      // 1.0 `hardRadius == radius`, so `edgeSpan == 0` and coverage is
      // ALREADY binary (`brush_dab_tip_geometry.dart`, and identically in the
      // kernel) — `antiAlias: none` on such a tip is a field set to no
      // effect. A 0.85 ramp gives the threshold something to cut, landing the
      // hard edge at r × (1 + h) / 2, and flipping AA back to high in the
      // panel visibly softens it.
      hardness: 0.85,
      spacing: BrushShape.minSpacing,
      // ⛔NEVER pair `antiAlias: none` with a tip MASK: the threshold hits
      // mask coverage too, and would binarize a grain or chalk tip whole.
      antiAlias: BrushAntiAlias.none,
      sizePressureCurve: BrushPressureCurve.linearFrom(0.85),
    ),
  ),
  // 🚨KABURA PEN (カブラペン) IS CLIP STUDIO'S THIRD NIB and the roster had
  // two. It sits between them by construction: a G-Pen's line swells hard
  // under pressure and a Maru Pen's barely does, so this one takes the middle
  // floor rather than a new idea.
  BrushPreset(
    id: const BrushPresetId('builtin-kabura-pen'),
    name: 'Kabura Pen',
    groupId: _penGroup,
    settings: BrushSettings(
      size: 7,
      hardness: 1.0,
      flow: 1.0,
      spacing: BrushShape.minSpacing,
      sizePressureCurve: BrushPressureCurve.linearFrom(0.55),
    ),
  ),
  // ⛔A TECHNICAL PEN IGNORES PRESSURE, and that is not an omission: ミリペン
  // draws one width because the nib cannot open. Leaving the curve off is the
  // brush — it is also the one row here whose absence of a curve is what
  // separates it from every other nib.
  BrushPreset(
    id: const BrushPresetId('builtin-technical-pen'),
    name: 'Technical Pen',
    groupId: _penGroup,
    settings: BrushSettings(
      size: 3,
      hardness: 1.0,
      flow: 1.0,
      spacing: BrushShape.minSpacing,
    ),
  ),
  BrushPreset(
    id: const BrushPresetId('builtin-rough-ink'),
    name: 'Rough Ink',
    groupId: _penGroup,
    settings: BrushSettings(
      size: 9,
      hardness: 1.0,
      flow: 1.0,
      spacing: BrushShape.minSpacing,
      // The LINE is clean and the EDGE is not: a dual grain bites the
      // silhouette without touching the nib's own pressure response.
      dualMask: grainBrushTipMask,
      dualMaskScale: 0.45,
      dualDensity: 0.45,
      sizePressureCurve: BrushPressureCurve.linearFrom(0.4),
      roundnessJitter: 0.2,
    ),
  ),
  BrushPreset(
    id: const BrushPresetId('builtin-dry-ink'),
    name: 'Dry Ink',
    groupId: _penGroup,
    settings: BrushSettings(
      size: 10,
      hardness: 1.0,
      flow: 0.95,
      spacing: 0.05,
      // The break in the line is the dual tip, not the flow: a hard nib
      // running out of ink skips, it does not fade.
      dualMask: grainBrushTipMask,
      dualMaskScale: 0.55,
      sizePressureCurve: BrushPressureCurve.linearFrom(0.3),
    ),
  ),

  // ---- Dry Media -------------------------------------------------------
  BrushPreset(
    id: const BrushPresetId('builtin-chalk-preset'),
    name: 'Chalk',
    groupId: _dryMediaGroup,
    settings: BrushSettings(
      size: 20,
      flow: 0.85,
      spacing: 0.2,
      tipMask: chalkBrushTipMask,
      sizePressureCurve: BrushPressureCurve.identity(),
    ),
  ),
  BrushPreset(
    id: const BrushPresetId('builtin-charcoal'),
    name: 'Charcoal',
    groupId: _dryMediaGroup,
    settings: BrushSettings(
      size: 28,
      flow: 0.9,
      spacing: 0.12,
      tipMask: chalkBrushTipMask,
      dualMask: grainBrushTipMask,
      dualMaskScale: 0.55,
      textureMaskSource: paperGrainTextureMask,
      textureScale: 1.8,
      textureDensity: 0.75,
      sizeJitter: 0.2,
      // ⚠️Spacing jitter is rolled once per SEGMENT, not per dab — the stick
      // catches and skips along the paper rather than shivering in place.
      // That is the right grain for charcoal, so nobody should "fix" it into
      // a per-dab roll.
      spacingJitter: 0.35,
      sizePressureCurve: BrushPressureCurve.linearFrom(0.4),
      opacityPressureCurve: BrushPressureCurve.identity(),
    ),
  ),
  BrushPreset(
    id: const BrushPresetId('builtin-pastel'),
    name: 'Pastel',
    groupId: _dryMediaGroup,
    settings: BrushSettings(
      size: 22,
      flow: 0.6,
      spacing: 0.1,
      tipMask: chalkBrushTipMask,
      textureMaskSource: canvasWeaveTextureMask,
      textureScale: 1.4,
      textureDensity: 0.7,
      angleJitter: 0.4,
      // Soft pastel lifts what is already down and drags it along.
      mixesGroundColor: true,
      colorStretch: 0.4,
      paintAmount: 0.9,
      paintDensity: 0.85,
      opacityPressureCurve: BrushPressureCurve.identity(),
    ),
  ),
  BrushPreset(
    id: const BrushPresetId('builtin-crayon'),
    name: 'Crayon',
    groupId: _dryMediaGroup,
    settings: BrushSettings(
      size: 16,
      flow: 0.8,
      spacing: 0.07,
      tipMask: grainBrushTipMask,
      textureMaskSource: canvasWeaveTextureMask,
      textureScale: 0.9,
      textureDensity: 0.9,
      sizePressureCurve: BrushPressureCurve.linearFrom(0.55),
    ),
  ),
  BrushPreset(
    id: const BrushPresetId('builtin-graphite-stick'),
    name: 'Graphite Stick',
    groupId: _dryMediaGroup,
    settings: BrushSettings(
      size: 26,
      flow: 0.75,
      spacing: 0.08,
      // ⚠️Roundness squashes a MASKED tip too — the mask sampler divides by
      // it the same way the analytic ellipse does — and the panel's tip icon
      // draws the ellipse, so the row shows the flat edge.
      roundness: 0.35,
      angleDegrees: 20,
      rotationMode: BrushTipRotationMode.fixed,
      tipMask: grainBrushTipMask,
      textureMaskSource: paperGrainTextureMask,
      textureScale: 2.0,
      textureDensity: 0.6,
      sizePressureCurve: BrushPressureCurve.linearFrom(0.6),
      opacityPressureCurve: BrushPressureCurve.linearFrom(0.35),
    ),
  ),

  // ---- Watercolor ------------------------------------------------------
  BrushPreset(
    id: const BrushPresetId('builtin-watercolor'),
    name: 'Watercolor',
    groupId: _watercolorGroup,
    settings: BrushSettings(
      size: 28,
      hardness: 0.3,
      flow: 0.265,
      opacity: 0.8,
      spacing: BrushShape.minSpacing,
      textureMaskSource: paperGrainTextureMask,
      textureScale: 2.0,
      textureDensity: 0.8,
      opacityPressureCurve: BrushPressureCurve.identity(),
    ),
  ),
  BrushPreset(
    id: const BrushPresetId('builtin-wet-watercolor'),
    name: 'Wet Watercolor',
    groupId: _watercolorGroup,
    settings: BrushSettings(
      size: 34,
      flow: 0.35,
      opacity: 0.8,
      spacing: 0.05,
      // The wet edge lives in the TIP, not in a new engine field.
      tipMask: wetBlotBrushTipMask,
      textureMaskSource: paperGrainTextureMask,
      textureScale: 2.0,
      textureDensity: 0.6,
      angleJitter: 1.0,
      sizeJitter: 0.2,
      // ⚠️The blend is applied ONCE per stroke at pen-up, so washes darken
      // stroke over stroke — which is what layering washes does — while a
      // single stroke crossing itself stays even, which is what one wet pass
      // does. Both halves of that are correct here; neither is a bug.
      blendMode: BrushBlendMode.multiply,
      mixesGroundColor: true,
      colorStretch: 0.4,
      paintAmount: 0.9,
      paintDensity: 0.6,
      opacityPressureCurve: BrushPressureCurve.identity(),
    ),
  ),
  BrushPreset(
    id: const BrushPresetId('builtin-dense-watercolor'),
    name: 'Dense Watercolor',
    groupId: _watercolorGroup,
    settings: BrushSettings(
      size: 22,
      hardness: 0.6,
      flow: 0.716,
      opacity: 0.9,
      spacing: BrushShape.minSpacing,
      textureMaskSource: paperGrainTextureMask,
      textureScale: 1.4,
      textureDensity: 0.45,
      mixesGroundColor: true,
      colorStretch: 0.3,
      paintAmount: 0.95,
      paintDensity: 0.95,
      sizePressureCurve: BrushPressureCurve.linearFrom(0.5),
    ),
  ),
  BrushPreset(
    id: const BrushPresetId('builtin-flat-wash'),
    name: 'Flat Wash',
    groupId: _watercolorGroup,
    settings: BrushSettings(
      size: 44,
      hardness: 0.35,
      flow: 0.207,
      opacity: 0.75,
      spacing: BrushShape.minSpacing,
      // A wide flat sable held square to the paper: the angle stays put so
      // the band keeps one width across the sweep.
      roundness: 0.2,
      rotationMode: BrushTipRotationMode.fixed,
      textureMaskSource: paperGrainTextureMask,
      textureScale: 2.5,
      textureDensity: 0.6,
      mixesGroundColor: true,
      colorStretch: 0.35,
      paintAmount: 0.9,
      paintDensity: 0.7,
      opacityPressureCurve: BrushPressureCurve.identity(),
    ),
  ),

  // ---- Oil -------------------------------------------------------------
  BrushPreset(
    id: const BrushPresetId('builtin-round-bristle'),
    name: 'Round Bristle',
    groupId: _oilGroup,
    settings: BrushSettings(
      size: 18,
      hardness: 0.9,
      flow: 0.775,
      spacing: BrushShape.minSpacing,
      tipMask: bristleBrushTipMask,
      // Bristles rake along the stroke, so the tip turns with it.
      rotationMode: BrushTipRotationMode.direction,
      sizePressureCurve: BrushPressureCurve.linearFrom(0.5),
    ),
  ),
  BrushPreset(
    id: const BrushPresetId('builtin-flat-bristle'),
    name: 'Flat Bristle',
    groupId: _oilGroup,
    settings: BrushSettings(
      size: 22,
      flow: 0.75,
      spacing: 0.05,
      roundness: 0.3,
      angleDegrees: 45,
      tipMask: bristleBrushTipMask,
      sizePressureCurve: BrushPressureCurve.linearFrom(0.6),
    ),
  ),
  BrushPreset(
    id: const BrushPresetId('builtin-gouache'),
    name: 'Gouache',
    groupId: _oilGroup,
    settings: BrushSettings(
      size: 20,
      hardness: 0.65,
      flow: 0.853,
      spacing: BrushShape.minSpacing,
      textureMaskSource: canvasWeaveTextureMask,
      textureScale: 1.5,
      textureDensity: 0.5,
      sizePressureCurve: BrushPressureCurve.linearFrom(0.6),
    ),
  ),
  BrushPreset(
    id: const BrushPresetId('builtin-oil-brush'),
    name: 'Oil Brush',
    groupId: _oilGroup,
    settings: BrushSettings(
      size: 26,
      flow: 0.9,
      spacing: BrushShape.minSpacing,
      tipMask: bristleBrushTipMask,
      rotationMode: BrushTipRotationMode.direction,
      textureMaskSource: canvasWeaveTextureMask,
      textureScale: 1.2,
      textureDensity: 0.4,
      // ⚠️Roundness jitter only ever SHRINKS — the bundle splays thinner,
      // never fatter — which is why a value this small still reads.
      roundnessJitter: 0.2,
      // Loaded paint picks up what it crosses.
      mixesGroundColor: true,
      colorStretch: 0.4,
      paintAmount: 0.9,
      paintDensity: 1.0,
      sizePressureCurve: BrushPressureCurve.linearFrom(0.55),
    ),
  ),
  BrushPreset(
    id: const BrushPresetId('builtin-palette-knife'),
    name: 'Palette Knife',
    groupId: _oilGroup,
    settings: BrushSettings(
      size: 34,
      hardness: 1.0,
      spacing: 0.05,
      // A blade has ONE width, so it carries no pressure curve at all — the
      // edge is the mark.
      roundness: 0.12,
      angleDegrees: 90,
      rotationMode: BrushTipRotationMode.direction,
      textureMaskSource: canvasWeaveTextureMask,
      textureDensity: 0.25,
      mixesGroundColor: true,
      colorStretch: 0.5,
      paintAmount: 0.95,
      paintDensity: 1.0,
    ),
  ),
  BrushPreset(
    id: const BrushPresetId('builtin-dry-brush'),
    name: 'Dry Brush',
    groupId: _oilGroup,
    settings: BrushSettings(
      size: 30,
      flow: 0.5,
      spacing: 0.06,
      tipMask: bristleBrushTipMask,
      rotationMode: BrushTipRotationMode.direction,
      dualMask: spongeBrushTipMask,
      dualMaskScale: 0.75,
      spacingJitter: 0.4,
      opacityJitter: 0.2,
      sizePressureCurve: BrushPressureCurve.linearFrom(0.3),
    ),
  ),

  // ---- Airbrush --------------------------------------------------------
  BrushPreset(
    id: const BrushPresetId('builtin-airbrush'),
    name: 'Airbrush',
    groupId: _airbrushGroup,
    settings: BrushSettings(
      size: 40,
      hardness: 0.05,
      flow: 0.062,
      opacity: 0.9,
      // Tight spacing is what makes an airbrush build rather than band.
      spacing: BrushShape.minSpacing,
      opacityPressureCurve: BrushPressureCurve.identity(),
    ),
  ),
  BrushPreset(
    id: const BrushPresetId('builtin-soft-brush'),
    name: 'Soft Brush',
    groupId: _airbrushGroup,
    settings: BrushSettings(
      size: 24,
      hardness: 0.25,
      flow: 0.394,
      spacing: BrushShape.minSpacing,
      opacityPressureCurve: BrushPressureCurve.identity(),
    ),
  ),
  BrushPreset(
    id: const BrushPresetId('builtin-spray'),
    name: 'Spray',
    groupId: _airbrushGroup,
    settings: BrushSettings(
      size: 44,
      hardness: 0.1,
      flow: 0.086,
      opacity: 0.85,
      spacing: BrushShape.minSpacing,
      textureMaskSource: paperGrainTextureMask,
      // 🚨TEXTURE SCALE 0.7 IS THE WHOLE SEPARATION from Airbrush. The
      // texture period is `mask size × scale`, so 0.7 is a ~45px grain that
      // reads as SPECKLE in a preview row, while Watercolor's 2.0 is a ~128px
      // period that reads as a soft gradient. Raise it and this row becomes a
      // second airbrush.
      textureScale: 0.7,
      textureDensity: 0.9,
      opacityPressureCurve: BrushPressureCurve.identity(),
    ),
  ),
  BrushPreset(
    id: const BrushPresetId('builtin-grit-spray'),
    name: 'Grit Spray',
    groupId: _airbrushGroup,
    settings: BrushSettings(
      size: 36,
      hardness: 0.35,
      flow: 0.3,
      opacity: 0.85,
      spacing: 0.05,
      dualMask: splatterBrushTipMask,
      dualMaskScale: 0.5,
      opacityPressureCurve: BrushPressureCurve.identity(),
    ),
  ),

  // ---- Blend -----------------------------------------------------------
  BrushPreset(
    id: const BrushPresetId('builtin-blender'),
    name: 'Blender',
    groupId: _blendGroup,
    settings: BrushSettings(
      size: 24,
      hardness: 0.35,
      flow: 0.7,
      spacing: 0.05,
      mixesGroundColor: true,
      // 🚨STRETCH 0.35, NEVER 1.0 — and this is arithmetic, not taste. The
      // reservoir is re-sampled every dab as `lerp(reservoir, ground,
      // stretch × coverage)` and then deposited as `lerp(ground, reservoir,
      // amount)`. At stretch 1.0 the reservoir BECOMES the ground each dab,
      // so the deposit is the colour that was already there: a provable
      // identity, i.e. an invisible brush. The smear IS the reservoir's lag,
      // so the stretch has to stay moderate.
      colorStretch: 0.35,
      paintAmount: 1.0,
      paintDensity: 0.9,
      opacityPressureCurve: BrushPressureCurve.identity(),
    ),
  ),
  BrushPreset(
    id: const BrushPresetId('builtin-water-blend'),
    name: 'Water Blend',
    groupId: _blendGroup,
    settings: BrushSettings(
      size: 34,
      hardness: 0.12,
      flow: 0.3,
      spacing: 0.05,
      textureMaskSource: paperGrainTextureMask,
      textureScale: 2.6,
      textureDensity: 0.6,
      mixesGroundColor: true,
      colorStretch: 0.3,
      paintAmount: 1.0,
      paintDensity: 0.45,
      // ⚠️The ABSENCE of a pressure curve is load-bearing: the preview drives
      // a synthetic 0-1-0 arc, so Watercolor's row tapers at both ends and
      // this one stays full width. That is what tells them apart in the list.
    ),
  ),
  BrushPreset(
    id: const BrushPresetId('builtin-blending-stump'),
    name: 'Blending Stump',
    groupId: _blendGroup,
    settings: BrushSettings(
      size: 14,
      flow: 0.4,
      spacing: 0.05,
      tipMask: grainBrushTipMask,
      textureMaskSource: paperGrainTextureMask,
      textureScale: 1.3,
      textureDensity: 0.5,
      mixesGroundColor: true,
      colorStretch: 0.35,
      paintAmount: 1.0,
      paintDensity: 0.6,
      sizePressureCurve: BrushPressureCurve.linearFrom(0.5),
    ),
  ),

  // ---- Texture ---------------------------------------------------------
  BrushPreset(
    id: const BrushPresetId('builtin-splatter-preset'),
    name: 'Splatter',
    groupId: _textureGroup,
    settings: BrushSettings(
      size: 28,
      spacing: 0.9,
      tipMask: splatterBrushTipMask,
    ),
  ),
  BrushPreset(
    id: const BrushPresetId('builtin-stipple'),
    name: 'Stipple',
    groupId: _textureGroup,
    settings: BrushSettings(
      size: 10,
      spacing: 0.6,
      scatterRadiusRatio: 1.6,
      scatterCount: 4,
      sizeJitter: 0.5,
      opacityJitter: 0.4,
    ),
  ),
  BrushPreset(
    id: const BrushPresetId('builtin-sponge'),
    name: 'Sponge',
    groupId: _textureGroup,
    settings: BrushSettings(
      size: 34,
      flow: 0.8,
      spacing: 0.35,
      tipMask: spongeBrushTipMask,
      // A clump that landed the same way twice would read as a pattern.
      angleJitter: 1.0,
      sizeJitter: 0.25,
    ),
  ),
  BrushPreset(
    id: const BrushPresetId('builtin-cloud'),
    name: 'Cloud',
    groupId: _textureGroup,
    settings: BrushSettings(
      size: 60,
      flow: 0.25,
      spacing: 0.25,
      tipMask: spongeBrushTipMask,
      // ⛔`hardness` is DELIBERATELY absent, and its absence is the record of
      // a defect: this preset used to carry `hardness: 0.2`, which never did
      // anything. Hardness is not read when a tip MASK is set — the coverage
      // comes from the mask sampler, not from the analytic falloff — so the
      // value was a leftover that read as "a soft cloud" to anyone skimming.
      // The 09-09 roster round could delete it because the library no longer
      // migrates: a version bump reseeds, so a retune reaches everyone.
      angleJitter: 1.0,
      scatterRadiusRatio: 0.5,
      scatterCount: 2,
      opacityPressureCurve: BrushPressureCurve.identity(),
    ),
  ),
  // 🚨HATCHING IS THE BRISTLE TIP HELD AT A FIXED ANGLE, and that is the
  // whole brush: parallel lines that stay parallel however the hand turns,
  // which is what a hatching pass is. ⛔`rotationMode.direction` would defeat
  // it — the lines would follow the stroke and never cross.
  BrushPreset(
    id: const BrushPresetId('builtin-hatching'),
    name: 'Hatching',
    groupId: _textureGroup,
    settings: BrushSettings(
      size: 16,
      hardness: 1.0,
      flow: 0.9,
      spacing: 0.06,
      tipMask: bristleBrushTipMask,
      rotationMode: BrushTipRotationMode.fixed,
      angleDegrees: 45,
      roundness: 0.7,
      opacityJitter: 0.15,
    ),
  ),
  BrushPreset(
    id: const BrushPresetId('builtin-rough-edge'),
    name: 'Rough Edge',
    groupId: _textureGroup,
    settings: BrushSettings(
      size: 22,
      hardness: 0.9,
      flow: 1.0,
      spacing: 0.1,
      tipMask: chalkBrushTipMask,
      // The EDGE is what varies, not the fill: roundness jitter chews the
      // silhouette while the dual grain keeps the inside from going flat.
      roundnessJitter: 0.45,
      angleJitter: 0.5,
      dualMask: grainBrushTipMask,
      dualMaskScale: 0.5,
      dualDensity: 0.6,
    ),
  ),
  BrushPreset(
    id: const BrushPresetId('builtin-concrete'),
    name: 'Concrete',
    groupId: _textureGroup,
    settings: BrushSettings(
      size: 20,
      hardness: 1.0,
      flow: 0.85,
      spacing: 0.05,
      dualMask: chalkBrushTipMask,
      dualMaskScale: 0.6,
      textureMaskSource: canvasWeaveTextureMask,
      textureScale: 0.8,
      textureDensity: 0.75,
      roundnessJitter: 0.3,
    ),
  ),
  // ---- Decoration ------------------------------------------------------
  // 🚨EVERY ONE OF THESE IS A SCATTER, which is the group's whole idea: one
  // press throws a handful of marks instead of laying one. The fields are the
  // placement ones P20 shipped and the panel now reaches
  // (`scatterRadiusRatio` / `scatterCount` / the jitters), so the roster could
  // grow this far with no engine change at all.
  //
  // ⚠️Scatter and jitter are exactly what the row preview does NOT draw (see
  // the header). These five are told apart by their TIPS, which is why four
  // new masks came with them.
  BrushPreset(
    id: const BrushPresetId('builtin-grass'),
    name: 'Grass',
    groupId: _decorationGroup,
    settings: BrushSettings(
      size: 26,
      hardness: 1.0,
      flow: 0.95,
      spacing: 0.6,
      tipMask: leafBrushTipMask,
      // Blades stand UP and lean a little, so the tip follows the stroke
      // rather than the fixed angle a fallen-leaf pile wants.
      rotationMode: BrushTipRotationMode.direction,
      angleDegrees: 90,
      angleJitter: 0.12,
      roundness: 0.35,
      sizeJitter: 0.45,
      scatterRadiusRatio: 0.8,
      scatterCount: 5,
      scatterBothAxes: false,
    ),
  ),
  BrushPreset(
    id: const BrushPresetId('builtin-sparkle'),
    name: 'Sparkle',
    groupId: _decorationGroup,
    settings: BrushSettings(
      size: 22,
      hardness: 1.0,
      flow: 1.0,
      spacing: 1.2,
      tipMask: starBrushTipMask,
      angleJitter: 0.25,
      sizeJitter: 0.6,
      opacityJitter: 0.4,
      scatterRadiusRatio: 1.6,
      scatterCount: 3,
    ),
  ),
  BrushPreset(
    id: const BrushPresetId('builtin-snow'),
    name: 'Snow',
    groupId: _decorationGroup,
    settings: BrushSettings(
      size: 18,
      hardness: 1.0,
      flow: 0.9,
      spacing: 1.0,
      tipMask: flakeBrushTipMask,
      // ⚠️A flake has six-fold symmetry, so a full half-turn of jitter says
      // the same thing twice — a sixth of a turn is all the variety there is.
      angleJitter: 0.17,
      sizeJitter: 0.55,
      opacityJitter: 0.3,
      scatterRadiusRatio: 2.0,
      scatterCount: 4,
    ),
  ),
  BrushPreset(
    id: const BrushPresetId('builtin-bubble'),
    name: 'Bubble',
    groupId: _decorationGroup,
    settings: BrushSettings(
      size: 24,
      hardness: 1.0,
      // Bubbles overlap without adding up: the ring is thin, and a low flow
      // is what keeps a cluster from reading as one solid blob.
      flow: 0.55,
      spacing: 1.4,
      tipMask: ringBrushTipMask,
      sizeJitter: 0.65,
      opacityJitter: 0.35,
      scatterRadiusRatio: 1.8,
      scatterCount: 3,
    ),
  ),
  BrushPreset(
    id: const BrushPresetId('builtin-leaves'),
    name: 'Leaves',
    groupId: _decorationGroup,
    settings: BrushSettings(
      size: 28,
      hardness: 1.0,
      flow: 0.9,
      spacing: 0.9,
      tipMask: leafBrushTipMask,
      // ⛔The opposite of Grass on purpose, out of the same tip: leaves lie at
      // every angle and grass stands up. One mask, two brushes — which is
      // what a full turn of angle jitter buys, and it is also what keeps the
      // two rows from being one brush wearing two names.
      angleJitter: 1.0,
      sizeJitter: 0.5,
      roundnessJitter: 0.25,
      scatterRadiusRatio: 1.5,
      scatterCount: 4,
    ),
  ),
]);

/// What a built-in is called when it is made: its id and its English name
/// in, the stored name out.
///
/// 🚨유저 2026-09-15 (brush-preset-names-language-Q1): 「만들 때 그 언어로
/// 적는다」 — the built-ins are named in the program language at the moment
/// the library makes them (first run, a new library version, 「기본값으로
/// 초기화」), and from then on the name is the user's text like any renamed
/// brush. The words live in the UI's string tables, which this layer may not
/// import, so whoever makes the library hands its namer in.
typedef BuiltinBrushName = String Function(String id, String english);

/// The namer that keeps the defaults' own English.
String keepEnglishName(String id, String english) => english;

/// [defaultBrushGroups], each named by [nameOf].
List<BrushGroup> namedDefaultBrushGroups(BuiltinBrushName nameOf) => [
  for (final group in defaultBrushGroups)
    group.copyWith(name: nameOf(group.id.value, group.name)),
];

/// [defaultBrushPresets], each named by [nameOf].
List<BrushPreset> namedDefaultBrushPresets(BuiltinBrushName nameOf) => [
  for (final preset in defaultBrushPresets)
    preset.copyWith(name: nameOf(preset.id.value, preset.name)),
];
