import 'dart:collection';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

import '../../core/rgba_premultiply.dart';
import '../../core/sync_image_upload.dart';
import '../../models/bitmap_surface.dart';
import '../../models/bitmap_tile.dart';
import '../../models/brush_blend_mode.dart';
import '../../models/brush_dab.dart';
import '../../models/dirty_region.dart';
import '../../models/layer_effect.dart';
import '../../models/tile_coord.dart';
import '../../services/brush_live_stroke_rasterizer.dart'
    show
        ActiveStrokePixelSource,
        BrushLiveStrokeRasterizer,
        PreBlendedOverlayTile,
        PromotedStrokeTile;
import '../../services/brush_stroke_blend.dart'
    show bitmapSurfaceRegionPixels, preBlendStrokeOverlayPixels;
import '../../services/cel_source_effect_pass.dart'
    show celSourceEffectSignature, celSourcePlugin;
import '../../services/cel_surface_as_shown.dart'
    show celStraightTileAsShown, celSurfaceAsShown, celTileAsShown;
import '../../services/cel_text_laying.dart' show celTextPlatesOver;
import 'bitmap_tile_image_cache.dart';
import 'chained_picture.dart';
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

  /// The colour keys the cel's row shows it through — the chain the cel's
  /// own painter shows its tiles through (`celSurfaceAsShown`).
  ///
  /// 🚨A COORDINATE THE OVERLAY REPLACES SHOWS THE OVERLAY'S PICTURE AND
  /// NOTHING ELSE, so that picture goes through the row's keys as it has the
  /// cel's texts laid ([_platesOver]): the bytes the committed tile will
  /// show. 🔬Without them a keyed sheet's ground showed bare under a stroke
  /// until the pen came up — 2,868 pixels apart on a keyed row, 0 on a bare
  /// one (공통 2026-10-16, card a-stroke-on-a-keyed-row-shows-its-tiles-unkeyed;
  /// 유저 절대규칙 2026-09-17: 「보이는 중이랑 결과랑 절대로 다르면 안 되」).
  ///
  /// ★Told by the host that builds the cel's painter, in the statement
  /// beside it: the keys are the ROW's, not the cel's, and that is where
  /// the cel's tiles are shown through them — so the two cannot show the
  /// cel two ways, and a stroke's start has nothing new to remember
  /// ([preBlendBase]'s reason).
  List<ResolvedLayerEffect> sourceEffects = const [];

  final Map<TileCoord, ui.Image> _tileImages = <TileCoord, ui.Image>{};

  /// 🗣️I-132-Q32 b 「무거운 플러그인은 그 행이 바뀔 때마다 캔버스가 그만큼
  /// 멈춘다」: on a row whose chain runs a plugin, a result changes the
  /// cel's whole picture — the plugin may move a pixel anywhere — so it is
  /// not shown a tile at a time. The stroke's result tiles so far, by
  /// coordinate, laid on the cel and run through its chain WHOLE at every
  /// change ([_showThroughPlugin]).
  final Map<TileCoord, BitmapTile> _landed = <TileCoord, BitmapTile>{};

  /// The plugin the row's chain runs, where a result here REPLACES the
  /// cel's tiles ([preBlended]) — null elsewhere.
  ResolvedLayerEffect? get _pluginOver =>
      preBlended ? celSourcePlugin(sourceEffects) : null;

  /// Whether a picture made here belongs to the ONE committed tile at its
  /// coordinate, so pen-up hands it over ([tileShownFor],
  /// [takeTileImageAt]) — not on a row whose chain runs a plugin, where the
  /// landed cel is pictured as a whole, as it is shown.
  bool get handsTilesOver => _pluginOver == null;

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
  /// 2026-09-17, `promoteFillDabs`): the tiles the commit will install,
  /// each pictured from its own bytes and shown at its coordinate exactly
  /// as a stroke's pre-blended tiles are — so the pen-up handoff takes
  /// them at [fillPromotionRevision] and nothing is pictured twice. Every
  /// picture exists before this returns: a fill appears whole.
  void showResultTiles(Iterable<PromotedStrokeTile> tiles) {
    if (_pluginOver != null) {
      for (final entry in tiles) {
        _landed[entry.coord] = entry.tile;
      }
      _showThroughPlugin();
      return;
    }
    for (final entry in tiles) {
      _install(
        entry.coord,
        BitmapTileImageCache.pictureOfTile(
          tileShownFor(entry.coord, entry.tile),
        ),
        revision: entry.revision,
      );
    }
  }

  /// The plates of the texts the cel under this stroke carries that stand
  /// over [coord], bottom → top — null where none does, which is nearly
  /// everywhere.
  ///
  /// 🚨★★★A COORDINATE THE OVERLAY REPLACES SHOWS THE OVERLAY'S PICTURE AND
  /// NOTHING ELSE, so that picture has to hold the cel's texts too (R9-rest,
  /// the text tool). The stroke's result is the DRAWING — what the commit
  /// will store — and a text is laid over the drawing when a cel is shown
  /// (`celSurfaceWithTextsLaid`). Shown bare, a stroke passing under a text
  /// would wipe the letters off every tile it touched for as long as the
  /// pen was down, and pen-up would put them back: 유저 절대규칙 2026-09-17,
  /// 「보이는 중이랑 결과랑 절대로 다르면 안 되」.
  ///
  /// Read off [preBlendBase] — the cel as the stroke found it — rather than
  /// set beside it, so there is no second thing for a stroke's start to
  /// forget.
  List<BitmapTile>? _platesOver(TileCoord coord) {
    final base = preBlendBase;
    return base == null ? null : celTextPlatesOver(base)?[coord];
  }

  /// The tile [coord] SHOWS when the cel holds [tile] there: [tile] itself,
  /// or it with the cel's texts laid over it and the row's keys through it
  /// ([sourceEffects]) — the tile the painter draws once the stroke has
  /// landed, and so the one a picture made for this coordinate belongs to
  /// ([takeTileImageAt]'s caller hands it over).
  BitmapTile tileShownFor(TileCoord coord, BitmapTile tile) =>
      celTileAsShown(tile, _platesOver(coord), _effectsOver, tileSize);

  /// The keys a result here is shown through: the row's ([sourceEffects])
  /// where it REPLACES the cel's tile ([preBlended]), and none where it is
  /// the stroke alone drawn over the cel's own tile — which its painter
  /// shows through them already. Read off [preBlendBase] as [_platesOver]
  /// is, for its reason.
  List<ResolvedLayerEffect> get _effectsOver =>
      preBlended ? sourceEffects : const [];

  /// Snapshots the overlay tiles that [region] touches from the live
  /// stroke [source] and pictures them — inside this call.
  void updateRegion({
    required ActiveStrokePixelSource source,
    required DirtyRegion region,
  }) {
    final coords = region.toTileCoords(tileSize: tileSize).toList();
    final preBlended = _preBlendedFrom(source);
    if (preBlended != null && _pluginOver != null) {
      _eachPreBlended(preBlended, coords, _keepLanded);
      _showThroughPlugin();
      return;
    }
    if (preBlended != null) {
      _eachPreBlended(preBlended, coords, _showPreBlended);
      return;
    }
    for (final coord in coords) {
      _showTile(coord, source);
    }
  }

  /// [blended] kept as the stroke's result at [coord] ([_landed]).
  void _keepLanded(TileCoord coord, PreBlendedOverlayTile blended) {
    try {
      _landed[coord] = BitmapTile.written(
        size: tileSize,
        write: (bytes) =>
            blended.readStraight((straight) => bytes.setAll(0, straight)),
      );
    } finally {
      blended.free();
    }
  }

  /// The cel with the stroke's result laid in ([_landed]), as its row shows
  /// it — run through the chain whole — pictured at every coordinate it or
  /// the cel as it stood shows, in ONE notification: what pen-up lands is
  /// what is on screen, and a coordinate the plugin cleared shows clear.
  void _showThroughPlugin() {
    final base = preBlendBase!;
    final shown = celSurfaceAsShown(
      base.putTiles([
        for (final MapEntry(key: coord, value: tile) in _landed.entries)
          (coord: coord, tile: tile),
      ]),
      sourceEffects,
    );
    final before = celSurfaceAsShown(base, sourceEffects);
    for (final coord in {...shown.tiles.keys, ...before.tiles.keys}) {
      if (_tileImages.remove(coord) case final previous?) {
        DeferredImageDisposer.instance.retire(previous);
      }
      _tileImages[coord] = BitmapTileImageCache.pictureOfTile(
        shown.tileAt(coord) ?? BitmapTile.blank(size: tileSize),
      );
    }
    notifyListeners();
  }

  /// [updateRegion]'s pictures for [coords], made OFF SCREEN and kept for
  /// [showStaged] — a dragged shape's stroke is pictured a few tiles a frame
  /// and comes up whole (I-69-Q4ⓒ). Answers false, staging nothing, where
  /// [source] does not pre-blend at this overlay's grid: there the pictures
  /// are made as they are shown, and nothing can be made ahead.
  bool stageRegion({
    required ActiveStrokePixelSource source,
    required List<TileCoord> coords,
  }) {
    final preBlended = _preBlendedFrom(source);
    // A row that runs a plugin shows a stroke as the whole cel it makes
    // ([_showThroughPlugin]), never a few tiles ahead.
    if (preBlended == null || _pluginOver != null) {
      return false;
    }
    _eachPreBlended(preBlended, coords, _stagePreBlended);
    return true;
  }

  /// Everything [stageRegion] made — the stroke of [strokeDabs] — in place
  /// of everything this overlay showed, in ONE notification, so the old
  /// stroke and the new never share a frame.
  void showStaged(List<BrushDab> strokeDabs) {
    _clearTiles();
    for (final MapEntry(key: coord, value: staged) in _staged.entries) {
      _tileImages[coord] = staged.image;
      final revision = staged.revision;
      if (revision != null) {
        _tileImageRevisions[coord] = revision;
      }
    }
    _staged.clear();
    dabs
      ..clear()
      ..addAll(strokeDabs);
    notifyListeners();
  }

  /// Drops what [stageRegion] made and [showStaged] has not shown: a stroke
  /// given up for a newer one. ⚠️Before the newer one is staged — a live
  /// stroke starts its tile revisions again from nothing, so a picture of
  /// the old one could pass for the new one's.
  void dropStaged() {
    for (final staged in _staged.values) {
      staged.image.dispose();
    }
    _staged.clear();
  }

  /// Pictures [stageRegion] made and nothing has shown yet.
  final Map<TileCoord, ({ui.Image image, int? revision})> _staged = {};

  /// How many pictures are staged and not shown.
  @visibleForTesting
  int get stagedCount => _staged.length;

  /// [source] when its tiles picture through the pre-blend at this grid —
  /// the road [updateRegion] takes for a whole region in one kernel call —
  /// or null.
  BrushLiveStrokeRasterizer? _preBlendedFrom(ActiveStrokePixelSource source) {
    final preBlendBase = this.preBlendBase;
    return preBlendBase != null &&
            source is BrushLiveStrokeRasterizer &&
            source.tileSize == tileSize &&
            preBlendBase.tileSize == tileSize
        ? source
        : null;
  }

  /// [coords] pre-blended against [preBlendBase] by [source], each handed
  /// to [take].
  ///
  /// ONE pooled kernel call for the whole region (ABI 24). A pointer move
  /// touches a neighbourhood of tiles, and staging + blending +
  /// premultiplying them one at a time never engaged the C worker pool:
  /// measured at 256px tiles, an 1800px brush spent 122ms of every frame
  /// there and now spends ~21ms.
  void _eachPreBlended(
    BrushLiveStrokeRasterizer source,
    List<TileCoord> coords,
    void Function(TileCoord coord, PreBlendedOverlayTile tile) take,
  ) {
    final blended = source.preBlendedOverlayTiles(
      coords: coords,
      base: preBlendBase!,
      mode: blendMode,
      erase: erase,
    );
    for (var i = 0; i < coords.length; i += 1) {
      final tile = blended[i];
      if (tile != null) {
        take(coords[i], tile);
      }
    }
  }

  void _showTile(TileCoord coord, ActiveStrokePixelSource source) {
    final preBlended = _preBlendedFrom(source);
    if (preBlended != null) {
      _showPromotable(coord, preBlended, preBlendBase!);
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
    final wall = source.pasteboard;
    final width = preBlendBase != null
        ? tileSize
        : math.min(tileSize, wall.rightExclusive - left);
    final height = preBlendBase != null
        ? tileSize
        : math.min(tileSize, wall.bottomExclusive - top);
    _install(
      coord,
      _pictureOfResult(
        coord,
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
      _install(
        coord,
        _pictureOfResult(coord, blended),
        revision: blended.revision,
      );
    } finally {
      blended.free();
    }
  }

  /// [_showPreBlended] kept off screen for [showStaged].
  void _stagePreBlended(TileCoord coord, PreBlendedOverlayTile blended) {
    try {
      // Never on screen, so nothing can still be drawing it.
      _staged.remove(coord)?.image.dispose();
      _staged[coord] = (
        image: _pictureOfResult(coord, blended),
        revision: blended.revision,
      );
    } finally {
      blended.free();
    }
  }

  /// The picture [coord] shows for [result] — a live stroke's bytes there,
  /// pre-blended against the cel: the result's own picture, or, where the
  /// cel's texts stand over the coordinate ([_platesOver]) or the row keys
  /// its colours ([sourceEffects]), the result as the cel shows it.
  ///
  /// Those are the bytes the committed tile will show there, made by the
  /// seam that will show them (`celStraightTileAsShown`, the same laying and
  /// the same keys' walk as a tile's own) — so pen-up hands this very
  /// picture to that tile ([tileShownFor]) and not a byte on screen moves.
  ///
  /// ⚠️A COPY of the result first: the laying and the keys write in place,
  /// and those bytes are the rasterizer's resident result — the commit's
  /// own.
  ui.Image _pictureOfResult(TileCoord coord, PictureBytes result) {
    final plates = _platesOver(coord);
    final effects = _effectsOver;
    if (plates == null && celSourceEffectSignature(effects).isEmpty) {
      return pictureOf(result);
    }
    return BitmapTileImageCache.pictureOfTile(
      BitmapTile.written(
        size: tileSize,
        write: (shown) {
          result.readStraight((straight) => shown.setAll(0, straight));
          celStraightTileAsShown(shown, plates, effects, tileSize);
        },
      ),
    );
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

  /// [coord]'s picture as a screen drawing it REDUCED samples it — carrying
  /// the engine's chain ([chainedPictureOf]), remade IN ITS PLACE where it
  /// carries none, at the stroke revision it represents: pen-up hands the
  /// very picture the screen showed to the committed tile. Null where
  /// nothing is pictured at [coord].
  ///
  /// The painter is not told: at 100% it is the same picture. ⚠️A screen
  /// that measures the live row by its pictures (`LiveSurfaceTokens`) sees
  /// the coordinate change once and patches the same bytes once.
  ui.Image? chainedTileImageAt(TileCoord coord) {
    final image = _tileImages[coord];
    if (image == null || carriesChain(image)) {
      return image;
    }
    final chained = chainedPictureOf(image);
    DeferredImageDisposer.instance.retire(image);
    _tileImages[coord] = chained;
    return chained;
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
    dropStaged();
    preBlendBase = null;
    dabs.clear();
    notifyListeners();
  }

  @override
  void dispose() {
    _clearTiles();
    dropStaged();
    super.dispose();
  }

  void _clearTiles() {
    _landed.clear();
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
