/// WHAT the one Edit Instance button would rename right now.
///
/// 유저 확정 2026-08-14 (T25): 「인스턴스 편집 버튼도 공통버튼으로 이동.
/// 그래서 **선택범위 통해 동사통일화** 가능하게. 그러고 **레이어 이름변경
/// 버튼 필요없어지니 삭제**」.
///
/// ★The ladder is DELETE's, deliberately — same order, same reasoning
/// ([DeleteSubject]). Two verbs that both ask 「지금 무엇이 선택됐나」 and
/// answer in different orders would be a rule the user has to hold two
/// versions of, and the whole point of the shared pill is that its buttons
/// share a subject.
///
/// Stated once, here, so the button, its tooltip and its enablement cannot
/// drift from what the press actually does.
enum EditInstanceSubject {
  /// A cut range is selected on the storyboard's track axis: rename the cut.
  cuts,

  /// Rows are selected on a rail: rename every RENAMEABLE one to the same
  /// name (확정 #20 — 「선택된 편집가능 레이어 전부를 같은 이름으로 일괄
  /// 변경」). The batch was already how `renameActiveLayerWithDialog`
  /// behaved; T25 only gives it a door on the shared pill.
  layers,

  /// The frame axis: the instance editor at the playhead, which
  /// kind-dispatches across the cel / camera / SE / instruction / text
  /// dialogs on its own.
  cells,

  /// Nothing to rename; the button dims.
  nothing,
}
