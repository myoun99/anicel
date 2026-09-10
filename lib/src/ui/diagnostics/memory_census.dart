import 'dart:io' show ProcessInfo;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import '../../native/qa_native_engine.dart';
import '../../services/brush_tip_stamp_cache.dart';
import '../editor_session_manager.dart';
import '../widgets/static_raster.dart';

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
/// **They are different, and cannot be made the same.** [rssBytes] is the
/// whole process — the Flutter engine, Skia, the Dart heap, the binary,
/// the embedded typefaces, the native library. [trackedBytes] is what this
/// app can enumerate. The gap is not a leak and not an error; it is
/// everything we did not write. So the panel shows both, and breaks items
/// out inside OURS, which is the branch 유저 chose.
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
    required this.rssBytes,
    required this.items,
    this.availableBytes,
  });

  /// What the OS says this PROCESS occupies in physical RAM.
  ///
  /// 🚨`ProcessInfo.currentRss`, NOT the native engine's
  /// `processFootprintBytes` — ABI v29 answers that one only on Apple
  /// platforms and returns 0 on Windows and Linux, which is why the System
  /// section has been printing "not measured here" on the very machine
  /// this is developed on. The Dart VM measures RSS everywhere.
  final int rssBytes;

  /// How much more the OS will let this process take, where the platform
  /// says. Null where it will not — the number refuses to guess, and the
  /// device's free RAM is a different question.
  final int? availableBytes;

  /// The enumerable holdings, largest first.
  final List<MemoryCensusItem> items;

  /// The sum of what we can account for. Always less than [rssBytes].
  int get trackedBytes {
    var total = 0;
    for (final item in items) {
      total += item.bytes;
    }
    return total;
  }

  /// Everything in the process that is not one of our caches: the engine,
  /// Skia, the Dart heap, the binary, the typefaces. Named rather than
  /// left as arithmetic, because a reader who sees only the gap assumes a
  /// leak.
  int get untrackedBytes {
    final rest = rssBytes - trackedBytes;
    return rest < 0 ? 0 : rest;
  }
}

/// Takes the census. Cheap — every number below is a counter the holder
/// already maintains, so this is addition, not measurement.
MemoryCensus collectMemoryCensus(EditorSessionManager session) {
  final items = <MemoryCensusItem>[
    MemoryCensusItem(
      id: 'drawings',
      bytes:
          session.renderCaches.brushFrameStore.hotBakedBytes +
          session.renderCaches.brushFrameStore.coldBakedBytes +
          // 🚨LIFTED PIXELS COUNT, and were missing until 2026-09-10. A
          // move or a transform holds the pixels it picked up — up to a
          // whole canvas — in the SAME store, and the readout said
          // nothing about them: mid-transform the panel showed less
          // memory than the app was holding, and the difference read as
          // engine overhead.
          //
          // ⛔Folded into `drawings` rather than given a row: it is the
          // same store holding the same user's artwork, it is zero the
          // moment the tool parks, and a row of its own would need a
          // fifth string in five languages to say "usually nothing".
          session.renderCaches.brushFrameStore.liftedPixelBytes,
    ),
    MemoryCensusItem(
      id: 'sheetInk',
      bytes:
          session.renderCaches.conteInkRowStore.hotBakedBytes +
          session.renderCaches.conteInkRowStore.coldBakedBytes +
          session.renderCaches.conteInkPageStore.hotBakedBytes +
          session.renderCaches.conteInkPageStore.coldBakedBytes +
          session.renderCaches.envelopeInkStore.hotBakedBytes +
          session.renderCaches.envelopeInkStore.coldBakedBytes,
    ),
    MemoryCensusItem(id: 'undo', bytes: session.historyManager.retainedBytes),
    MemoryCensusItem(
      id: 'playbackFrames',
      bytes: session.renderCaches.cutFrameCompositeCache.estimatedBytes,
      detail: session.renderCaches.cutFrameCompositeCache.pinnedBytes,
    ),
    MemoryCensusItem(
      id: 'layerImages',
      bytes: session.renderCaches.layerFrameImageCache.estimatedBytes,
      detail: session.renderCaches.layerFrameImageCache.pinnedBytes,
    ),
    MemoryCensusItem(
      id: 'brushTips',
      bytes:
          BrushTipStampCache.instance.residentBytes +
          // ⛔The NATIVE copies of the same things belong on the same row:
          // a stamp's bytes and a mask's alphas uploaded for the kernels.
          // They were byte-budgeted and reported to nobody, so they read
          // as engine overhead — 2026-09-10.
          (QaNativeEngine.instance?.nativeUploadBytes ?? 0),
    ),
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
          // ⛔The editing canvas's display buffer belongs on the same row:
          // it is a panel holding a raster of itself, one canvas-resolution
          // image (33MB at 4K) kept for as long as nothing changes. It
          // lives in a widget State, so it is PUSHED here — 2026-09-10.
          session.renderCaches.canvasBufferBytes,
    ),
    // Pushed by the mounted viewers rather than read off a holder the
    // session owns — see [RenderCaches.viewerRasterBytesByViewer].
    MemoryCensusItem(
      id: 'viewerPages',
      bytes: session.renderCaches.viewerRasterBytes,
    ),
  ]..sort((a, b) => b.bytes.compareTo(a.bytes));

  return MemoryCensus(
    rssBytes: ProcessInfo.currentRss,
    // ⛔The availability half IS answered everywhere — ABI v29 only
    // withholds the FOOTPRINT on Windows and Linux. Dropping this would
    // throw away the one number the native engine can still give.
    availableBytes: QaNativeEngine.instance?.availableMemoryBytes,
    items: items,
  );
}
