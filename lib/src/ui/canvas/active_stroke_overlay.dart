import 'dart:collection';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

import '../../core/rgba_premultiply.dart';
import '../../core/sync_image_upload.dart';
import '../../models/bitmap_surface.dart';
import '../../models/brush_blend_mode.dart';
import '../../models/brush_dab.dart';
import '../../models/canvas_size.dart';
import '../../models/dirty_region.dart';
import '../../models/pasteboard_bounds.dart';
import '../../models/tile_coord.dart';
import '../../services/brush_live_stroke_rasterizer.dart'
    show
        ActiveStrokePixelSource,
        BrushLiveStrokeRasterizer,
        PreBlendedOverlayTile,
        PromotedStrokeTile;
import '../../services/brush_stroke_blend.dart'
    show bitmapSurfaceRegionPixels, preBlendStrokeOverlayPixels;
import 'bitmap_tile_image_cache.dart';
import 'deferred_image_disposal.dart';

/// Mutable state of the in-progress stroke overlay.
///
/// A lightweight editor-local [ChangeNotifier]: the interactive view blends
/// new dabs into its live CPU stroke buffer and hands the touched region to
/// [updateRegion]; every picture that lands notifies the canvas painter
/// through the `CustomPainter.repaint` hook, so strokes repaint without
/// rebuilding any widgets.
///
/// The overlay displays through the EXACT pipeline the committed tiles use:
/// straight-alpha buffer bytes become tile pictures through the one door
/// ([pictureOf]) that the painter draws with nearest sampling. One
/// rasterization path means live and committed pixels cannot diverge at
/// any zoom — replaying the stroke as rect geometry (a previous
/// representation) rasterized differently from nearest-sampled images at
/// fractional zoom, visibly shifting the active stroke's pixels against
/// committed strokes.
///
/// 🚨★★★PICTURED INSIDE THE FLUSH, ON EVERY ENGINE (유저 절대규칙
/// 2026-09-17: 「보이는 중이랑 결과랑 절대로 다르면 안 되」). The picture of
/// a coordinate and the stroke revision it shows are recorded in the same
/// synchronous call that pre-blended it, so the pen-up handoff finds a
/// picture at every promoted tile's revision and nothing ever has to stand
/// in for a committed tile afterwards — there is no decode in flight, no
/// settle window, no stand-in. Where the engine uploads (Impeller, every
/// platform since 3.47) the picture is a real texture; where it draws
/// (Skia, the test runner) it is a rasterized picture — the door makes the
/// same bytes either way.
class ActiveStrokeOverlayModel extends ChangeNotifier {
  ActiveStrokeOverlayModel({int tileSize = defaultCelTileSize})
    : _tileSize = tileSize;

  int _tileSize;

  /// Edge length of an overlay tile in canvas pixels.
  ///
  /// PROMOTION round: the interactive view aligns this with the
  /// committed surface's tile size at stroke start ([configureTileSize])
  /// so a pre-blended result tile REPLACES the committed tile at the
  /// same coordinate in the painter's base pass — no clips, no
  /// isolation layer, and the per-frame draw count stays the idle
  /// frame's. A mismatched grid still displays through the isolation
  /// fallback, just without the replacement economics.
  int get tileSize => _tileSize;

  /// Aligns the overlay grid with the surface about to be stroked. Only
  /// legal while the overlay is empty (call after [reset]) — images are
  /// keyed by tile coordinate, which changes meaning with the grid.
  void configureTileSize(int tileSize) {
    assert(_tileImages.isEmpty, 'configureTileSize requires an empty overlay');
    _tileSize = tileSize;
  }

  /// Dabs of the current stroke, kept for observability and tests; rendering
  /// uses [tileImages], which carry the exact rasterized pixels.
  final List<BrushDab> dabs = <BrushDab>[];

  /// Whether the current stroke ERASES: the painter then draws the overlay
  /// tiles destination-out so the preview removes committed pixels exactly
  /// where the commit will. Set by the interactive view at stroke start.
  bool erase = false;

  /// The stroke's BRUSH blend (BB-1, R26 #9). With [preBlendBase] set the
  /// mode feeds the CPU pre-blend below and the GPU never blends at all;
  /// only plain color-mode strokes still preview through ui.BlendMode.
  BrushBlendMode blendMode = BrushBlendMode.color;

  /// R27 #4: the cel's committed surface at stroke start — non-null puts
  /// the overlay in PRE-BLEND mode: every tile picture runs the COMMIT's
  /// own per-pixel math (stroke against these base bytes) and shows the
  /// finished result, which the painter draws as a plain REPLACEMENT
  /// (BlendMode.src inside the cel isolation layer). The GPU's float
  /// approximation of the blend — the BB-1 ±1/255 honest limit — is out
  /// of the loop entirely: what lands at pen-up is byte-for-byte what
  /// was already on screen.
  ///
  /// Set for every non-plain mode (erase included); null keeps the classic
  /// stroke-only tiles for color-mode strokes. Immutable surface, and
  /// mid-stroke the cel cannot change under it (commits happen at pen-up
  /// only).
  BitmapSurface? preBlendBase;

  /// Whether tiles carry PRE-BLENDED result pixels (replacement
  /// semantics) rather than stroke-only pixels the painter must blend.
  bool get preBlended => preBlendBase != null;

  final Map<TileCoord, ui.Image> _tileImages = <TileCoord, ui.Image>{};

  /// The stroke revision each picture represents (promotable path only).
  /// Pen-up hands an image to the adopted tile ONLY when the two revisions
  /// agree: a stale image pinned onto a fresher tile would show the wrong
  /// pixels for as long as that tile lives.
  final Map<TileCoord, int> _tileImageRevisions = <TileCoord, int>{};

  /// Overlay tile pictures by tile coordinate. Tiles never overlap, so the
  /// painter draws each with plain source-over at `(coord * tileSize)`,
  /// exactly like the committed tile images.
  late final Map<TileCoord, ui.Image> tileImages = UnmodifiableMapView(
    _tileImages,
  );

  /// Whether the overlay currently has stroke content to draw.
  bool get hasStrokeContent => _tileImages.isNotEmpty;

  /// 🚨★★★A FILL'S RESULT TILES, AS THIS OVERLAY'S PICTURES (유저 절대규칙
  /// 2026-09-17, `promoteFillDab`): the tiles the commit will install,
  /// each pictured from its own bytes and shown at its coordinate exactly
  /// as a stroke's pre-blended tiles are — so the pen-up handoff takes
  /// them at [fillPromotionRevision] and nothing is pictured twice. Every
  /// picture exists before this returns: a fill appears whole.
  void showResultTiles(Iterable<PromotedStrokeTile> tiles) {
    for (final entry in tiles) {
      _install(
        entry.coord,
        BitmapTileImageCache.pictureOfTile(entry.tile),
        revision: entry.revision,
      );
    }
  }

  /// Snapshots the overlay tiles that [region] touches from the live
  /// stroke [source] and pictures them — inside this call.
  void updateRegion({
    required ActiveStrokePixelSource source,
    required DirtyRegion region,
  }) {
    final coords = region.toTileCoords(tileSize: tileSize).toList();
    final preBlendBase = this.preBlendBase;
    if (preBlendBase != null &&
        source is BrushLiveStrokeRasterizer &&
        source.tileSize == tileSize &&
        preBlendBase.tileSize == tileSize) {
      // ONE pooled kernel call for the whole dirty region (ABI 24). A
      // pointer move touches a neighbourhood of tiles, and staging +
      // blending + premultiplying them one at a time never engaged the C
      // worker pool: measured at 256px tiles, an 1800px brush spent
      // 122ms of every frame there and now spends ~21ms.
      final blended = source.preBlendedOverlayTiles(
        coords: coords,
        base: preBlendBase,
        mode: blendMode,
        erase: erase,
      );
      for (var i = 0; i < coords.length; i += 1) {
        final tile = blended[i];
        if (tile != null) {
          _showPreBlended(coords[i], tile);
        }
      }
      return;
    }
    for (final coord in coords) {
      _showTile(coord, source);
    }
  }

  void _showTile(TileCoord coord, ActiveStrokePixelSource source) {
    final preBlendBase = this.preBlendBase;
    if (preBlendBase != null &&
        source is BrushLiveStrokeRasterizer &&
        source.tileSize == tileSize &&
        preBlendBase.tileSize == tileSize) {
      _showPromotable(coord, source, preBlendBase);
      return;
    }
    final left = coord.x * tileSize;
    final top = coord.y * tileSize;
    // Snapshot clamps at the PASTEBOARD edge, not the canvas — live
    // strokes paint (and must display) past the canvas rect.
    //
    // A PRE-BLENDED tile is the exception: it REPLACES the committed tile
    // at its coordinate, so it has to cover the whole tile. A clamped
    // edge tile would leave the rest of that coordinate showing nothing
    // (the base pass skipped it) — a transparent strip through committed
    // artwork while stroking near the pasteboard wall. Committed tiles
    // are full too, and the painter's pasteboard clip crops both alike;
    // the extra pixels are just base bytes copied through.
    final sourceCanvasSize = CanvasSize(
      width: source.canvasWidth,
      height: source.canvasHeight,
    );
    final width = preBlendBase != null
        ? tileSize
        : math.min(tileSize, sourceCanvasSize.pasteboardRightExclusive - left);
    final height = preBlendBase != null
        ? tileSize
        : math.min(tileSize, sourceCanvasSize.pasteboardBottomExclusive - top);
    _install(
      coord,
      pictureOf(
        _SnapshotBytes(
          source: source,
          coord: coord,
          tileSize: tileSize,
          width: width,
          height: height,
          preBlend: preBlendBase,
          mode: blendMode,
          erase: erase,
        ),
      ),
      revision: null,
    );
  }

  /// The PROMOTABLE picture: the rasterizer pre-blends the coordinate
  /// against the cel and keeps the straight result resident, so this
  /// image and the tile pen-up adopts are the same pixels — the image
  /// hands over at pen-up instead of being thrown away and pictured
  /// again. Tiles are FULL here (no pasteboard-edge clamp): a committed
  /// tile is full too, and the painter's pasteboard clip crops both the
  /// same way.
  void _showPromotable(
    TileCoord coord,
    BrushLiveStrokeRasterizer source,
    BitmapSurface base,
  ) {
    final blended = source.preBlendedOverlayTile(
      tileX: coord.x,
      tileY: coord.y,
      base: base,
      mode: blendMode,
      erase: erase,
    );
    if (blended == null) {
      // Nothing to show: the coordinate is untouched, or the selection
      // excludes it — either way the committed tile IS the result.
      return;
    }
    _showPreBlended(coord, blended);
  }

  /// Pictures an already pre-blended tile (single or batched) and adopts
  /// the image as this coordinate's overlay picture, with its revision
  /// recorded beside it. The tile's staging is released read or not.
  void _showPreBlended(TileCoord coord, PreBlendedOverlayTile blended) {
    try {
      _install(coord, pictureOf(blended), revision: blended.revision);
    } finally {
      blended.free();
    }
  }

  /// [image] becomes [coord]'s picture — the one it showed before retired
  /// DEFERRED (a frame may still be holding it), the stroke [revision] it
  /// represents recorded beside it — and the painter is told.
  void _install(TileCoord coord, ui.Image image, {required int? revision}) {
    final previous = _tileImages[coord];
    if (previous != null) {
      DeferredImageDisposer.instance.retire(previous);
    }
    _tileImages[coord] = image;
    if (revision != null) {
      _tileImageRevisions[coord] = revision;
    }
    notifyListeners();
  }

  /// Takes the picture for [coord] IF it represents [revision] —
  /// ownership transfers to the caller (the tile image cache), so it is
  /// removed here WITHOUT being retired. Null when nothing is pictured
  /// there or the image is a revision behind the tile being adopted.
  ///
  /// This is what makes pen-up free: the image the user has been looking
  /// at becomes the committed tile's image, with no second picture and no
  /// window where the tile has none.
  ui.Image? takeTileImageAt(TileCoord coord, {required int revision}) {
    if (_tileImageRevisions[coord] != revision) {
      return null;
    }
    _tileImageRevisions.remove(coord);
    return _tileImages.remove(coord);
  }

  /// Clears the overlay and retires its tile pictures; the single
  /// notification makes the handoff to the committed tiles atomic.
  void reset() {
    _clearTiles();
    preBlendBase = null;
    dabs.clear();
    notifyListeners();
  }

  @override
  void dispose() {
    _clearTiles();
    super.dispose();
  }

  void _clearTiles() {
    for (final image in _tileImages.values) {
      // The overlay being cleared is what the on-screen frame currently
      // shows (e.g. the stroke at commit); defer disposal past the frames
      // that may still reference it.
      DeferredImageDisposer.instance.retire(image);
    }
    _tileImages.clear();
    _tileImageRevisions.clear();
  }
}

/// One overlay tile of the CLASSIC route (a host whose overlay grid differs
/// from its surface's, or a plain colour-mode stroke), as the door reads
/// it: the straight rows snapshotted from the live stroke — pre-blended
/// against the cel when the overlay replaces coordinates — or, where the
/// engine uploads, the R25 fused snapshot + premultiply in ONE C call over
/// the native buffer (per 2000px move that is ~256 tiles — the Dart loops
/// were the big-brush stall and the visible pre-stroke tiles). Same bytes:
/// the C premultiply is parity-pinned against this exact rounding.
class _SnapshotBytes implements PictureBytes {
  _SnapshotBytes({
    required this.source,
    required this.coord,
    required this.tileSize,
    required this.width,
    required this.height,
    required this.preBlend,
    required this.mode,
    required this.erase,
  });

  final ActiveStrokePixelSource source;
  final TileCoord coord;
  final int tileSize;
  @override
  final int width;
  @override
  final int height;
  final BitmapSurface? preBlend;
  final BrushBlendMode mode;
  final bool erase;

  /// The straight-alpha rows, then — R27 #4 — the COMMIT's result,
  /// computed by the commit's own math against the cel's committed bytes
  /// where the overlay replaces coordinates: the painter replaces the base
  /// with it, and pen-up lands the exact same bytes. (This forgoes the
  /// fused C snapshot: correctness is the rule here; the giant-brush +
  /// blend-mode combo pays some Dart time and is flagged for a native
  /// lift if it ever shows.)
  Uint8List _straight() {
    final left = coord.x * tileSize;
    final top = coord.y * tileSize;
    final straight = Uint8List(width * height * 4);
    for (var y = 0; y < height; y += 1) {
      source.copyRow(left, top + y, width, straight, y * width * 4);
    }
    final preBlend = this.preBlend;
    if (preBlend == null) {
      return straight;
    }
    return preBlendStrokeOverlayPixels(
      dst: bitmapSurfaceRegionPixels(
        preBlend,
        DirtyRegion(
          left: left,
          top: top,
          rightExclusive: left + width,
          bottomExclusive: top + height,
        ),
      ),
      src: straight,
      mode: mode,
      erase: erase,
      pixelCount: width * height,
    );
  }

  @override
  T readStraight<T>(T Function(Uint8List straight) use) => use(_straight());

  @override
  T readPremultiplied<T>(T Function(Uint8List premultiplied) use) {
    final source = this.source;
    if (preBlend == null &&
        width == tileSize &&
        height == tileSize &&
        source is BrushLiveStrokeRasterizer &&
        source.tileSize == tileSize) {
      final fused = source.premultipliedOverlayTile(coord.x, coord.y);
      if (fused != null) {
        try {
          return use(fused.view);
        } finally {
          fused.free();
        }
      }
    }
    // Premultiplied in place with the same per-pixel branches/rounding as
    // the kernel: the alpha==0 case must ZERO the color bytes — a
    // straight-alpha stroke pixel can round to alpha 0 while keeping
    // non-zero color, which would be invalid premultiplied data.
    final bytes = _straight();
    premultiplyRgbaInPlace(bytes);
    return use(bytes);
  }
}
