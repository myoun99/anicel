import '../../models/brush_frame_key.dart';
import '../brush_frame_editing_coordinator.dart';
import '../cache_invalidation_executor.dart';
import '../command.dart';

/// Moves PICTURES among cels — the pixels, the letters laid in them with
/// them — and never the cels: ids, names, exposures and links stay where
/// they are.
///
/// 🗣️F-330 (유저 2026-10-10): 「같은 위치에 대한 행이동은 타임라인을 바꾸는게
/// 아니고 서로의 그림을 바꾸는거라 가능해도될듯」 — and I-98 (10-14):
/// 「내부 그림만 바꿔치기 하는 느낌. 프레임 이름은 그 위에 붙는 라벨」. A
/// name is the cel's, so a move that moves no cel cannot lose one — the
/// warning that came with F-330 (「이름이 사라진다던가 하는 버그」).
///
/// [moves] trade, they do not copy: every cel that gives its picture takes
/// one — a swap is `[(a, b), (b, a)]`, a rigid hop of two rows over a third
/// is the turn `[(a, b), (b, c), (c, a)]`. Every picture is read before any
/// is written, so the order of [moves] says nothing.
///
/// ⛔Not `RekeyBrushFramesCommand`: its pairs must be disjoint, and a trade
/// is the overlapping chain it refuses (a → b with b → a would lose a
/// picture). This writes through the one undo primitive
/// ([BrushFrameEditingCoordinator.restoreSurfaceSnapshot]) — references,
/// not copies.
///
/// Undo runs the moves backwards. Each key is resolved to its canonical cel
/// first — a 겸용 row is a window onto its group's cel — and a move from a
/// cel to itself, or of a cel an earlier move already gave, does nothing.
class MoveCelPicturesCommand implements Command {
  MoveCelPicturesCommand({
    required this.coordinator,
    required this.moves,
    this.cacheInvalidationSink,
  });

  final BrushFrameEditingCoordinator coordinator;
  final List<(BrushFrameKey from, BrushFrameKey to)> moves;
  final CacheInvalidationSink? cacheInvalidationSink;

  @override
  String get description => 'Move pictures';

  @override
  void execute() => _hang(moves);

  @override
  void undo() => _hang([for (final (from, to) in moves) (to, from)]);

  void _hang(List<(BrushFrameKey from, BrushFrameKey to)> hangs) {
    final store = coordinator.frameStore;
    final given = <BrushFrameKey>{};
    final taken = [
      for (final (from, to) in hangs)
        if (store.canonicalKeyOf(from) case final cel
            when cel != store.canonicalKeyOf(to) && given.add(cel))
          (picture: coordinator.currentSurfaceOf(from), to: to),
    ];
    for (final (:picture, :to) in taken) {
      coordinator.restoreSurfaceSnapshot(
        to,
        picture,
        cacheInvalidationSink: cacheInvalidationSink,
      );
    }
  }
}
