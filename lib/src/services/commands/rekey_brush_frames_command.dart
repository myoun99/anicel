import '../../models/brush_frame_key.dart';
import '../brush_frame_store.dart';
import '../command.dart';

/// Re-homes brush drawings to new store keys — the brush-store half of a
/// cross-layer block move (R10-④b), composed with the layer timeline
/// updates into one undo step. Undo replays the pairs reversed, so the
/// drawings land back under their original keys.
///
/// ⚠️THE PAIRS ARE DISJOINT, by construction rather than by a check: a
/// frameId names one cel, so a cel appears in exactly one pair and no
/// `to` is another pair's `from`. That is what makes reversing each pair
/// enough — an OVERLAPPING chain (a → b, b → c) would need the replay to
/// reverse the list ORDER too, and the undo as written would drop the
/// drawing that landed on b. Measured 2026-09-05 while pinning this; no
/// caller builds one, and a caller that starts to must fix the replay.
class RekeyBrushFramesCommand implements Command {
  RekeyBrushFramesCommand({required this.store, required this.pairs});

  final BrushFrameStore store;
  final List<(BrushFrameKey from, BrushFrameKey to)> pairs;

  @override
  String get description => 'Rekey ${pairs.length} brush frame(s)';

  @override
  void execute() {
    store.rekeyFrames(pairs);
  }

  @override
  void undo() {
    store.rekeyFrames([for (final (from, to) in pairs) (to, from)]);
  }
}
