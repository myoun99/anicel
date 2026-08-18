import 'dart:async';
import 'dart:collection';
import 'dart:typed_data' show Uint8List;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' hide Uint8List;
import 'package:flutter/material.dart';

import '../../native/qa_native_engine.dart';
import 'timeline_frame_window.dart';
import 'timeline_glyph_cache.dart';
import 'timeline_grid_tile_ops.dart';
import 'timeline_row_cells_painter.dart';

/// The drawing rows' SUBSTRATE tile store (UI-R18 O7 T2, R18-T).
///
/// A row's cells — the paper-block fills and their borders, plus the ink
/// over them — rasterize ONCE per (row, span, look) through the native
/// `qa_grid_raster_tile` and land here as a premultiplied [ui.Image]; the
/// row painter then draws one `drawImageRect` per span instead of 2-3
/// canvas calls per cell.
///
/// ⚠️ The ink is IN the tile. The emitter writes the substrate and then
/// the foreground — hold-dash capsules inline, glyph text through the A8
/// atlas (T3) — into one op stream, and `_paint` skips its Dart foreground
/// pass for any span a tile covers. This doc used to say the opposite
/// ("foreground ink stays the painter's Dart pass on top"), which was true
/// of the tile's first shape and has misled at least one reader into
/// costing a text-layering round wrongly; the stale-while-revalidate note
/// below is the honest description, naming the two technologies it chooses
/// between as "baked A8 glyphs ↔ TextPainter".
///
/// The classic Dart pass is the FALLBACK, for spans with no usable tile.
///
/// Contracts:
/// - Tiles are TRANSPARENT (background 0): accumulation from
///   transparent black is premultiplied, the raw-upload contract, so a
///   tile composites pixel-true over any panel background.
/// - The tile grid rides the SHARED window policy
///   ([timelineFrameWindowSpanFor]): tile i covers cells
///   [i*span, (i+1)*span) — scrolling reuses tiles bucket by bucket.
/// - Keys carry the full LOOK identity (layer object identity — layers
///   are immutable, an edit is a new instance — active flag, extents,
///   playback count, scheme, DPR): any mismatch re-rasters, so edits
///   invalidate exactly like `shouldRepaint`.
/// - NO native engine (flutter_tester, unsupported platforms, load
///   failure) = the store stands down entirely ([tileFor] returns null
///   and requests nothing): rows keep the classic Dart paint, tests and
///   packaging stay byte-for-byte on today's path.
class TimelineGridTileStore {
  TimelineGridTileStore._();

  static final TimelineGridTileStore instance = TimelineGridTileStore._();

  /// Bumped when a tile upload lands — the row painters merge this into
  /// their repaint listenable, so the landed tile paints on the next
  /// frame (cold spans show the classic paint meanwhile: no flash).
  final ValueNotifier<int> revision = ValueNotifier<int>(0);

  /// LRU cap. A span tile at 96px × a 28px row × DPR 2 ≈ 42KB; 768
  /// covers dozens of rows × the whole scroll neighborhood before
  /// eviction starts.
  static const int capacity = 768;

  final LinkedHashMap<String, _TileEntry> _entries =
      LinkedHashMap<String, _TileEntry>();
  final Map<String, _TileRequest> _pending = <String, _TileRequest>{};
  bool _drainScheduled = false;

  /// The substrate generation the LIVE paints carry — the newest
  /// [TimelineRowCellsPainter.substrateGeneration] a [tileFor] call has
  /// seen. Paints only happen for the live state, so the last generation
  /// a paint carried IS the live one; no host wiring, no setter to race.
  ///
  /// 🚨#29 프레임 블록 회색 깜빡임: a request captures the painter, but the
  /// painter's resolvers answer FROM THE LIVE SESSION at drain time
  /// (`celHasContentForLayer` reads `activeCutOrNull`). The drain is
  /// serial, up to 32 deep, with real async hops between rasters — so a
  /// cut switch mid-queue made every remaining request bake the OLD
  /// cut's rows against the NEW cut's answers: a miss, painted grey,
  /// stored, and served again later as a perfectly valid hit. A drained
  /// request whose generation is no longer live is DEAD, not stale —
  /// rastering it would consult resolvers that no longer describe its
  /// rows.
  String _liveGeneration = '';

  /// Test hook.
  @visibleForTesting
  void clear() {
    for (final entry in _entries.values) {
      entry.image.dispose();
    }
    _entries.clear();
    _pending.clear();
  }

  /// The fresh substrate tile for [painter]'s span starting at
  /// [spanStartIndex], or null (cold/stale — the classic paint covers
  /// this frame, and a raster is scheduled off the paint phase).
  ui.Image? tileFor({
    required TimelineRowCellsPainter painter,
    required int spanStartIndex,
    required int spanEndIndexExclusive,
    required double devicePixelRatio,
  }) {
    if (QaNativeEngine.instance == null) {
      return null;
    }
    _liveGeneration = painter.substrateGeneration;
    // 🚨The generation is IN the key, not only compared later: the key is
    // deliberately the layer's ID (an edited layer is a NEW instance that
    // must find its old tile and show it stale while re-rastering), and
    // the same ID legitimately exists in other cuts — old files written
    // before PR #1070 even carry duplicate ids across cuts. Without the
    // generation, cut B's row was served cut A's pixels whenever the
    // geometry happened to match, which after a mid-drain poisoning is
    // exactly how a grey block went from "flicker" to "stays".
    final key =
        '${painter.substrateGeneration}|${painter.layer.id.value}:'
        '${painter.axis.index}:$spanStartIndex';
    final entry = _entries.remove(key);
    if (entry != null) {
      _entries[key] = entry;
      if (entry.matches(painter, spanEndIndexExclusive, devicePixelRatio)) {
        return entry.image;
      }
    }
    // Cold or stale: schedule ONE raster per key (the newest look wins —
    // a stale in-flight request re-checks at drain time). The queue is
    // CAPPED (UI-R20 #4): a scrollbar teleport requests dozens of spans
    // per frame and most are passed before their raster would land —
    // dropping the OLDEST keeps the drain working on what is actually
    // on screen now.
    _pending.remove(key);
    _pending[key] = _TileRequest(
      painter: painter,
      spanStartIndex: spanStartIndex,
      spanEndIndexExclusive: spanEndIndexExclusive,
      devicePixelRatio: devicePixelRatio,
    );
    while (_pending.length > 32) {
      _pending.remove(_pending.keys.first);
    }
    if (!_drainScheduled) {
      _drainScheduled = true;
      // Off the paint phase; microtasks run before the next frame, so a
      // tile can land within a frame or two.
      scheduleMicrotask(_drain);
    }
    // Stale-while-revalidate (UI-R20 #6, widened for R26 #27): WHATEVER
    // went stale — a look flip or a content edit (a new layer instance) —
    // keep showing the stale tile while the fresh raster lands, as long as
    // the GEOMETRY still matches (a mis-sized tile would stretch).
    // Dropping to the classic pass instead swaps text rendering
    // technologies for a frame (baked A8 glyphs ↔ TextPainter), which
    // reads as every glyph momentarily thinning/thickening.
    //
    // R9 #16: this used to fire on EVERY host rebuild, because the
    // resolver closures are method tear-offs and [_TileEntry.matches]
    // compared them with `identical` — which is false for two tear-offs of
    // the same method. That is fixed at the comparison, so the stale path
    // now runs only when something genuinely changed, and it stays as the
    // graceful landing for those cases. The drain rasters the NEWEST look
    // within a frame or two, so content lags one beat at most.
    // ⛔Both stale arms demand the GENERATION even though the key already
    // carries it: stale-while-revalidate exists precisely for "same row,
    // new instance", and without this term it is also "same id, other
    // cut" — the alias that turned a mid-drain grey from a flicker into
    // a resident.
    if (entry != null &&
        entry.substrateGeneration == painter.substrateGeneration &&
        entry.frameCellExtent == painter.frameCellExtent &&
        entry.crossAxisExtent == painter.crossAxisExtent &&
        entry.spanEndIndexExclusive == spanEndIndexExclusive &&
        entry.devicePixelRatio == devicePixelRatio) {
      return entry.image;
    }
    // R27 #10: a ZOOM step changes the geometry of every visible tile at
    // once, and dropping all of them to the classic Dart pass is what
    // made zooming crawl. The tile covers the SAME frames either way and
    // the painter draws it into a `dst` rect built from the CURRENT
    // geometry — so the stale raster simply scales, the way every pro
    // timeline shows a stretched last frame while the real one renders.
    // Bounded so an extreme jump (a 10× slider throw) still takes the
    // crisp path rather than showing mush.
    if (entry != null &&
        entry.substrateGeneration == painter.substrateGeneration &&
        entry.spanEndIndexExclusive == spanEndIndexExclusive &&
        entry.devicePixelRatio == devicePixelRatio &&
        entry.crossAxisExtent == painter.crossAxisExtent &&
        _withinRescaleBand(entry.frameCellExtent, painter.frameCellExtent)) {
      return entry.image;
    }
    return null;
  }

  /// How far a stale tile may be stretched before the classic pass is the
  /// better answer.
  static bool _withinRescaleBand(double from, double to) {
    if (from <= 0 || to <= 0) {
      return false;
    }
    final ratio = to / from;
    return ratio >= 0.5 && ratio <= 2.0;
  }

  Future<void> _drain() async {
    _drainScheduled = false;
    final engine = QaNativeEngine.instance;
    if (engine == null) {
      _pending.clear();
      return;
    }
    while (_pending.isNotEmpty) {
      final key = _pending.keys.first;
      final request = _pending.remove(key)!;
      // A dead-generation request is discarded, not rastered: its
      // painter's resolvers answer from the live session, which no longer
      // describes its rows. ⛔This check and the resolver reads are one
      // synchronous block — `_raster` emits the substrate and collects
      // the glyph cells before its first await — so nothing can change
      // the session between the check and the answers it guards.
      if (request.painter.substrateGeneration != _liveGeneration) {
        continue;
      }
      final rastered = await _raster(engine, request);
      if (rastered == null) {
        continue;
      }
      _entries.remove(key)?.image.dispose();
      _entries[key] = _TileEntry(
        substrateGeneration: request.painter.substrateGeneration,
        layer: request.painter.layer,
        coverageIdentity: request.painter.coverageIdentity,
        frameCellExtent: request.painter.frameCellExtent,
        crossAxisExtent: request.painter.crossAxisExtent,
        colorScheme: request.painter.colorScheme,
        exposureStateForLayer: request.painter.exposureStateForLayer,
        frameNameForLayer: request.painter.frameNameForLayer,
        celHasContentForLayer: request.painter.celHasContentForLayer,
        // ⛔The revision the RASTER sampled, never a live read. `_raster`
        // suspends between its content reads and this landing (the glyph
        // A8 bake, the ImmutableBuffer upload are real awaits), so a
        // crossing that bumps the revision inside that window would give
        // pixels of revision N a stamp of N+1 — and `matches()` compares
        // the NUMBER, so the poisoned tile was served as fresh forever
        // (the LRU survives cut trips and the 'projectId:cutId' string is
        // reproduced exactly on return; only the NEXT bump healed it).
        celContentRevision: rastered.celContentRevision,
        baseTextStyle: request.painter.baseTextStyle,
        spanEndIndexExclusive: request.spanEndIndexExclusive,
        devicePixelRatio: request.devicePixelRatio,
        framesPerSecond: request.painter.framesPerSecond,
        image: rastered.image,
      );
      while (_entries.length > capacity) {
        _entries.remove(_entries.keys.first)!.image.dispose();
      }
      revision.value += 1;
    }
  }

  // --- Glyph A8 bake cache (T3) ---------------------------------------
  //
  // Foreground glyphs bake ONCE per (text, shape-style, DPR) into an A8
  // coverage bitmap (white text rendered off-screen, alpha extracted);
  // tiles blit them through the op stream's GLYPH op, tinted with the
  // painter's exact ink per cell.

  static const int _glyphCapacity = 1024;
  final LinkedHashMap<String, _BakedGlyph?> _glyphs =
      LinkedHashMap<String, _BakedGlyph?>();
  final Map<String, Future<_BakedGlyph?>> _glyphBakes =
      <String, Future<_BakedGlyph?>>{};

  static String _glyphKey(String text, TextStyle style, double dpr) =>
      '$text|${style.fontSize}|${style.fontWeight}|${style.fontStyle}|'
      '${style.fontFamily}|$dpr';

  Future<_BakedGlyph?> _glyphA8(String text, TextStyle style, double dpr) {
    final key = _glyphKey(text, style, dpr);
    if (_glyphs.containsKey(key)) {
      final cached = _glyphs.remove(key);
      _glyphs[key] = cached;
      return Future<_BakedGlyph?>.value(cached);
    }
    return _glyphBakes[key] ??= _bakeGlyph(text, style, dpr).then((baked) {
      _glyphBakes.remove(key);
      _glyphs[key] = baked;
      while (_glyphs.length > _glyphCapacity) {
        _glyphs.remove(_glyphs.keys.first);
      }
      return baked;
    });
  }

  Future<_BakedGlyph?> _bakeGlyph(
    String text,
    TextStyle style,
    double dpr,
  ) async {
    // COVERAGE bake: white text on transparent, alpha channel out — the
    // GLYPH op multiplies the per-cell ink's alpha by it.
    final textPainter = timelineGlyphPainter(
      text,
      style.copyWith(color: const Color(0xFFFFFFFF)),
    );
    if (textPainter.width <= 0 || textPainter.height <= 0) {
      return null;
    }
    final width = (textPainter.width * dpr).ceil() + 2;
    final height = (textPainter.height * dpr).ceil() + 2;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder)
      ..translate(1, 1)
      ..scale(dpr, dpr);
    textPainter.paint(canvas, Offset.zero);
    final picture = recorder.endRecording();
    final image = picture.toImageSync(width, height);
    picture.dispose();
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    image.dispose();
    if (data == null) {
      return null;
    }
    final alpha = Uint8List(width * height);
    for (var i = 0; i < alpha.length; i += 1) {
      alpha[i] = data.getUint8(i * 4 + 3);
    }
    return _BakedGlyph(
      width: width,
      height: height,
      logicalWidth: textPainter.width,
      logicalHeight: textPainter.height,
      alpha: alpha,
    );
  }

  /// Rasters the request and returns the image TOGETHER WITH the content
  /// revision the raster's answers described — sampled in the same
  /// synchronous block as the substrate emit, so pixels and stamp can
  /// never disagree.
  Future<({ui.Image image, int celContentRevision})?> _raster(
    QaNativeEngine engine,
    _TileRequest request,
  ) async {
    final painter = request.painter;
    final dpr = request.devicePixelRatio;
    final spanCells = request.spanEndIndexExclusive - request.spanStartIndex;
    final width = (spanCells * painter.frameCellExtent * dpr).ceil();
    final height = (painter.crossAxisExtent * dpr).ceil();
    if (width <= 0 || height <= 0 || spanCells <= 0) {
      return null;
    }
    final horizontal = painter.axis == Axis.horizontal;
    final tileWidth = horizontal ? width : height;
    final tileHeight = horizontal ? height : width;

    final writer = TimelineGridTileOpWriter();
    // Sampled HERE — the substrate emit below reads every content answer
    // (`celHasContentForLayer` per cell) in this same synchronous block,
    // and nothing can bump the revision inside one block. This value is
    // what the pixels actually describe; the drain stamps it verbatim.
    final sampledCelContentRevision = painter.celContentRevision;
    timelineGridEmitSubstrate(
      writer,
      painter: painter,
      spanStartIndex: request.spanStartIndex,
      spanEndIndexExclusive: request.spanEndIndexExclusive,
      devicePixelRatio: dpr,
    );
    final atlas = await _emitForeground(
      writer,
      painter: painter,
      spanStartIndex: request.spanStartIndex,
      spanEndIndexExclusive: request.spanEndIndexExclusive,
      devicePixelRatio: dpr,
    );

    final ops = writer.build();
    final pixels = Uint8List(tileWidth * tileHeight * 4);
    final result = engine.gridRasterTileBytes(
      pixels: pixels,
      tileWidth: tileWidth,
      tileHeight: tileHeight,
      backgroundRgba: 0,
      ops: ops,
      atlas: atlas?.alpha,
      atlasWidth: atlas?.width ?? 0,
      atlasHeight: atlas?.height ?? 0,
    );
    if (result != 0) {
      assert(false, 'qa_grid_raster_tile failed: $result');
      return null;
    }

    final image = await _upload(pixels, tileWidth, tileHeight);
    return (image: image, celContentRevision: sampledCelContentRevision);
  }

  /// Bakes and emits the span's FOREGROUND ink (T3): hold-dash capsules
  /// inline, glyph text through the A8 atlas — geometry and ink probed
  /// from the painter (the substrate's fidelity rule). Returns the
  /// transient atlas the GLYPH ops reference, or null (no glyphs).
  Future<_TileAtlas?> _emitForeground(
    TimelineGridTileOpWriter writer, {
    required TimelineRowCellsPainter painter,
    required int spanStartIndex,
    required int spanEndIndexExclusive,
    required double devicePixelRatio,
  }) async {
    final dpr = devicePixelRatio;
    final horizontal = painter.axis == Axis.horizontal;
    final originRect = painter.cellRectFor(spanStartIndex);
    final originMain = horizontal ? originRect.left : originRect.top;

    final glyphCells =
        <({Rect rect, String text, TextStyle style, int rgba, String key})>[];
    for (
      var frameIndex = spanStartIndex;
      frameIndex < spanEndIndexExclusive;
      frameIndex += 1
    ) {
      final model = painter.cellModelAt(frameIndex);
      if (model.glyph.isEmpty) {
        continue;
      }
      final ink = painter.foregroundInkFor(model);
      final cellRect = painter.cellRectFor(frameIndex);
      final rect = horizontal
          ? cellRect.shift(Offset(-originMain, 0))
          : cellRect.shift(Offset(0, -originMain));
      if (model.ghost && model.glyph == timelineHoldDashGlyph) {
        // The hold dash (UI-R12 #18): a 1.4px capsule with the 3px
        // per-boundary break — the round caps come from the rrect SDF.
        if (horizontal) {
          if (rect.width > 4) {
            writer.rrectFill(
              (rect.left + 1.5) * dpr,
              (rect.center.dy - 0.7) * dpr,
              (rect.width - 3) * dpr,
              1.4 * dpr,
              0.7 * dpr,
              15,
              timelineGridPackRgba(ink),
            );
          }
        } else if (rect.height > 4) {
          writer.rrectFill(
            (rect.center.dx - 0.7) * dpr,
            (rect.top + 1.5) * dpr,
            1.4 * dpr,
            (rect.height - 3) * dpr,
            0.7 * dpr,
            15,
            timelineGridPackRgba(ink),
          );
        }
        continue;
      }
      final style = painter.glyphStyleFor(model);
      glyphCells.add((
        rect: rect,
        text: model.glyph,
        style: style,
        rgba: timelineGridPackRgba(ink),
        key: _glyphKey(model.glyph, style, dpr),
      ));
    }
    if (glyphCells.isEmpty) {
      return null;
    }

    final baked = <String, _BakedGlyph>{};
    for (final cell in glyphCells) {
      if (baked.containsKey(cell.key)) {
        continue;
      }
      final glyph = await _glyphA8(cell.text, cell.style, dpr);
      if (glyph != null) {
        baked[cell.key] = glyph;
      }
    }
    if (baked.isEmpty) {
      return null;
    }

    // Transient atlas: the span's distinct glyphs stacked vertically.
    var atlasWidth = 0;
    var atlasHeight = 0;
    final rowOf = <String, int>{};
    for (final entry in baked.entries) {
      rowOf[entry.key] = atlasHeight;
      atlasHeight += entry.value.height;
      if (entry.value.width > atlasWidth) {
        atlasWidth = entry.value.width;
      }
    }
    final atlas = Uint8List(atlasWidth * atlasHeight);
    for (final entry in baked.entries) {
      final glyph = entry.value;
      final rowStart = rowOf[entry.key]!;
      for (var y = 0; y < glyph.height; y += 1) {
        atlas.setRange(
          (rowStart + y) * atlasWidth,
          (rowStart + y) * atlasWidth + glyph.width,
          glyph.alpha,
          y * glyph.width,
        );
      }
    }

    for (final cell in glyphCells) {
      final glyph = baked[cell.key];
      if (glyph == null) {
        continue;
      }
      // The classic pass centers on the LOGICAL text size; the bake pads
      // 1 physical px on each side.
      final destX =
          (cell.rect.center.dx * dpr - glyph.logicalWidth * dpr / 2).round() -
          1;
      final destY =
          (cell.rect.center.dy * dpr - glyph.logicalHeight * dpr / 2).round() -
          1;
      writer.glyph(
        destX,
        destY,
        0,
        rowOf[cell.key]!,
        glyph.width,
        glyph.height,
        cell.rgba,
      );
    }
    return _TileAtlas(width: atlasWidth, height: atlasHeight, alpha: atlas);
  }

  Future<ui.Image> _upload(
    Uint8List pixels,
    int tileWidth,
    int tileHeight,
  ) async {
    final buffer = await ui.ImmutableBuffer.fromUint8List(pixels);
    final descriptor = ui.ImageDescriptor.raw(
      buffer,
      width: tileWidth,
      height: tileHeight,
      pixelFormat: ui.PixelFormat.rgba8888,
    );
    final codec = await descriptor.instantiateCodec();
    final frame = await codec.getNextFrame();
    codec.dispose();
    descriptor.dispose();
    buffer.dispose();
    return frame.image;
  }
}

class _TileRequest {
  const _TileRequest({
    required this.painter,
    required this.spanStartIndex,
    required this.spanEndIndexExclusive,
    required this.devicePixelRatio,
  });

  final TimelineRowCellsPainter painter;
  final int spanStartIndex;
  final int spanEndIndexExclusive;
  final double devicePixelRatio;
}

class _TileEntry {
  const _TileEntry({
    required this.substrateGeneration,
    required this.layer,
    required this.coverageIdentity,
    required this.frameCellExtent,
    required this.crossAxisExtent,
    required this.colorScheme,
    required this.exposureStateForLayer,
    required this.frameNameForLayer,
    required this.celHasContentForLayer,
    required this.celContentRevision,
    required this.baseTextStyle,
    required this.spanEndIndexExclusive,
    required this.devicePixelRatio,
    required this.framesPerSecond,
    required this.image,
  });

  /// #29: the (project, cut) world this tile's resolvers answered from.
  /// Redundant with the key today — and REQUIRED here anyway, so that if
  /// the key ever loses its generation segment the stale arms below still
  /// refuse to serve one cut's pixels to another. A silent regression is
  /// the one failure mode a cache is not allowed to have.
  final String substrateGeneration;

  final Object layer;

  /// ㉘: what the row's coverage follows when it is not the layer — a
  /// camera row's keys live on `cut.camera`, so a tile baked before a key
  /// was added kept matching forever and served the old picture back.
  final Object? coverageIdentity;

  final double frameCellExtent;
  final double crossAxisExtent;
  final Object colorScheme;
  final Object exposureStateForLayer;
  final Object? frameNameForLayer;
  final Object? celHasContentForLayer;

  /// The RESOLVER above answers per cell, so its identity says nothing
  /// about whether a cel just gained pixels — a fresh stroke left this
  /// tile "matching" and serving the old grey back. The revision is the
  /// content's own version — the value `_raster` SAMPLED alongside its
  /// content reads, never a live read at store time (a crossing landing
  /// mid-raster would stamp pre-crossing pixels as post-crossing and
  /// `matches` would serve them fresh forever).
  final int celContentRevision;

  final TextStyle baseTextStyle;
  final int spanEndIndexExclusive;
  final double devicePixelRatio;

  /// D32/D38: the interior seam strengths depend on the counting fps (a
  /// second boundary's line is the strongest), so a project fps change
  /// must re-raster — rare, but a stale strength would otherwise survive
  /// until an unrelated bump.
  final int framesPerSecond;
  final ui.Image image;

  /// The `shouldRepaint` identity, tile edition: any changed look fact
  /// re-rasters (glyphs live in the tiles too — T3 — so the glyph
  /// sources join the key).
  bool matches(
    TimelineRowCellsPainter painter,
    int spanEndIndexExclusive,
    double devicePixelRatio,
  ) {
    // The cut's LENGTH is deliberately absent: it is not baked into these
    // tiles any more (the out-of-cut wash became its own overlay), so a
    // cut-length drag re-rasters nothing.
    return substrateGeneration == painter.substrateGeneration &&
        identical(layer, painter.layer) &&
        coverageIdentity == painter.coverageIdentity &&
        frameCellExtent == painter.frameCellExtent &&
        crossAxisExtent == painter.crossAxisExtent &&
        identical(colorScheme, painter.colorScheme) &&
        // R9 #16: `==`, NOT `identical`. A host hands these in as instance
        // method tear-offs (`_session.exposureStateForLayer`), and Dart
        // makes a FRESH closure object for each tear-off — measured:
        // `identical(s.f, s.f)` is false while `s.f == s.f` is true, and
        // tear-offs of different receivers are correctly unequal. So
        // `identical` here answered "no" on every rebuild, every tile went
        // stale, and up to 32 of them re-rastered one await at a time with
        // a repaint each: the ~100ms lag between the [+] tap and the cel
        // appearing. `==` asks the question we actually mean — is this the
        // same function? — without weakening the contract.
        exposureStateForLayer == painter.exposureStateForLayer &&
        frameNameForLayer == painter.frameNameForLayer &&
        celHasContentForLayer == painter.celHasContentForLayer &&
        celContentRevision == painter.celContentRevision &&
        baseTextStyle == painter.baseTextStyle &&
        framesPerSecond == painter.framesPerSecond &&
        this.spanEndIndexExclusive == spanEndIndexExclusive &&
        this.devicePixelRatio == devicePixelRatio;
  }
}

/// One baked glyph: A8 coverage at physical resolution (1px pad on
/// every side) plus the LOGICAL text size the classic pass centers on.
class _BakedGlyph {
  const _BakedGlyph({
    required this.width,
    required this.height,
    required this.logicalWidth,
    required this.logicalHeight,
    required this.alpha,
  });

  final int width;
  final int height;
  final double logicalWidth;
  final double logicalHeight;
  final Uint8List alpha;
}

/// The per-raster transient atlas (a vertical stack of the span's
/// distinct glyphs) the GLYPH ops reference.
class _TileAtlas {
  const _TileAtlas({
    required this.width,
    required this.height,
    required this.alpha,
  });

  final int width;
  final int height;
  final Uint8List alpha;
}

/// Emits the SUBSTRATE op stream for [painter]'s cells in
/// [spanStartIndex, spanEndIndexExclusive): the background fill and the
/// block border per cell — geometry probed from the painter itself
/// ([TimelineRowCellsPainter.cellRectFor] / `resolvedCellStyleFor`), so
/// the tile look can never drift from the classic paint's. Coordinates
/// are tile-local physical pixels (row coords minus the span origin,
/// times DPR). Foreground ink (glyphs, dashes) stays the painter's Dart
/// pass.
Int32List timelineGridSubstrateOps({
  required TimelineRowCellsPainter painter,
  required int spanStartIndex,
  required int spanEndIndexExclusive,
  required double devicePixelRatio,
}) {
  final writer = TimelineGridTileOpWriter();
  timelineGridEmitSubstrate(
    writer,
    painter: painter,
    spanStartIndex: spanStartIndex,
    spanEndIndexExclusive: spanEndIndexExclusive,
    devicePixelRatio: devicePixelRatio,
  );
  return writer.build();
}

/// The writer-append form of [timelineGridSubstrateOps] — the store
/// appends the foreground pass (T3) to the same stream.
void timelineGridEmitSubstrate(
  TimelineGridTileOpWriter writer, {
  required TimelineRowCellsPainter painter,
  required int spanStartIndex,
  required int spanEndIndexExclusive,
  required double devicePixelRatio,
}) {
  final horizontal = painter.axis == Axis.horizontal;
  final originRect = painter.cellRectFor(spanStartIndex);
  final originMain = horizontal ? originRect.left : originRect.top;

  for (
    var frameIndex = spanStartIndex;
    frameIndex < spanEndIndexExclusive;
    frameIndex += 1
  ) {
    final style = painter.resolvedCellStyleFor(frameIndex);
    final background = style.background;
    final border = style.border;
    if (background.a <= 0 && border.a <= 0) {
      continue;
    }
    final rect = painter.cellRectFor(frameIndex);
    final local = horizontal
        ? rect.shift(Offset(-originMain, 0))
        : rect.shift(Offset(0, -originMain));

    // The radius map is uniform-6 per rounded corner (the painter's
    // _cellRadius): a corner MASK captures it exactly.
    final radius = style.radius;
    var mask = 0;
    var radiusValue = 0.0;
    if (radius != null) {
      if (radius.topLeft.x > 0) {
        mask |= TimelineGridTileOp.cornerTopLeft;
        radiusValue = radius.topLeft.x;
      }
      if (radius.topRight.x > 0) {
        mask |= TimelineGridTileOp.cornerTopRight;
        radiusValue = radius.topRight.x;
      }
      if (radius.bottomLeft.x > 0) {
        mask |= TimelineGridTileOp.cornerBottomLeft;
        radiusValue = radius.bottomLeft.x;
      }
      if (radius.bottomRight.x > 0) {
        mask |= TimelineGridTileOp.cornerBottomRight;
        radiusValue = radius.bottomRight.x;
      }
    }

    if (background.a > 0) {
      writer.rrectFill(
        local.left * devicePixelRatio,
        local.top * devicePixelRatio,
        local.width * devicePixelRatio,
        local.height * devicePixelRatio,
        radiusValue * devicePixelRatio,
        mask,
        timelineGridPackRgba(background),
      );
    }
    if (border.a > 0) {
      // Border.all paints INSIDE the box: stroke centered half a pixel
      // in (the painter's borderRect = rect.deflate(0.5), width 1).
      final borderRect = local.deflate(0.5);
      writer.rrectStroke(
        borderRect.left * devicePixelRatio,
        borderRect.top * devicePixelRatio,
        borderRect.width * devicePixelRatio,
        borderRect.height * devicePixelRatio,
        radiusValue * devicePixelRatio,
        mask,
        1.0 * devicePixelRatio,
        timelineGridPackRgba(border),
      );
    }

    // D32/D38: the block-interior seam — the painter's own contract
    // ([TimelineRowCellsPainter.heldSeamLineFor]) probed and mirrored, an
    // opaque plain-rect fill (the multiply was computed in Dart, so no
    // blend op is needed here).
    final seam = painter.heldSeamLineFor(frameIndex);
    if (seam != null) {
      final seamLocal = horizontal
          ? seam.rect.shift(Offset(-originMain, 0))
          : seam.rect.shift(Offset(0, -originMain));
      writer.rrectFill(
        seamLocal.left * devicePixelRatio,
        seamLocal.top * devicePixelRatio,
        seamLocal.width * devicePixelRatio,
        seamLocal.height * devicePixelRatio,
        0,
        0,
        timelineGridPackRgba(seam.color),
      );
    }
  }
}
