/// WHAT the one Delete button would remove right now.
///
/// 유저 확정 2026-08-12 (⑰): 「딜리트버튼, 슬 통일하고싶음. 버튼 그냥 하나로.」
/// ⇒ delete stopped being three buttons hard-wired to three nouns and became
/// one verb that asks what is selected. The ORDER is the user's, and it is
/// stated once, here, so the button, its tooltip and its enablement cannot
/// drift from what the press actually does.
enum DeleteSubject {
  /// A cut range is selected on the storyboard's track axis.
  cuts,

  /// Rows are selected on a rail.
  ///
  /// ⚠️Nothing produces this yet — row multi-selection is ⑨. It exists so the
  /// rung has a name before it has a wire: the alternative is discovering the
  /// ordering question again when ⑨ lands.
  layers,

  /// The frame axis: lane keys, a live cell range, or the block under the
  /// playhead — `deleteCellAtCurrentFrame` already resolves those three in
  /// that order, which is why they are one rung here rather than three.
  cells,

  /// Nothing to remove; the button dims.
  nothing,
}
