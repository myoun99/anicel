/// The item that takes [items]`[at]`'s place when it goes — the one after
/// it, or the one before when it is the last — or null when it stands
/// alone.
///
/// 🚨ONE LAW. 🗣️F-426 (유저 2026-10-21): 「선택한 브러시 그룹 삭제시, 다른
/// 그룹 선택하도록. 왜 저번에 브러시 삭제하면 다른 브러시 선택하게할때
/// 유동적으로 이부분도 안했는지 의문. 최대한 법 통일」. A closed project tab
/// handed the screen to the tab beside it and a deleted brush handed its
/// tools the brush beside it (F-250 ③), each spelled out by hand; a deleted
/// group handed its tools the library's first brush, as if nothing stood
/// beside it. The third is what earned this.
T? itemBeside<T>(List<T> items, int at) {
  RangeError.checkValidIndex(at, items, 'at');
  if (at + 1 < items.length) {
    return items[at + 1];
  }
  return at > 0 ? items[at - 1] : null;
}
