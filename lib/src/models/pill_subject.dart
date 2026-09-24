/// WHAT a SHARED-pill verb acts on right now — delete, Edit Instance and the
/// link-independent button ask ONE ladder.
///
/// 유저 확정 2026-08-12 (⑰): 「딜리트버튼, 슬 통일하고싶음. 버튼 그냥 하나로.」
/// ⇒ delete stopped being three buttons hard-wired to three nouns and became
/// one verb that asks what is selected. The ORDER is the user's, and it is
/// stated once, here, so a button, its tooltip and its enablement cannot
/// drift from what its press actually does.
///
/// 유저 확정 2026-08-14 (T25): 「인스턴스 편집 버튼도 공통버튼으로 이동.
/// 그래서 **선택범위 통해 동사통일화** 가능하게」 — Edit Instance took the
/// same ladder, in the same order, for the same reason: two verbs that both
/// ask 「지금 무엇이 선택됐나」 and answer in different orders would be a
/// rule the user has to hold two versions of.
///
/// 🗣️I-45 (유저 2026-09-23): 「정확히는 다른 편집버튼등의 로직 그대로 따라감.
/// 그거 공용화해서 재사용할수있으면 재사용해서 법 하나로 통일. 선택안하면
/// 현재프레임, 선택하면 해당 선택한 소재가 기준임」. The link-independent
/// button was the THIRD verb on this ladder, and each of the first two had
/// kept an enum of its own with the same four values — so the ladder became
/// one type and one function ([pillSubjectOn]) rather than a third copy.
///
/// ⚠️Where the verbs DIFFER is only in the predicate each rung uses:
/// deleting asks what is deletable, renaming what is renameable, unlinking
/// what is linked — a camera row selects and renames but does not delete.
enum PillSubject {
  /// A cut range is selected on the storyboard's track axis.
  cuts,

  /// Rows are selected on a rail.
  layers,

  /// The frame axis: a live cell range, or the block under the playhead
  /// (and for delete, lane keys first) — the verb resolves those itself,
  /// which is why they are one rung here rather than three.
  cells,

  /// Nothing to act on; the button dims.
  nothing,
}

/// THE LADDER, written once: the cut range when cuts are this panel's noun,
/// then the selected rows, then the frame axis.
///
/// Each verb says only whether ITS rung holds something it may act on;
/// [layers] and [cells] are asked in that order and only as far as the
/// answer needs.
///
/// 🚨R5q1 (유저 2026-08-25, 답 1번): 「삭제·편집도 패널을 따라 대상을
/// 바꾼다」 — [cuts] is the caller's 「a cut range is selected AND cuts are
/// this panel's noun」, never the selection alone.
PillSubject pillSubjectOn({
  required bool cuts,
  required bool Function() layers,
  required bool Function() cells,
}) {
  if (cuts) {
    return PillSubject.cuts;
  }
  // ⑨: rows outrank cells. A row selection is the more specific statement
  // — you named the rows out loud — while the cell rung answers from where
  // the playhead happens to stand.
  if (layers()) {
    return PillSubject.layers;
  }
  return cells() ? PillSubject.cells : PillSubject.nothing;
}
