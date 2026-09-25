/// WHICH PANEL the user is working in — the one whose rows the arrows, the
/// flip and the bound keys answer to.
///
/// 🗣️유저 2026-08-05: 「마지막으로 무언가 액션이 있었던 패널을 기준으로」, and
/// 2026-09-24, when both panels could be open at once: 「마지막으로 만진 패널.
/// 1번기준대로 하자. 그리고 탭 버튼 눌러 콘티로 바꾸는것도 콘티를 만진것으로.
/// 콘티패널내부의 어느 공간 클릭하던. … 입구같은거나 규칙/법 완벽하게
/// 통일 … 위아래 이동이 타임라인 내부로 샌다거나 그런거 싹 다 해결」.
///
/// ★It is a PANEL and not a row kind because a row alone cannot say it: an S
/// row and the transition row show on both panels under one address — the
/// cut timeline's copy is a projection of the track's row, and picking the
/// projection is a different act from picking the original (#741, 유저
/// 2026-07-27). The panel is what tells the two apart, so the panel is what
/// the standing records.
enum WorkingPanel {
  /// The cut timeline and its X-sheet: the active cut's rows, on the cut's
  /// own frame axis.
  timeline,

  /// The storyboard (콘티 패널): every track's rows, on the track's global
  /// frame axis.
  storyboard,
}
