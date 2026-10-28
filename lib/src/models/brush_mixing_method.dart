/// What a brush with 混色 on does with the picture under it.
///
/// 🗣️I-75 (유저 2026-10-27): the blur brush lives in the mixing group as
/// 「흐리기」 (Q1), with no slider of its own — its radius is the brush's
/// size and its strength the flow and the pressure (Q3) — and it blurs
/// further the more it is rubbed (Q4).
enum BrushMixingMethod {
  /// 下地混色 — the brush carries a reservoir that picks colour up from the
  /// cel and lays a blend of the two back down ([BrushShape.paintAmount],
  /// [BrushShape.paintDensity], [BrushShape.colorStretch]). Every mixing
  /// brush meant this before I-75.
  mix,

  /// ぼかし — the brush lays no colour: each dab moves the picture under it
  /// toward that picture blurred, by what the dab would have laid as paint.
  /// The law is beside `BrushBlurPicture`.
  blur;

  static BrushMixingMethod fromName(Object? name) =>
      values.asNameMap()[name] ?? mix;
}
