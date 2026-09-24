import '../../models/block_run_move.dart';
import '../../models/cut.dart';
import '../../models/cut_id.dart';

/// The leading gaps of the cuts at and after [index] once a cut of
/// [leadingGap] + [duration] frames lands in front of `cuts[index]` — only
/// the gaps that change.
///
/// 🚨★★ 유저 #19 (2026-08-15): 「미는건 뒤에 공간없으면 밀어도되는데,
/// **공간이 여유분이 있는데도 여유분 뒤의 컷을 밀어버림**」. A cut takes its
/// room out of the free space ahead, and only what that space cannot hold
/// pushes.
///
/// 🚨F-97 (유저 2026-09-12): 「링크컷 만들때는 뒤 컷이 떨어져 있어서 공간이
/// 있는데도 뒤 컷들 전부 밀어냄. 근데 새 컷 만들때는 빈공간있으면 뒤 컷
/// 안밀어냄. 새 컷 만드는거랑 똑같이 해서 법 하나로 통일. 근데 이런거 애초에
/// 프레임블록 로직이랑 똑같이 법 통일」. Every cut that lands in front of
/// others asks here — a new cut and a 겸용 cut alike — and the push is the
/// frame axis's own ([startsClearingFrontier]): each gap ahead is spent
/// before the push reaches the cut behind it.
Map<CutId, int> followerGapsAfterInsert(
  List<Cut> cuts, {
  required int index,
  required int leadingGap,
  required int duration,
}) {
  if (index >= cuts.length) {
    return const {};
  }
  final starts = slotStartsOf([
    for (final cut in cuts)
      (leadingGap: cut.leadingGapFrames, length: cut.duration),
  ]);
  final landing =
      (index == 0 ? 0 : starts[index - 1] + cuts[index - 1].duration) +
      leadingGap;
  final followers = cuts.sublist(index);
  final moved = startsClearingFrontier([
    for (final (position, cut) in followers.indexed)
      (start: starts[index + position], length: cut.duration),
  ], frontier: landing + duration);
  final gaps = leadingGapsOf(
    starts: [landing, ...moved],
    lengths: [duration, for (final cut in followers) cut.duration],
  );
  return {
    for (final (position, cut) in followers.indexed)
      if (gaps[position + 1] != cut.leadingGapFrames)
        cut.id: gaps[position + 1],
  };
}
