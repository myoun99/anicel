/// Where a dragged entry LANDS — the one arithmetic every reorder in this
/// app was writing for itself.
///
/// 🚨★★★**TWO DIFFERENT INDICES, AND MIXING THEM UP IS THE OFF-BY-ONE
/// EVERY REORDER HAS HAD.**
///
///  * A **SLOT** is a gap in the list that STILL CONTAINS the dragged
///    entry — `0..length`. A caret drawn between rows reports one, and so
///    does the obsolete `ReorderableListView.onReorder`.
///  * A **TARGET** is a position in the list WITHOUT it — `0..length-1`.
///    `ReorderableListView.onReorderItem` and
///    `BrushPresetReorderGrid.onReorder` both hand this over already.
///
/// Landing after yourself is one position fewer once you are lifted out,
/// so a slot read as a target moves the entry one short — and the shortfall
/// is invisible everywhere except at the very end of the list, where "one
/// short" is the only place it can be seen.
///
/// 유저 2026-09-10: 「브러시 탭 그룹 움직일때 그룹 하나를 맨 밑으로 옮기려하면
/// 맨 밑의 한칸 위로 강제로 이동되니까 규칙 다른거있으면 다 통일해서 법 하나로
/// 만들어서」. The rail was indexing a TARGET into the list that still held
/// the moved tab; the grid beside it was already doing this correctly, and
/// the track rail had the sentence written out in a comment of its own.
/// Three implementations, one law.
///
/// See also `reorderedByIds`, which APPLIES a finished order; this decides
/// what that order should be.
library;

/// A [slot] read as a target.
///
/// Use this at the boundary where a caret between rows becomes a position,
/// and nowhere else — a value that has been through here is a target and
/// must not be corrected twice.
int reorderTargetForSlot({required int slot, required int movedIndex}) =>
    slot > movedIndex ? slot - 1 : slot;

/// The entry [target] names once the moved one is lifted out, or null when
/// it lands past the end (an APPEND).
///
/// [ordered] is the list as it stands, with the moved entry still in it at
/// [movedIndex]; [target] is a target index (see the two indices above).
/// Out-of-range targets clamp rather than throw: a pointer can leave the
/// list, and the ends are where it means to be.
T? reorderAnchorAt<T>(
  List<T> ordered, {
  required int movedIndex,
  required int target,
}) {
  if (movedIndex < 0 || movedIndex >= ordered.length) {
    return null;
  }
  final without = [...ordered]..removeAt(movedIndex);
  final clamped = target.clamp(0, without.length);
  return clamped < without.length ? without[clamped] : null;
}
