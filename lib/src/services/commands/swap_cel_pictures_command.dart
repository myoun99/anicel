import '../../models/brush_frame_key.dart';
import '../brush_frame_editing_coordinator.dart';
import '../cache_invalidation_executor.dart';
import '../command.dart';

/// Swaps the PICTURES of pairs of cels — the pixels, the letters laid in
/// them with them — and never the cels: ids, names, exposures and links stay
/// where they are.
///
/// 🗣️F-330 (유저 2026-10-10): 「같은 위치에 대한 행이동은 타임라인을 바꾸는게
/// 아니고 서로의 그림을 바꾸는거라 가능해도될듯」 — and I-98 (10-14):
/// 「내부 그림만 바꿔치기 하는 느낌. 프레임 이름은 그 위에 붙는 라벨」. A
/// name is the cel's, so a swap that moves no cel cannot lose one — the
/// warning that came with F-330 (「이름이 사라진다던가 하는 버그」).
///
/// ⛔Not `RekeyBrushFramesCommand`: its pairs must be disjoint, and a swap
/// is the overlapping pair it refuses (a → b with b → a would lose a
/// picture). This re-reads both pictures and writes each into the other
/// through the one undo primitive
/// ([BrushFrameEditingCoordinator.restoreSurfaceSnapshot]) — references, not
/// copies.
///
/// A swap undoes itself: undo runs the same pass. Each pair is resolved to
/// its canonical cels first — a 겸용 row is a window onto its group's cel —
/// so a pair that names one cel twice, or a cel an earlier pair already
/// swapped, does nothing.
class SwapCelPicturesCommand implements Command {
  SwapCelPicturesCommand({
    required this.coordinator,
    required this.pairs,
    this.cacheInvalidationSink,
  });

  final BrushFrameEditingCoordinator coordinator;
  final List<(BrushFrameKey, BrushFrameKey)> pairs;
  final CacheInvalidationSink? cacheInvalidationSink;

  @override
  String get description => 'Swap pictures';

  @override
  void execute() => _swap();

  @override
  void undo() => _swap();

  void _swap() {
    final store = coordinator.frameStore;
    final swapped = <BrushFrameKey>{};
    for (final (a, b) in pairs) {
      final celA = store.canonicalKeyOf(a);
      final celB = store.canonicalKeyOf(b);
      if (celA == celB ||
          swapped.contains(celA) ||
          swapped.contains(celB)) {
        continue;
      }
      swapped
        ..add(celA)
        ..add(celB);
      final pictureA = coordinator.currentSurfaceOf(a);
      final pictureB = coordinator.currentSurfaceOf(b);
      coordinator
        ..restoreSurfaceSnapshot(
          a,
          pictureB,
          cacheInvalidationSink: cacheInvalidationSink,
        )
        ..restoreSurfaceSnapshot(
          b,
          pictureA,
          cacheInvalidationSink: cacheInvalidationSink,
        );
    }
  }
}
