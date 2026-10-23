/// How a brush's paper texture meets the coverage of each dab — Clip
/// Studio's テクスチャ合成モード, Photoshop's texture Mode.
///
/// Both formats offer more (Clip Studio lists nine, Photoshop ten); this
/// engine draws the two a brush here asks for.
enum BrushTextureMode {
  /// The paper darkens the coverage by its density:
  /// `coverage * ((1 - density) + density * sample)`. Every brush drew this
  /// and only this before F-451, so the dab's silhouette is always the
  /// tip's own.
  multiply,

  /// 高さ — the paper's HEIGHT decides where the dab touches it: the
  /// texture's sample is how high the paper stands there, and the coverage
  /// times the density is how deep the dab reaches into it. Where the tip
  /// presses less — towards its rim — only the paper's peaks are reached,
  /// so the paper cuts into the silhouette itself (Clip Studio: 「ストロー
  /// クの縁にだけ」).
  ///
  /// 🗣️F-451 (유저 2026-10-23): 「사각형을 지키면서 질감으로 얼버무리고
  /// 있는거고. 그런 실루엣적인 변화를 원함」 — the line a real pencil
  /// leaves misses a pixel here and there at its edge, and a multiplied
  /// texture never can.
  ///
  /// ↩️No built-in pencil wears it since F-456 (유저 2026-10-23: 「결여가
  /// 너무 일정함(같은부분 다시 그려도 결여된 픽셀이 안채워짐)」): a valley
  /// deeper than the reach takes nothing at all, so the same pixels stay
  /// bare however often a line is laid again. Their edges break by the
  /// faces they throw per dab instead (`BrushShape.tipsPerTurn`).
  ///
  /// ⚠️THE DENSITY READS DIFFERENTLY HERE, as Photoshop's depth does under
  /// its Height mode: not how much of the paper shows, but how far the dab
  /// presses into it — at 0 it reaches nothing.
  height;

  static BrushTextureMode fromName(Object? name) =>
      values.asNameMap()[name] ?? multiply;
}
