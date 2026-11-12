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
import '../../models/tile_coord.dart';
import '../../native/engine_tile_ledger.dart';
import '../../services/brush_live_stroke_rasterizer.dart'
    show
        ActiveStrokePixelSource,
        BrushLiveStrokeRasterizer,
        PreBlendedOverlayTile,
        PromotedStrokeTile;
import '../../services/brush_stroke_blend.dart'
    show bitmapSurfaceRegionPixels, preBlendStrokeOverlayPixels;
import '../../services/cel_surface_as_shown.dart' show celTileAsShown;
import '../../services/cel_text_laying.dart' show celTextPlatesOver;
import 'bitmap_tile_image_cache.dart';
import 'chained_picture.dart';
import 'deferred_image_disposal.dart';
import 'fill_range_mark.dart';

/// Mutable state of the in-progress stroke overlay.
///
/// A lightweight editor-local [ChangeNotifier]: the interactive view blends
/// new dabs into its live CPU stroke buffer and hands the touched region to
/// [updateRegion], which notifies the canvas painter through the
/// `CustomPainter.repaint` hook, so strokes repaint without rebuilding any
/// widgets.
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
/// 🚨★★★PICTURED IN THE CALL THAT READS IT, ON EVERY ENGINE (유저 절대규칙
/// 2026-09-17: 「보이는 중이랑 결과랑 절대로 다르면 안 되」). What a stroke
/// touched is pictured the first time anything reads the pictures
/// ([tileImages], [pictureOwed]) — the picture of a
/// coordinate and the stroke revision it shows recorded in the same
/// synchronous call that pre-blended it — so the pen-up handoff finds a
/// picture at every promoted tile's revision and nothing ever has to stand
/// in for a committed tile afterwards — there is no decode in flight, no
/// settle window, no stand-in. Where the engine uploads (Impeller, every
/// platform since 3.47) the picture is a real texture; where it draws
/// (Skia, the test runner) it is a rasterized picture — the door makes the
/// same bytes either way.
///
/// ↩️Pictured inside every flush until F-533 (유저 2026-11-01 「최대한 그
/// 외적으로 좋아지기만 하는 부분에서 구조를 효율적으로 리팩토링」): a step goes
/// into the frame's picture only once the last is in, so under load most
/// flushes uploaded pictures the next flush replaced with nothing having
/// drawn them, on a raster thread already 96% busy. 🔬Main PC, 144 Hz, a new
/// project, under eighteen suites of tests, in turn in one run, 300 px/s:
/// pictures made 2381 → 666 at 100% and 1919 → 350 fitted, a flush 0.8 → 0.3
/// ms, input to raster done p50 36.1 → 35.0 and 73.1 → 66.1 ms. Quiet, a
/// flush for each step, 2879 → 2086, and no later.
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
    assert(!strokeInHand, 'configureTileSize requires an empty overlay');
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
  ///
  /// 🚨A COORDINATE THE OVERLAY REPLACES SHOWS THE OVERLAY'S PICTURE AND
  /// NOTHING ELSE, and the engine runs the row's chain over it there as over
  /// the cel's tiles — its keys and its plugins: the bytes the committed
  /// tile will show. ↩️The keys were run here, on each result tile (공통
  /// 2026-10-16, card a-stroke-on-a-keyed-row-shows-its-tiles-unkeyed —
  /// 2,868 pixels apart without them; 유저 절대규칙 2026-09-17: 「보이는 중이랑
  /// 결과랑 절대로 다르면 안 되」), until the engine keyed a row's stored bytes
  /// (float-warp-resamples-in-the-c-engine (1), 2026-11-11); and on a row
  /// whose chain ran a plugin at its head, the result was laid on the cel
  /// and run through it whole at every change (🗣️I-132-Q32 b 「무거운
  /// 플러그인은 그 행이 바뀔 때마다 캔버스가 그만큼 멈춘다」), until the plugin
  /// was a step of the chain ((2)) — whose frame waits for it instead.
  bool get preBlended => preBlendBase != null;

  /// What each coordinate the overlay shows is shown by ([_Shown]) — one
  /// record, so a picture, the tile it is of and the revision it shows
  /// cannot part.
  final Map<TileCoord, _Shown> _shown = <TileCoord, _Shown>{};

  /// Where the stroke moved and no picture shows it yet ([pictureOwed]).
  final Set<TileCoord> _owed = <TileCoord>{};

  /// What shows [_owed]: null where nothing is owed.
  ActiveStrokePixelSource? _owedFrom;

  /// Where the stroke moved, a region an [updateRegion], since the pictures
  /// last changed any other way: from then on it is another list, and a
  /// mark in this one tells nothing ([movedSince]). It goes with its stroke.
  List<DirtyRegion> _moves = [];

  /// Overlay tile pictures by tile coordinate. Tiles never overlap, so the
  /// painter draws each with plain source-over at `(coord * tileSize)`,
  /// exactly like the committed tile images.
  Map<TileCoord, ui.Image> get tileImages {
    pictureOwed();
    return _PicturesOf(this);
  }

  /// 🚨★★★THE TILE EACH COORDINATE SHOWS, where the overlay REPLACES the
  /// cel's tile there ([preBlended]) — what its picture is of: what a screen
  /// that lays tiles rather than drawing pictures lays in the cel's place
  /// (`EngineStackScreen`, flip lane ⓐ: 「쥔 픽셀은 타일로 쥐고 그림은 거기서
  /// 낸다」). None where the overlay holds the stroke alone, drawn over the
  /// cel's own tile — no tile shows that.
  Map<TileCoord, BitmapTile> get shownTiles {
    pictureOwed();
    return {
      for (final MapEntry(key: coord, value: shown) in _shown.entries)
        coord: ?shown.tile,
    };
  }

  /// Whether the overlay currently has stroke content to draw.
  bool get hasStrokeContent => tileImages.isNotEmpty;

  /// Whether a stroke is in hand here, its pictures made or not: what asks
  /// of a stroke in every paint, whether or not anything draws it.
  bool get strokeInHand => _owedFrom != null || _shown.isNotEmpty;

  /// Where the pictures stand, for [movedSince] to be asked from.
  OverlayMoveMark get moveMark => (moves: _moves, count: _moves.length);

  /// The range a fill held down will cover (I-160), marked over the row
  /// this overlay draws on — null while no fill is held.
  ///
  /// Here because a fill IS a stroke of this overlay, of one dab: the press
  /// marks where it reaches and the lift shows the result in its place,
  /// both through this model's one notification ([reset] clears it).
  FillRangeMark? get fillRange => _fillRange;
  FillRangeMark? _fillRange;

  /// Marks [mark] as the range a held fill covers, in place of any before.
  void showFillRange(FillRangeMark? mark) {
    if (identical(mark, _fillRange)) {
      return;
    }
    _fillRange = mark;
    notifyListeners();
  }

  /// What the stroke moved since [mark] — inside the tiles whose pictures it
  /// changed, the pixels that are not what they were. Null where that cannot
  /// be told: the pictures changed some other way since (a fill's tiles, a
  /// shape put up, a tile handed over, a plugin's whole cel), or they are
  /// another stroke's, or nothing moved.
  DirtyRegion? movedSince(OverlayMoveMark mark) {
    if (!identical(mark.moves, _moves)) {
      return null;
    }
    DirtyRegion? moved;
    for (final region in _moves.skip(mark.count)) {
      moved = moved?.union(region) ?? region;
    }
    return moved;
  }

  /// 🚨★★★A FILL'S RESULT TILES, AS THIS OVERLAY'S PICTURES (유저 절대규칙
  /// 2026-09-17, `promoteFillDabs`): the tiles the commit will install,
  /// each pictured from its own bytes and shown at its coordinate exactly
  /// as a stroke's pre-blended tiles are — so the pen-up handoff takes
  /// them at [fillPromotionRevision] and nothing is pictured twice. Every
  /// picture exists before this returns: a fill appears whole.
  void showResultTiles(Iterable<PromotedStrokeTile> tiles) {
    pictureOwed();
    for (final entry in tiles) {
      final shown = tileShownFor(entry.coord, entry.tile);
      _install(entry.coord, (
        image: BitmapTileImageCache.pictureOfTile(shown),
        tile: shown,
        landed: null,
        revision: entry.revision,
      ));
    }
    _moves = [];
    notifyListeners();
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
  /// or it with the cel's texts laid over it — the tile the painter draws
  /// once the stroke has landed, and so the one a picture made for this
  /// coordinate belongs to ([takeTileImageAt]'s caller hands it over).
  BitmapTile tileShownFor(TileCoord coord, BitmapTile tile) =>
      celTileAsShown(tile, _platesOver(coord), tileSize);

  /// The overlay tiles that [region] touches moved in the live stroke
  /// [source]: pictured when they are next read ([pictureOwed]).
  void updateRegion({
    required ActiveStrokePixelSource source,
    required DirtyRegion region,
  }) {
    _owedFrom = source;
    _owed.addAll(region.toTileCoords(tileSize: tileSize));
    _moves.add(region);
    notifyListeners();
  }

  /// Snapshots the overlay tiles the stroke moved since the last read from
  /// its live source, and pictures them — inside this call. ⚠️Before the
  /// source gives up what it holds: a pen-up's promotion takes the tiles
  /// out of it.
  void pictureOwed() {
    final source = _owedFrom;
    if (source == null) {
      return;
    }
    final coords = _owed.toList();
    _owedFrom = null;
    _owed.clear();
    final preBlended = _preBlendedFrom(source);
    if (preBlended != null) {
      _eachPreBlended(preBlended, coords, _showPreBlended);
      return;
    }
    for (final coord in coords) {
      _showTile(coord, source);
    }
  }

  /// [result] — a whole tile of the stroke's result, pre-blended against
  /// the cel — as a tile of its own: the rasterizer's resident bytes are
  /// blended again in place.
  BitmapTile _tileOf(PictureBytes result) =>
      (result is PreBlendedOverlayTile ? result.landed : null) ??
      BitmapTile.written(
        size: tileSize,
        write: (bytes) =>
            result.readStraight((straight) => bytes.setAll(0, straight)),
      );

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
    if (preBlended == null) {
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
    _shown.addAll(_staged);
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
      staged.image?.dispose();
    }
    _staged.clear();
  }

  /// Pictures [stageRegion] made and nothing has shown yet.
  final Map<TileCoord, _Shown> _staged = {};

  /// How many pictures are staged and not shown.
  @visibleForTesting
  int get stagedCount => _staged.length;

  /// [source] when its tiles picture through the pre-blend at this grid —
  /// the road [pictureOwed] takes for a whole region in one kernel call —
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
  /// ONE call for the whole region: a pointer move touches a neighbourhood
  /// of tiles, and the engine lands them in one pass. ↩️The C's reason
  /// (ABI 24, till 2026-11-12): staging + blending + premultiplying them
  /// one at a time never engaged its worker pool — measured at 256px tiles,
  /// an 1800px brush spent 122ms of every frame there and ~21ms in one
  /// pooled call.
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
      _shownOf(
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
        revision: null,
      ),
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
  /// recorded beside it.
  void _showPreBlended(TileCoord coord, PreBlendedOverlayTile blended) {
    _install(coord, _shownOf(coord, blended, revision: blended.revision));
  }

  /// [_showPreBlended] kept off screen for [showStaged].
  void _stagePreBlended(TileCoord coord, PreBlendedOverlayTile blended) {
    // Never on screen, so nothing can still be drawing it.
    _staged.remove(coord)?.image?.dispose();
    _staged[coord] = _shownOf(coord, blended, revision: blended.revision);
  }

  /// What [coord] is shown by for [result] — a live stroke's bytes there,
  /// at [revision]. Pre-blended against the cel ([preBlended]): the tile the
  /// coordinate shows — the result, or, where the cel's texts stand over
  /// the coordinate ([_platesOver]), the result as the cel shows it
  /// ([tileShownFor]) — and its picture. Else the stroke alone, which no
  /// tile shows.
  ///
  /// Those are the bytes the committed tile will show there, made by the
  /// seam that will show them — so pen-up hands this very picture to that
  /// tile ([tileShownFor]) and not a byte on screen moves.
  _Shown _shownOf(
    TileCoord coord,
    PictureBytes result, {
    required int? revision,
  }) {
    if (!preBlended) {
      return (
        image: pictureOf(result),
        tile: null,
        landed: null,
        revision: revision,
      );
    }
    final landed = _tileOf(result);
    final shown = tileShownFor(coord, landed);
    if (result is PreBlendedOverlayTile && result.landed != null) {
      // No picture: the screen lays the tile, and one read back to make a
      // picture of it would cost every tile of every frame ([_imageAt]).
      return (image: null, tile: shown, landed: landed, revision: revision);
    }
    return (
      // Shown as it is, the result is pictured from its own bytes: the door
      // reads the premultiplied ones the blend already made.
      image: identical(shown, landed)
          ? pictureOf(result)
          : BitmapTileImageCache.pictureOfTile(shown),
      tile: shown,
      landed: null,
      revision: revision,
    );
  }

  /// [shown] becomes what [coord] is shown by — the picture it showed before
  /// retired DEFERRED (a frame may still be holding it).
  void _install(TileCoord coord, _Shown shown) {
    final previous = _shown[coord];
    if (previous != null) {
      _letGo(previous);
    }
    _shown[coord] = shown;
  }

  /// What [shown] holds, let go: its picture past the frames that may still
  /// be drawing it, the slot of the tile the engine laid at once — a frame
  /// composes before anything lands over it.
  void _letGo(_Shown shown) {
    final image = shown.image;
    if (image != null) {
      DeferredImageDisposer.instance.retire(image);
    }
    final landed = shown.landed;
    if (landed != null) {
      EngineTileLedger.instance.retire(landed);
    }
  }

  /// [coord]'s picture, made from its tile the first time it is asked where
  /// none was — the engine's results, which only a screen that draws
  /// pictures asks for ([_shownOf]).
  ui.Image? _imageAt(TileCoord coord) {
    final shown = _shown[coord];
    if (shown == null || shown.image != null) {
      return shown?.image;
    }
    final image = BitmapTileImageCache.pictureOfTile(shown.tile!);
    _shown[coord] = (
      image: image,
      tile: shown.tile,
      landed: shown.landed,
      revision: shown.revision,
    );
    return image;
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
    pictureOwed();
    final image = _imageAt(coord);
    if (image == null || carriesChain(image)) {
      return image;
    }
    final shown = _shown[coord]!;
    final chained = chainedPictureOf(image);
    DeferredImageDisposer.instance.retire(image);
    _shown[coord] = (
      image: chained,
      tile: shown.tile,
      landed: shown.landed,
      revision: shown.revision,
    );
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
    if (_shown[coord]?.revision != revision) {
      return null;
    }
    _moves = [];
    final taken = _shown.remove(coord)!;
    final landed = taken.landed;
    if (landed != null) {
      EngineTileLedger.instance.retire(landed);
    }
    return taken.image;
  }

  /// Clears the overlay and retires its tile pictures; the single
  /// notification makes the handoff to the committed tiles atomic.
  void reset() {
    _clearTiles();
    dropStaged();
    preBlendBase = null;
    dabs.clear();
    _fillRange = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _clearTiles();
    dropStaged();
    super.dispose();
  }

  void _clearTiles() {
    _owed.clear();
    _owedFrom = null;
    _moves = [];
    for (final shown in _shown.values) {
      // The overlay being cleared is what the on-screen frame currently
      // shows (e.g. the stroke at commit); defer disposal past the frames
      // that may still reference it.
      _letGo(shown);
    }
    _shown.clear();
  }
}

/// What a coordinate of the overlay is shown by: its [image], the [tile]
/// that picture is of where a tile shows the coordinate
/// ([ActiveStrokeOverlayModel.shownTiles]), and the stroke [revision] it
/// shows, on the promotable road — pen-up hands the picture to the adopted
/// tile ONLY when the two revisions agree: a stale one pinned onto a fresher
/// tile would show the wrong pixels for as long as that tile lives.
typedef _Shown = ({
  ui.Image? image,
  BitmapTile? tile,
  BitmapTile? landed,
  int? revision,
});

/// The pictures of [_shown], by coordinate — a view, so a paint's reads
/// make no map.
final class _PicturesOf extends UnmodifiableMapBase<TileCoord, ui.Image> {
  _PicturesOf(this._overlay);

  final ActiveStrokeOverlayModel _overlay;

  @override
  ui.Image? operator [](Object? key) =>
      key is TileCoord ? _overlay._imageAt(key) : null;

  @override
  Iterable<TileCoord> get keys => _overlay._shown.keys;
}

/// A place in the moves of an overlay's pictures
/// ([ActiveStrokeOverlayModel.moveMark]): what they moved since it is what
/// [ActiveStrokeOverlayModel.movedSince] tells.
typedef OverlayMoveMark = ({List<DirtyRegion> moves, int count});

/// One overlay tile of the CLASSIC route (a host whose overlay grid differs
/// from its surface's, or a plain colour-mode stroke), as the door reads
/// it: the straight rows snapshotted from the live stroke — pre-blended
/// against the cel when the overlay replaces coordinates.
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
  /// with it, and pen-up lands the exact same bytes.
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
    // Premultiplied in place: the alpha==0 case must ZERO the color bytes
    // — a straight-alpha stroke pixel can round to alpha 0 while keeping
    // non-zero color, which would be invalid premultiplied data.
    final bytes = _straight();
    premultiplyRgbaInPlace(bytes);
    return use(bytes);
  }
}
