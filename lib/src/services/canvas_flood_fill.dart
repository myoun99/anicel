import 'dart:ffi' show Pointer, Uint8;
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show Offset;

import '../core/argb_channels.dart';
import '../core/floor_math.dart';
import '../core/point_bounds.dart';
import '../models/dirty_region.dart';
import '../models/bitmap_surface.dart';
import '../models/bitmap_tile.dart';
import '../models/brush_dab.dart';
import '../models/brush_stamp_image.dart';
import '../models/brush_tip_shape.dart';
import '../models/canvas_point.dart';
import '../models/cut.dart';
import '../models/drawing_guide.dart';
import '../models/layer_id.dart';
import '../models/pasteboard_bounds.dart';
import '../models/tiles_covering.dart';
import '../native/qa_native_engine.dart';
import '../core/dev_profile.dart';
import '../core/seed_tolerance.dart';
import 'canvas_read_source.dart';
import 'canvas_selection_region.dart';
import 'cel_text_laying.dart';
import 'cut_frame_composite_plan.dart';
import 'brush_stroke_blend.dart' show bitmapSurfaceRegionPixels;
import 'guide_geometry.dart';
import 'layer_pose_matrix.dart';
import 'resample/resample_kernel.dart';
import 'resample/selection_resample.dart';
import 'mask_morphology.dart';
import 'mask_soft_edge.dart';

/// P6 fill options — the Tool Settings panel's knobs (R11-④).
class FloodFillOptions {
  const FloodFillOptions({
    this.tolerance = 32,
    this.expandPx = 1,
    this.antiAlias = true,
    this.gapClosePx = 0,
    this.extendBeyondCanvas = false,
    this.source = CanvasReadSource.display,
  });

  /// Which layers the flood reads (I-36) — the eyedropper's question and
  /// answers ([CanvasReadSource]). The default is the user's first mode,
  /// 「참조(보이는거 전부)」.
  final CanvasReadSource source;

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
  /// finite apron around it (see [pasteboardFillMarginCap]) so regions
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
    CanvasReadSource? source,
  }) {
    return FloodFillOptions(
      tolerance: tolerance ?? this.tolerance,
      expandPx: expandPx ?? this.expandPx,
      antiAlias: antiAlias ?? this.antiAlias,
      gapClosePx: gapClosePx ?? this.gapClosePx,
      extendBeyondCanvas: extendBeyondCanvas ?? this.extendBeyondCanvas,
      source: source ?? this.source,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is FloodFillOptions &&
      other.tolerance == tolerance &&
      other.expandPx == expandPx &&
      other.antiAlias == antiAlias &&
      other.gapClosePx == gapClosePx &&
      other.extendBeyondCanvas == extendBeyondCanvas &&
      other.source == source;

  @override
  int get hashCode => Object.hash(
    tolerance,
    expandPx,
    antiAlias,
    gapClosePx,
    extendBeyondCanvas,
    source,
  );
}

/// The extended fill's apron width per side: as far as the pasteboard
/// reaches past the paper ([PasteboardReach.pastEdgeOf], I-109), capped so
/// the fill raster stays allocatable (a full 3×3 pasteboard raster of an
/// 8K canvas would be gigabytes). Canvases at or under the cap get the
/// exact pasteboard as their fill wall; larger ones get a generous apron
/// — either way the wall is FINITE, which is what makes leak detection
/// and "no infinite flood" structural.
const int pasteboardFillMarginCap = 1024;

int _pasteboardFillMargin(int canvasDimension, PasteboardReach reach) =>
    math.min(reach.pastEdgeOf(canvasDimension), pasteboardFillMarginCap);

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

/// The fill's sampling target: the picture as DRAWN — the layers it reads
/// composed over nothing, premultiplied RGBA, the coverage in the fourth
/// byte — composited LAZILY tile by tile as the flood visits pixels — a
/// fill only pays for the region it actually floods, never the whole
/// canvas (R11-③: the eager full-canvas compose froze the tap for seconds
/// on big canvases). It lies in the space the SEED is in, and a posed
/// layer is read through its pose — see the constructor.
///
/// 🚨NO PAPER UNDER IT (board F-416, [pixelWithinTolerance] has the
/// user's words): the paper is not drawn, so a fill neither stops at it
/// nor runs through it into what is drawn its colour. ↩️It was 「fill what
/// you see」 — the layers over the project's paper (R10-C, 07-12; an
/// absent paper read as black since 09-15) — and ink of the paper's
/// colour was the paper: a fill on white ink on a white paper took the
/// whole canvas, and with the fill past the canvas on, a white shape
/// running onto the pasteboard flooded to the wall and was refused as
/// open.
class LazyCanvasRasterRgb {
  /// With the native engine loaded the raster lives in native memory
  /// (R18 A-2b): the compose loops write through typed-data views
  /// unchanged, and the C flood stepper reads the SAME bytes — no
  /// copies between compose and flood.
  factory LazyCanvasRasterRgb({
    required Cut cut,
    required int frameIndex,
    required LayerFrameSurfaceResolver surfaceResolver,
    bool extendBeyondCanvas = false,
    PasteboardReach pasteboardReach = PasteboardReach.whole,
    CanvasReadSource source = CanvasReadSource.display,
    LayerId? activeLayerId,
    LayerPlacement? space,
  }) {
    // Extended (pasteboard) fills widen the raster by a finite apron and
    // shift its origin into negative world space; the default raster IS
    // the canvas at origin (0, 0), byte-identical to before.
    final marginX = extendBeyondCanvas
        ? _pasteboardFillMargin(cut.canvasSize.width, pasteboardReach)
        : 0;
    final marginY = extendBeyondCanvas
        ? _pasteboardFillMargin(cut.canvasSize.height, pasteboardReach)
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
      read: layersReadBy(source, activeLayerId),
      space: space,
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
    required Set<LayerId>? read,
    required LayerPlacement? space,
    required QaFloodNativeHandles? handles,
    required this.originX,
    required this.originY,
    required int rasterWidth,
    required int rasterHeight,
  }) : nativeHandles = handles,
       width = rasterWidth,
       height = rasterHeight,
       rgb = handles?.rgbView ?? Uint8List(rasterWidth * rasterHeight * 4),
       _tilesX = (rasterWidth + _tileSize - 1) ~/ _tileSize,
       _composed =
           handles?.composedView ??
           Uint8List(
             ((rasterWidth + _tileSize - 1) ~/ _tileSize) *
                 ((rasterHeight + _tileSize - 1) ~/ _tileSize),
           ) {
    // Surfaces resolve ONCE (a cold resolve may replay paint commands).
    //
    // WHICH layers is [read] — the read source's answer, the one the
    // eyedropper reads by too (I-36). HOW each is read is [_carryInto]'s:
    // in the seed's [space], through the layer's placement.
    final entries = resolveCutFrameCompositeEntries(
      cut: cut,
      frameIndex: frameIndex,
    );
    _ReadLayer? readOf(CutFrameCompositeEntry entry, {double strength = 1}) {
      final carry = _carryInto(entry, space);
      final surface = surfaceResolver(entry.layer, entry.frame);
      if (!carry.shows || surface == null) {
        return null;
      }
      return _ReadLayer(
        // The cel as it SHOWS: a letter bounds a fill as a drawn line
        // does (유저 2026-10-06: 「셀의 그림이랑 정확히 동일」).
        surface: celSurfaceWithTextsLaid(surface),
        opacity: entry.opacity * strength,
        toArtwork: carry.toArtwork,
      );
    }

    for (final entry in entries) {
      if (read != null && !read.contains(entry.layer.id)) {
        continue;
      }
      // A row that clips to the layer below walls the fill where it shows
      // — where its base is (I-92) — in the whole picture; a read of one
      // row reads it as drawn, as the eyedropper does.
      final clip = read != null
          ? null
          : flatClipOf(
              cut: cut,
              layer: entry.layer,
              frameIndex: frameIndex,
              entries: entries,
            );
      final layer = readOf(entry, strength: clip?.strength ?? 1);
      if (layer == null) {
        continue;
      }
      if (clip == null) {
        _layers.add(layer);
        continue;
      }
      final cutBy = [
        for (final base in clip.cutBy) ?readOf(base),
      ];
      if (cutBy.isNotEmpty) {
        _layers.add(
          _ReadLayer(
            surface: layer.surface,
            opacity: layer.opacity,
            toArtwork: layer.toArtwork,
            cutBy: cutBy,
          ),
        );
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

  /// `width*height*4` bytes, premultiplied RGBA (four bytes a pixel —
  /// R22-D's SIMD contract); only composed tiles hold real pixels — read
  /// through
  /// [ensureComposedAt].
  final Uint8List rgb;

  final int _tilesX;
  final Uint8List _composed;
  final List<_ReadLayer> _layers = [];

  /// Guarantees the tile containing pixel [index] (row-major) is composed.
  /// The tile a pixel [index] sits in, and where that tile starts.
  ///
  /// ⛔THE ROUTES MUST AGREE ON WHICH TILE A PIXEL IS IN. The per-pixel
  /// path and the batch path each wrote this arithmetic out; a route that
  /// computed a different tile would mark one composed and compose
  /// another, and the flood would then read nothing where a layer is.
  ({int tileIndex, int left, int top}) _tileOf(int index) {
    final tileX = (index % width) ~/ _tileSize;
    final tileY = (index ~/ width) ~/ _tileSize;
    return (
      tileIndex: tileY * _tilesX + tileX,
      left: tileX * _tileSize,
      top: tileY * _tileSize,
    );
  }

  void ensureComposedAt(int index) {
    final tile = _tileOf(index);
    if (_composed[tile.tileIndex] != 0) {
      return;
    }
    _composed[tile.tileIndex] = 1;
    _composeTile(tile.left, tile.top);
  }

  /// R25-③: composes every still-uncomposed tile that [pixelIndices]
  /// touch through ONE pooled native call — within a tile the clear +
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
      final tile = _tileOf(index);
      if (_composed[tile.tileIndex] != 0) {
        continue;
      }
      _composed[tile.tileIndex] = 1;
      final left = tile.left;
      final top = tile.top;
      final right = math.min(left + _tileSize, width);
      final bottom = math.min(top + _tileSize, height);
      final firstBlend = blends.length;
      for (final under in _layerTilesUnder(
        left: left,
        top: top,
        rightExclusive: right,
        bottomExclusive: bottom,
      )) {
        final tile = under.tile;
        // The staged pointer outlives this loop (the batch call below
        // reads it), so the TILE must stay reachable until then —
        // keepAlive does that (see BitmapTile.readPixels).
        keepAlive.add(tile);
        blends.add((
          pixels: tile.readPixels((pointer, _) => pointer),
          tileSize: tile.size,
          baseX: under.baseX,
          baseY: under.baseY,
          clipLeft: under.clipLeft,
          clipTop: under.clipTop,
          clipRightExclusive: under.clipRightExclusive,
          clipBottomExclusive: under.clipBottomExclusive,
          opacityInt: under.opacityInt,
        ));
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

    // R18 A-2c: with a native-backed raster the clear and the layer
    // blends run in the C kernels — byte-identical to the Dart loops
    // below (parity-pinned); Dart stays the reference and the fallback.
    final native = QaNativeEngine.instance;
    final handles = nativeHandles;
    if (native != null && handles != null) {
      native.fillClearRect(
        handles: handles,
        left: left,
        top: top,
        rightExclusive: right,
        bottomExclusive: bottom,
      );
      for (final under in _layerTilesUnder(
        left: left,
        top: top,
        rightExclusive: right,
        bottomExclusive: bottom,
      )) {
        under.tile.readPixels(
          (pointer, _) => native.fillComposeTile(
            handles: handles,
            tilePixels: pointer,
            tileSize: under.tile.size,
            baseX: under.baseX,
            baseY: under.baseY,
            clipLeft: under.clipLeft,
            clipTop: under.clipTop,
            clipRightExclusive: under.clipRightExclusive,
            clipBottomExclusive: under.clipBottomExclusive,
            opacityInt: under.opacityInt,
          ),
        );
      }
      return;
    }

    for (var y = top; y < bottom; y += 1) {
      final rowStart = (y * width + left) * 4;
      rgb.fillRange(rowStart, rowStart + (right - left) * 4, 0);
    }
    for (final under in _layerTilesUnder(
      left: left,
      top: top,
      rightExclusive: right,
      bottomExclusive: bottom,
    )) {
      final tile = under.tile;
      // Snapshot the tile's buffer ONCE (the getter copies).
      final pixels = tile.pixels;
      final tileSize = tile.size;
      final baseX = under.baseX;
      final baseY = under.baseY;
      final clipLeft = under.clipLeft;
      final clipRight = under.clipRightExclusive;
      final opacityInt = under.opacityInt;
      for (var y = under.clipTop; y < under.clipBottomExclusive; y += 1) {
        var source = ((y - baseY) * tileSize + (clipLeft - baseX)) * 4;
        var target = (y * width + clipLeft) * 4;
        for (var x = clipLeft; x < clipRight; x += 1) {
          final alphaByte = pixels[source + 3];
          if (alphaByte != 0) {
            final effective = (alphaByte * opacityInt + 127) ~/ 255;
            final inverse = 255 - effective;
            rgb[target] =
                (pixels[source] * effective + rgb[target] * inverse + 127) ~/
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
            rgb[target + 3] =
                (255 * effective + rgb[target + 3] * inverse + 127) ~/ 255;
          }
          source += 4;
          target += 4;
        }
      }
    }
  }

  /// Every existing layer tile under a raster rect, in layer stack order:
  /// the tile, its layer's byte opacity, and where the tile's origin and
  /// the clipped rect land in RASTER space. The three composes — per-tile
  /// native, batched native, the Dart reference — walk exactly this, so
  /// they cannot disagree on which tile a pixel reads from or where a
  /// tile straddling a compose wall is cut.
  ///
  /// Per TILE, never per pixel: the per-pixel loops stay in the callers.
  Iterable<_LayerTileUnder> _layerTilesUnder({
    required int left,
    required int top,
    required int rightExclusive,
    required int bottomExclusive,
  }) sync* {
    // Surface tiles live in WORLD space (raster + origin); bases pass
    // back in raster space, so tile-local offsets stay (world - base).
    final region = DirtyRegion(
      left: left + originX,
      top: top + originY,
      rightExclusive: rightExclusive + originX,
      bottomExclusive: bottomExclusive + originY,
    );
    for (final layer in _layers) {
      // Integer blend (R15-⑥): the per-pixel double multiply/round path
      // was a whole-canvas-scale cost on big fills; the raster only feeds
      // seed MATCHING (tolerance compares), so byte-rounded source-over
      // is exact enough by construction.
      final opacityInt = (layer.opacity * 255).round();
      if (layer.toArtwork != null || layer.cutBy != null) {
        yield _carriedTileUnder(layer, region);
        continue;
      }
      for (final covered in tilesCovering(layer.surface, region)) {
        yield (
          tile: covered.tile,
          opacityInt: opacityInt,
          baseX: covered.worldLeft - originX,
          baseY: covered.worldTop - originY,
          clipLeft: covered.left - originX,
          clipTop: covered.top - originY,
          clipRightExclusive: covered.rightExclusive - originX,
          clipBottomExclusive: covered.bottomExclusive - originY,
        );
      }
    }
  }

  /// [layer] carried onto one compose rect ([world], the rect in raster
  /// WORLD space) as a compose-sized tile, so the three composes blend it
  /// like any stored tile: through its `toArtwork`, and cut by its base
  /// where it clips to the layer below ([_ReadLayer.cutBy], I-92).
  _LayerTileUnder _carriedTileUnder(_ReadLayer layer, DirtyRegion world) {
    final pixels = _pixelsOn(layer, world);
    final cutBy = layer.cutBy;
    if (cutBy != null) {
      // What the base covers, its pixels laid together — and the row's
      // premultiplied pixels kept that much: `srcATop`'s cut, which the
      // clipping group's picture is.
      final covered = Uint8List(_tileSize * _tileSize);
      for (final base in cutBy) {
        final basePixels = _pixelsOn(base, world);
        for (var i = 0; i < covered.length; i += 1) {
          final alpha = basePixels[i * 4 + 3];
          covered[i] = alpha + (covered[i] * (255 - alpha) + 127) ~/ 255;
        }
      }
      for (var i = 0; i < pixels.length; i += 1) {
        pixels[i] = (pixels[i] * covered[i >> 2] + 127) ~/ 255;
      }
    }
    return (
      tile: BitmapTile(size: _tileSize, pixels: pixels),
      opacityInt: (layer.opacity * 255).round(),
      baseX: world.left - originX,
      baseY: world.top - originY,
      clipLeft: world.left - originX,
      clipTop: world.top - originY,
      clipRightExclusive: world.rightExclusive - originX,
      clipBottomExclusive: world.bottomExclusive - originY,
    );
  }

  /// [layer]'s pixels on the compose tile at [world]'s origin, in raster
  /// WORLD space — straight off its tiles where it is read 1:1, resampled
  /// by the resampler that carries a transformed picture everywhere else
  /// where it is posed.
  ///
  /// Blend, not pick: the screen draws a posed layer filtered, and the fill
  /// reads what the screen shows.
  static Uint8List _pixelsOn(_ReadLayer layer, DirtyRegion world) {
    final toArtwork = layer.toArtwork;
    if (toArtwork == null) {
      return bitmapSurfaceRegionPixels(
        layer.surface,
        DirtyRegion(
          left: world.left,
          top: world.top,
          rightExclusive: world.left + _tileSize,
          bottomExclusive: world.top + _tileSize,
        ),
      );
    }
    final source = _preimageOf(toArtwork, world);
    final pixels = Uint8List(BitmapTile.bytesFor(_tileSize));
    resampleSelectionInto(
      src: bitmapSurfaceRegionPixels(layer.surface, source),
      srcWidth: source.width,
      srcHeight: source.height,
      dst: pixels,
      dstWidth: _tileSize,
      dstHeight: _tileSize,
      transform: _resampleFold(toArtwork, world, source),
      mode: ResampleMode.blend,
    );
    return pixels;
  }

  /// What a compose tile at [world]'s origin can read of a layer carried by
  /// [toArtwork]: its corners' preimage, one tent wider.
  static DirtyRegion _preimageOf(GuideTransform toArtwork, DirtyRegion world) {
    final corners = [
      for (final (x, y) in [
        (world.left, world.top),
        (world.left + _tileSize, world.top),
        (world.left, world.top + _tileSize),
        (world.left + _tileSize, world.top + _tileSize),
      ])
        toArtwork.apply(CanvasPoint(x: x.toDouble(), y: y.toDouble())),
    ];
    final bounds = pointsBounds([
      for (final corner in corners) Offset(corner.x, corner.y),
    ]);
    return DirtyRegion(
      left: bounds.left.floor() - 2,
      top: bounds.top.floor() - 2,
      rightExclusive: bounds.right.ceil() + 2,
      bottomExclusive: bounds.bottom.ceil() + 2,
    );
  }

  /// [toArtwork] folded for a tile at [world]'s origin reading [source].
  static ResampleTransform _resampleFold(
    GuideTransform toArtwork,
    DirtyRegion world,
    DirtyRegion source,
  ) => planeResampleTransform(
    toSource: toArtwork,
    srcLeft: source.left,
    srcTop: source.top,
    outLeft: world.left,
    outTop: world.top,
  );
}

/// A layer the raster reads: its surface, its opacity, — for a layer NOT
/// placed as the seed's space — how raster WORLD maps into its artwork
/// (null = read 1:1; see [_carryInto]), and — for one that clips to the
/// layer below — its base's layers, which cut it ([flatClipOf]; null =
/// nothing cuts it).
final class _ReadLayer {
  const _ReadLayer({
    required this.surface,
    required this.opacity,
    required this.toArtwork,
    this.cutBy,
  });

  final BitmapSurface surface;
  final double opacity;
  final GuideTransform? toArtwork;
  final List<_ReadLayer>? cutBy;
}

/// How [entry] is read by a raster laid in [space]: null `toArtwork` for a
/// layer placed exactly as that space (read 1:1, byte for byte as before —
/// every layer, when nothing is posed); otherwise the map from raster WORLD
/// into the layer's artwork, out through the space's placement and in
/// through the inverse of the layer's own. `shows` is false when the
/// layer's placement collapses it: it shows nothing, so it walls nothing.
///
/// 🚨I-36 — THE POSE LAW, the eyedropper's since R28 #7: a posed layer is
/// read THROUGH its pose, never skipped. P5+P6 skipped posed layers in both
/// tools as a 「v1」; the eyedropper outgrew it, the fill kept it, so line
/// art with a transform key — or inside a folder with one — never walled a
/// fill (유저 2026-09-24: 「이 과정에서 법 다른거 통일」). The raster lies in
/// the SEED's space because that is where the pen is and where the dab
/// lands: the draw-through wrap hands the seed over in the posed layer's
/// artwork.
({bool shows, GuideTransform? toArtwork}) _carryInto(
  CutFrameCompositeEntry entry,
  LayerPlacement? space,
) {
  final placement = entry.placement;
  if (placement == space) {
    return (shows: true, toArtwork: null);
  }
  final fromCanvas = placement == null
      ? const GuideTransform.identity()
      : canvasToArtwork(placement);
  if (fromCanvas == null) {
    return (shows: false, toArtwork: null);
  }
  final carried = space == null ? fromCanvas : fromCanvas.compose(space);
  return (shows: true, toArtwork: carried.isIdentity ? null : carried);
}

/// One layer tile under a compose rect — see
/// [LazyCanvasRasterRgb._layerTilesUnder].
typedef _LayerTileUnder = ({
  BitmapTile tile,
  int opacityInt,
  int baseX,
  int baseY,
  int clipLeft,
  int clipTop,
  int clipRightExclusive,
  int clipBottomExclusive,
});

/// Scanline flood fill over the fill raster from the seed, within
/// [FloodFillOptions.tolerance] of the SEED pixel; null when the seed is
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
  final seed = seedAt(rgb, seedIndex);
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
        seed: seed,
        tolerance: tolerance,
        gapClosePx: options.gapClosePx,
      );
      if (result != null) {
        final (
          left: cropLeft,
          top: cropTop,
          right: cropRight,
          bottom: cropBottom,
        ) = _floodFinishBox(
          minX: result.minX,
          maxX: result.maxX,
          minY: result.minY,
          maxY: result.maxY,
          width: width,
          height: height,
          options: options,
        );
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
      seed: seed,
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
      seed: seed,
      tolerance: tolerance,
      ensureComposed: ensureComposed,
      ensureComposedBatch: ensureComposedBatch,
    );
    if (result != null) {
      // The finish (crop + expand + anti-alias) runs natively too
      // (A-2d): the verification lab showed these full-region passes
      // were most of what remained in the fill.flood probe. The crop is
      // the Dart tail's own ([_floodFinishBox]).
      final (
        left: cropLeft,
        top: cropTop,
        right: cropRight,
        bottom: cropBottom,
      ) = _floodFinishBox(
        minX: result.minX,
        maxX: result.maxX,
        minY: result.minY,
        maxY: result.maxY,
        width: width,
        height: height,
        options: options,
      );
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

  // Pure byte compare (pixelWithinTolerance) — the caller guarantees the
  // pixel's compose tile via the crossing checks below (one ensure per
  // 256px boundary).
  final filled = Uint8List(width * height);
  final stack = <int>[seedY * width + seedX];
  filled[seedY * width + seedX] = 255;
  var minX = seedX;
  var maxX = seedX;
  var minY = seedY;
  var maxY = seedY;

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
      if (!pixelWithinTolerance(
        rgb,
        (rowStart + left - 1) * 4,
        seed,
        tolerance,
      )) {
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
      if (!pixelWithinTolerance(
        rgb,
        (rowStart + right + 1) * 4,
        seed,
        tolerance,
      )) {
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
        if (filled[neighborIndex] == 0 &&
            pixelWithinTolerance(
              rgb,
              neighborIndex * 4,
              seed,
              tolerance,
            )) {
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

/// How far past its coverage a fill's finish reaches: [FloodFillOptions.
/// expandPx] generations of growth — and, with the anti-alias, one pixel
/// more: the fill's ramp spreads ONE PIXEL OUTWARD past its own edge
/// ([softenMaskBoundary], unclamped), so a box a fill is finished in holds
/// that pixel on every side.
///
/// 🗣️유저 답 the-fill-ramp-is-cut-at-its-box-Q1 (10-09): 「상자를 한 칸 넓혀
/// 어디서나 번지게」. ↩️The box was the coverage grown by the expand alone,
/// and a ramp that met its edge was cut there — the shape tool's 4px
/// horizontal line read `86 · 100 · 100 · 86 · 14%`, the spread on one side
/// only, and the bucket's lost it at the last cells of what it filled.
int fillFinishReach(FloodFillOptions options) =>
    options.expandPx + (options.antiAlias ? 1 : 0);

/// The box a flood's coverage `[minX, maxX] × [minY, maxY]` is finished
/// in: its bounds grown by what the finish reaches ([fillFinishReach]), cut
/// at the canvas — the one box the Dart tail and both native finishes are
/// handed.
({int left, int top, int right, int bottom}) _floodFinishBox({
  required int minX,
  required int maxX,
  required int minY,
  required int maxY,
  required int width,
  required int height,
  required FloodFillOptions options,
}) {
  final reach = fillFinishReach(options);
  return (
    left: math.max(0, minX - reach),
    top: math.max(0, minY - reach),
    right: math.min(width - 1, maxX + reach),
    bottom: math.min(height - 1, maxY + reach),
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
  // Crop FIRST (with room for what the finish reaches), then run the
  // expand and anti-alias passes region-locally: the old grow pass copied
  // and scanned a full-canvas array per pass.
  final (
    left: cropLeft,
    top: cropTop,
    right: cropRight,
    bottom: cropBottom,
  ) = _floodFinishBox(
    minX: minX,
    maxX: maxX,
    minY: minY,
    maxY: maxY,
    width: width,
    height: height,
    options: options,
  );
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

  dilateMask4(
    mask,
    width: regionWidth,
    height: regionHeight,
    passes: options.expandPx,
  );

  if (options.antiAlias) {
    // ⛔UNCLAMPED, and that is the fill's meaning: paint that stops dead on
    // the outline reads as a hard edge, so the fill's ramp is allowed one
    // pixel past its own. The SELECTION's is not — see [softenMaskBoundary].
    softenMaskBoundary(
      mask,
      width: regionWidth,
      height: regionHeight,
      insideOutlineOnly: false,
    );
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
/// 1. fillable = per-pixel tolerance test against the seed;
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
  required int seed,
  required FloodFillOptions options,
}) {
  const infinity = 60000;
  final pixelCount = width * height;
  final tolerance = options.tolerance;

  final fillable = Uint8List(pixelCount);
  for (var index = 0, base = 0; index < pixelCount; index += 1, base += 4) {
    if (pixelWithinTolerance(rgb, base, seed, tolerance)) {
      fillable[index] = 1;
    }
  }

  final dist = Uint16List(pixelCount);
  chamferDistance34(
    dist,
    from: fillable,
    zeroWhen: 0,
    width: width,
    height: height,
    infinity: infinity,
    // The canvas edge is NOT a barrier: a fill against the wall stays open.
    borderDistance: infinity,
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
  chamferDistance34(
    growDist,
    from: filled,
    zeroWhen: 255,
    width: width,
    height: height,
    infinity: infinity,
    borderDistance: infinity,
  );
  var minX = width;
  var maxX = -1;
  var minY = height;
  var maxY = -1;
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

/// An AREA laid as stamp pieces ([_stampPieces]): every pixel [region]
/// covers, painted [color] whatever is under it and whoever asked — the
/// fill tool's shape fill (유저 확정: 올가미 채우기는 A — 내부에 뭐가 있든
/// 채운다), and what the shape tool lays without the brush: its fill and
/// its plain line (I-69). Under a symmetry guide [region] is every copy
/// together. Empty when the region covers no pixel at all.
///
/// It shares the flood's tail rather than resembling it. Once there is a
/// coverage mask the two are the same problem, so the expand and
/// anti-alias passes are the bucket's own — [dilateMask4] and
/// [softenMaskBoundary], run as [_cropAndFinishFloodRegion] runs them —
/// which is why "AA follows the fill" (유저 확정) needed no new rasterizer:
/// the bucket's AA has always been a post-pass over a binary mask, and a
/// region's mask is binary too.
///
/// What it does NOT share is the front: no lazy compose, no seed, no
/// tolerance. An area never looks at the picture, so it never pays to
/// composite one — this is markedly cheaper than a flood, not a variant of
/// it.
///
/// 🚨★★★IT IS FINISHED ONLY WHERE IT REACHES (board
/// `an-area-dab-costs-its-box`, 2026-10-09). It was finished as ONE SHEET
/// over its whole box — the coverage box grown by the expand — so its cost
/// followed the box and not the paint: a 4px diagonal across a 2010×1510
/// box built 17–34 ms and an 11.5 MB stamp, and its landing staged every
/// tile of the box, the same as filling the box solid (the VM on the
/// desktop). Now the rows come as RUNS first
/// ([CanvasSelectionRegion.pixelRunsFor] — no byte per pixel), the runs
/// say which tiles the finished area can reach ([_tilesReached]), and only
/// those are finished, each in a window of its own ([_finishedWindow]).
///
/// ⛔WHAT LANDS IS THE SHEET'S BYTES, and that is what the window is for,
/// not a hope. A finished byte reads the hard mask no farther than the
/// passes reach — `expandPx` 4-neighbour generations, then one soften —
/// and the sheet's edges were its box's. A window is its tile grown by
/// that reach and cut at that same box, so every pixel of the tile reads
/// exactly what the sheet read. The box itself holds all the finish reaches
/// ([fillFinishReach]), the ramp past the expand included, so nothing of
/// the area is cut at it.
List<BrushDab> buildRegionFillDabs({
  required CanvasSelectionRegion region,
  required int color,
  double opacity = 1.0,
  FloodFillOptions options = const FloodFillOptions(),
}) => regionFillPieces(
  region: region,
  color: color,
  opacity: opacity,
  options: options,
).toList();

/// [buildRegionFillDabs]'s pieces one at a time, each made as it is asked
/// for — what lets a shape being dragged be laid a few pieces a frame and
/// shown when it is whole (I-69-Q4ⓒ). Every pass over it makes its pieces
/// afresh.
Iterable<BrushDab> regionFillPieces({
  required CanvasSelectionRegion region,
  required int color,
  double opacity = 1.0,
  FloodFillOptions options = const FloodFillOptions(),
}) sync* {
  final bounds = region.coverageBounds;
  final left = bounds.left.floor();
  final top = bounds.top.floor();
  final width = bounds.right.ceil() - left;
  final height = bounds.bottom.ceil() - top;
  if (width <= 0 || height <= 0) {
    return;
  }
  final rows = region.pixelRunsFor(
    left: left,
    top: top,
    width: width,
    height: height,
  );
  final hard = (rows: rows, left: left, top: top);
  final reach = fillFinishReach(options);
  // The sheet the area is finished as: the coverage box, with room for all
  // the finish reaches — the expand AND the ramp past it.
  final sheet = DirtyRegion(
    left: left - reach,
    top: top - reach,
    rightExclusive: left + width + reach,
    bottomExclusive: top + height + reach,
  );
  final reached = _tilesReached(hard, sheet: sheet, reach: reach);
  yield* _stampPieces(
    sheet,
    color: color,
    opacity: opacity,
    finishedAround: (piece) => reached(piece)
        ? _finishedWindow(
            hard,
            piece: piece,
            sheet: sheet,
            reach: reach,
            options: options,
          )
        : null,
  );
}

/// A region's hard coverage as rows of runs: row `r` is the canvas row
/// `top + r`, its `[start, end, …]` columns counted from `left`
/// ([CanvasSelectionRegion.pixelRunsFor]).
typedef _HardRuns = ({List<List<int>> rows, int left, int top});

/// A finished coverage mask and where it sits on the canvas, at least as
/// large as the piece it was finished for.
typedef _FinishedMask = ({Uint8List mask, int left, int top, int width});

/// The grid an area is cut on: the cel's own tiles. It decides only how
/// the area is cut, never a byte of what lands — a piece lands 1:1 wherever
/// it is — and on the cel's grid each piece stages exactly the tiles it
/// covers when it lands, a run of them along one tile row. A surface on
/// another grid lands the same bytes.
const int _pieceSize = defaultCelTileSize;

/// Which of [sheet]'s tiles the finished area can reach: a tile within
/// [reach] of a covered pixel. The rest would finish to nothing, and are
/// never finished.
bool Function(TileSpan piece) _tilesReached(
  _HardRuns hard, {
  required DirtyRegion sheet,
  required int reach,
}) {
  final range = sheet.tileRange(tileSize: _pieceSize);
  final columns = range.lastX - range.firstX + 1;
  final grid = Uint8List(columns * (range.lastY - range.firstY + 1));
  for (var row = 0; row < hard.rows.length; row += 1) {
    final runs = hard.rows[row];
    if (runs.isEmpty) {
      continue;
    }
    final y = hard.top + row;
    final firstY =
        floorDiv(math.max(y - reach, sheet.top), _pieceSize) - range.firstY;
    final lastY =
        floorDiv(math.min(y + reach, sheet.bottomExclusive - 1), _pieceSize) -
        range.firstY;
    for (var r = 0; r + 1 < runs.length; r += 2) {
      final x0 = math.max(hard.left + runs[r] - reach, sheet.left);
      final x1 = math.min(
        hard.left + runs[r + 1] - 1 + reach,
        sheet.rightExclusive - 1,
      );
      final firstX = floorDiv(x0, _pieceSize) - range.firstX;
      final lastX = floorDiv(x1, _pieceSize) - range.firstX;
      for (var tileRow = firstY; tileRow <= lastY; tileRow += 1) {
        grid.fillRange(
          tileRow * columns + firstX,
          tileRow * columns + lastX + 1,
          1,
        );
      }
    }
  }
  return (piece) =>
      grid[(piece.coord.y - range.firstY) * columns +
          (piece.coord.x - range.firstX)] !=
      0;
}

/// The area finished over [piece] as the one sheet over [sheet] would have
/// finished it: its hard mask over a window — the piece grown by [reach],
/// cut at [sheet] — then the expand and the anti-alias pass, as
/// [_cropAndFinishFloodRegion] runs them. Exact over the piece, which is
/// all a reader takes from it ([buildRegionFillDabs] says why).
_FinishedMask _finishedWindow(
  _HardRuns hard, {
  required TileSpan piece,
  required DirtyRegion sheet,
  required int reach,
  required FloodFillOptions options,
}) {
  final left = math.max(piece.left - reach, sheet.left);
  final top = math.max(piece.top - reach, sheet.top);
  final width = math.min(piece.rightExclusive + reach, sheet.rightExclusive) -
      left;
  final height =
      math.min(piece.bottomExclusive + reach, sheet.bottomExclusive) - top;
  final mask = Uint8List(width * height);
  final firstRow = math.max(top, hard.top);
  final endRow = math.min(top + height, hard.top + hard.rows.length);
  for (var y = firstRow; y < endRow; y += 1) {
    final runs = hard.rows[y - hard.top];
    final offset = (y - top) * width;
    for (var r = 0; r + 1 < runs.length; r += 2) {
      final start = math.max(hard.left + runs[r], left);
      final end = math.min(hard.left + runs[r + 1], left + width);
      if (start < end) {
        mask.fillRange(offset + start - left, offset + end - left, 255);
      }
    }
  }
  dilateMask4(mask, width: width, height: height, passes: options.expandPx);
  if (options.antiAlias) {
    // ⛔UNCLAMPED — the fill's ramp, as in [_cropAndFinishFloodRegion].
    softenMaskBoundary(
      mask,
      width: width,
      height: height,
      insideOutlineOnly: false,
    );
  }
  return (mask: mask, left: left, top: top, width: width);
}

/// The whole P6 tap: compose → fill from [point] → the region as stamp
/// pieces ([_stampPieces]), committed through the exact stroke funnel —
/// three-route parity, undo and .anicel serialization come free. Empty
/// when nothing fills (seed off the fill raster), or when an EXTENDED
/// fill's flood reaches the apron wall — the region is not closed;
/// [onOpenRegion] fires so the UI can say so instead of silently flooding
/// the surround.
///
/// [symmetry] makes the tap fill every copy of the seed, unioned into the
/// same one region — see the loop below for why the stroke path's dab
/// replication is the wrong tool here.
///
/// [activeLayerId] is the 「현재」 of [FloodFillOptions.source] — the layer
/// the dab lands on. [space] is where [point] and the dab are: that layer's
/// ARTWORK when it is posed (the draw-through wrap hands the seed over in
/// it), null for the canvas.
List<BrushDab> buildFillDabs({
  required Cut cut,
  required int frameIndex,
  required LayerFrameSurfaceResolver surfaceResolver,
  required CanvasPoint point,
  required int color,
  double opacity = 1.0,
  FloodFillOptions options = const FloodFillOptions(),
  LayerId? activeLayerId,
  LayerPlacement? space,
  SymmetryShape? symmetry,
  void Function()? onOpenRegion,
  PasteboardReach pasteboardReach = PasteboardReach.whole,
}) {
  // With no pasteboard (I-109) there is nothing past the paper to fill
  // into: the fill is the canvas's, as it is with the apron off — a region
  // at the paper's edge is not refused as open.
  final extended =
      options.extendBeyondCanvas && pasteboardReach != PasteboardReach.none;
  final raster = labProbe(
    'fill.raster-ctor',
    () => LazyCanvasRasterRgb(
      cut: cut,
      frameIndex: frameIndex,
      surfaceResolver: surfaceResolver,
      extendBeyondCanvas: extended,
      pasteboardReach: pasteboardReach,
      source: options.source,
      activeLayerId: activeLayerId,
      space: space,
    ),
  );
  // A symmetry guide fills every copy of the SEED, not every copy of the
  // finished region: the mirrored region is whatever the picture encloses
  // over there, which is the whole point of drawing under a symmetry.
  //
  // ⛔The stroke path's `replicateDabs` cannot do this job. A fill arrives
  // as ONE `stamp` (an RGBA image) and the stamp blend ignores angle, so a
  // replicated fill dab would paste an UN-mirrored copy of *this* region on
  // the other side. Reflecting the seed and flooding again is the only
  // thing that reads the other side's own outline.
  //
  // The raster is built ONCE and every flood samples it, so N copies cost N
  // floods and not N composites — and every copy sees the same untouched
  // picture, which is what makes the result independent of seed order.
  //
  // [symmetry] is the CANVAS's and [point] is in [space]: the copies are
  // the canvas's, read through the seed's placement like a stroke's.
  final seeds = symmetry == null
      ? <CanvasPoint>[point]
      : [
          for (final copy in symmetryCopiesIn(guideSpaceOf(space), symmetry))
            copy.apply(point),
        ];
  final parts = <FloodFillRegion>[];
  var reachedWall = false;
  for (final seed in seeds) {
    final part = labProbe(
      'fill.flood',
      () => floodFillRegion(
        rgb: raster.rgb,
        width: raster.width,
        height: raster.height,
        seedX: seed.x.floor() - raster.originX,
        seedY: seed.y.floor() - raster.originY,
        options: options,
        ensureComposed: raster.ensureComposedAt,
        ensureComposedBatch: raster.ensureComposedBatch,
        nativeHandles: raster.nativeHandles,
      ),
    );
    if (part == null) {
      continue;
    }
    if (extended) {
      // Leak detection: a flood that reached the apron's outer wall means
      // the region is OPEN (nothing bounded it before the wall). Refuse
      // the fill — the raster analogue of Flash refusing to fill an
      // unclosed shape.
      //
      // Judged per COPY: one copy landing in open space says nothing about
      // the others, and dropping the whole fill because a mirror missed
      // would make the symmetry's own copies veto the seed's.
      final reached =
          part.left <= 0 ||
          part.top <= 0 ||
          part.left + part.width >= raster.width ||
          part.top + part.height >= raster.height;
      if (reached) {
        reachedWall = true;
        continue;
      }
    }
    parts.add(part);
  }
  final region = _unionRegions(parts);
  if (extended) {
    // The extended raster grew the engine's fill arenas ~9×; give the
    // memory back once this tap's flood is done (the next canvas fill
    // re-allocs canvas size).
    QaNativeEngine.instance?.trimFloodRasterArena(
      keepBytes: cut.canvasSize.width * cut.canvasSize.height * 4,
    );
  }
  if (region == null) {
    // The notice is the OPEN-region one only when a flood actually hit the
    // wall; a seed that simply landed outside the raster answers nothing in
    // silence, exactly as it did before symmetry existed.
    if (reachedWall) {
      onOpenRegion?.call();
    }
    return const [];
  }
  // The flood finished its region as one sheet already (the raster is
  // whole either way), so every piece is cut from that one mask.
  final finished = (
    mask: region.mask,
    left: region.left + raster.originX,
    top: region.top + raster.originY,
    width: region.width,
  );
  return _stampPieces(
    DirtyRegion(
      left: finished.left,
      top: finished.top,
      rightExclusive: finished.left + region.width,
      bottomExclusive: finished.top + region.height,
    ),
    color: color,
    opacity: opacity,
    finishedAround: (_) => finished,
  ).toList();
}

/// The regions a fill flooded, merged into the single region the stamp path
/// expects — coverage per pixel is the MAX of the parts, not their sum, so
/// two copies that overlap stay one flat fill instead of a darker seam.
///
/// One allocation for the whole merge: the union rect is measured first and
/// every part is blitted into it. Folding pairwise instead would re-allocate
/// a growing mask per copy, which on a large canvas is the fill's whole
/// budget spent on garbage.
///
/// A lone part is returned UNTOUCHED — the no-symmetry path, which is nearly
/// every fill, must not pay a copy of the mask to pass through here.
FloodFillRegion? _unionRegions(List<FloodFillRegion> parts) {
  if (parts.isEmpty) {
    return null;
  }
  if (parts.length == 1) {
    return parts.first;
  }
  var left = parts.first.left;
  var top = parts.first.top;
  var right = parts.first.left + parts.first.width;
  var bottom = parts.first.top + parts.first.height;
  for (final part in parts.skip(1)) {
    left = math.min(left, part.left);
    top = math.min(top, part.top);
    right = math.max(right, part.left + part.width);
    bottom = math.max(bottom, part.top + part.height);
  }
  final width = right - left;
  final height = bottom - top;
  final mask = Uint8List(width * height);
  for (final part in parts) {
    for (var y = 0; y < part.height; y += 1) {
      final source = y * part.width;
      final target = (part.top - top + y) * width + (part.left - left);
      for (var x = 0; x < part.width; x += 1) {
        final coverage = part.mask[source + x];
        if (coverage > mask[target + x]) {
          mask[target + x] = coverage;
        }
      }
    }
  }
  return FloodFillRegion(
    left: left,
    top: top,
    width: width,
    height: height,
    mask: mask,
  );
}

/// A finished coverage mask painted [color] and handed over as STAMP
/// PIECES: one dab for each run of cel tiles of [box] that the mask covers
/// at all, along a tile row, in row-major order. [finishedAround] hands
/// the finished mask over a tile, or null for a tile it knows is empty.
/// Empty when no tile has a covered pixel.
///
/// 🚨★★★EVERY MASK A FILL LAYS IS CUT HERE — the bucket's flood and an
/// area alike (board `an-area-dab-costs-its-box`, 2026-10-09). A piece lands
/// 1:1 on its own pixels and the pieces share none, so every pixel that
/// shows is what one stamp over the whole box landed, through every route
/// a stamp takes (the blend, the erase, the selection's fold, 뒤에 그리기).
/// What they do not carry is the box's empty tiles: one stamp was the box's
/// width × height × 4 bytes however little of it was paint, its landing
/// staged every tile of the box, and the history held it all.
/// ⚠️Only bytes nobody sees can part: under alpha 0 a soft edge keeps the
/// colour it was painted with, and a composite of the whole stroke (a
/// blend, 뒤에 그리기) clears that wherever it passes — the one stamp passed
/// over its whole box, a piece passes over itself.
///
/// ⚠️A RUN, NOT A TILE, and it was measured: a stamp lands in one native
/// call that fans its tiles out across the worker pool, and the call has a
/// price of its own. A piece a tile filled the 2010×1510 ellipse in 173
/// calls and landed it in 28 ms where the one stamp had taken 12 (the VM on
/// the desktop); a run of the row's covered tiles takes one call per run,
/// and a thin line still carries only the tiles it crosses.
Iterable<BrushDab> _stampPieces(
  DirtyRegion box, {
  required int color,
  required double opacity,
  required _FinishedMask? Function(TileSpan tile) finishedAround,
}) sync* {
  // ⚠️ONE id per fill, and a piece's first tile in it. Pieces are made
  // inside one microsecond, and a stamp is equal to another by id, size and
  // bytes — two solid pieces sharing an id would be one stamp to any set of
  // them (the 확정 slot counts its stamps' bytes as a set).
  final id = 'fill-${DateTime.now().microsecondsSinceEpoch}';
  var sequence = 0;
  final run = <({TileSpan tile, Uint8List coverage})>[];
  BrushDab laid() {
    final first = run.first.tile;
    final dab = _colorStampDab(
      left: first.left,
      top: first.top,
      width: run.last.tile.rightExclusive - first.left,
      height: first.bottomExclusive - first.top,
      mask: _joined(run),
      color: color,
      opacity: opacity,
      id: '$id-${first.coord.x}.${first.coord.y}',
      sequence: sequence,
    );
    sequence += 1;
    run.clear();
    return dab;
  }

  for (final tile in tileSpansOf(box, tileSize: _pieceSize)) {
    if (run.isNotEmpty && run.last.tile.coord.y != tile.coord.y) {
      yield laid();
    }
    final finished = finishedAround(tile);
    final coverage = finished == null ? null : _coverageOf(tile, finished);
    if (coverage == null) {
      if (run.isNotEmpty) {
        yield laid();
      }
      continue;
    }
    run.add((tile: tile, coverage: coverage));
  }
  if (run.isNotEmpty) {
    yield laid();
  }
}

/// [finished]'s bytes over [tile], or null when not one of them is
/// covered.
Uint8List? _coverageOf(TileSpan tile, _FinishedMask finished) {
  final width = tile.rightExclusive - tile.left;
  final height = tile.bottomExclusive - tile.top;
  final coverage = Uint8List(width * height);
  var covers = false;
  for (var y = 0; y < height; y += 1) {
    final from =
        (tile.top + y - finished.top) * finished.width +
        (tile.left - finished.left);
    coverage.setRange(y * width, y * width + width, finished.mask, from);
    if (!covers) {
      for (var x = y * width; x < y * width + width; x += 1) {
        if (coverage[x] != 0) {
          covers = true;
          break;
        }
      }
    }
  }
  return covers ? coverage : null;
}

/// The coverages of a run of neighbouring tiles along one tile row, side by
/// side as one mask.
Uint8List _joined(List<({TileSpan tile, Uint8List coverage})> run) {
  if (run.length == 1) {
    return run.single.coverage;
  }
  final first = run.first.tile;
  final width = run.last.tile.rightExclusive - first.left;
  final height = first.bottomExclusive - first.top;
  final joined = Uint8List(width * height);
  for (final (:tile, :coverage) in run) {
    final tileWidth = tile.rightExclusive - tile.left;
    final x = tile.left - first.left;
    for (var y = 0; y < height; y += 1) {
      joined.setRange(
        y * width + x,
        y * width + x + tileWidth,
        coverage,
        y * tileWidth,
      );
    }
  }
  return joined;
}

/// One piece of a fill's coverage painted [color] and handed over as a
/// stamp dab landing on the pixels `[left, left+width) × [top,
/// top+height)`.
///
/// The fill lands as a COLOR STAMP (R15-⑥): rgba = fill color × mask
/// coverage, drawn 1:1 by the stamp blend path. The old square-padded
/// tip-mask dab re-sampled the giant mask bilinearly per pixel at every
/// materialization — a multi-second slice on large fills — and the stamp
/// is byte-exact by construction.
BrushDab _colorStampDab({
  required int left,
  required int top,
  required int width,
  required int height,
  required Uint8List mask,
  required int color,
  required double opacity,
  required String id,
  required int sequence,
}) {
  final r = argbRed(color);
  final g = argbGreen(color);
  final b = argbBlue(color);
  final rgba = labProbe('fill.stamp-build', () {
    final bytes = Uint8List(width * height * 4);
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
    // Centred on the piece: a stamp lands at its centre less half its size
    // ([BrushStampImage.landingRect]), which is the piece's own corner.
    center: CanvasPoint(x: left + width / 2, y: top + height / 2),
    color: color,
    size: math.max(width, height).toDouble(),
    opacity: opacity,
    flow: 1,
    hardness: 1,
    tipShape: BrushTipShape.square,
    pressure: 1,
    sequence: sequence,
    stamp: BrushStampImage(id: id, width: width, height: height, rgba: rgba),
  );
}
