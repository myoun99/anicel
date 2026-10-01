/// THE numbering law of 자동 이름 지정 (I-18), written once for both nouns
/// it numbers.
///
/// 🗣️I-18-Q1 (유저): 「그림마다 번호 — 다시 나오는 블록은 같은 번호」, and of
/// the cuts: 「이 로직은 컷번호 바꿀때도 그대로 적용. 그러니 공용화해서
/// 같이구현」.
///
/// Each thing takes the next number the FIRST time it is shown, and every
/// later showing reads the number it already has: blocks showing the
/// drawings `a b a c`, numbered from 5, read `5 6 5 7`. A cut is shown once
/// on its track, so cuts simply count up — the same function, not a second
/// one for them.
///
/// ⚠️[attachExposureShape] (`attached_layer_mount.dart`) also keys a walk by
/// first appearance, and it is NOT this: it answers each block's ORDINAL —
/// the index of the block that first showed its cel, gaps in the count and
/// all — where this answers a NAME counted over the distinct things alone.
/// Two readings of one walk are not one law yet; the third walk of this
/// shape is the one that merges them (the rule of three).
Map<K, String> namesByFirstAppearance<K>(
  Iterable<K> shownInOrder, {
  required int from,
}) {
  final names = <K, String>{};
  for (final shown in shownInOrder) {
    names.putIfAbsent(shown, () => '${from + names.length}');
  }
  return names;
}
