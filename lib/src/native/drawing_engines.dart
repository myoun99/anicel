import '../models/bitmap_surface.dart';
import '../services/cel_shells.dart';
import 'app_gpu_engine.dart';
import 'engine_selection_masks.dart';
import 'engine_strokes.dart';
import 'engine_tile_ledger.dart';
import 'native_scratch.dart';

/// What the process's drawing holds that is no project's — the scratch
/// buffers, the GPU engine's tile ledger — heard together where what only
/// makes their next call cheaper is given back. None is opened to hear it.
/// ↩️The tile blocks parked for reuse were the first of them till
/// 2026-11-21: a freed block waits nowhere now (`TileBlocks`).
///
/// Here, not on any of them: each would reach the others. ↩️While the
/// blocks' lists heard it too, a tile reached its blocks' file
/// (bitmap_tile.dart imports tile_blocks.dart) and the ledger the tile, so
/// the blocks calling the ledger would have closed an import loop.
abstract final class DrawingEngines {
  /// The OS says memory is tight, or a closed project was collected:
  /// every scratch buffer (each regrows on its next call), the ledger's
  /// pages nobody holds (pool-pages-given-back), and
  /// the pages of the engine's pictures nobody holds — theirs lie in a
  /// pool as the cels' do (engine-pictures-keep-to-pool-pages) — and what
  /// the strokes, a selection's kernels and the frame grids' batch keep for
  /// their next.
  static void respondToMemoryPressure() {
    NativeScratch.releaseAll();
    EngineTileLedger.opened?.respondToMemoryPressure();
    EnginePictures.giveBackPast(0);
    EngineStrokes.letGoIdle();
    EngineSelectionMasks.letGoIdle();
    AppGpuGridBatch.letGoKept();
  }

  /// What keeps a cel's tiles on the engine once a look lets go of its
  /// pixels here ([CelShells]) — the app's ledger, whichever its engine has
  /// now ([EngineTileLedger.opened]), and none where nothing opened one:
  /// no tile then has a slot to keep.
  static const CelShells celShells = _TheAppsLedger();

  /// Gives back what [respondToMemoryPressure] gives back once [holder] has
  /// been collected — a CLOSED project's pictures (F-505).
  ///
  /// 🗣️유저 2026-10-29 (F-505): 「무거운거 닫으면 언두기록도 안되니
  /// 초기프로젝트분만큼만 메모리 존재해야하는데 … 닫았는데도 1700메가사용중.
  /// 그중 … 묘화엔진 타일풀이 413」. A tile's block comes back when the
  /// collector finds the tile, after the close. ↩️It was parked for reuse
  /// then, up to the lists' cap — a close's worth of blocks nobody would
  /// ask for — till the lists went (2026-11-21, `TileBlocks`): a freed
  /// block is the allocator's at once, and what is given back here is the
  /// rest — the ledger's pages and the pictures' its tiles lay on.
  /// ⚠️The callback is the collector's message, which lands AFTER the tiles
  /// the same collection found were already handed back: their native
  /// finalizers run inside it. It gives back on the spot, once for each
  /// holder: after the first nothing is left to give, and a timer to
  /// gather them would be one a test's clock holds. The ledger's slots go
  /// by a finalizer's message of their own, which may land after it: the
  /// ledger lets go a collected tile's slot itself first.
  static void giveBackOnceCollected(Object holder) =>
      _givesBackOnceCollected.attach(holder, 0);

  static final Finalizer<int> _givesBackOnceCollected = Finalizer<int>(
    (_) => respondToMemoryPressure(),
  );
}

/// [DrawingEngines.celShells]: the app ledger's, asked anew each time.
final class _TheAppsLedger implements CelShells {
  const _TheAppsLedger();

  @override
  void lay(BitmapSurface surface, {required Object cel}) =>
      EngineTileLedger.opened?.lay(surface, cel: cel);

  @override
  void restBeforeLong() => EngineTileLedger.opened?.restBeforeLong();

  @override
  BitmapSurface? shellOf(
    BitmapSurface surface, {
    required BitmapSurface Function() readAgain,
  }) => EngineTileLedger.opened?.shellOf(surface, readAgain: readAgain);

  @override
  bool isWhole(BitmapSurface shell) =>
      EngineTileLedger.opened?.isWhole(shell) ?? false;
}
