/// THE MARK A KEY WEARS ON THE FRAME AXIS (I-89 ②).
///
/// 🗣️유저 10-10: 「ae식 반반등은 검증된 업계기준이라 아주 마음에들어」 — a
/// key's mark is After Effects': its LEFT half says the side arriving at
/// the key, its RIGHT half the side leaving it, each by the side's KIND.
/// What a mark answers is the kind alone: an ease at 33% and one at 50%
/// draw the same half.
library;

import 'property_track.dart';

/// What one frame's key mark says.
sealed class KeyMark {
  const KeyMark();

  /// The ordinary key: straight on both sides.
  static const KeyMark linear = SidesKeyMark(
    incoming: KeySideKind.linear,
    outgoing: KeySideKind.linear,
  );

  /// A union whose keyed members disagree.
  static const KeyMark mixed = MixedKeyMark._();
}

/// A key's two sides, by kind.
final class SidesKeyMark extends KeyMark {
  const SidesKeyMark({required this.incoming, required this.outgoing});

  final KeySideKind incoming;
  final KeySideKind outgoing;

  @override
  bool operator ==(Object other) =>
      other is SidesKeyMark &&
      other.incoming == incoming &&
      other.outgoing == outgoing;

  @override
  int get hashCode => Object.hash(incoming, outgoing);

  @override
  String toString() => 'SidesKeyMark($incoming → $outgoing)';
}

/// 🚨F-17 (유저: 「멤버 타입이 서로 다르면 헤더에 동그라미」): a UNION whose
/// keyed members do not wear one mark. ↩️It was a disc; since I-89 ② a disc
/// is 「부드럽게 지나감」, so it is the same circle left HOLLOW (유저 10-10
/// 「추천대로」). Never a member lane's: one key has nothing to disagree
/// with.
final class MixedKeyMark extends KeyMark {
  const MixedKeyMark._();

  @override
  String toString() => 'KeyMark.mixed';
}

/// [key]'s mark.
KeyMark keyMarkOf(PropertyKey<Object?> key) => SidesKeyMark(
  incoming: keySideKindOf(key.incoming),
  outgoing: keySideKindOf(key.outgoing),
);

/// Every key of [track], by frame — a lane's marks.
Map<int, KeyMark> keyMarksOf(PropertyTrack<Object?> track) => {
  for (final entry in track.keys.entries) entry.key: keyMarkOf(entry.value),
};

/// A GROUP's marks from its members' ([lanes]): at each frame some member
/// keys, the mark every member keyed there wears — [KeyMark.mixed] where
/// they do not all wear one. The ONE union every group header draws
/// (transform, camera, effect, name tag), so a header cannot say a thing
/// its members do not.
Map<int, KeyMark> unionKeyMarks(Iterable<Map<int, KeyMark>> lanes) {
  final union = <int, KeyMark>{};
  for (final lane in lanes) {
    for (final MapEntry(key: frame, value: mark) in lane.entries) {
      final seen = union[frame];
      union[frame] = seen == null || seen == mark ? mark : KeyMark.mixed;
    }
  }
  return union;
}
