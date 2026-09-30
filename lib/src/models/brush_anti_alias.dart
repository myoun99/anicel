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
///
/// ↩️🚨★★★I-50 (유저 2026-09-30, 「경도와 따로 — 단계마다 고정 폭, 클튜 샘플로
/// 맞춤」 — after 「aa 값이 3인데도 너무 약함」): for an ANALYTIC round tip the
/// step is no longer a contrast on the hardness ramp. That ramp is zero wide
/// on a hardness-100% nib (G펜, 잉크 펜, 마루 펜 …), so tightening it did
/// nothing and every step drew the same staircase — what edge those pens had
/// was the stamp's bilinear sampling, about a pixel. The step now GIVES the
/// tip an edge [edgeWidth] canvas pixels wide INSIDE its rim: the rim stays
/// where the size puts it and the ramp grows inward — and where the hardness
/// ramp is the wider of the two, that ramp stands as it was.
/// ↩️「굵기 안바꾸고」 was first read as "half coverage stays put", and the
/// first cut of this law centred the ramp there. Measured against the
/// user's Clip Studio lines (`参考/brush/cls_gpen_AA.png`, board I-50) that
/// drew every line a pixel and more too thick; the lines fit a ramp that
/// ENDS at the rim — so the rim is the thickness that holds, and the
/// half-coverage width narrows with the step as Clip Studio's does. The
/// ladder `k` below stays for every other tip: a raster tip has no distance
/// to its edge to widen, and a square's edge was never widened.
enum BrushAntiAlias {
  /// 없음 — a hard edge. The ramp collapses to a threshold at half
  /// coverage, which is the cut this engine already uses for its own hard
  /// edges (`qa_engine.c`'s fill writes `coverage = 0.5 - d`).
  none,

  /// 1단계 — `k = 4` off a round tip.
  low,

  /// 2단계 — `k = 2` off a round tip.
  medium,

  /// 3단계 — `k = 1` off a round tip, the ramp it always had; on a round
  /// tip the widest edge ([edgeWidth]). A brush that says nothing is here.
  high;

  /// The contrast factor every tip but an analytic round one takes, or
  /// `null` for [none]'s threshold (`brushDabEdgeLaw` says which applies).
  double? get contrast => switch (this) {
    none => null,
    low => 4.0,
    medium => 2.0,
    high => 1.0,
  };

  /// How wide, in canvas pixels, the edge an ANALYTIC round tip is given at
  /// this step — the distance its coverage takes to fall from 1 at the hard
  /// radius to 0 at the rim. 0 for [none], whose cut happens after sampling.
  ///
  /// 📏Fitted 2026-10-01 (board I-50) to the user's Clip Studio G펜 lines at
  /// size 10, drawn through this engine's own stamp path — the 8-bit stamp,
  /// its bilinear sampling, the interpolator's 1px step — and compared by
  /// the lines' edge spread (RMS 2.2 · 4.5 · 3.6 of 255). ⚠️At size 50 Clip
  /// Studio's edge stays wider than these draw: the 1px step piles fifty
  /// stamps across a width Clip Studio covers with a handful, and the pile
  /// tightens every ramp — hardness ramps included (board I-50).
  double get edgeWidth => switch (this) {
    none => 0.0,
    low => 0.4375,
    medium => 1.875,
    high => 2.75,
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
