import 'dart:io' show ProcessInfo;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import '../../native/native_scratch.dart';
import '../../native/qa_native_engine.dart';
import '../../services/brush_tip_stamp_cache.dart';
import '../../services/cut_piece_slot.dart';
import '../../services/last_stroke_slot.dart';
import '../canvas/bitmap_tile_image_cache.dart';
import '../canvas/tile_pyramid.dart';
import '../editor_session_manager.dart';
import '../widgets/static_raster.dart';
import '../widgets/still_raster.dart';

/// ONE line of the memory readout: what a thing is, in the user's words,
/// and what it costs right now.
@immutable
class MemoryCensusItem {
  const MemoryCensusItem({
    required this.id,
    required this.bytes,
    this.detail = 0,
  });

  /// Stable key for the label lookup — never shown raw.
  final String id;

  final int bytes;

  /// A second number the row may show inside the first (bytes that cannot
  /// be evicted while playback holds them). Zero when the item has none.
  final int detail;
}

/// 🚨★★★WHAT THE APP IS HOLDING, counted in ONE place.
///
/// 유저 2026-08-28: 「이 앱이 쓰는 메모리의 총합. 그리고 추가적으로 거기서
/// 어떤항목이 얼만큼 차지하는지도 보여주고」 — and, when asked whether the
/// OS number and ours are the same: 「os합이랑 우리가 쓰는 합이랑 다르다면
/// os합 보여주고 우리가쓰는 합 보여주고 그 합 안에서 항목 나눠서 보여줌」.
///
/// **They are different, and cannot be made the same.** [footprintBytes]
/// is the whole process as the OS counts it; [trackedBytes] is what this
/// app can enumerate. The gap is not a leak and not an error; it is
/// everything we did not write. So the panel shows both, and breaks items
/// out inside OURS, which is the branch 유저 chose.
///
/// 🆕유저 2026-09-10: 「같은수로 하고싶은데 다른 멀티플랫폼도 같아지는건가?」
/// — the big number is now the SAME number that OS's own task manager
/// puts next to the app, and it is that on every platform. See
/// [footprintBytes].
///
/// ⛔ONE CENSUS. Preferences ▸ System already prints a memory line, and the
/// new Memory tab prints more of the same numbers. Two counters would
/// disagree the first time either learned about a cache — which is exactly
/// how [SheetInkController]'s two copies drifted. Both read this.
///
/// ⛔THIS LIVES IN `ui/`, not `services/`, on purpose: it reads
/// [StaticRaster.censusBytes] and the playback caches, which are UI-layer
/// objects, and the dependency direction forbids `services` importing
/// `ui/`. Counting UI memory is a UI concern.
@immutable
class MemoryCensus {
  const MemoryCensus({
    required this.footprintBytes,
    required this.items,
    this.availableBytes,
    this.deviceBytes,
  });

  /// What the OS says this PROCESS is holding — the SAME number that OS's
  /// own task manager shows next to the app.
  ///
  /// 🎯ONE QUESTION ON EVERY PLATFORM: the bytes that belong to this
  /// process alone and come back when it exits. Windows private working
  /// set (작업 관리자 ▸ 메모리), Apple `phys_footprint` (활성 상태 보기 ▸
  /// 메모리, and the number jetsam reads), Linux/Android `Private_Clean +
  /// Private_Dirty`. ⚠️They are NOT comparable between systems — each is
  /// its own system's answer — and that is exactly the point: whatever the
  /// user is looking at, this matches it.
  ///
  /// ⛔NOT `ProcessInfo.currentRss` any more, and the note that used to
  /// stand here — "the native engine answers only on Apple" — is what
  /// changed: `qa_process_footprint_bytes` answers everywhere now.
  /// RSS is `WorkingSet64`, which counts pages SHARED with other
  /// processes: the DLLs and the mapped typefaces. Measured here
  /// 2026-09-10, idle release: 194.8MB RSS against 139.3MB private, and
  /// the 55.5MB gap is shared pages — not a leak, and not ours.
  ///
  /// ⚠️RSS remains the fallback, and only for a run with no native engine
  /// at all, where every other native number is already absent too.
  final int footprintBytes;

  /// How much more the OS will let this process take, where the platform
  /// says. Null where it will not — the number refuses to guess, and the
  /// device's free RAM is a different question.
  final int? availableBytes;

  /// The device's RAM, or null where the platform will not say — the
  /// memory tab's widest tier.
  final int? deviceBytes;

  /// The enumerable holdings, largest first.
  final List<MemoryCensusItem> items;

  /// The sum of what we can account for. Always less than [footprintBytes].
  int get trackedBytes {
    var total = 0;
    for (final item in items) {
      total += item.bytes;
    }
    return total;
  }

  /// Everything private to this process that is not one of our caches: the
  /// Dart heap, Skia's and the engine's allocations, the AOT snapshot's
  /// writable pages. Named rather than left as arithmetic, because a
  /// reader who sees only the gap assumes a leak.
  ///
  /// ⛔The BINARY and the TYPEFACES used to be listed here and no longer
  /// belong: [footprintBytes] counts private pages, and a mapped DLL or a
  /// mapped .ttf is neither private nor charged to us (measured here
  /// 2026-09-10: 293MB of images and 82MB of mapped files, none of it in
  /// the number the user reads).
  int get untrackedBytes {
    final rest = footprintBytes - trackedBytes;
    return rest < 0 ? 0 : rest;
  }
}

/// Takes the census. Cheap — every number below is a counter the holder
/// already maintains, so this is addition, not measurement.
///
/// 🚨EVERY OPEN PROJECT (I-7). The app is holding what all of its tabs hold,
/// so a project's rows are the SUM over [sessions] — the tab on screen and
/// the ones behind it — and what the app holds once for all of them (the
/// held stroke, the cut piece, the engine) is counted once. A census of the
/// tab on screen alone would put every other tab's drawings in
/// `untrackedBytes`, which the panel reads out as the engine's.
MemoryCensus collectMemoryCensus(Iterable<EditorSessionManager> sessions) {
  int sum(int Function(EditorSessionManager session) bytesOf) =>
      sessions.fold(0, (total, session) => total + bytesOf(session));
  final items = <MemoryCensusItem>[
    MemoryCensusItem(
      id: 'drawings',
      bytes: sum(
        (session) =>
            session.renderCaches.brushFrameStore.hotBakedBytes +
            // ⛔NOT `coldBakedBytes` (2026-09-11): a cooled cel is written to
            // the run's 이사대기 room and only a file ref stays in memory —
            // those are bytes on DISK. Counted here, 「ours」 swelled and the
            // engine's share shrank by exactly as much.
            // 🚨LIFTED PIXELS COUNT, and were missing until 2026-09-10. A
            // move or a transform holds the pixels it picked up — up to a
            // whole canvas — in the SAME store, and the readout said
            // nothing about them: mid-transform the panel showed less
            // memory than the app was holding, and the difference read as
            // engine overhead.
            //
            // ⛔Folded into `drawings` rather than given a row: it is the
            // same store holding the same user's artwork, it is zero the
            // moment the tool lets go, and a row of its own would need a
            // fifth string in five languages to say "usually nothing".
            session.renderCaches.brushFrameStore.reclaimableViewBytes,
      ),
    ),
    MemoryCensusItem(
      id: 'sheetInk',
      bytes: sum(
        (session) =>
            // Resident only, like the drawings row above.
            session.renderCaches.sheetInkStores.fold(
              0,
              (sum, store) => sum + store.hotBakedBytes,
            ),
      ),
    ),
    MemoryCensusItem(
      id: 'undo',
      bytes:
          sum((session) => session.historyManager.retainedBytes) +
          // 확정's held stroke (confirm-button): a past edit kept to be laid
          // down again, which is what this row counts. Folded in rather than
          // given a row, for the reason `drawings` gives above. The app's,
          // so once ([CutPieceSlot.allPieceBytes]).
          LastStrokeSlot.allStrokeBytes,
    ),
    MemoryCensusItem(
      id: 'playbackFrames',
      bytes: sum(
        (session) => session.renderCaches.cutFrameCompositeCache.estimatedBytes,
      ),
      detail: sum(
        (session) => session.renderCaches.cutFrameCompositeCache.pinnedBytes,
      ),
    ),
    MemoryCensusItem(
      id: 'layerImages',
      bytes: sum(
        (session) => session.renderCaches.layerFrameImageCache.estimatedBytes,
      ),
      detail: sum(
        (session) => session.renderCaches.layerFrameImageCache.pinnedBytes,
      ),
    ),
    MemoryCensusItem(
      id: 'brushTips',
      bytes:
          BrushTipStampCache.instance.residentBytes +
          // ⛔The NATIVE copies of the same things belong on the same row:
          // a stamp's bytes and a mask's alphas uploaded for the kernels.
          // They were byte-budgeted and reported to nobody, so they read
          // as engine overhead — 2026-09-10.
          (QaNativeEngine.instance?.nativeUploadBytes ?? 0) +
          // The cut tool's HELD piece is the stamp's tip (유저: 「잘라내기 할
          // 때마다 가지고 있는 찍기 팁 교체야」), so it rides this row — the
          // app's one slot, counted once. 🆕I-14: a cut from the media
          // viewer holds its source at full size.
          CutPieceSlot.allPieceBytes,
    ),
    // 🚨THE CANVAS'S OWN PICTURES, which a phone keeps as GPU textures:
    // every decoded tile, alive as long as its tile is — the picture on
    // screen and, through the tiles it keeps, the undo history's. The
    // share had no row and read as engine overhead (C-ipad-crash,
    // 2026-09-11). Since 4c (2026-09-16) the row also holds the LEVEL
    // TILES — the same pictures halved for a zoomed-out screen
    // ([TilePyramid]), screen-bounded, and let go with the paints that
    // stop asking for them.
    MemoryCensusItem(
      id: 'tileImages',
      bytes: BitmapTileImageCache.liveImageBytes + TilePyramid.liveBytes,
    ),
    // 🚨THE DRAWING ENGINE'S OWN MEMORY, which is nobody's picture: tile
    // blocks parked for reuse and grow-only scratch sized by the largest
    // call so far. Both resident, both read as engine overhead until
    // C-ipad-crash (2026-09-11). ✂️Two rows since 2026-09-16: the pool has
    // a ceiling the allowance sets ([CacheBudgetLine.enginePool]) and the
    // scratch has none — one row would have been half inside the
    // allowance and half out.
    MemoryCensusItem(
      id: 'enginePool',
      bytes: QaNativeEngine.instance?.tilePoolParkedBytes ?? 0,
    ),
    MemoryCensusItem(id: 'engineScratch', bytes: NativeScratch.liveBytes),
    // 🚨THE ONE HOLDER THAT IS NOT OURS AT ALL. Flutter's own image cache
    // is allowed 100 MiB and 1000 entries by default and nothing in this
    // app ever set either — so the readout could not say whether it held
    // nothing or a tenth of a gigabyte. It answers now, and
    // [AnicelBinding] gives it a ceiling that suits an app which decodes
    // its own pixels.
    //
    // ⚠️A source scan cannot find this one: the ratchet reads `lib/`, and
    // this counter lives in the framework. It is here because someone
    // looked, which is the argument for looking.
    MemoryCensusItem(
      id: 'imageCache',
      bytes: PaintingBinding.instance.imageCache.currentSizeBytes,
    ),
    MemoryCensusItem(
      id: 'panelRasters',
      bytes:
          StaticRaster.censusBytes +
          // A dock region's still image (2026-09-25) is the same kind of
          // holding: a panel region kept as a raster while nothing changes.
          StillRaster.censusBytes +
          // ⛔The editing canvas's display buffer belongs on the same row:
          // it is a panel holding a raster of itself, kept for as long as
          // nothing changes. It lives in a widget State, so it is PUSHED
          // here — 2026-09-10.
          //
          // ⚠️NOT one image. A derived buffer pins the one it was drawn
          // from, so this is the whole chain, up to
          // `DisplayBufferCache._maxChainBytes` — it read one image until
          // 2026-09-12, and the canvases it was not counting showed up in
          // 「엔진·폰트·프레임워크」 as 10GB nothing would own.
          sum((session) => session.renderCaches.canvasBufferBytes),
    ),
    // Pushed by the mounted viewers rather than read off a holder the
    // session owns — see [RenderCaches.viewerRasterBytesByViewer].
    MemoryCensusItem(
      id: 'viewerPages',
      bytes: sum((session) => session.renderCaches.viewerRasterBytes),
    ),
    // Pushed by the workspace, whose State owns the store — see
    // [RenderCaches.storyboardThumbnailBytes].
    MemoryCensusItem(
      id: 'storyboardThumbnails',
      bytes: sum(
        (session) => session.renderCaches.storyboardThumbnailBytes,
      ),
    ),
    // A movie kept as a reference, decoded where it is shown. Its pictures
    // live in the cel store and are paid from the drawings' hot budget —
    // but they are not the user's artwork, so not that row: a take warmed
    // for playback would read as drawings grown by hundreds of megabytes.
    MemoryCensusItem(
      id: 'moviePictures',
      bytes: sum(
        (session) => session.renderCaches.brushFrameStore.movieCelBytes,
      ),
    ),
  ]..sort((a, b) => b.bytes.compareTo(a.bytes));

  return MemoryCensus(
    // ⛔The PLATFORM's own answer, not the Dart VM's RSS — see
    // [MemoryCensus.footprintBytes] for why they differ and which one the
    // user is looking at. `ProcessInfo.currentRss` stands in only when no
    // native engine loaded at all.
    footprintBytes:
        QaNativeEngine.instance?.processFootprintBytes ??
        ProcessInfo.currentRss,
    availableBytes: QaNativeEngine.instance?.availableMemoryBytes,
    deviceBytes: QaNativeEngine.instance?.physicalMemoryBytes,
    items: items,
  );
}
