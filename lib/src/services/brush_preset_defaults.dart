import '../models/brush_anti_alias.dart';
import '../models/brush_blend_mode.dart';
import '../models/brush_group.dart';
import '../models/brush_group_icon.dart';
import '../models/brush_group_id.dart';
import '../models/brush_input_source.dart';
import '../models/brush_mixing_method.dart';
import '../models/brush_preset.dart';
import '../models/brush_preset_id.dart';
import '../models/brush_pressure_curve.dart';
import '../models/brush_settings.dart';
import '../models/brush_settings_row.dart';
import '../models/brush_shape.dart';
import '../models/brush_texture_mode.dart';
import '../models/brush_tip_order.dart';
import '../models/brush_tip_rotation_mode.dart';
import 'brush_tip_mask_defaults.dart';

const BrushGroupId _basicGroup = BrushGroupId('builtin-basic-group');
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
/// ドットペン too. ↩️Anime Pen is gone (board F-218, 유저 2026-09-28
/// 「이상한것들 쳐내고. 애니펜 이런거」): a pixel line is the 없음 step of
/// any brush's anti-alias, so the setting stays and the extra row does not.
///
/// 🚨**BASIC COMES FIRST** (board F-218, 유저 2026-09-28: 「포토샵보면
/// 둥근라운드 딱딱한라운드 뭐 이런 진짜 기본적인 브러시가 제대로 있는데
/// 여긴 이상함. 대표적인 기본적인 브러시들 추가」). The two rounds every
/// painting program opens with were already here under other names — Ink
/// Pen and Soft Brush — so they MOVED and were renamed rather than being
/// added beside themselves.
final List<BrushGroup> defaultBrushGroups = List.unmodifiable(<BrushGroup>[
  const BrushGroup(id: _basicGroup, name: 'Basic', icon: BrushGroupIcon.brush),
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
///
/// 🚨**A FLOW SAYS WHAT ONE STAMP PER TENTH OF THE SIZE LAYS** (유저
/// 2026-10-01, board `one-pixel-steps-change-a-brush-with-its-size`:
/// 「엔진이 쌓임을 환산 — 크기와 무관하게(클튜처럼)」). A dab lays its share of
/// such a stamp (`stampShareOf`), so one flow piles up the same at every
/// size. Every brush that lays a share at its own size took the flow that
/// lays there what its pixel-apart pile laid before, `1 − (1 − flow)^(1 /
/// share)` — twenty of them (Soft Round at 24 px: share 0.417, 0.394 became
/// 0.6992; Airbrush at 40 px: share 0.25, 0.062 became 0.2259). A brush at
/// flow 1 keeps it: whole is whole at any share.
///
/// ↩️**AND SO DOES A 색 늘이기** (2026-10-24, board
/// `mixing-strength-follows-the-dab-spacing`): the mixer lifts its share of
/// a stamp's pickup as well, so every mixing brush took the stretch that
/// pulls, at its own size, what it pulled per dab before — the same
/// `1 − (1 − stretch)^(1 / share)`, eight of them (Oil Brush at 26 px: share
/// 0.385, 0.4 became 0.7349). Pastel lays whole and keeps its 0.4.
/// The ランダム rows a preset throws (F-176-Q2): each amount is how far below
/// its base a throw may land — what the brush's jitter slider said before the
/// row replaced it — so the row's 最小値 is one minus it.
Map<BrushDynamicsKey, BrushPressureCurve> _randomRows({
  double size = 0.0,
  double opacity = 0.0,
  double roundness = 0.0,
  double spacing = 0.0,
}) => {
  for (final (target, amount) in [
    (BrushPressureTarget.size, size),
    (BrushPressureTarget.opacity, opacity),
    (BrushPressureTarget.roundness, roundness),
    (BrushPressureTarget.spacing, spacing),
  ])
    if (amount > 0.0)
      (target, BrushInputSource.random): BrushPressureCurve.linearFrom(
        1.0 - amount,
      ),
};

/// The tilted pencil's lean, all of it by 0.65: rising, and falling.
///
/// ⚠️Its end at a lean of 0.65, not 1.0: a Wacom pen reports little past
/// 60° from upright (altitude ⅓, lean ⅔), so a row that ran to 1.0 would
/// never show its end on the tablet it was made on.
///
/// ↩️The grades leaned with the pen on these too (F-433, 유저 2026-10-21:
/// 「일반 연필에도 어느정도 기울기로 형태 바뀌는거 넣고」) until F-462 ②
/// (유저 2026-10-25: 「일반연필 기울기에따라 뭐 바뀐다거나 다 잊고,
/// 눕히는연필만 지금 방향성대로 기울기에따라 팁 바뀌는느낌은 좋음」).
///
/// ⚠️Two points at the far height, 0.5 and 0.8: the points pull the curve
/// ([BrushPressureCurve]), and it reaches their height only between two of
/// them — from the middle of their edge, 0.65, on. ↩️One point at 0.65 was
/// the curve's own point while the curve ran through its points (F-456).
const _leaningIn = [
  BrushCurvePoint(0.0, 0.0),
  BrushCurvePoint(0.5, 1.0),
  BrushCurvePoint(0.8, 1.0),
  BrushCurvePoint(1.0, 1.0),
];
const _leaningOut = [
  BrushCurvePoint(0.0, 1.0),
  BrushCurvePoint(0.5, 0.0),
  BrushCurvePoint(0.8, 0.0),
  BrushCurvePoint(1.0, 0.0),
];

/// 🚨HOW MUCH OF THE PAPER'S TOOTH A LEAD LEAVES BARE, by the pen's pressure
/// (유저 F-451, 2026-10-23: 「진짜연필 다시한번 참고해서 다시한번 제대로
/// 구현」): pressed lightly, a lead catches the paper's peaks and its valleys
/// stay pale; pressed hard, it fills towards them. The paper multiplies, so
/// its density is how much of it shows: the row falls from the brush's
/// density at the faintest touch to [heaviest] of it at the hardest.
///
/// ↩️It was the REACH into the paper's height (`BrushTextureMode.height`), a
/// cut: a valley deeper than the reach took nothing, so at one pressure the
/// same pixels stayed bare however often the line was laid again (유저
/// F-456: 「결여가 너무 일정함(같은부분 다시 그려도 결여된 픽셀이
/// 안채워짐)」). Multiplied, a valley takes a share every stroke.
Map<BrushDynamicsKey, BrushPressureCurve> _toothRow(double heaviest) => {
  (BrushPressureTarget.textureDensity, BrushInputSource.pressure):
      BrushPressureCurve(const [
        BrushCurvePoint(0.0, 1.0),
        BrushCurvePoint(1.0, 0.0),
      ], minimum: heaviest),
};

/// 🗣️HOW DEEP A LEAD REACHES INTO THE PAPER, by the pen's pressure (F-462 ②,
/// 유저 2026-10-25: 「클튜브러시 그대로 참고하되 따라한 느낌만 안나도록
/// 참고해서 우리방식대로 재구현」). Under a paper worked by its height
/// (`BrushTextureMode.height`) the density is the reach: the row climbs from
/// [lightest] of the brush's at the faintest touch, which catches only the
/// paper's peaks and breaks the line into grain, to all of it at the
/// hardest. Clip Studio's pencils cut their paper so, dab by dab (紙質
/// 減算 · 描点ごとに適用 — the user's screenshots on
/// `the-gouache-is-a-round-with-a-weave` Q1).
///
/// ↩️F-456 left the height for a multiplied tooth (유저 2026-10-23:
/// 「결여가 너무 일정함(같은부분 다시 그려도 결여된 픽셀이 안채워짐)」): under
/// F-451 every dab laid one smooth face, so it reached the same texels however
/// often it was laid. The crumbs' mottle moves the reach dab to dab now
/// ([pencilCrumbBrushTipMasks]); multiplied, a lead only paled and laid
/// smooth.
Map<BrushDynamicsKey, BrushPressureCurve> _reachRow(double lightest) => {
  (BrushPressureTarget.textureDensity, BrushInputSource.pressure):
      BrushPressureCurve.linearFrom(lightest),
};

/// The built-ins as the library seeds them: each as made below, showing in
/// the panel what its group's brushes show ([_shownByGroup]).
final List<BrushPreset> defaultBrushPresets = List.unmodifiable(<BrushPreset>[
  for (final preset in _builtinsAsMade)
    preset.copyWith(
      settings: BrushSettings.fromShape(
        preset.settings.shape,
        shown: {
          ...BrushSettingsRow.shownByDefault,
          ...?_shownByGroup[preset.groupId],
        },
      ),
    ),
]);

/// What each group's brushes show in the panel besides the three every
/// brush does ([BrushSettingsRow.shownByDefault]) — the setting a brush of
/// that kind is turned by most. I-141: the user named the three and left
/// the rest of the first choice to me; a brush's own is changed in the
/// brush detail window.
final Map<BrushGroupId, Set<BrushSettingsRow>> _shownByGroup = {
  _basicGroup: {BrushSettingsRow.hardness},
  _pencilGroup: {BrushSettingsRow.textureDensity},
  _dryMediaGroup: {BrushSettingsRow.textureDensity},
  _penGroup: {BrushSettingsRow.postCorrection},
  for (final group in [_watercolorGroup, _oilGroup, _blendGroup])
    group: {
      BrushSettingsRow.paintAmount,
      BrushSettingsRow.paintDensity,
      BrushSettingsRow.colorStretch,
    },
  _airbrushGroup: {BrushSettingsRow.flow},
  for (final group in [_textureGroup, _decorationGroup])
    group: {BrushSettingsRow.scatter, BrushSettingsRow.scatterCount},
};

final List<BrushPreset> _builtinsAsMade = <BrushPreset>[
  // ---- Basic -----------------------------------------------------------
  // 🚨THE TWO ROUNDS ARE OLD BRUSHES UNDER NEW NAMES (board F-218): the ids
  // stay `builtin-ink-pen` and `builtin-soft-brush`, so a project's resumed
  // tools and the hand bank still find them.
  BrushPreset(
    id: const BrushPresetId('builtin-ink-pen'),
    name: 'Hard Round',
    groupId: _basicGroup,
    settings: BrushSettings(
      size: 8,
      hardness: 1.0,
      spacing: BrushShape.minSpacing,
      sizePressureCurve: BrushPressureCurve.identity(),
    ),
  ),
  BrushPreset(
    id: const BrushPresetId('builtin-soft-brush'),
    name: 'Soft Round',
    groupId: _basicGroup,
    settings: BrushSettings(
      size: 24,
      // Photoshop's Soft Round is hardness 0: the falloff starts at the
      // centre.
      hardness: 0.0,
      flow: 0.6992,
      spacing: BrushShape.minSpacing,
      opacityPressureCurve: BrushPressureCurve.identity(),
    ),
  ),

  // ---- Pencil ----------------------------------------------------------
  // 🚨A PENCIL SET IS ITS GRADES (board F-218, 유저 2026-09-28: 「연필은 싹
  // 다 비슷비슷한 브러시라 차이를 못느끼겠음. 제대로 차이 두도록. 현실기반?」).
  // Three of the eight pencils here were plain round tips with no graphite in
  // them at all — a thin pen each. Now every graphite pencil wears the paper's
  // tooth, and the four grades step the way the leads do: the harder, the
  // paler, finer and crisper; the softer, the darker, coarser and broader.
  // ⚠️The picker draws every row at one size, so the grades are kept apart
  // by what it CAN draw — tone (flow · opacity), grain (texture density) and
  // edge (hardness) — never by size alone.
  //
  // ↩️THE LEAD IS A BLOCK, AND THE GRAIN IS THE PAPER'S (유저 F-433,
  // 2026-10-21: 「크게해서 dab 찍어보면 … 그물모양임 … 다른 연필 브러시도
  // 조정」). The grades wore the grain TIP, whose speckle grows with the dab;
  // now they wear the lead's side ([pencilSideBrushTipMask]) on the graphite
  // tooth ([graphiteToothTextureMask]), which stays a pixel or two at any
  // size. With no grain in the tip, the gap between stamps is no longer what
  // they look like, so they lay at the finest spacing like any general brush.
  //
  // ↩️THE TIP IS THE LEAD, UPRIGHT TO FLAT, AND THE PAPER CUTS ITS EDGE (유저
  // F-451, 2026-10-23: 「팁 사각형인채로 질감만 얼버무려서 연필느낌내는건 너무
  // 구현도가 낮음」). The side was one block at every lean; now each wears
  // the six footprints of [pencilLeadBrushTipMasks], taken by the pen's
  // lean — round upright, square laid flat — and the tooth worked by its
  // HEIGHT, not by multiplying, so where the lead barely touched the paper
  // broke the silhouette.
  //
  // ↩️THREE FACES A STEP, AND THE PAPER MULTIPLIES AGAIN (유저 F-456,
  // 2026-10-23: 「결여가 너무 심함 … 결여가 너무 일정함」; Q4: 「기울기가
  // 단계를 고르고, 그 단계 안에서 여러 장 중 무작위」). The height's cut left
  // the same valleys bare stroke after stroke and broke a light line into
  // dashes. Now the lean picks the step, each dab throws one of its three
  // faces, whose rims chip differently, and the tooth multiplies: each
  // density is how much paper a light touch leaves showing, and
  // [_toothRow] how much of it a full press still does. ⚠️The flows fell
  // with it (to 0.3–0.45): a multiplied tooth only slows how fast a pixel
  // piles up to its ceiling (`settledDabAlpha`), so at the old flows the
  // dozen stamps a pixel takes along one stroke filled the valleys before
  // the stroke ended — 4B laid flat black (📏F-456 probe, the same stroke).
  //
  // ↩️CRUMBS AT RANDOM, ON A PAPER CUT BY ITS HEIGHT, AND NO LEAN (F-462 ②,
  // 유저 2026-10-25: 「클튜 연필브러시들은 육각형식으로 안하니까 그거 참고해서
  // 다시 개편. 육각형같은거 잊어도됨. 일반연필 기울기에따라 뭐 바뀐다거나 다
  // 잊고」). Clip Studio's pencils throw one of a few irregular tips a dab,
  // turned at random, and cut their paper dab by dab. These do it with parts
  // of their own: three crumbs ([pencilCrumbBrushTipMasks]) thrown at random
  // and turned all the way round, on the graphite tooth worked by its height
  // and reached deeper the harder the pen presses ([_reachRow]) — so each
  // density is how deep a full press reaches, and the softer the lead the
  // deeper. The lead's six footprints and the lean rows are the tilted
  // pencil's alone. 🔬Drawn beside the user's Clip Studio 鉛筆 line
  // (`pencil_subtract`, the dual-off column, by eye): multiplied, the grades
  // laid a smooth tone under a faint tooth; cut by the height they break
  // into its dense speck, a light line into scattered grain.
  BrushPreset(
    id: const BrushPresetId('builtin-hard-pencil'),
    name: '2H Pencil',
    groupId: _pencilGroup,
    settings: BrushSettings(
      size: 3,
      hardness: 1.0,
      flow: 0.5,
      opacity: 0.6,
      spacing: BrushShape.minSpacing,
      tips: pencilCrumbBrushTipMasks,
      tipOrder: BrushTipOrder.random,
      angleJitter: 1.0,
      textureMaskSource: graphiteToothTextureMask,
      textureScale: 1.0,
      textureDensity: 0.88,
      textureMode: BrushTextureMode.height,
      sizePressureCurve: BrushPressureCurve.linearFrom(0.5),
      opacityPressureCurve: BrushPressureCurve.linearFrom(0.85),
      curves: _reachRow(0.6),
    ),
  ),
  BrushPreset(
    id: const BrushPresetId('builtin-pencil'),
    name: 'HB Pencil',
    groupId: _pencilGroup,
    settings: BrushSettings(
      size: 4,
      hardness: 0.95,
      flow: 0.5,
      opacity: 0.75,
      spacing: BrushShape.minSpacing,
      tips: pencilCrumbBrushTipMasks,
      tipOrder: BrushTipOrder.random,
      angleJitter: 1.0,
      textureMaskSource: graphiteToothTextureMask,
      textureScale: 1.0,
      textureDensity: 0.92,
      textureMode: BrushTextureMode.height,
      sizePressureCurve: BrushPressureCurve.linearFrom(0.4),
      opacityPressureCurve: BrushPressureCurve.linearFrom(0.8),
      curves: _reachRow(0.62),
    ),
  ),
  BrushPreset(
    id: const BrushPresetId('builtin-soft-pencil'),
    name: '2B Pencil',
    groupId: _pencilGroup,
    settings: BrushSettings(
      size: 6,
      hardness: 0.85,
      flow: 0.55,
      opacity: 0.88,
      spacing: BrushShape.minSpacing,
      tips: pencilCrumbBrushTipMasks,
      tipOrder: BrushTipOrder.random,
      angleJitter: 1.0,
      textureMaskSource: graphiteToothTextureMask,
      textureScale: 1.1,
      textureDensity: 0.96,
      textureMode: BrushTextureMode.height,
      sizePressureCurve: BrushPressureCurve.linearFrom(0.35),
      opacityPressureCurve: BrushPressureCurve.linearFrom(0.75),
      curves: _reachRow(0.65),
    ),
  ),
  BrushPreset(
    id: const BrushPresetId('builtin-dark-pencil'),
    name: '4B Pencil',
    groupId: _pencilGroup,
    settings: BrushSettings(
      size: 8,
      hardness: 0.75,
      flow: 0.6,
      spacing: BrushShape.minSpacing,
      tips: pencilCrumbBrushTipMasks,
      tipOrder: BrushTipOrder.random,
      angleJitter: 1.0,
      textureMaskSource: graphiteToothTextureMask,
      textureScale: 1.2,
      textureDensity: 1.0,
      textureMode: BrushTextureMode.height,
      sizePressureCurve: BrushPressureCurve.linearFrom(0.3),
      opacityPressureCurve: BrushPressureCurve.linearFrom(0.7),
      curves: _reachRow(0.7),
    ),
  ),
  // 🚨THE USER'S OWN SHARP (유저 F-433, 2026-10-21: 「프리셋 기본 샤프 연필,
  // 내가 만든 샤프로 교체」). The values are what their exported brush
  // (`シャープ.anibrush`) carried — the preset as shipped, with what their hand
  // had set laid over it: the finer size, step and pressure rows, the
  // canvas weave at full density and no anti-alias. Its tilt is left as
  // they made it: a lead this thin has no side to lean on.
  // 🗣️All but its blend (F-433-Q1, 유저 2026-10-21: 「뒤에는 내가 잘못
  // 지정한채로 내보낸거임. 블렌드는 표준. 기본aa는 없음」) — the file's 뒤에
  // (behind) was a slip, so it blends like every pencil.
  // ↩️No anti-alias was barred from every preset (board F-218, 09-28: a
  // pixel line is the 없음 step any brush can take), and the same answer
  // lifted it: 「aa없는 프리셋을 금지한다고 내가 발언했다면 지금 철회함.
  // 브러시 개성에 맞춰서 없거나 1단계거나 다르게 하는거 가능. 중요한건 개성」.
  BrushPreset(
    id: const BrushPresetId('builtin-mechanical-pencil'),
    name: 'Mechanical Pencil',
    groupId: _pencilGroup,
    settings: BrushSettings(
      size: 1.5,
      hardness: 1.0,
      spacing: 0.0207,
      textureMaskSource: canvasWeaveTextureMask,
      textureScale: 1.0,
      textureDensity: 1.0,
      sizePressureCurve: BrushPressureCurve.linearFrom(0.7083),
      opacityPressureCurve: BrushPressureCurve.linearFrom(0.4821),
      antiAlias: BrushAntiAlias.none,
    ),
  ),
  // The colored pencil throws the graphite's crumbs (F-462 ②) but keeps its
  // paper MULTIPLIED — my call, not the user's: wax spreads over the tooth
  // where graphite only catches its peaks, so it pales and fills instead of
  // breaking into grain, and the two stay apart in the picker.
  BrushPreset(
    id: const BrushPresetId('builtin-colored-pencil'),
    name: 'Colored Pencil',
    groupId: _pencilGroup,
    settings: BrushSettings(
      size: 6,
      flow: 0.4,
      spacing: BrushShape.minSpacing,
      tips: pencilCrumbBrushTipMasks,
      tipOrder: BrushTipOrder.random,
      angleJitter: 1.0,
      textureMaskSource: graphiteToothTextureMask,
      textureScale: 1.4,
      textureDensity: 0.9,
      opacityPressureCurve: BrushPressureCurve.identity(),
      curves: _toothRow(0.65),
    ),
  ),
  // 🚨THE USER'S COLOURING PENCIL (유저 F-433: 「색연필 샤프도 내가 만든거
  // 프리셋에 등록 … 눕힌 연필같은식으로 연필느낌나는 칠하는 연필」). Its size,
  // flow, step, both pressure rows and the dab turned at random every stamp
  // are what their `色鉛筆シャープ.anibrush` carried. ⛔ITS TIP IS NOT: theirs
  // was taken from another program's brush, so this one wears a scumble
  // generated here to the same purpose ([colorClumpBrushTipMask]).
  BrushPreset(
    id: const BrushPresetId('builtin-coloring-pencil'),
    name: 'Coloring Pencil',
    groupId: _pencilGroup,
    settings: BrushSettings(
      size: 454,
      hardness: 1.0,
      spacing: 0.0398,
      angleJitter: 1.0,
      tips: [colorClumpBrushTipMask],
      sizePressureCurve: BrushPressureCurve(const [
        BrushCurvePoint(0.0, 0.1488),
        BrushCurvePoint(0.5247, 0.3274),
        BrushCurvePoint(0.8333, 0.7798),
        BrushCurvePoint(1.0, 1.0),
      ]),
      opacityPressureCurve: BrushPressureCurve(const [
        BrushCurvePoint(0.0, 0.0),
        BrushCurvePoint(0.4012, 0.2083),
        BrushCurvePoint(0.7037, 0.6607),
        BrushCurvePoint(1.0, 1.0),
      ]),
    ),
  ),
  // 🚨THE PENCIL LAID ON ITS SIDE (board F-218, 유저: 「각도에 따라 눕히는
  // 연필. 연필 눕혀서 그리기도 하잖아 아날로그에서. 그런거 그대로 재현한
  // 연필」). Upright it draws a line; leaned over, the side of the lead
  // spreads the same graphite wide.
  //
  // ↩️F-176-Q4 (유저 2026-10-18): 「세워서그리면 얇은선, 눕혀서 그리면 연필처럼
  // dab이 길어지는? 그런거 기대했는데 전혀아니고 펜 실제 각도에 따라 dab 각도
  // 바뀌는건가했는데 그거조차도아님. 가능하도록」. It used to hold a FIXED
  // 35° tip squashed to 0.55 whatever the pen did, so leaning only made it
  // bigger. Now the tip turns with the pen's lean (ペンの方向) and squashes
  // as it lies down: round under an upright pen, a mark four times as long
  // as it is wide along the way the pen leans when it is flat.
  //
  // ↩️UPRIGHT IS THE THINNEST NOW, and the size is what it lays FLAT (유저
  // F-433, 2026-10-21: 「최대한 세우면 최대한 dab이 얇은? 느낌이어야하고
  // 기울일수록 커지고 원형률 바뀌고 해야함. 후자는 되는데 세웠을때 얇은게
  // 안되있음」). The tilt size row's 最小値 was 100% — "lean 0.0 is where a
  // pen held UPRIGHT sits … lower it and this brush draws below its size for
  // anyone who holds the stylus straight" — and that is exactly what the user
  // asked of this one brush: held straight it is the point of the lead.
  // ↩️And its tone answers the PRESSURE alone (「불투명도 제한같은거? 기울기
  // 이런거 걸어놧는데, 없애고 똑같이 불투명도 필압으로 하는게 좋을듯. 그게
  // 리얼한 느낌나니까」): the tilt rows that paled it and softened its edge as
  // it lay down are gone — a lead's side cuts as hard as its point.
  BrushPreset(
    id: const BrushPresetId('builtin-shading-pencil'),
    name: 'Tilted Pencil',
    groupId: _pencilGroup,
    settings: BrushSettings(
      size: 48,
      hardness: 1.0,
      flow: 0.35,
      spacing: BrushShape.minSpacing,
      rotationMode: BrushTipRotationMode.penTilt,
      tips: pencilLeadBrushTipMasks,
      tipOrder: BrushTipOrder.lean,
      tipsPerTurn: pencilLeadFacesPerStep,
      textureMaskSource: graphiteToothTextureMask,
      textureScale: 1.0,
      textureDensity: 0.9,
      curves: {
        (BrushPressureTarget.size, BrushInputSource.pressure):
            BrushPressureCurve.linearFrom(0.8),
        (BrushPressureTarget.opacity, BrushInputSource.pressure):
            BrushPressureCurve.linearFrom(0.15),
        // ↩️It paled its FLOW by pressure, 「light pressure catches only the
        // tooth's peaks」 — which flow cannot do: it thins every pixel alike.
        // The tooth does (F-451, F-456).
        ..._toothRow(0.5),
        (BrushPressureTarget.size, BrushInputSource.tilt): BrushPressureCurve(
          _leaningIn,
          minimum: 0.08,
        ),
        // Lying down, the lead's side is long and narrow: four times as long
        // as it is wide when it is flat.
        (BrushPressureTarget.roundness, BrushInputSource.tilt):
            BrushPressureCurve(_leaningOut, minimum: 0.25),
      },
    ),
  ),
  // 🗣️THE ROUGH EDGE IS A PENCIL (F-462, 유저 2026-10-25: 「거친 가장자리는
  // 연필로서 연필그룹에 등록. 이름은 알아서. 거친연필? 이거는 참고로 후술할
  // 연필개편에 포함되지않음」) — the Texture group's Rough Edge, moved here
  // under a pencil's name and left as it drew: the pencil rework that
  // follows does not touch it. The id stays, as the rounds' did (F-218).
  BrushPreset(
    id: const BrushPresetId('builtin-rough-edge'),
    name: 'Rough Pencil',
    groupId: _pencilGroup,
    settings: BrushSettings(
      size: 22,
      hardness: 0.9,
      flow: 1.0,
      spacing: 0.1,
      tips: [chalkBrushTipMask],
      // The EDGE is what varies, not the fill: roundness jitter chews the
      // silhouette while the dual grain keeps the inside from going flat.
      curves: _randomRows(roundness: 0.45),
      angleJitter: 0.5,
      dualMask: grainBrushTipMask,
      // 🎨THE SECOND TIP IS A STROKE OF ITS OWN (an-imported-pencil-drops-
      // its-second-brush-Q3, 10-29): its stamps pile on a plane of their
      // own, so laid as close as the first tip's they fill it and the grain
      // is gone. As big as the tip, half a tip apart and each turned at
      // random, the grain stays — the six dual brushes' before and after
      // are on that card.
      dualMaskScale: 1.2,
      dualSpacing: 0.5,
      dualAngleJitter: 1.0,
      dualDensity: 0.6,
    ),
  ),

  // ---- Pen -------------------------------------------------------------
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
  // 🚨A BRUSH PEN IS NOT A SOFTER G-PEN (board F-218: the two drew nearly
  // the same row, 4.3 levels apart). Its tip is felt or hair: the line leaves
  // the paper as a hairline and swells late and wide — so the edge is softer
  // and the swell is an S.
  // 🗣️A LIGHT TOUCH LAYS THINNER INK, as the F-218 proposal had it, and at
  // an edge of none too (유저 2026-10-02, brush-pen-wet-ink-Q1: 「G펜처럼
  // 진짜 aa가 필요없는 알기쉬운펜만 aa껐을때 2치화되있으면되. 그 외는 브러시
  // 개성따라 넣어도 전혀문제없어. 개성이 젤 중요」). ↩️It shipped without the
  // flow curve so H39 (「aa off시엔 진짜 안티앨리어싱 완전없었으면」) could
  // hold it among the round pens; the answer took it out of that list.
  BrushPreset(
    id: const BrushPresetId('builtin-brush-pen'),
    name: 'Brush Pen',
    groupId: _penGroup,
    settings: BrushSettings(
      size: 14,
      hardness: 0.7,
      spacing: BrushShape.minSpacing,
      flowPressureCurve: BrushPressureCurve.linearFrom(0.6),
      sizePressureCurve: BrushPressureCurve(const [
        BrushCurvePoint(0.0, 0.02),
        BrushCurvePoint(0.3, 0.1),
        BrushCurvePoint(0.7, 0.55),
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
  // 🗣️A MARKER IS A TRANSPARENT INK ON A CHISEL NIB (the-gouache-is-a-
  // round-with-a-weave-Q5, 유저 2026-10-24: 「곱하기 + 끌 촉(45°)」). Laid over
  // another colour it darkens it — blue over yellow is a deep green — and the
  // nib held at 45° draws wide one way and thin the other. ↩️It was a
  // translucent round that let 30% of what lay under it through. The cost
  // was said with the choice: a light colour does not show over a dark one,
  // as with a real marker.
  BrushPreset(
    id: const BrushPresetId('builtin-marker'),
    name: 'Marker',
    groupId: _penGroup,
    settings: BrushSettings(
      size: 16,
      hardness: 0.9,
      opacity: 0.8,
      flow: 0.6,
      spacing: BrushShape.minSpacing,
      blendMode: BrushBlendMode.multiply,
      roundness: 0.45,
      angleDegrees: 45,
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
    id: const BrushPresetId('builtin-dry-ink'),
    name: 'Dry Ink',
    groupId: _penGroup,
    settings: BrushSettings(
      size: 10,
      hardness: 1.0,
      flow: 0.95,
      spacing: 0.05,
      // The break in the line is the dual tip, not the flow: a hard nib
      // running out of ink skips, it does not fade. Thrown a third of a tip
      // off the line, the grain lands thin in places and the nib skips
      // there (the second tip's way: Rough Pencil's note).
      dualMask: grainBrushTipMask,
      dualMaskScale: 1.2,
      dualSpacing: 0.4,
      dualAngleJitter: 1.0,
      dualScatterRadiusRatio: 0.3,
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
      tips: [chalkBrushTipMask],
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
      tips: [chalkBrushTipMask],
      // A whole tip apart and larger than the stick, the grain piles once
      // and the stroke stays light and clouded (the second tip's way: Rough
      // Pencil's note).
      dualMask: grainBrushTipMask,
      dualMaskScale: 1.5,
      dualSpacing: 1.0,
      dualAngleJitter: 1.0,
      dualScatterRadiusRatio: 0.15,
      textureMaskSource: paperGrainTextureMask,
      textureScale: 1.8,
      textureDensity: 0.75,
      curves: _randomRows(size: 0.2, spacing: 0.35),
      // ⚠️Spacing's ランダム row is thrown once per SEGMENT, not per dab — the
      // stick catches and skips along the paper rather than shivering in
      // place. That is the right grain for charcoal, so nobody should "fix"
      // it into a per-dab roll.
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
      tips: [chalkBrushTipMask],
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
      flow: 0.8996,
      spacing: 0.07,
      tips: [grainBrushTipMask],
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
      flow: 0.8233,
      spacing: 0.08,
      // ⚠️Roundness squashes a MASKED tip too — the mask sampler divides by
      // it the same way the analytic ellipse does — and the panel's tip icon
      // draws the ellipse, so the row shows the flat edge.
      roundness: 0.35,
      angleDegrees: 20,
      rotationMode: BrushTipRotationMode.fixed,
      tips: [grainBrushTipMask],
      textureMaskSource: paperGrainTextureMask,
      textureScale: 2.0,
      textureDensity: 0.6,
      sizePressureCurve: BrushPressureCurve.linearFrom(0.6),
      opacityPressureCurve: BrushPressureCurve.linearFrom(0.35),
    ),
  ),

  // ---- Watercolor ------------------------------------------------------
  // 🚨A WATERCOLOUR HERE IS CLEAN, AND ONE IS ANALOGUE (board F-218, 유저:
  // 「수채브러시에 질감있는것도 그냥 한없이 의문임. 질감 있다면 그냥 수채가
  // 아니라 아날로그 수채라던가 이런식으로 하고 질감도 진짜 아날로그질감
  // 종이질감」). The digital washes carry no paper; the paper — cold-press
  // tooth, not the generic grain — lives on Analog Watercolor alone.
  BrushPreset(
    id: const BrushPresetId('builtin-watercolor'),
    name: 'Watercolor',
    groupId: _watercolorGroup,
    settings: BrushSettings(
      size: 28,
      hardness: 0.3,
      flow: 0.5774,
      opacity: 0.8,
      spacing: BrushShape.minSpacing,
      opacityPressureCurve: BrushPressureCurve.identity(),
    ),
  ),
  BrushPreset(
    id: const BrushPresetId('builtin-analog-watercolor'),
    name: 'Analog Watercolor',
    groupId: _watercolorGroup,
    settings: BrushSettings(
      size: 28,
      hardness: 0.3,
      // ⚠️Lower than Watercolor's on purpose: the paper multiplies every
      // dab, and a pile that reaches the stroke's ceiling has no tooth left
      // to show — at Watercolor's flow the hollows and the crowns both
      // filled (measured as it shipped, board F-218).
      flow: 0.4261,
      opacity: 0.8,
      spacing: BrushShape.minSpacing,
      textureMaskSource: coldPressTextureMask,
      textureScale: 1.0,
      textureDensity: 1.0,
      opacityPressureCurve: BrushPressureCurve.identity(),
    ),
  ),
  BrushPreset(
    id: const BrushPresetId('builtin-wet-watercolor'),
    name: 'Wet Watercolor',
    groupId: _watercolorGroup,
    settings: BrushSettings(
      size: 34,
      flow: 0.5775,
      opacity: 0.8,
      spacing: 0.05,
      // The wet edge lives in the TIP, not in a new engine field.
      tips: [wetBlotBrushTipMask],
      angleJitter: 1.0,
      curves: _randomRows(size: 0.2),
      // ⚠️The blend is applied ONCE per stroke at pen-up, so washes darken
      // stroke over stroke — which is what layering washes does — while a
      // single stroke crossing itself stays even, which is what one wet pass
      // does. Both halves of that are correct here; neither is a bug.
      blendMode: BrushBlendMode.multiply,
      mixesGroundColor: true,
      colorStretch: 0.64,
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
      flow: 0.9375,
      opacity: 0.9,
      spacing: BrushShape.minSpacing,
      mixesGroundColor: true,
      colorStretch: 0.5441,
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
      flow: 0.6392,
      opacity: 0.75,
      spacing: BrushShape.minSpacing,
      // A wide flat sable held square to the paper: the angle stays put so
      // the band keeps one width across the sweep.
      //
      // 🗣️Turned to 90° (the-gouache-is-a-round-with-a-weave-Q6, 유저
      // 2026-10-24: 「90° 로 돌려 둔다」): a wash is swept sideways, and at 0°
      // the flat lay along the sweep and drew a line a fifth of its size.
      // A sideways sweep lays the wide band now, a downward one the line.
      roundness: 0.2,
      angleDegrees: 90,
      rotationMode: BrushTipRotationMode.fixed,
      mixesGroundColor: true,
      colorStretch: 0.8494,
      paintAmount: 0.9,
      paintDensity: 0.7,
      opacityPressureCurve: BrushPressureCurve.identity(),
    ),
  ),

  // ---- Oil -------------------------------------------------------------
  BrushPreset(
    id: const BrushPresetId('builtin-flat-bristle'),
    name: 'Flat Bristle',
    groupId: _oilGroup,
    settings: BrushSettings(
      size: 22,
      flow: 0.9375,
      spacing: 0.05,
      roundness: 0.3,
      angleDegrees: 45,
      tips: [bristleBrushTipMask],
      sizePressureCurve: BrushPressureCurve.linearFrom(0.6),
    ),
  ),
  BrushPreset(
    id: const BrushPresetId('builtin-gouache'),
    name: 'Gouache',
    groupId: _oilGroup,
    // 🗣️A DRY BRUSH: where it touches it covers, opaque and flat, and only
    // where it does not is the paper bare (유저 2026-10-24, the-gouache-is-
    // a-round-with-a-weave-Q2 → a). Pressed hard it reaches the paper's
    // valleys; pressed lightly only its peaks take paint. ↩️It was a hard
    // round under a canvas weave multiplied at 0.5, which a stroke piled to
    // the ceiling — a Hard Round in every picture (유저 10-23: 「뭐가
    // 과슈인지?」). ⛔Multiplied paper turned a light stroke translucent, a
    // watercolour's; the weave in height read as a stamp's print.
    // ⚠️Chosen with its cost said: a light stroke laid again leaves the same
    // valleys bare — F-456's complaint on the pencils — and pressing harder
    // fills them.
    settings: BrushSettings(
      size: 20,
      hardness: 0.85,
      flow: 0.9784,
      spacing: BrushShape.minSpacing,
      textureMaskSource: paperGrainTextureMask,
      textureScale: 1.5,
      textureMode: BrushTextureMode.height,
      sizePressureCurve: BrushPressureCurve.linearFrom(0.6),
      curves: {
        (BrushPressureTarget.textureDensity, BrushInputSource.pressure):
            BrushPressureCurve.linearFrom(0.2),
      },
    ),
  ),
  BrushPreset(
    id: const BrushPresetId('builtin-oil-brush'),
    name: 'Oil Brush',
    groupId: _oilGroup,
    settings: BrushSettings(
      size: 26,
      flow: 0.9975,
      spacing: BrushShape.minSpacing,
      tips: [bristleBrushTipMask],
      // Bristles rake along the stroke, so the tip turns with it.
      rotationMode: BrushTipRotationMode.direction,
      textureMaskSource: canvasWeaveTextureMask,
      textureScale: 1.2,
      textureDensity: 0.4,
      // ⚠️Roundness's ランダム row only ever SHRINKS — the bundle splays
      // thinner, never fatter — which is why a floor this high still reads.
      curves: _randomRows(roundness: 0.2),
      // Loaded paint picks up what it crosses.
      mixesGroundColor: true,
      colorStretch: 0.7349,
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
      colorStretch: 0.75,
      paintAmount: 0.95,
      paintDensity: 1.0,
    ),
  ),
  // ⚠️A DRY BRUSH STILL HAS TO SHOW (board F-218: its row laid 2% ink — the
  // sponge at full density ate nearly every dab). The sponge bites at a
  // little over half, so the stroke breaks into dry streaks instead of
  // vanishing.
  BrushPreset(
    id: const BrushPresetId('builtin-dry-brush'),
    name: 'Dry Brush',
    groupId: _oilGroup,
    settings: BrushSettings(
      size: 30,
      flow: 0.9009,
      spacing: 0.06,
      tips: [bristleBrushTipMask],
      rotationMode: BrushTipRotationMode.direction,
      // Twice the bristles' width, so the sponge's streaks run the whole
      // stroke: at 0.75 its second stroke bit only the middle (the second
      // tip's way: Rough Pencil's note).
      dualMask: spongeBrushTipMask,
      dualMaskScale: 2.0,
      dualSpacing: 0.06,
      dualDensity: 0.55,
      curves: _randomRows(spacing: 0.4, opacity: 0.2),
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
      flow: 0.2259,
      opacity: 0.9,
      // Tight spacing is what makes an airbrush build rather than band.
      spacing: BrushShape.minSpacing,
      opacityPressureCurve: BrushPressureCurve.identity(),
    ),
  ),
  // ↩️SPRAY IS GONE (board F-218). It was kept apart from Airbrush by its
  // texture scale alone — 0.7, a ~45px grain meant to read as speckle — and
  // measured it did not: its row stood 2.2 levels from Airbrush's, the
  // closest pair in the whole roster. Speckle is Grit Spray's.
  BrushPreset(
    id: const BrushPresetId('builtin-grit-spray'),
    name: 'Grit Spray',
    groupId: _airbrushGroup,
    settings: BrushSettings(
      size: 36,
      hardness: 0.35,
      flow: 0.51,
      opacity: 0.85,
      spacing: 0.05,
      // Small grit thrown far, two at a stamp, and short of full density,
      // so the spray's soft body shows between (the second tip's way: Rough
      // Pencil's note).
      dualMask: splatterBrushTipMask,
      dualMaskScale: 0.6,
      dualSpacing: 0.5,
      dualAngleJitter: 1.0,
      dualScatterRadiusRatio: 0.8,
      dualScatterCount: 2,
      dualDensity: 0.8,
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
      flow: 0.91,
      spacing: 0.05,
      mixesGroundColor: true,
      // 🚨STRETCH 0.35, NEVER 1.0 — and this is arithmetic, not taste. The
      // reservoir is re-sampled every dab as `lerp(reservoir, ground,
      // stretch × coverage)` and then deposited as `lerp(ground, reservoir,
      // amount)`. At stretch 1.0 the reservoir BECOMES the ground each dab,
      // so the deposit is the colour that was already there: a provable
      // identity, i.e. an invisible brush. The smear IS the reservoir's lag,
      // so the stretch has to stay moderate.
      colorStretch: 0.5775,
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
      flow: 0.51,
      spacing: 0.05,
      textureMaskSource: paperGrainTextureMask,
      textureScale: 2.6,
      textureDensity: 0.6,
      mixesGroundColor: true,
      colorStretch: 0.51,
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
      flow: 0.5111,
      spacing: 0.05,
      tips: [grainBrushTipMask],
      textureMaskSource: paperGrainTextureMask,
      textureScale: 1.3,
      textureDensity: 0.5,
      mixesGroundColor: true,
      colorStretch: 0.4531,
      paintAmount: 1.0,
      paintDensity: 0.6,
      sizePressureCurve: BrushPressureCurve.linearFrom(0.5),
    ),
  ),
  // 🗣️I-75 (유저 2026-10-27, Q1 「섞기 그룹에 「흐리기」」): the blur, as a
  // setting of mixing rather than a tool. How far it smears is its size and
  // how hard it rubs its flow and the pen's pressure (Q3) — so pressure
  // drives the flow here.
  // At the finest step, as every general brush lays (the roster's law): a
  // blur dab costs far more than a paint dab, and that is the kernel's to
  // answer, not the step's (⛔해상도로 속도를 사지 않는다).
  BrushPreset(
    id: const BrushPresetId('builtin-blur'),
    name: 'Blur',
    groupId: _blendGroup,
    settings: BrushSettings(
      size: 40,
      hardness: 0.3,
      flow: 0.3,
      spacing: BrushShape.minSpacing,
      mixesGroundColor: true,
      mixingMethod: BrushMixingMethod.blur,
      flowPressureCurve: BrushPressureCurve.identity(),
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
      tips: [splatterBrushTipMask],
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
      curves: _randomRows(size: 0.5, opacity: 0.4),
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
      tips: [spongeBrushTipMask],
      // A clump that landed the same way twice would read as a pattern.
      angleJitter: 1.0,
      curves: _randomRows(size: 0.25),
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
      tips: [spongeBrushTipMask],
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
  // ↩️HATCHING WENT (F-462, 유저 2026-10-25: 「좋은것들은 좋은데 안좋은건 고쳐도
  // 안좋으니 정리. 우선 텍스처의 해칭 삭제」): the bristle tip held at 45°,
  // its marks parted at half its size after the-gouache-is-a-round-with-a-
  // weave-Q4 (10-24) — short soft pieces, never the long parallels a
  // hatching pass is. The Rough Edge beside it went to the pencils.
  BrushPreset(
    id: const BrushPresetId('builtin-concrete'),
    name: 'Concrete',
    groupId: _textureGroup,
    settings: BrushSettings(
      size: 20,
      hardness: 1.0,
      flow: 0.9775,
      spacing: 0.05,
      // A little larger than the tip, and turned at random (the second
      // tip's way: Rough Pencil's note).
      dualMask: chalkBrushTipMask,
      dualMaskScale: 1.2,
      dualSpacing: 0.4,
      dualAngleJitter: 1.0,
      textureMaskSource: canvasWeaveTextureMask,
      textureScale: 0.8,
      textureDensity: 0.75,
      curves: _randomRows(roundness: 0.3),
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
      size: 30,
      hardness: 1.0,
      flow: 0.95,
      spacing: 0.45,
      // A tuft of its own (F-462 ③): its blades rise from their own places
      // and lean their own ways. ↩️It threw the leaf's lens five at a time
      // across the stroke, and every dab stood as one column of blades end
      // to end — 「너무 일직선」 (유저 2026-10-25).
      tips: [grassClumpBrushTipMask],
      // Tufts stand UP and lean a little, so the tip follows the stroke
      // rather than the fixed angle a fallen-leaf pile wants. The tuft rises
      // up its mask, so a sideways sweep stands it upright as it is.
      // ↩️It wore roundness 0.35 at 90°: the squeeze takes the mask's
      // height and every blade landed a round dot (measured 10-24, the-
      // gouache-is-a-round-with-a-weave's sweep).
      rotationMode: BrushTipRotationMode.direction,
      angleJitter: 0.08,
      curves: _randomRows(size: 0.45),
      scatterRadiusRatio: 0.35,
      scatterCount: 2,
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
      tips: [starBrushTipMask],
      angleJitter: 0.25,
      curves: _randomRows(size: 0.6, opacity: 0.4),
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
      tips: [flakeBrushTipMask],
      // ⚠️A flake has six-fold symmetry, so a full half-turn of jitter says
      // the same thing twice — a sixth of a turn is all the variety there is.
      angleJitter: 0.17,
      curves: _randomRows(size: 0.55, opacity: 0.3),
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
      tips: [ringBrushTipMask],
      curves: _randomRows(size: 0.65, opacity: 0.35),
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
      tips: [leafBrushTipMask],
      // ⛔The opposite of Grass on purpose: leaves lie at every angle and
      // grass stands up — what a full turn of angle jitter buys, and what
      // keeps the two rows from being one brush wearing two names. ↩️They
      // shared this tip until F-462 ③ (2026-10-29): a leaf stood upright
      // read as a picket fence, so Grass draws its own fanned tuft now.
      angleJitter: 1.0,
      curves: _randomRows(size: 0.5, roundness: 0.25),
      scatterRadiusRatio: 1.5,
      scatterCount: 4,
    ),
  ),
];

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
