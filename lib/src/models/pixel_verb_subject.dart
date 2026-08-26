/// WHAT the two PIXEL verbs — 색 변환 and 픽셀 비우기 — would act on right now.
///
/// 유저 확정 2026-08-26: 「조작은 무조건 서있는 레이어에 조작하게 하는거야.
/// 그러니 **선택범위 있으면 그거 전부, 아니면 서있는곳** 조작하는거야」.
///
/// ⛔**A ROW SELECTION DOES NOT FAN THE VERB OUT ACROSS LAYERS.** The first
/// cut of this had a rung that took every selected row, mapped it through
/// `owningLayerId` and acted on all of them — 유저: 「프로퍼티행에 서있는데도
/// 레이어 그림에 적용하게한거 아니지? **내가 비슷한얘기 옛날에 했다가
/// 폐기했어**」. Selecting rows says which rows are selected; it does not say
/// 「recolour all of their drawings」. Only a FRAME RANGE says that, because a
/// frame range is drawn across the cels themselves.
///
/// ⛔The enum names the TIME axis only. The SPACE axis is a separate law and
/// is not a rung here: 「선택 있으면 그 영역, 없으면 전체(페이스트보드 포함)」,
/// which the user has now said three times (③·⑤·색 변환) — it applies to every
/// cel this ladder names, whichever rung produced it.
///
/// Stated once, here, so the buttons, their tooltips and their enablement
/// cannot drift from what the press actually does.
enum PixelVerbSubject {
  /// A live frame-range selection: every cel in its (frame × row) block.
  ///
  /// This is the only rung that touches more than one cel, and it is allowed
  /// to because the user drew the range over those cels.
  range,

  /// No range: the one cel where you are standing.
  standing,

  /// No cel this verb may touch; the buttons dim.
  ///
  /// ⛔Dimmed, never hidden (「없다가 생기는 UI 금지」).
  nothing,
}
