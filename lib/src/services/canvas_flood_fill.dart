import 'dart:ffi' show Pointer, Uint8;
import 'dart:math' as math;
import 'dart:typed_data';

import '../core/floor_math.dart';
import '../models/bitmap_surface.dart';
import '../models/bitmap_tile.dart';
import '../models/brush_dab.dart';
import '../models/brush_stamp_image.dart';
import '../models/brush_tip_shape.dart';
import '../models/canvas_point.dart';
import '../models/cut.dart';
import '../models/tile_coord.dart';
import '../native/qa_native_engine.dart';
import '../ui/dev_profile.dart';
import 'canvas_color_sampler.dart';
import 'canvas_selection.dart';
import 'canvas_selection_region.dart';
import 'cut_frame_composite_plan.dart';

/// P6 fill options — the Tool Settings panel's knobs (R11-④).
class FloodFillOptions {
  const FloodFillOptions({
    this.tolerance = 32,
    this.expandPx = 1,
    this.antiAlias = true,
    this.gapClosePx = 0,
    this.extendBeyondCanvas = false,
  });

  /// Max per-channel distance from the seed color that still fills.
  final int tolerance;

  /// Region growth in pixels AFTER the fill — closes the classic hairline
  /// gap between the fill and anti-aliased ink edges.
  final int expandPx;

  /// One soft pass over the mask edge.
  final bool antiAlias;

  /// Close-gap fill (R20-C1, the CSP "틈 닫기"): barriers act as if
  /// thickened by this radius, so the fill cannot leak through line-art
  /// gaps narrower than ~2× this value; the region then grows back to
  /// the REAL barriers. 0 = off. Forces a full compose (the leak search
  /// needs the whole picture), so it costs more than a plain fill.
  final int gapClosePx;

  /// Pasteboard fill: the fill boundary moves from the canvas rect to a
  /// finite apron around it (see [pasteboardFillMargin]) so regions
  /// crossing the canvas edge fill too. A flood that reaches the apron's
  /// outer wall means the region is NOT closed — the fill aborts and the
  /// caller reports the leak instead of flooding the surround
  /// (the raster equivalent of Flash's closed-shape rule).
  final bool extendBeyondCanvas;

  FloodFillOptions copyWith({
    int? tolerance,
    int? expandPx,
    bool? antiAlias,
    int? gapClosePx,
    bool? extendBeyondCanvas,
  }) {
    return FloodFillOptions(
      tolerance: tolerance ?? this.tolerance,
      expandPx: expandPx ?? this.expandPx,
      antiAlias: antiAlias ?? this.antiAlias,
      gapClosePx: gapClosePx ?? this.gapClosePx,
      extendBeyondCanvas: extendBeyondCanvas ?? this.extendBeyondCanvas,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is FloodFillOptions &&
      other.tolerance == tolerance &&
      other.expandPx == expandPx &&
      other.antiAlias == antiAlias &&
      other.gapClosePx == gapClosePx &&
      other.extendBeyondCanvas == extendBeyondCanvas;

  @override
  int get hashCode =>
      Object.hash(tolerance, expandPx, antiAlias, gapClosePx, extendBeyondCanvas);
}

/// The extended fill's apron width per side: one canvas size, capped so
/// the fill raster stays allocatable (a full 3×3 pasteboard raster of an
/// 8K canvas would be gigabytes). Canvases at or under the cap get the
/// exact pasteboard as their fill wall; larger ones get a generous apron
/// — either way the wall is FINITE, which is what makes leak detection
/// and "no infinite flood" structural.
const int pasteboardFillMarginCap = 1024;

int _pasteboardFillMargin(int canvasDimension) =>
    math.min(canvasDimension, pasteboardFillMarginCap);

/// The filled region as a coverage mask in canvas coordinates.
class FloodFillRegion {
  const FloodFillRegion({
    required this.left,
    required this.top,
    required this.width,
    required this.height,
    required this.mask,
  });

  final int left;
  final int top;
  final int width;
  final int height;

  /// Row-major coverage bytes (width × height), 0..255.
  final Uint8List mask;
}

/// The fill's sampling target ("fill what you see"): the visible picture
/// as a straight-RGB raster, composited LAZILY tile by tile as the flood
/// visits pixels — a fill only pays for the region it actually floods,
/// never the whole canvas (R11-③: the eager full-canvas compose froze the
/// tap for seconds on big canvases). Posed layers are skipped (v1, same
/// rule as the eyedropper).
class LazyCanvasRasterRgb {
  /// With the native engine loaded the raster lives in native memory
  /// (R18 A-2b): the compose loops write through typed-data views
  /// unchanged, and the C flood stepper reads the SAME bytes — no
  /// copies between compose and flood.
  factory LazyCanvasRasterRgb({
    required Cut cut,
    required int frameIndex,
    required LayerFrameSurfaceResolver surfaceResolver,
    int paperColor = canvasPaperColor,
    bool extendBeyondCanvas = false,
  }) {
    // Extended (pasteboard) fills widen the raster by a finite apron and
    // shift its origin into negative world space; the default raster IS
    // the canvas at origin (0, 0), byte-identical to before.
    final marginX = extendBeyondCanvas
        ? _pasteboardFillMargin(cut.canvasSize.width)
        : 0;
    final marginY = extendBeyondCanvas
        ? _pasteboardFillMargin(cut.canvasSize.height)
        : 0;
    final rasterWidth = cut.canvasSize.width + marginX * 2;
    final rasterHeight = cut.canvasSize.height + marginY * 2;
    final handles = QaNativeEngine.instance?.acquireFloodRaster(
      width: rasterWidth,
      height: rasterHeight,
      composeTileSize: _tileSize,
    );
    return LazyCanvasRasterRgb._(
      cut: cut,
      frameIndex: frameIndex,
      surfaceResolver: surfaceResolver,
      paperColor: paperColor,
      handles: handles,
      originX: -marginX,
      originY: -marginY,
      rasterWidth: rasterWidth,
      rasterHeight: rasterHeight,
    );
  }

  LazyCanvasRasterRgb._({
    required Cut cut,
    required int frameIndex,
    required LayerFrameSurfaceResolver surfaceResolver,
    required int paperColor,
    required QaFloodNativeHandles? handles,
    required this.originX,
    required this.originY,
    required int rasterWidth,
    required int rasterHeight,
  }) : nativeHandles = handles,
       width = rasterWidth,
       height = rasterHeight,
       rgb = handles?.rgbView ?? Uint8List(rasterWidth * rasterHeight * 4),
       _paperR = (paperColor >> 16) & 0xFF,
       _paperG = (paperColor >> 8) & 0xFF,
       _paperB = paperColor & 0xFF,
       _tilesX = (rasterWidth + _tileSize - 1) ~/ _tileSize,
       _composed =
           handles?.composedView ??
           Uint8List(
             ((rasterWidth + _tileSize - 1) ~/ _tileSize) *
                 ((rasterHeight + _tileSize - 1) ~/ _tileSize),
           ) {
    // Surfaces resolve ONCE (a cold resolve may replay paint commands).
    final entries = [
      for (final entry in resolveCutFrameCompositeEntries(
        cut: cut,
        frameIndex: frameIndex,
      ))
        if (entry.pose == null) entry,
    ];
    // R20-C2 reference layers (the CSP lighthouse): when any visible
    // layer carries the fill-reference flag, the fill reads ONLY the
    // flagged layers — paint layers stop blocking or leaking fills
    // traced against the line art. No flag = today's fill-what-you-see.
    final hasReference = entries.any((entry) => entry.layer.isFillReference);
    for (final entry in entries) {
      if (hasReference && !entry.layer.isFillReference) {
        continue;
      }
      final surface = surfaceResolver(entry.layer, entry.frame);
      if (surface != null) {
        _layers.add((surface: surface, opacity: entry.opacity));
      }
    }
  }

  static const int _tileSize = 256;

  /// Non-null when the raster is native-backed — hand this to
  /// [floodFillRegion] so the C stepper floods the same memory.
  final QaFloodNativeHandles? nativeHandles;

  /// Raster dimensions (canvas + apron when extended).
  final int width;
  final int height;

  /// World coordinate of raster (0, 0): (0, 0) for canvas fills,
  /// negative for extended (pasteboard) fills. World = raster + origin.
  final int originX;
  final int originY;

  /// `width*height*4` RGBX bytes (X always 0 — R22-D SIMD contract);
  /// only composed tiles hold real pixels — read through
  /// [ensureComposedAt].
  final Uint8List rgb;

  final int _paperR;
  final int _paperG;
  final int _paperB;
  final int _tilesX;
  final Uint8List _composed;
  final List<({BitmapSurface surface, double opacity})> _layers = [];

  /// Guarantees the tile containing pixel [index] (row-major) is composed.
  void ensureComposedAt(int index) {
    final x = index % width;
    final y = index ~/ width;
    final tileIndex = (y ~/ _tileSize) * _tilesX + (x ~/ _tileSize);
    if (_composed[tileIndex] != 0) {
      return;
    }
    _composed[tileIndex] = 1;
    _composeTile((x ~/ _tileSize) * _tileSize, (y ~/ _tileSize) * _tileSize);
  }

  /// R25-③: composes every still-uncomposed tile that [pixelIndices]
  /// touch through ONE pooled native call — within a tile the paper +
  /// layer order is preserved (bytes identical to [ensureComposedAt]);
  /// tiles fan out across the worker pool. Engine-less falls back to
  /// the per-tile path.
  void ensureComposedBatch(Int32List pixelIndices) {
    final native = QaNativeEngine.instance;
    final handles = nativeHandles;
    if (native == null || handles == null) {
      for (final index in pixelIndices) {
        ensureComposedAt(index);
      }
      return;
    }
    final tiles =
        <
          ({
            int left,
            int top,
            int rightExclusive,
            int bottomExclusive,
            int firstBlend,
            int blendCount,
          })
        >[];
    // Holds every tile whose POINTER is staged below, so none of their
    // buffers can be finalized before the batch call consumes them.
    final keepAlive = <BitmapTile>[];
    final blends =
        <
          ({
            Pointer<Uint8> pixels,
            int tileSize,
            int baseX,
            int baseY,
            int clipLeft,
            int clipTop,
            int clipRightExclusive,
            int clipBottomExclusive,
            int opacityInt,
          })
        >[];
    for (final index in pixelIndices) {
      final x = index % width;
      final y = index ~/ width;
      final tileIndex = (y ~/ _tileSize) * _tilesX + (x ~/ _tileSize);
      if (_composed[tileIndex] != 0) {
        continue;
      }
      _composed[tileIndex] = 1;
      final left = (x ~/ _tileSize) * _tileSize;
      final top = (y ~/ _tileSize) * _tileSize;
      final right = math.min(left + _tileSize, width);
      final bottom = math.min(top + _tileSize, height);
      final firstBlend = blends.length;
      // Surface tiles live in WORLD space (raster + origin); bases pass
      // back in raster space, so tile-local offsets stay (world - base).
      final worldLeft = left + originX;
      final worldTop = top + originY;
      final worldRight = right + originX;
      final worldBottom = bottom + originY;
      for (final layer in _layers) {
        final surface = layer.surface;
        final opacityInt = (layer.opacity * 255).round();
        final surfaceTileSize = surface.tileSize;
        for (
          var ty = floorDiv(worldTop, surfaceTileSize);
          ty <= floorDiv(worldBottom - 1, surfaceTileSize);
          ty += 1
        ) {
          for (
            var tx = floorDiv(worldLeft, surfaceTileSize);
            tx <= floorDiv(worldRight - 1, surfaceTileSize);
            tx += 1
          ) {
            // ⚠️ `tileAt`, NOT `surface.tiles[...]`. The `tiles` getter is
            // `Map.unmodifiable(_tiles)` — it copies the WHOLE map, and
            // this is the inner line of a nested loop over every tile the
            // fill touches. Measured at 82.7 ms for a 1024-tile canvas,
            // which is a tap that feels broken rather than a frame that
            // is slightly late.
            final tile = surface.tileAt(TileCoord(x: tx, y: ty));
            if (tile == null) {
              continue;
            }
            final baseX = tx * surfaceTileSize - originX;
            final baseY = ty * surfaceTileSize - originY;
            // The staged pointer outlives this loop (the batch call below
            // reads it), so the TILE must stay reachable until then —
            // keepAlive does that (see BitmapTile.readPixels).
            keepAlive.add(tile);
            blends.add((
              pixels: tile.readPixels((pointer, _) => pointer),
              tileSize: tile.size,
              baseX: baseX,
              baseY: baseY,
              clipLeft: math.max(left, baseX),
              clipTop: math.max(top, baseY),
              clipRightExclusive: math.min(right, baseX + surfaceTileSize),
              clipBottomExclusive: math.min(bottom, baseY + surfaceTileSize),
              opacityInt: opacityInt,
            ));
          }
        }
      }
      tiles.add((
        left: left,
        top: top,
        rightExclusive: right,
        bottomExclusive: bottom,
        firstBlend: firstBlend,
        blendCount: blends.length - firstBlend,
      ));
    }
    if (tiles.isEmpty) {
      return;
    }
    native.fillComposeBatch(
      rasterWidth: width,
      paperR: _paperR,
      paperG: _paperG,
      paperB: _paperB,
      tiles: tiles,
      blends: blends,
    );
    // Reached only after the kernel has read every staged pointer: this
    // use is what keeps the tiles above alive across the call.
    keepAlive.clear();
  }

  void _composeTile(int left, int top) {
    final right = math.min(left + _tileSize, width);
    final bottom = math.min(top + _tileSize, height);

    // R18 A-2c: with a native-backed raster the paper fill and the layer
    // blends run in the C kernels — byte-identical to the Dart loops
    // below (parity-pinned); Dart stays the reference and the fallback.
    final native = QaNativeEngine.instance;
    final handles = nativeHandles;
    if (native != null && handles != null) {
      native.fillPaperRect(
        handles: handles,
        left: left,
        top: top,
        rightExclusive: right,
        bottomExclusive: bottom,
        paperR: _paperR,
        paperG: _paperG,
        paperB: _paperB,
      );
      for (final layer in _layers) {
        final surface = layer.surface;
        final opacityInt = (layer.opacity * 255).round();
        final surfaceTileSize = surface.tileSize;
        for (
          var ty = floorDiv(top + originY, surfaceTileSize);
          ty <= floorDiv(bottom + originY - 1, surfaceTileSize);
          ty += 1
        ) {
          for (
            var tx = floorDiv(left + originX, surfaceTileSize);
            tx <= floorDiv(right + originX - 1, surfaceTileSize);
            tx += 1
          ) {
            // ⚠️ `tileAt`, NOT `surface.tiles[...]`. The `tiles` getter is
            // `Map.unmodifiable(_tiles)` — it copies the WHOLE map, and
            // this is the inner line of a nested loop over every tile the
            // fill touches. Measured at 82.7 ms for a 1024-tile canvas,
            // which is a tap that feels broken rather than a frame that
            // is slightly late.
            final tile = surface.tileAt(TileCoord(x: tx, y: ty));
            if (tile == null) {
              continue;
            }
            final baseX = tx * surfaceTileSize - originX;
            final baseY = ty * surfaceTileSize - originY;
            tile.readPixels(
              (pointer, _) => native.fillComposeTile(
                handles: handles,
                tilePixels: pointer,
                tileSize: tile.size,
                baseX: baseX,
                baseY: baseY,
                clipLeft: math.max(left, baseX),
                clipTop: math.max(top, baseY),
                clipRightExclusive: math.min(right, baseX + surfaceTileSize),
                clipBottomExclusive: math.min(bottom, baseY + surfaceTileSize),
                opacityInt: opacityInt,
              ),
            );
          }
        }
      }
      return;
    }

    for (var y = top; y < bottom; y += 1) {
      // RGBX (R22-D): X writes 0 so the raster matches the native
      // kernels byte for byte.
      var target = (y * width + left) * 4;
      for (var x = left; x < right; x += 1) {
        rgb[target] = _paperR;
        rgb[target + 1] = _paperG;
        rgb[target + 2] = _paperB;
        rgb[target + 3] = 0;
        target += 4;
      }
    }
    for (final layer in _layers) {
      final surface = layer.surface;
      // Integer blend (R15-⑥): the per-pixel double multiply/round path
      // was a whole-canvas-scale cost on big fills; the raster only feeds
      // seed MATCHING (tolerance compares), so byte-rounded source-over
      // is exact enough by construction.
      final opacityInt = (layer.opacity * 255).round();
      final surfaceTileSize = surface.tileSize;
      for (
        var ty = floorDiv(top + originY, surfaceTileSize);
        ty <= floorDiv(bottom + originY - 1, surfaceTileSize);
        ty += 1
      ) {
        for (
          var tx = floorDiv(left + originX, surfaceTileSize);
          tx <= floorDiv(right + originX - 1, surfaceTileSize);
          tx += 1
        ) {
          // ⚠️ `tileAt`, NOT `surface.tiles[...]` — the getter copies the
          // whole map, and this is inside a nested loop. See above.
          final tile = surface.tileAt(TileCoord(x: tx, y: ty));
          if (tile == null) {
            continue;
          }
          // Snapshot the tile's buffer ONCE (the getter copies).
          final pixels = tile.pixels;
          final baseX = tx * surfaceTileSize - originX;
          final baseY = ty * surfaceTileSize - originY;
          final clipLeft = math.max(left, baseX);
          final clipRight = math.min(right, baseX + surfaceTileSize);
          final clipTop = math.max(top, baseY);
          final clipBottom = math.min(bottom, baseY + surfaceTileSize);
          for (var y = clipTop; y < clipBottom; y += 1) {
            var source =
                ((y - baseY) * surfaceTileSize + (clipLeft - baseX)) * 4;
            var target = (y * width + clipLeft) * 4;
            for (var x = clipLeft; x < clipRight; x += 1) {
              final alphaByte = pixels[source + 3];
              if (alphaByte != 0) {
                final effective = (alphaByte * opacityInt + 127) ~/ 255;
                final inverse = 255 - effective;
                rgb[target] =
                    (pixels[source] * effective +
                        rgb[target] * inverse +
                        127) ~/
                    255;
                rgb[target + 1] =
                    (pixels[source + 1] * effective +
                        rgb[target + 1] * inverse +
                        127) ~/
                    255;
                rgb[target + 2] =
                    (pixels[source + 2] * effective +
                        rgb[target + 2] * inverse +
                        127) ~/
                    255;
              }
              source += 4;
              target += 4;
            }
          }
        }
      }
    }
  }
}

/// Scanline flood fill over an RGB raster from the seed, within
/// [FloodFillOptions.tolerance] of the SEED color; null when the seed is
/// out of bounds. Includes expand + anti-alias post passes.
///
/// R14-② performance contract: [ensureComposed] fires per COMPOSE-TILE
/// crossing (256px, [LazyCanvasRasterRgb]'s tile), never per pixel — the
/// old per-visit dynamic dispatch across tens of millions of pixels was
/// the multi-second fill freeze on large regions. The vertical seeding
/// enqueues one seed per contiguous run (not every matching pixel), and
/// the expand/anti-alias passes operate on the CROPPED region instead of
/// copying the full canvas array per pass.
FloodFillRegion? floodFillRegion({
  required Uint8List rgb,
  required int width,
  required int height,
  required int seedX,
  required int seedY,
  FloodFillOptions options = const FloodFillOptions(),
  void Function(int index)? ensureComposed,
  void Function(Int32List pixelIndices)? ensureComposedBatch,
  QaFloodNativeHandles? nativeHandles,
}) {
  if (seedX < 0 || seedY < 0 || seedX >= width || seedY >= height) {
    return null;
  }
  ensureComposed?.call(seedY * width + seedX);
  final seedIndex = (seedY * width + seedX) * 4;
  final seedR = rgb[seedIndex];
  final seedG = rgb[seedIndex + 1];
  final seedB = rgb[seedIndex + 2];
  final tolerance = options.tolerance;

  // R20-C1 close-gap fill: barriers thickened by the gap radius (chamfer
  // distance-transform erosion of the fillable field), flood, then grow
  // back to the real barriers. Needs the WHOLE picture composed — the
  // leak search is global by nature.
  if (options.gapClosePx > 0) {
    if (ensureComposed != null) {
      const composeTile = 256;
      for (var ty = 0; ty < height; ty += composeTile) {
        final rowStart = ty * width;
        for (var tx = 0; tx < width; tx += composeTile) {
          ensureComposed(rowStart + tx);
        }
      }
    }
    final native = QaNativeEngine.instance;
    if (native != null && nativeHandles != null) {
      final result = native.gapCloseFillRun(
        handles: nativeHandles,
        seedX: seedX,
        seedY: seedY,
        seedR: seedR,
        seedG: seedG,
        seedB: seedB,
        tolerance: tolerance,
        gapClosePx: options.gapClosePx,
      );
      if (result != null) {
        final cropLeft = math.max(0, result.minX - options.expandPx);
        final cropTop = math.max(0, result.minY - options.expandPx);
        final cropRight = math.min(width - 1, result.maxX + options.expandPx);
        final cropBottom = math.min(height - 1, result.maxY + options.expandPx);
        return FloodFillRegion(
          left: cropLeft,
          top: cropTop,
          width: cropRight - cropLeft + 1,
          height: cropBottom - cropTop + 1,
          mask: native.finishFillMask(
            canvasWidth: width,
            cropLeft: cropLeft,
            cropTop: cropTop,
            regionWidth: cropRight - cropLeft + 1,
            regionHeight: cropBottom - cropTop + 1,
            expandPx: options.expandPx,
            antiAlias: options.antiAlias,
          ),
        );
      }
      // Stack overflow inside the kernel (pathological run counts) —
      // fall through to the Dart reference, which grows freely.
    }
    return _gapCloseFloodRegion(
      rgb: rgb,
      width: width,
      height: height,
      seedX: seedX,
      seedY: seedY,
      seedR: seedR,
      seedG: seedG,
      seedB: seedB,
      options: options,
    );
  }

  // R18 A-2b / R22-E3: with a native-backed raster the wave-parallel C
  // engine runs the flood (per-compose-tile local floods across the
  // worker pool around the lazy compose; result set identical by
  // construction — parity-pinned). The Dart loop below stays as the
  // reference and the fallback.
  final native = QaNativeEngine.instance;
  if (native != null && nativeHandles != null && ensureComposed != null) {
    final result = native.floodFillRun(
      handles: nativeHandles,
      seedX: seedX,
      seedY: seedY,
      seedR: seedR,
      seedG: seedG,
      seedB: seedB,
      tolerance: tolerance,
      ensureComposed: ensureComposed,
      ensureComposedBatch: ensureComposedBatch,
    );
    if (result != null) {
      // The finish (crop + expand + anti-alias) runs natively too
      // (A-2d): the verification lab showed these full-region passes
      // were most of what remained in the fill.flood probe. Same crop
      // math as the Dart tail below.
      final cropLeft = math.max(0, result.minX - options.expandPx);
      final cropTop = math.max(0, result.minY - options.expandPx);
      final cropRight = math.min(width - 1, result.maxX + options.expandPx);
      final cropBottom = math.min(height - 1, result.maxY + options.expandPx);
      return FloodFillRegion(
        left: cropLeft,
        top: cropTop,
        width: cropRight - cropLeft + 1,
        height: cropBottom - cropTop + 1,
        mask: native.finishFillMask(
          canvasWidth: width,
          cropLeft: cropLeft,
          cropTop: cropTop,
          regionWidth: cropRight - cropLeft + 1,
          regionHeight: cropBottom - cropTop + 1,
          expandPx: options.expandPx,
          antiAlias: options.antiAlias,
        ),
      );
    }
    // Wave arena failure (belt) — fall through to the Dart reference,
    // which starts from its own clean heap state.
  }

  // Pure byte compare — the caller guarantees the pixel's compose tile via
  // the crossing checks below (one ensure per 256px boundary).
  bool matchesComposed(int index) {
    final base = index * 4;
    return (rgb[base] - seedR).abs() <= tolerance &&
        (rgb[base + 1] - seedG).abs() <= tolerance &&
        (rgb[base + 2] - seedB).abs() <= tolerance;
  }

  final filled = Uint8List(width * height);
  final stack = <int>[seedY * width + seedX];
  filled[seedY * width + seedX] = 255;
  var minX = seedX, maxX = seedX, minY = seedY, maxY = seedY;

  while (stack.isNotEmpty) {
    final index = stack.removeLast();
    final y = index ~/ width;
    final rowStart = y * width;

    // Expand the scanline run left and right; ensure fires only when the
    // walk crosses into a new 256px compose tile.
    var left = index - rowStart;
    while (left > 0 && filled[rowStart + left - 1] == 0) {
      if ((left & 0xFF) == 0) {
        ensureComposed?.call(rowStart + left - 1);
      }
      if (!matchesComposed(rowStart + left - 1)) {
        break;
      }
      left -= 1;
      filled[rowStart + left] = 255;
    }
    var right = index - rowStart;
    while (right < width - 1 && filled[rowStart + right + 1] == 0) {
      if (((right + 1) & 0xFF) == 0) {
        ensureComposed?.call(rowStart + right + 1);
      }
      if (!matchesComposed(rowStart + right + 1)) {
        break;
      }
      right += 1;
      filled[rowStart + right] = 255;
    }
    minX = math.min(minX, left);
    maxX = math.max(maxX, right);
    minY = math.min(minY, y);
    maxY = math.max(maxY, y);

    // Seed the rows above and below across the run — ONE seed per
    // contiguous matching run (the seed's own expansion fills the rest);
    // enqueueing every matching pixel used to flood the queue with the
    // whole region.
    for (final dy in const [-1, 1]) {
      final neighborY = y + dy;
      if (neighborY < 0 || neighborY >= height) {
        continue;
      }
      final neighborRow = neighborY * width;
      ensureComposed?.call(neighborRow + left);
      var runOpen = false;
      for (var x = left; x <= right; x += 1) {
        if ((x & 0xFF) == 0 && x != left) {
          ensureComposed?.call(neighborRow + x);
        }
        final neighborIndex = neighborRow + x;
        if (filled[neighborIndex] == 0 && matchesComposed(neighborIndex)) {
          if (!runOpen) {
            filled[neighborIndex] = 255;
            stack.add(neighborIndex);
            runOpen = true;
          }
        } else {
          runOpen = false;
        }
      }
    }
  }

  return _cropAndFinishFloodRegion(
    filled: filled,
    width: width,
    height: height,
    minX: minX,
    maxX: maxX,
    minY: minY,
    maxY: maxY,
    options: options,
  );
}

/// The shared post-flood tail: crop to the flooded bounds, then the
/// expand and anti-alias passes region-locally (both the Dart and the
/// native flood produce the same `filled` set, so this tail is common).
FloodFillRegion _cropAndFinishFloodRegion({
  required Uint8List filled,
  required int width,
  required int height,
  required int minX,
  required int maxX,
  required int minY,
  required int maxY,
  required FloodFillOptions options,
}) {
  // Crop FIRST (with room for the expand growth), then run the expand and
  // anti-alias passes region-locally: the old grow pass copied and scanned
  // a full-canvas array per pass.
  final cropLeft = math.max(0, minX - options.expandPx);
  final cropTop = math.max(0, minY - options.expandPx);
  final cropRight = math.min(width - 1, maxX + options.expandPx);
  final cropBottom = math.min(height - 1, maxY + options.expandPx);
  final regionWidth = cropRight - cropLeft + 1;
  final regionHeight = cropBottom - cropTop + 1;
  final mask = Uint8List(regionWidth * regionHeight);
  for (var y = 0; y < regionHeight; y += 1) {
    final sourceStart = (cropTop + y) * width + cropLeft;
    mask.setRange(
      y * regionWidth,
      y * regionWidth + regionWidth,
      filled,
      sourceStart,
    );
  }

  // Expand: grow the region by N pixels (covers anti-aliased ink edges).
  for (var pass = 0; pass < options.expandPx; pass += 1) {
    final grown = Uint8List.fromList(mask);
    for (var y = 0; y < regionHeight; y += 1) {
      for (var x = 0; x < regionWidth; x += 1) {
        final index = y * regionWidth + x;
        if (mask[index] != 0) {
          continue;
        }
        final touches =
            (x > 0 && mask[index - 1] != 0) ||
            (x < regionWidth - 1 && mask[index + 1] != 0) ||
            (y > 0 && mask[index - regionWidth] != 0) ||
            (y < regionHeight - 1 && mask[index + regionWidth] != 0);
        if (touches) {
          grown[index] = 255;
        }
      }
    }
    mask.setAll(0, grown);
  }

  if (options.antiAlias) {
    // One soft edge pass: boundary mask pixels average their 4-neighbors.
    final smoothed = Uint8List.fromList(mask);
    for (var y = 0; y < regionHeight; y += 1) {
      for (var x = 0; x < regionWidth; x += 1) {
        final index = y * regionWidth + x;
        final center = mask[index];
        final leftV = x > 0 ? mask[index - 1] : 0;
        final rightV = x < regionWidth - 1 ? mask[index + 1] : 0;
        final upV = y > 0 ? mask[index - regionWidth] : 0;
        final downV = y < regionHeight - 1 ? mask[index + regionWidth] : 0;
        final sum = center + leftV + rightV + upV + downV;
        if (sum != center * 5) {
          smoothed[index] = ((center * 3 + (sum - center)) / 7).round();
        }
      }
    }
    mask.setAll(0, smoothed);
  }

  return FloodFillRegion(
    left: cropLeft,
    top: cropTop,
    width: regionWidth,
    height: regionHeight,
    mask: mask,
  );
}

/// The close-gap fill reference pipeline (R20-C1) — the C kernel
/// reproduces this EXACTLY (integer chamfer math throughout; parity is
/// pinned):
///
/// 1. fillable = per-pixel tolerance test against the seed color;
/// 2. chamfer 3-4 distance transform to the nearest barrier;
/// 3. erode: only pixels farther than `3 × gap` chamfer units fill —
///    a leak through a gap narrower than ~2×gap can't survive. If the
///    seed itself sits closer than that to a barrier, the gap HALVES
///    until the seed survives (deterministic; gap 0 degenerates to the
///    plain fill);
/// 4. scanline flood over the eroded field;
/// 5. grow back: a second distance transform from the flooded set,
///    keeping fillable pixels within `3 × gap` — the region reaches the
///    REAL barriers again (and slightly into the gap mouths, like CSP).
FloodFillRegion? _gapCloseFloodRegion({
  required Uint8List rgb,
  required int width,
  required int height,
  required int seedX,
  required int seedY,
  required int seedR,
  required int seedG,
  required int seedB,
  required FloodFillOptions options,
}) {
  const infinity = 60000;
  final pixelCount = width * height;
  final tolerance = options.tolerance;

  final fillable = Uint8List(pixelCount);
  for (var index = 0, base = 0; index < pixelCount; index += 1, base += 4) {
    if ((rgb[base] - seedR).abs() <= tolerance &&
        (rgb[base + 1] - seedG).abs() <= tolerance &&
        (rgb[base + 2] - seedB).abs() <= tolerance) {
      fillable[index] = 1;
    }
  }

  final dist = Uint16List(pixelCount);
  _chamferDistance(
    dist,
    from: fillable,
    zeroWhen: 0,
    width: width,
    height: height,
    infinity: infinity,
  );

  // Seed survival: halve the gap until the seed escapes erosion.
  var gap = options.gapClosePx;
  final seedIndex = seedY * width + seedX;
  while (gap > 0 && dist[seedIndex] <= 3 * gap) {
    gap ~/= 2;
  }
  final erodeThreshold = 3 * gap;

  // Scanline flood over the eroded field.
  final filled = Uint8List(pixelCount);
  final stack = <int>[seedIndex];
  filled[seedIndex] = 255;
  bool eroded(int index) => dist[index] > erodeThreshold;
  if (!eroded(seedIndex)) {
    return null; // The seed is a barrier pixel (gap already 0 here).
  }
  while (stack.isNotEmpty) {
    final index = stack.removeLast();
    final y = index ~/ width;
    final rowStart = y * width;
    var left = index - rowStart;
    while (left > 0 &&
        filled[rowStart + left - 1] == 0 &&
        eroded(rowStart + left - 1)) {
      left -= 1;
      filled[rowStart + left] = 255;
    }
    var right = index - rowStart;
    while (right < width - 1 &&
        filled[rowStart + right + 1] == 0 &&
        eroded(rowStart + right + 1)) {
      right += 1;
      filled[rowStart + right] = 255;
    }
    for (final dy in const [-1, 1]) {
      final neighborY = y + dy;
      if (neighborY < 0 || neighborY >= height) {
        continue;
      }
      final neighborRow = neighborY * width;
      var runOpen = false;
      for (var x = left; x <= right; x += 1) {
        final neighborIndex = neighborRow + x;
        if (filled[neighborIndex] == 0 && eroded(neighborIndex)) {
          if (!runOpen) {
            filled[neighborIndex] = 255;
            stack.add(neighborIndex);
            runOpen = true;
          }
        } else {
          runOpen = false;
        }
      }
    }
  }

  // Grow back to the real barriers: distance from the flooded set.
  final growDist = Uint16List(pixelCount);
  _chamferDistance(
    growDist,
    from: filled,
    zeroWhen: 255,
    width: width,
    height: height,
    infinity: infinity,
  );
  var minX = width, maxX = -1, minY = height, maxY = -1;
  for (var index = 0; index < pixelCount; index += 1) {
    if (fillable[index] != 0 && growDist[index] <= erodeThreshold) {
      filled[index] = 255;
      final x = index % width;
      final y = index ~/ width;
      if (x < minX) minX = x;
      if (x > maxX) maxX = x;
      if (y < minY) minY = y;
      if (y > maxY) maxY = y;
    } else {
      filled[index] = 0;
    }
  }
  if (maxX < 0) {
    return null;
  }

  return _cropAndFinishFloodRegion(
    filled: filled,
    width: width,
    height: height,
    minX: minX,
    maxX: maxX,
    minY: minY,
    maxY: maxY,
    options: options,
  );
}

/// Two-pass 3-4 chamfer distance transform: [target] receives the
/// distance (orthogonal step 3, diagonal 4, saturated at [infinity])
/// from every pixel to the nearest SOURCE pixel, where source means
/// `from[i] == zeroWhen`. Off-canvas neighbors are ignored (the canvas
/// edge is NOT a barrier). Integer math only — the C kernel mirrors it
/// exactly.
void _chamferDistance(
  Uint16List target, {
  required Uint8List from,
  required int zeroWhen,
  required int width,
  required int height,
  required int infinity,
}) {
  for (var index = 0; index < target.length; index += 1) {
    target[index] = from[index] == zeroWhen ? 0 : infinity;
  }
  // Forward pass (top-left → bottom-right).
  for (var y = 0; y < height; y += 1) {
    final row = y * width;
    for (var x = 0; x < width; x += 1) {
      final index = row + x;
      var best = target[index];
      if (best == 0) {
        continue;
      }
      if (x > 0 && target[index - 1] + 3 < best) {
        best = target[index - 1] + 3;
      }
      if (y > 0) {
        final up = index - width;
        if (target[up] + 3 < best) {
          best = target[up] + 3;
        }
        if (x > 0 && target[up - 1] + 4 < best) {
          best = target[up - 1] + 4;
        }
        if (x < width - 1 && target[up + 1] + 4 < best) {
          best = target[up + 1] + 4;
        }
      }
      target[index] = best > infinity ? infinity : best;
    }
  }
  // Backward pass (bottom-right → top-left).
  for (var y = height - 1; y >= 0; y -= 1) {
    final row = y * width;
    for (var x = width - 1; x >= 0; x -= 1) {
      final index = row + x;
      var best = target[index];
      if (best == 0) {
        continue;
      }
      if (x < width - 1 && target[index + 1] + 3 < best) {
        best = target[index + 1] + 3;
      }
      if (y < height - 1) {
        final down = index + width;
        if (target[down] + 3 < best) {
          best = target[down] + 3;
        }
        if (x < width - 1 && target[down + 1] + 4 < best) {
          best = target[down + 1] + 4;
        }
        if (x > 0 && target[down - 1] + 4 < best) {
          best = target[down - 1] + 4;
        }
      }
      target[index] = best > infinity ? infinity : best;
    }
  }
}

/// The SHAPE fill (유저 확정: 올가미 채우기는 A — 내부에 뭐가 있든 채운다):
/// the outline the user just drew, filled with [color] whatever is under
/// it.
///
/// It shares the flood's tail rather than resembling it. Once there is a
/// coverage mask the two are the same problem, so the expand and
/// anti-alias passes are literally [_cropAndFinishFloodRegion] — which is
/// why "AA follows the fill" (유저 확정) needed no new rasterizer: the
/// bucket's AA has always been a post-pass over a binary mask, and a
/// polygon's mask is binary too.
///
/// What it does NOT share is the front: no lazy compose, no seed, no
/// tolerance. A shape fill never looks at the picture, so it never pays to
/// composite one — this is markedly cheaper than a flood, not a variant of
/// it. Null when the outline covers no pixels at all.
BrushDab? buildShapeFillDab({
  required CanvasSelectionShape shape,
  required int color,
  FloodFillOptions options = const FloodFillOptions(),
}) {
  final region = CanvasSelectionRegion.shape(shape);
  final bounds = region.coverageBounds;
  final left = bounds.left.floor();
  final top = bounds.top.floor();
  final width = bounds.right.ceil() - left;
  final height = bounds.bottom.ceil() - top;
  if (width <= 0 || height <= 0) {
    return null;
  }
  final mask = region.maskFor(
    left: left,
    top: top,
    width: width,
    height: height,
  );
  var covers = false;
  for (final coverage in mask) {
    if (coverage != 0) {
      covers = true;
      break;
    }
  }
  if (!covers) {
    return null;
  }
  // The mask arrives cropped already, so the tail is handed the box it
  // will keep — the grow pass still needs room to grow into, which is what
  // the expand margin below is for.
  final margin = options.expandPx;
  final padded = Uint8List((width + margin * 2) * (height + margin * 2));
  for (var y = 0; y < height; y += 1) {
    padded.setRange(
      (y + margin) * (width + margin * 2) + margin,
      (y + margin) * (width + margin * 2) + margin + width,
      mask,
      y * width,
    );
  }
  final region2 = _cropAndFinishFloodRegion(
    filled: padded,
    width: width + margin * 2,
    height: height + margin * 2,
    minX: margin,
    maxX: margin + width - 1,
    minY: margin,
    maxY: margin + height - 1,
    options: options,
  );
  return _colorStampDab(
    region: region2,
    color: color,
    originX: left - margin,
    originY: top - margin,
  );
}

/// The whole P6 tap: compose → fill from [point] → the region as ONE
/// mask-tipped dab ("fill = one dab"), committed through the exact stroke
/// funnel — three-route parity, undo and .anicel serialization come free.
/// Null when nothing fills (seed off the fill raster), or when an
/// EXTENDED fill's flood reaches the apron wall — the region is not
/// closed; [onOpenRegion] fires so the UI can say so instead of silently
/// flooding the surround.
BrushDab? buildFillDab({
  required Cut cut,
  required int frameIndex,
  required LayerFrameSurfaceResolver surfaceResolver,
  required CanvasPoint point,
  required int color,
  FloodFillOptions options = const FloodFillOptions(),
  int paperColor = canvasPaperColor,
  void Function()? onOpenRegion,
}) {
  final raster = labProbe(
    'fill.raster-ctor',
    () => LazyCanvasRasterRgb(
      cut: cut,
      frameIndex: frameIndex,
      surfaceResolver: surfaceResolver,
      paperColor: paperColor,
      extendBeyondCanvas: options.extendBeyondCanvas,
    ),
  );
  final region = labProbe(
    'fill.flood',
    () => floodFillRegion(
      rgb: raster.rgb,
      width: raster.width,
      height: raster.height,
      seedX: point.x.floor() - raster.originX,
      seedY: point.y.floor() - raster.originY,
      options: options,
      ensureComposed: raster.ensureComposedAt,
      ensureComposedBatch: raster.ensureComposedBatch,
      nativeHandles: raster.nativeHandles,
    ),
  );
  if (options.extendBeyondCanvas) {
    // The extended raster grew the engine's fill arenas ~9×; give the
    // memory back once this tap's flood is done (the next canvas fill
    // re-allocs canvas size).
    QaNativeEngine.instance?.trimFloodRasterArena(
      keepBytes: cut.canvasSize.width * cut.canvasSize.height * 4,
    );
  }
  if (region == null) {
    return null;
  }
  if (options.extendBeyondCanvas) {
    // Leak detection: a flood that reached the apron's outer wall means
    // the region is OPEN (nothing bounded it before the wall). Refuse
    // the fill — the raster analogue of Flash refusing to fill an
    // unclosed shape.
    final reachedWall =
        region.left <= 0 ||
        region.top <= 0 ||
        region.left + region.width >= raster.width ||
        region.top + region.height >= raster.height;
    if (reachedWall) {
      onOpenRegion?.call();
      return null;
    }
  }

  return _colorStampDab(
    region: region,
    color: color,
    originX: raster.originX,
    originY: raster.originY,
  );
}

/// A coverage mask painted [color] and handed over as ONE stamp dab, its
/// region coordinates offset by ([originX], [originY]) into world space.
///
/// The fill lands as a COLOR STAMP (R15-⑥): rgba = fill color × mask
/// coverage, drawn 1:1 by the stamp blend path. The old square-padded
/// tip-mask dab re-sampled the giant mask bilinearly per pixel at every
/// materialization — a multi-second slice on large fills — and the stamp
/// is byte-exact by construction.
BrushDab _colorStampDab({
  required FloodFillRegion region,
  required int color,
  required int originX,
  required int originY,
}) {
  final r = (color >> 16) & 0xFF;
  final g = (color >> 8) & 0xFF;
  final b = color & 0xFF;
  final rgba = labProbe('fill.stamp-build', () {
    final mask = region.mask;
    final bytes = Uint8List(region.width * region.height * 4);
    if (Endian.host == Endian.little) {
      // One word store per pixel (R19-8K): the four byte stores below
      // were a 197ms term on an 8000² fill. Little-endian word layout
      // [r, g, b, coverage] is byte-identical to the byte loop.
      final words = Uint32List.view(bytes.buffer, 0, mask.length);
      final baseRgb = r | (g << 8) | (b << 16);
      for (var index = 0; index < mask.length; index += 1) {
        final coverage = mask[index];
        if (coverage == 0) {
          continue;
        }
        words[index] = baseRgb | (coverage << 24);
      }
      return bytes;
    }
    for (var index = 0; index < mask.length; index += 1) {
      final coverage = mask[index];
      if (coverage == 0) {
        continue;
      }
      final offset = index * 4;
      bytes[offset] = r;
      bytes[offset + 1] = g;
      bytes[offset + 2] = b;
      bytes[offset + 3] = coverage;
    }
    return bytes;
  });
  return BrushDab(
    // Region coords are raster-space; the dab lands in WORLD space.
    center: CanvasPoint(
      x: region.left + originX + region.width / 2,
      y: region.top + originY + region.height / 2,
    ),
    color: color,
    size: math.max(region.width, region.height).toDouble(),
    opacity: 1,
    flow: 1,
    hardness: 1,
    tipShape: BrushTipShape.square,
    pressure: 1,
    sequence: 0,
    stamp: BrushStampImage(
      id: 'fill-${DateTime.now().microsecondsSinceEpoch}',
      width: region.width,
      height: region.height,
      rgba: rgba,
    ),
  );
}
