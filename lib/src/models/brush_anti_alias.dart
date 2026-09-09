/// How hard a brush's own edge lands (유저 2026-09-08, 클튜 4단).
///
/// A dab's coverage ramp is what makes its edge soft: the pixels between
/// [BrushShape.hardness]'s inner disc and the outer radius fade out. This
/// tightens that ramp WITHOUT moving the radius — 유저, after drawing Clip
/// Studio's G펜 at all four settings and reading the tip preview at 354.3%:
/// 「브러시 팁 프리뷰 보니까 **굵기 안바꾸고 가장자리만 조이는거였어**」.
///
/// ⛔That sentence is what rules out the other shape this could have taken.
/// Photoshop-style "alpha threshold" (`a = a >= t ? 255 : 0` with a rising
/// t) also hardens the edge, but it THINS the stroke as it goes — the user
/// looked and it does not thin. So the law is a contrast remap about the
/// half-coverage radius, which is exactly the radius that stays put.
///
/// ⚠️NOT the same law as the FILL's `antiAlias` (`canvas_flood_fill.dart`),
/// which is a boolean soft pass over a REGION MASK — a different algorithm
/// on a different subject that happens to share the English word. They are
/// deliberately not unified; if one changes the other has no reason to.
///
/// The ladder is `k = ∞ / 4 / 2 / 1`. ⚠️**4 and 2 are a geometric placing,
/// not a measurement** — nothing in the repo, in Clip Studio's files, or in
/// anything the user said fixes the two middle values. They are settings, so
/// they get adjusted by drawing next to Clip Studio, not by inventing a
/// constant with more decimal places.
///
/// ⛔THIS USED TO SAY "NOT IMPORTED YET", and to suggest mapping Clip
/// Studio's column straight through as `BrushAntiAlias.values[index]`. Both
/// halves are dead: the column WAS dumped out of the user's real files the
/// next day and the import landed (`24050b58`, 2026-09-09), and the round
/// that wrote it REFUSED the `values[index]` shortcut on purpose — an
/// explicit table means reordering this enum cannot silently re-map every
/// imported brush. The verified decision, and exactly which of its claims
/// are measured, live with `_antiAliasOf` in `sut_decoder.dart`.
enum BrushAntiAlias {
  /// 없음 — a hard edge. The ramp collapses to a threshold at half
  /// coverage, which is the cut this engine already uses for its own hard
  /// edges (`qa_engine.c`'s fill writes `coverage = 0.5 - d`).
  none,

  /// 1단계 — `k = 4`.
  low,

  /// 2단계 — `k = 2`.
  medium,

  /// 3단계 — `k = 1`: the ramp the engine drew before this existed, so a
  /// brush that says nothing draws exactly as it always did.
  high;

  /// The contrast factor, or `null` for [none]'s threshold.
  ///
  /// ⚠️Read this ONCE per dab and hoist it — [applyTo] is the definition,
  /// not the hot path. `BrushDabPlan` keeps the hoisted pair.
  double? get contrast => switch (this) {
    none => null,
    low => 4.0,
    medium => 2.0,
    high => 1.0,
  };

  /// [coverage] with this edge applied. The definition of the law; the
  /// rasterizers inline it against hoisted values.
  double applyTo(double coverage) => switch (this) {
    none => coverage >= 0.5 ? 1.0 : 0.0,
    high => coverage,
    _ => ((coverage - 0.5) * contrast! + 0.5).clamp(0.0, 1.0).toDouble(),
  };

  String toJson() => name;

  /// The step written under [name], or null when it is absent or unknown.
  static BrushAntiAlias? named(String? name) {
    for (final step in values) {
      if (step.name == name) {
        return step;
      }
    }
    return null;
  }
}
