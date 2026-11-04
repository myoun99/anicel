import 'dart:collection';

import 'timeline_coverage.dart' show unitStartAt;
import 'timeline_exposure.dart';

/// What an FX bundle's keys are read at — every frame, or the head of the
/// block the frame shows: AE's way, or the drawing's.
///
/// 🗣️backlog-21-Q4 (유저 2026-10-09): 「FX 묶음마다 — 묶음 헤더에 스위치
/// 하나」 · 「적용 기준 프레임/블록은 fx묶음마다」, from the 07-25 proposal:
/// 블록 단위로 「바꾸는」 게 아니라 두 옵션 — a move keyed across `1--2--3--`
/// goes on moving through the holds by the frame, and holds at each
/// drawing's head value by the block, so it steps on the drawings' twos and
/// threes. The bundle's chip picks it (I-120-Q10, 유저 2026-11-04: 「프레임/
/// 블록 고르는거 리스트팝오버로」).
enum FxBasis {
  frame('Frame'),
  block('Block');

  const FxBasis(this.label);

  /// The English word — the program's language reads `FxBasisWords`.
  final String label;

  String toJson() => name;

  static FxBasis fromJson(Object? json) => FxBasis.values.firstWhere(
    (basis) => basis.name == json,
    orElse: () => FxBasis.frame,
  );
}

/// The frame a bundle on [basis] reads its keys at, for what shows at
/// [frameIndex] on a row whose blocks are [blocks]: the frame itself, or
/// the head of the block covering it — an empty cell being a block of its
/// own, as the onion skin's block unit counts it ([unitStartAt]).
///
/// [blocks] is null for a row that has none to step on (a folder, an
/// adjustment, the camera — 🗣️I-120-Q9: 「그런 행에는 스위치를 두지 않는다
/// (늘 프레임 기준)」), which reads every frame whatever it says.
int fxReadFrame(
  FxBasis basis,
  SplayTreeMap<int, TimelineExposure>? blocks,
  int frameIndex,
) => basis == FxBasis.block && blocks != null
    ? unitStartAt(blocks, frameIndex)
    : frameIndex;
