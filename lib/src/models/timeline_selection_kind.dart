/// The KINDS of selection a timeline surface can hold.
///
/// 🚨유저 확정 2026-08-12 (⑨): 「선택범위는 하나만 작동하도록. 프레임셀
/// 선택범위 작동시키고 레이어쪽 선택범위 작동하면 기존 프레임셀쪽 사라지게.
/// 반대도 마찬가지 (…) 즉 **선택한 상태라는건 한 종류만 존재하도록**」.
///
/// This enum exists so that rule can be stated ONCE
/// (`EditorSessionManager.claimSelection`) instead of as a sentence per
/// pair. It is not a mode switch: nothing reads "which kind is live" to
/// decide behaviour — each selection keeps its own state and its own verbs,
/// and this only says which of them may be non-empty.
enum TimelineSelectionKind {
  /// A frame-cell range on a cut's own axis.
  cells,

  /// A property-lane key range.
  lanes,

  /// A cut range on the storyboard's track axis.
  cuts,

  /// Rail ROWS (⑨).
  rows,
}
