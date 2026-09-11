import 'package:flutter/foundation.dart';

import '../../native/qa_native_engine.dart';
import '../../services/brush_frame_store.dart';
import '../../services/brush_live_stroke_rasterizer.dart';
import '../../services/brush_tip_stamp_cache.dart';
import '../../services/history_manager.dart';
import '../../services/memory_allowance.dart';
import '../media/viewer_raster_budget.dart';
import '../playback/playback_cache_budget.dart';

/// Every cache's budget, as ONE set — the numbers the memory tab's
/// allowance moves together.
///
/// 🗣️유저 2026-09-11: 「앱이 사용하기로 허가된 메모리? 유저가 커스텀하는?
/// … RAM/8얘기는 그걸 바탕으로 정해진다던가?」 Each cache keeps its own law
/// for the device (cels RAM/4, undo RAM/8, a viewer a sixth of the cels);
/// the allowance SCALES them, every one by the same factor.
///
/// ⛔EVERY holder the session can set a ceiling on is a line here. Scaling
/// only the device-scaled ones would make the allowance a lie: playback's
/// 600MB and the native uploads' 640MB would sit outside it, and they are
/// two of the largest. Not lines: what is sized by the screen (the panel
/// rasters, the tile images), the engine's tile pool (capped in C), and
/// the framework's image cache (ceilinged by the binding at startup).
@immutable
class CacheBudgets {
  const CacheBudgets({
    required this.drawings,
    required this.sheetInk,
    required this.undo,
    required this.playback,
    required this.viewerPages,
    required this.storyboardThumbnails,
    required this.nativeUploads,
    required this.brushTips,
    required this.liveStroke,
  });

  /// Today's budgets on a device with [physicalMemoryBytes] of RAM — null
  /// (no engine: tests, host runs) keeps the desktop-class ceilings, as
  /// every device law here already does.
  factory CacheBudgets.forDevice({required int? physicalMemoryBytes}) {
    final drawings = deviceScaledHotCelBudget(
      physicalMemoryBytes: physicalMemoryBytes,
    );
    final viewer = viewerRasterBytesFor(
      physicalMemoryBytes: physicalMemoryBytes,
    );
    return CacheBudgets(
      drawings: drawings,
      sheetInk: drawings,
      undo: deviceScaledUndoByteBudget(
        physicalMemoryBytes: physicalMemoryBytes,
      ),
      playback: playbackCacheBudgetBytes,
      viewerPages: viewer,
      storyboardThumbnails: viewer,
      nativeUploads: 2 * QaNativeEngine.stampUploadByteBudget,
      brushTips: BrushTipStampCache.defaultByteBudget,
      liveStroke: BrushLiveStrokeRasterizer.defaultResidentResultByteBudget,
    );
  }

  /// The least each line may be scaled to: what it already keeps under a
  /// memory warning — or nothing, for a cache that always keeps its newest
  /// entry whatever its budget says.
  static const CacheBudgets floors = CacheBudgets(
    drawings: BrushFrameStore.hotCelFloorBytes,
    sheetInk: 0,
    undo: HistoryManager.retainedByteBudgetUnderPressure,
    playback: playbackCacheBudgetUnderPressureBytes,
    viewerPages: viewerPageBytesAtCap,
    storyboardThumbnails: viewerPageBytesAtCap,
    nativeUploads: 0,
    brushTips: 0,
    liveStroke: 0,
  );

  /// The drawings' hot tier.
  final int drawings;

  /// The three sheet-ink stores TOGETHER, split evenly between them.
  ///
  /// ⛔One cel store's worth, not three: the census already shows the
  /// three as ONE holding (`sheetInk`), and each running on the drawings'
  /// own law would give handwriting three times the pictures' memory.
  final int sheetInk;

  final int undo;

  /// Playback frames and layer images — one enforcer holds both.
  final int playback;

  /// ONE viewer's pages; each mounted viewer keeps its own.
  final int viewerPages;

  final int storyboardThumbnails;

  /// The engine's stamp and mask copies, split evenly between the two
  /// caches.
  final int nativeUploads;

  final int brushTips;

  final int liveStroke;

  List<int> get _lines => [
    drawings,
    sheetInk,
    undo,
    playback,
    viewerPages,
    storyboardThumbnails,
    nativeUploads,
    brushTips,
    liveStroke,
  ];

  int get total => _lines.fold(0, (sum, bytes) => sum + bytes);

  /// The factor that scales these budgets to add up to [allowanceBytes].
  double factorFor(int allowanceBytes) =>
      total <= 0 ? 1 : allowanceBytes / total;

  /// These budgets scaled [by] one factor — none under its [floors] line,
  /// so an allowance below `floors.total` still adds up to `floors.total`.
  CacheBudgets scaledBy(double by) {
    int scaled(int bytes, int floor) =>
        MemoryAllowance.scaled(bytes, floor: floor, by: by);
    return CacheBudgets(
      drawings: scaled(drawings, floors.drawings),
      sheetInk: scaled(sheetInk, floors.sheetInk),
      undo: scaled(undo, floors.undo),
      playback: scaled(playback, floors.playback),
      viewerPages: scaled(viewerPages, floors.viewerPages),
      storyboardThumbnails: scaled(
        storyboardThumbnails,
        floors.storyboardThumbnails,
      ),
      nativeUploads: scaled(nativeUploads, floors.nativeUploads),
      brushTips: scaled(brushTips, floors.brushTips),
      liveStroke: scaled(liveStroke, floors.liveStroke),
    );
  }

  /// These budgets scaled to add up to [allowanceBytes].
  CacheBudgets toAllowance(int allowanceBytes) =>
      scaledBy(factorFor(allowanceBytes));

  @override
  bool operator ==(Object other) =>
      other is CacheBudgets && listEquals(other._lines, _lines);

  @override
  int get hashCode => Object.hashAll(_lines);
}
