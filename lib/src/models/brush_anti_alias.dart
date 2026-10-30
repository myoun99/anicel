/// The edge an anti-alias step gives an analytic round tip
/// ([BrushAntiAlias.edge]): a ramp [width] wide, [widthPerRadius] wider a
/// pixel of radius up to a radius of [widthReach], ending [inset] inside
/// the rim, the inset in full from a radius of [insetReach] up.
typedef BrushTipEdge = ({
  double width,
  double widthPerRadius,
  double widthReach,
  double inset,
  double insetReach,
});

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
/// tip an edge ([edge]) canvas pixels wide INSIDE its rim: the rim stays
/// where the size puts it and the ramp grows inward — and where the hardness
/// ramp is the wider of the two, that ramp stands as it was.
/// ↩️「굵기 안바꾸고」 was first read as "half coverage stays put", and the
/// first cut of this law centred the ramp there. Measured against the
/// user's Clip Studio lines (`参考/brush/cls_gpen_AA.png`, board I-50) that
/// drew every line a pixel and more too thick; the lines fit a ramp that
/// ENDS at the rim — so the rim is the thickness that holds, and the
/// half-coverage width narrows with the step as Clip Studio's does. The
/// ladder `k` below stays for a square, whose edge was never widened.
/// ↩️It stayed for a raster tip too, until the greys of a pale tip turned
/// out to be what it was wiping ([brushDabEdgeLaw] has the measure).
enum BrushAntiAlias {
  /// 없음 — a hard edge. The ramp collapses to a threshold at half
  /// coverage, which is the cut this engine already uses for its own hard
  /// edges (`qa_engine.c`'s fill writes `coverage = 0.5 - d`).
  ///
  /// ⚠️The threshold cuts a raster tip's MASK coverage too, so a grain or
  /// chalk tip at 없음 is binarised whole — a preset that wants a pixel line
  /// pairs it with a plain round tip (written on Anime Pen until board
  /// F-218 retired that preset).
  none,

  /// 1단계 — `k = 4` on a square.
  low,

  /// 2단계 — `k = 2` on a square.
  medium,

  /// 3단계 — `k = 1` on a square, the ramp it always had; on a round tip
  /// the widest edge ([edge]). A brush that says nothing is here.
  high;

  /// The contrast factor a square takes, or `null` for [none]'s threshold
  /// (`brushDabEdgeLaw` says which applies).
  double? get contrast => switch (this) {
    none => null,
    low => 4.0,
    medium => 2.0,
    high => 1.0,
  };

  /// The edge an ANALYTIC round tip is given at this step: a ramp
  /// [BrushTipEdge.width] canvas pixels wide — and
  /// [BrushTipEdge.widthPerRadius] more for each pixel of radius, up to
  /// [BrushTipEdge.widthReach] — that ends [BrushTipEdge.inset] inside the
  /// rim, the inset shrinking with the radius below
  /// [BrushTipEdge.insetReach], so the finest nibs are a cone to the rim.
  /// Nothing for [none], whose cut happens after sampling.
  ///
  /// 📏Fitted 2026-10-25 (board a-one-pixel-dab-drops-out-by-where-it-lies,
  /// Q4 「AA 가장자리는 쌓이지 않는다」 · Q5 「100 · 300px 표본을 더 준다」) to
  /// the user's Clip Studio G펜 lines at sizes 1–8, 10, 50, 100 and 300 and
  /// every step — the ink of a line's column at 1–50, and the 10–90% and
  /// full edge bands at 10, 50, 100 and 300 — as a line whose cross-section
  /// is ONE dab's, as the pixel's square covers it: the edge does not pile
  /// ([tipCoverageAt] · [tipPileAt]). Clip Studio's edge widens with the
  /// size and then stops (3단계 10–90% about 1.3px at 10, 1.7 at 50, 1.9 at
  /// 100, 2.5 at 300; 2단계 1.8 at both 100 and 300): one width for every
  /// size left twice the error (0.95 against 0.48 over 1–50), and a width
  /// that went on widening drew 300 far too soft — the reach is where each
  /// step's stops.
  /// ⚠️Past 300 is unmeasured: the edge holds its width at 300's.
  /// ↩️Q4's fit stopped every step's widening at radius 25, the largest
  /// sample then (total error over the four band sizes 2.56 against 0.62).
  /// ↩️I-50's ramps 0.4375 · 1.6 · 2.75 wide ENDING at the rim (2026-10-01)
  /// were fitted at sizes 10 and 50 through a stamp path where every dab
  /// piled its edge too (`a_g_pen_edge_matches_clip_studio_test`); measured
  /// at every size of the samples they drew 약 a pixel too thick from 1.5px
  /// up, 중 half a pixel at 4–10px, and the 1px line at a quarter of Clip
  /// Studio's ink — and no width alone fitted every size, since a different
  /// number of dabs piled the edge at each.
  BrushTipEdge get edge => switch (this) {
    none => (
      width: 0.0,
      widthPerRadius: 0.0,
      widthReach: 0.0,
      inset: 0.0,
      insetReach: 1.0,
    ),
    low => (
      width: 0.44,
      widthPerRadius: 0.0045,
      widthReach: 120.0,
      inset: 0.30,
      insetReach: 1.2,
    ),
    medium => (
      width: 0.95,
      widthPerRadius: 0.019,
      widthReach: 60.0,
      inset: 0.17,
      insetReach: 2.0,
    ),
    high => (
      width: 1.25,
      widthPerRadius: 0.025,
      widthReach: 70.0,
      inset: 0.12,
      insetReach: 3.0,
    ),
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
