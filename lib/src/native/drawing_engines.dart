import 'app_gpu_engine.dart';
import 'engine_strokes.dart';
import 'engine_tile_ledger.dart';
import 'native_scratch.dart';
import 'tile_blocks.dart';

/// What the process's drawing holds that is no project's — the tile blocks
/// parked for reuse, the scratch buffers, the GPU engine's tile ledger —
/// heard together where what only makes their next call cheaper is given
/// back. None is opened to hear it.
///
/// Here, not on any of them: a tile reaches its blocks' file
/// (bitmap_tile.dart imports tile_blocks.dart), and the ledger reaches the
/// tile, so the blocks calling the ledger would close an import loop.
abstract final class DrawingEngines {
  /// The OS says memory is tight, or a closed project was collected: the
  /// parked tile blocks, every scratch buffer (each regrows on its next
  /// call), the ledger's pages nobody holds (pool-pages-given-back), and
  /// the pages of the engine's pictures nobody holds — theirs lie in a
  /// pool as the cels' do (engine-pictures-keep-to-pool-pages).
  static void respondToMemoryPressure() {
    TileBlocks.trim();
    NativeScratch.releaseAll();
    EngineTileLedger.opened?.respondToMemoryPressure();
    EnginePictures.giveBack();
    EngineStrokes.letGoIdle();
  }

  /// Gives back what [respondToMemoryPressure] gives back once [holder] has
  /// been collected — a CLOSED project's pictures (F-505).
  ///
  /// 🗣️유저 2026-10-29 (F-505): 「무거운거 닫으면 언두기록도 안되니
  /// 초기프로젝트분만큼만 메모리 존재해야하는데 … 닫았는데도 1700메가사용중.
  /// 그중 … 묘화엔진 타일풀이 413」. A tile's block comes back when the
  /// collector finds the tile, after the close — and was parked for reuse up
  /// to the pool's cap, a close's worth of blocks nobody would ask for.
  /// ⚠️The callback is the collector's message, which lands AFTER the tiles
  /// the same collection found were already handed back: their native
  /// finalizers run inside it. It gives back on the spot, once for each
  /// holder: after the first nothing is parked, and a timer to gather them
  /// would be one a test's clock holds. The ledger's slots go by a
  /// finalizer's message of their own, which may land after it: the ledger
  /// lets go a collected tile's slot itself first.
  static void giveBackOnceCollected(Object holder) =>
      _givesBackOnceCollected.attach(holder, 0);

  static final Finalizer<int> _givesBackOnceCollected = Finalizer<int>(
    (_) => respondToMemoryPressure(),
  );
}
