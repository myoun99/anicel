/// WHAT the two PIXEL verbs — 색 변환 and 픽셀 비우기 — would act on right now.
///
/// 유저 확정 2026-08-15: 「그럼 순서 맞추자」 ⇒ the order is [DeleteSubject]'s,
/// with the cuts rung dropped (「컷쪽은 굳이? 뭐 할게있나 싶네」). Two verbs that
/// both ask 「지금 무엇이 선택됐나」 and answer in different orders would be a
/// rule the user has to hold two versions of.
///
/// ⛔This enum names the TIME axis only. The SPACE axis is a separate law and
/// is not a rung here: 「선택 있으면 그 영역, 없으면 전체(페이스트보드 포함)」,
/// which the user has now said three times (③·⑤·색 변환) — it applies to every
/// cel this ladder names, whichever rung produced it.
///
/// Stated once, here, so the buttons, their tooltips and their enablement
/// cannot drift from what the press actually does.
enum PixelVerbSubject {
  /// Rows are selected on a rail: each row's cel at ITS current index.
  ///
  /// ⚠️`rows` mixes kinds ("whatever KIND those rows are", 유저 08-12), so the
  /// gate — `layerAcceptsBrushInput` — does the filtering. A selection of
  /// three rows where one is a camera row is not a refusal; it is two cels.
  layers,

  /// The frame axis: the (frame × row) block of a live frame-range selection,
  /// or the cel under the playhead when there is no range.
  ///
  /// They are one rung rather than two because the range is the more specific
  /// statement of the same question — which cels on the frame axis — and the
  /// playhead is what that question falls back to.
  cells,

  /// No cel this verb may touch; the buttons dim.
  ///
  /// ⛔Dimmed, never hidden (「없다가 생기는 UI 금지」).
  nothing,
}
