import 'brush_settings_group.dart';

/// One row of a brush's settings, in the order the tool settings panel
/// lists them, and the [group] the brush detail window files it under.
///
/// 🗣️I-141 (유저 2026-10-29): a brush shows in the panel only the rows it
/// SHOWS ([BrushSettings.shown]), chosen in the brush detail window — Clip
/// Studio's way (Q1 ⓐ 「클튜식 — 상세 창에서 고른다」) — in the panel's own
/// order (Q2 「패널 본래 순서 그대로」), with no group heads: 「클튜처럼
/// 보이도록 고정한 항목은 항목헤더같은거 표시안함. 멤버만 심플하게 하나씩
/// 보여주는느낌」.
///
/// ⚠️THE ORDER OF THE VALUES IS THE PANEL'S ORDER — both the panel and the
/// window walk [values], so moving a row here moves it on screen.
/// ⚠️THE NAMES ARE WRITTEN IN BRUSH FILES: renaming a value drops it from
/// every brush that showed it.
enum BrushSettingsRow {
  flow(BrushSettingsGroup.ink),
  tip(BrushSettingsGroup.tip),
  tipOrder(BrushSettingsGroup.tip),
  tipsPerTurn(BrushSettingsGroup.tip),
  hardness(BrushSettingsGroup.tip),
  antiAlias(BrushSettingsGroup.tip),
  roundness(BrushSettingsGroup.tip),
  angle(BrushSettingsGroup.tip),
  spacing(BrushSettingsGroup.tip),
  mixing(BrushSettingsGroup.mixing),
  mixingMethod(BrushSettingsGroup.mixing),
  paintAmount(BrushSettingsGroup.mixing),
  paintDensity(BrushSettingsGroup.mixing),
  colorStretch(BrushSettingsGroup.mixing),
  scatter(BrushSettingsGroup.scattering),
  scatterCount(BrushSettingsGroup.scattering),
  scatterBothAxes(BrushSettingsGroup.scattering),
  dualTip(BrushSettingsGroup.texture),
  dualScale(BrushSettingsGroup.texture),
  dualDensity(BrushSettingsGroup.texture),
  dualBlend(BrushSettingsGroup.texture),
  dualRoundness(BrushSettingsGroup.texture),
  dualAngle(BrushSettingsGroup.texture),
  dualSpacing(BrushSettingsGroup.texture),
  dualScatter(BrushSettingsGroup.texture),
  dualScatterCount(BrushSettingsGroup.texture),
  dualScatterBothAxes(BrushSettingsGroup.texture),
  texture(BrushSettingsGroup.texture),
  textureScale(BrushSettingsGroup.texture),
  textureDensity(BrushSettingsGroup.texture),
  textureMode(BrushSettingsGroup.texture),
  textureInvert(BrushSettingsGroup.texture),
  textureBrightness(BrushSettingsGroup.texture),
  textureContrast(BrushSettingsGroup.texture),
  sharpenCorners(BrushSettingsGroup.correction),
  stabilizerOn(BrushSettingsGroup.correction),
  stabilizer(BrushSettingsGroup.correction),
  steadyingBySpeed(BrushSettingsGroup.correction),
  postCorrection(BrushSettingsGroup.correction),
  postBySpeed(BrushSettingsGroup.correction),
  postByViewScale(BrushSettingsGroup.correction),
  postBezier(BrushSettingsGroup.correction);

  const BrushSettingsRow(this.group);

  final BrushSettingsGroup group;

  /// What a brush shows when nothing says otherwise — a brush another
  /// app's file brought, or one whose own file names none: the three every
  /// brush is shown with (I-141, the three the user named — 손떨림 보정
  /// 적용 · 손떨림 보정 · 안티앨리어스).
  static const Set<BrushSettingsRow> shownByDefault = {
    antiAlias,
    stabilizerOn,
    stabilizer,
  };
}
