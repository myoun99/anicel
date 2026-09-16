import 'package:flutter/foundation.dart';

import '../../native/qa_native_engine.dart';
import '../../services/brush_frame_store.dart';
import '../../services/brush_live_stroke_rasterizer.dart';
import '../../services/brush_tip_stamp_cache.dart';
import '../../services/history_manager.dart';
import '../../services/memory_allowance.dart';
import '../media/viewer_raster_budget.dart';
import '../playback/playback_cache_budget.dart';

/// One line of the memory tab's allowance: a holder the session can set a
/// ceiling on — its law for the device, the floor it keeps under a memory
/// warning, and the census rows it accounts for.
///
/// 🗣️유저 2026-09-16: 「타일그림이나 렌더링이나 그런 관련된거 바뀔수있으니
/// 낡지않을구조로」 — a holder is ONE entry here. Adding one is this list plus
/// the line that applies it (`_applyCacheBudgets`); the tab's 「inside the
/// allowance / outside it」 reads [censusIds], so a cache that gains a
/// ceiling moves inside without a word of UI changing. Before this the
/// budgets were nine hand-written fields, and a new holder was six edits.
///
/// ⛔EVERY holder the session can set a ceiling on is an entry. Scaling only
/// the device-scaled ones would make the allowance a lie: playback's 600MB
/// and the native uploads' 640MB would sit outside it, and they are two of
/// the largest. 🗣️유저 2026-09-16 (memory-allowance-Q2): 「천장을 걸 수 있는
/// 것은 전부 허용치 안으로」 — so the engine's parked tile blocks (a
/// compile-time cap in C until then) and the framework's image cache
/// (ceilinged by the binding at startup) are entries too. What is sized by
/// the screen and has no cache to cap is not — and says so by being a
/// census row no entry names.
enum CacheBudgetLine {
  /// The drawings' hot tier.
  drawings({'drawings'}),

  /// The three sheet-ink stores TOGETHER, split evenly between them.
  ///
  /// ⛔One cel store's worth, not three: the census already shows the three
  /// as ONE holding, and each running on the drawings' own law would give
  /// handwriting three times the pictures' memory.
  sheetInk({'sheetInk'}),

  undo({'undo'}),

  /// Playback frames and layer images — one enforcer holds both.
  playback({'playbackFrames', 'layerImages'}),

  /// ONE viewer's pages; each mounted viewer keeps its own.
  viewerPages({'viewerPages'}),

  storyboardThumbnails({'storyboardThumbnails'}),

  /// The engine's stamp and mask copies, split evenly between the two
  /// caches.
  nativeUploads({'nativeUploads'}),

  brushTips({'brushTips'}),

  liveStroke({'liveStroke'}),

  /// The framework's own image cache — `Image.asset` and its kind. This app
  /// decodes its own pixels, so the ceiling suits a cache that is nearly
  /// empty; it exists so a list of assets added one day cannot quietly take
  /// the framework's default tenth of a gigabyte.
  imageCache({'imageCache'}),

  /// The drawing engine's tile blocks parked for reuse.
  enginePool({'enginePool'});

  const CacheBudgetLine(this.censusIds);

  /// The memory census rows this line is the ceiling of.
  final Set<String> censusIds;

  /// Whether some line accounts for the census row [id] — the tab draws
  /// that row inside the allowance, and names the rest as outside it.
  static bool covers(String id) =>
      values.any((line) => line.censusIds.contains(id));

  /// The framework's image cache ceiling ([imageCache]).
  static const int frameworkImageCacheBytes = 8 * 1024 * 1024;

  /// The engine's parked tile blocks ([enginePool]): one full 8K frame of
  /// tiles (256MB) plus headroom for a previous frame still draining — the
  /// number C starts from.
  static const int engineTilePoolBytes = 512 * 1024 * 1024;

  /// This line's budget on a device with [physicalMemoryBytes] of RAM — null
  /// (no engine: tests, host runs) keeps the desktop-class ceiling, as every
  /// device law here already does.
  int lawFor({required int? physicalMemoryBytes}) => switch (this) {
    CacheBudgetLine.drawings ||
    CacheBudgetLine.sheetInk => deviceScaledHotCelBudget(
      physicalMemoryBytes: physicalMemoryBytes,
    ),
    CacheBudgetLine.undo => deviceScaledUndoByteBudget(
      physicalMemoryBytes: physicalMemoryBytes,
    ),
    CacheBudgetLine.playback => playbackCacheBudgetBytes,
    CacheBudgetLine.viewerPages ||
    CacheBudgetLine.storyboardThumbnails => viewerRasterBytesFor(
      physicalMemoryBytes: physicalMemoryBytes,
    ),
    CacheBudgetLine.nativeUploads => 2 * QaNativeEngine.stampUploadByteBudget,
    CacheBudgetLine.brushTips => BrushTipStampCache.defaultByteBudget,
    CacheBudgetLine.liveStroke =>
      BrushLiveStrokeRasterizer.defaultResidentResultByteBudget,
    CacheBudgetLine.imageCache => frameworkImageCacheBytes,
    CacheBudgetLine.enginePool => engineTilePoolBytes,
  };

  /// The least this line may be scaled to: what it already keeps under a
  /// memory warning — or nothing, for a cache that always keeps its newest
  /// entry whatever its budget says.
  int get floor => switch (this) {
    CacheBudgetLine.drawings => BrushFrameStore.hotCelFloorBytes,
    CacheBudgetLine.undo => HistoryManager.retainedByteBudgetUnderPressure,
    CacheBudgetLine.playback => playbackCacheBudgetUnderPressureBytes,
    CacheBudgetLine.viewerPages ||
    CacheBudgetLine.storyboardThumbnails => viewerPageBytesAtCap,
    CacheBudgetLine.sheetInk ||
    CacheBudgetLine.nativeUploads ||
    CacheBudgetLine.brushTips ||
    CacheBudgetLine.liveStroke ||
    CacheBudgetLine.imageCache ||
    CacheBudgetLine.enginePool => 0,
  };
}

/// Every cache's budget, as ONE set — the numbers the memory tab's
/// allowance moves together, one per [CacheBudgetLine].
///
/// 🗣️유저 2026-09-11: 「앱이 사용하기로 허가된 메모리? 유저가 커스텀하는?
/// … RAM/8얘기는 그걸 바탕으로 정해진다던가?」 Each cache keeps its own law
/// for the device (cels RAM/4, undo RAM/8, a viewer a sixth of the cels);
/// the allowance SCALES them, every one by the same factor.
@immutable
class CacheBudgets {
  const CacheBudgets._(this._bytes);

  /// [lines] made explicit, byte for byte — a test's fixture, or the
  /// [floors]. Every line must be given.
  factory CacheBudgets.of(Map<CacheBudgetLine, int> lines) {
    assert(
      lines.length == CacheBudgetLine.values.length,
      'every line needs a budget: ${CacheBudgetLine.values.toSet().difference(lines.keys.toSet())}',
    );
    return CacheBudgets._(Map.unmodifiable(lines));
  }

  /// Today's budgets on a device with [physicalMemoryBytes] of RAM.
  factory CacheBudgets.forDevice({required int? physicalMemoryBytes}) =>
      CacheBudgets._(
        Map.unmodifiable({
          for (final line in CacheBudgetLine.values)
            line: line.lawFor(physicalMemoryBytes: physicalMemoryBytes),
        }),
      );

  /// The least each line may be scaled to.
  static final CacheBudgets floors = CacheBudgets._(
    Map.unmodifiable({
      for (final line in CacheBudgetLine.values) line: line.floor,
    }),
  );

  final Map<CacheBudgetLine, int> _bytes;

  int operator [](CacheBudgetLine line) => _bytes[line]!;

  int get drawings => this[CacheBudgetLine.drawings];
  int get sheetInk => this[CacheBudgetLine.sheetInk];
  int get undo => this[CacheBudgetLine.undo];
  int get playback => this[CacheBudgetLine.playback];
  int get viewerPages => this[CacheBudgetLine.viewerPages];
  int get storyboardThumbnails => this[CacheBudgetLine.storyboardThumbnails];
  int get nativeUploads => this[CacheBudgetLine.nativeUploads];
  int get brushTips => this[CacheBudgetLine.brushTips];
  int get liveStroke => this[CacheBudgetLine.liveStroke];
  int get imageCache => this[CacheBudgetLine.imageCache];
  int get enginePool => this[CacheBudgetLine.enginePool];

  int get total => _bytes.values.fold(0, (sum, bytes) => sum + bytes);

  /// The factor that scales these budgets to add up to [allowanceBytes].
  double factorFor(int allowanceBytes) =>
      total <= 0 ? 1 : allowanceBytes / total;

  /// These budgets scaled [by] one factor — none under its [floors] line,
  /// so an allowance below `floors.total` still adds up to `floors.total`.
  CacheBudgets scaledBy(double by) => CacheBudgets._(
    Map.unmodifiable({
      for (final entry in _bytes.entries)
        entry.key: MemoryAllowance.scaled(
          entry.value,
          floor: entry.key.floor,
          by: by,
        ),
    }),
  );

  /// These budgets scaled to add up to [allowanceBytes].
  CacheBudgets toAllowance(int allowanceBytes) =>
      scaledBy(factorFor(allowanceBytes));

  @override
  bool operator ==(Object other) =>
      other is CacheBudgets && mapEquals(other._bytes, _bytes);

  @override
  int get hashCode => Object.hashAll(
    [for (final line in CacheBudgetLine.values) _bytes[line]],
  );
}
