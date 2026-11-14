import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:gpu_engine/gpu_engine.dart';

import '../core/floor_math.dart';
import '../core/lru.dart';
import '../core/rgba_premultiply.dart';
import '../core/sync_image_upload.dart';
import '../models/bitmap_surface.dart';
import '../models/bitmap_tile.dart';
import '../models/brush_blend_mode.dart';
import '../models/brush_dab.dart';
import '../models/brush_tip_mask.dart';
import '../models/brush_texture_mode.dart';
import '../models/dirty_region.dart';
import '../models/pasteboard_bounds.dart';
import '../models/tile_coord.dart';
import '../native/app_gpu_engine.dart';
import '../native/engine_strokes.dart';
import '../native/engine_tile_ledger.dart';
import 'brush_blur_picture.dart';
import 'brush_dab_dirty_region.dart';
import 'brush_dab_kernel.dart';
import 'selection_clip.dart';
import 'brush_stroke_blend.dart'
    show
        bitmapSurfaceRegionPixels,
        engineBlendModeOf,
        preBlendStrokeOverlayPixels,
        separableBlendModeNativeId,
        strokeCoverageMask,
        strokeOpacityCoverage;

/// A pre-blended overlay tile — the bytes the door ([pictureOf]) turns
/// into the coordinate's picture — and the stroke [revision] they were
/// blended at (pen-up hands the picture of a matching revision straight to
/// the adopted tile — a stale one would pin wrong pixels forever, so the
/// number travels with it).
///
/// Reads STRAIGHT from the result as it stands (the door's Skia road), and
/// PREMULTIPLIED from a premultiply made only when asked (the door's
/// Impeller road). Either way the engine's form is made once and the other
/// never.
class PreBlendedOverlayTile implements PictureBytes {
  /// A result the engine laid: [landed], its tile, the bytes read from it
  /// only where a caller on the CPU asks.
  PreBlendedOverlayTile._landed(this.landed, this.size, this.revision)
    : _straight = Uint8List(0);

  /// A result blended here, on a grid that is not the engine's.
  PreBlendedOverlayTile._resident(this._straight, this.size, this.revision)
    : landed = null;

  /// The tile the engine laid this result in; null on the route that holds
  /// its bytes here.
  final BitmapTile? landed;

  /// The resident straight result — the rasterizer's own buffer, valid
  /// until the next blend at this coordinate.
  final Uint8List _straight;
  final int size;
  final int revision;

  @override
  int get width => size;

  @override
  int get height => size;

  @override
  T readStraight<T>(T Function(Uint8List straight) use) {
    final tile = landed;
    return tile == null
        ? use(_straight)
        : tile.readPixels((_, straight) => use(straight));
  }

  @override
  T readPremultiplied<T>(T Function(Uint8List premultiplied) use) {
    final tile = landed;
    return tile == null
        ? use(premultipliedRgbaCopy(_straight))
        : tile.readPixels(
            (_, straight) => use(premultipliedRgbaCopy(straight)),
          );
  }
}

/// A finished stroke tile handed to the cel surface, with the stroke
/// [revision] its pixels represent.
class PromotedStrokeTile {
  PromotedStrokeTile(this.coord, this.tile, this.revision);

  /// WHERE this tile goes. It is the map key the commit will store it
  /// under, carried beside the tile instead of read back off it — the
  /// coordinate is a fact about the SURFACE, not about the pixels.
  final TileCoord coord;

  final BitmapTile tile;
  final int revision;
}

/// A tile's stroke coverage off the engine's grid — the opacity ceiling
/// (F-12): 1 byte per pixel on the stroke grid, built once per stroke.
///
/// [allOutside]: a ceiling of nothing needs no blend at all. ↩️It held a
/// selection's coverage too till 2026-11-14 ([cutOnTheEngineOnly]).
class _MaskTile {
  _MaskTile({required this.bytes, required this.allOutside});

  final Uint8List bytes;
  final bool allOutside;
}

/// One resident pre-blended result: straight-alpha bytes, the stroke
/// revision they cover, and whether they differ from the base at all.
class _ResultTile {
  _ResultTile({
    required this.bytes,
    required this.revision,
    required this.changed,
  });

  final Uint8List bytes;
  final int revision;
  final bool changed;
}

/// Read access to the in-progress stroke's straight-alpha pixels — what
/// the live overlay snapshots its tile images from.
abstract interface class ActiveStrokePixelSource {
  /// The wall the stroke stops at — its cel's ([BitmapSurface.pasteboard]).
  PasteboardWall get pasteboard;

  /// Copies [count] straight-alpha RGBA pixels starting at canvas (x, y)
  /// into [target] at [targetOffset]. Unpainted pixels read as transparent
  /// zeros.
  void copyRow(int x, int y, int count, Uint8List target, int targetOffset);
}

/// Rasterizes the in-progress stroke incrementally into SPARSE
/// straight-alpha RGBA tiles allocated on demand.
///
/// Storage is tile-sparse so the cost of a stroke scales with the region
/// it actually paints, never with the canvas: the old canvas-sized buffer
/// made big logical surfaces (the timesheet ink planes at high resolution)
/// pay tens/hundreds of MB per stroke.
///
/// This runs the exact blend math of the commit rasterizer
/// (`materializeBrushDabSequenceOnBitmapSurface`) — same coverage sampling of
/// pixel centers against the true fractional dab center, same floating-point
/// grouping, same rounding — so the pixels painted while drawing are
/// byte-identical to the committed result. The live display and the commit
/// fast-path both consume these pixels, which is what unifies the on-screen
/// stroke with the committed artwork. Equivalence with the commit rasterizer
/// is locked by `active_stroke_overlay_parity_test.dart` (byte-exact).
class BrushLiveStrokeRasterizer implements ActiveStrokePixelSource {
  BrushLiveStrokeRasterizer({
    required this.pasteboard,
    this.tileSize = defaultTileSize,
  });

  /// Edge length of a sparse stroke tile in canvas pixels when the caller
  /// states none — the committed surface's own default.
  static const int defaultTileSize = defaultCelTileSize;

  /// Edge length of a sparse stroke tile in canvas pixels.
  ///
  /// PROMOTION round: the interactive view sets this to the CEL surface's
  /// tile size, so a stroke tile, its pre-blended result tile and the
  /// committed tile at the same coordinate are ONE grid — the display
  /// replaces per coordinate (no clips, no isolation layer) and pen-up
  /// ADOPTS the result buffers as the committed tiles outright. (The old
  /// fixed 128 bounded the per-move upload a little tighter, but forced
  /// quadrant bookkeeping everywhere the two grids met.)
  final int tileSize;

  @override
  final PasteboardWall pasteboard;

  /// Straight-alpha RGBA tile buffers keyed by `tileY * tilesPerRow +
  /// tileX`, allocated (zeroed) the first time a dab touches the tile — on
  /// a grid that is not the engine's, where the dab kernel runs here
  /// ([blendDabTilesDart]).
  ///
  /// ↩️R21, till 2026-11-12: with the C engine loaded these were its
  /// buffers and a call's dabs went through its kernel — a 1000px dab is
  /// ~1M pixels, and this loop was the reported big-brush stall on the UI
  /// thread. The app's grid is the engine's since ([_onEngine]).
  /// ⏳What still asks this route are tests, on grids of 1 to 256 — 66
  /// suites that day (card `the-cpu-brush-is-asked-by-tests-alone`).
  final Map<int, Uint8List> _tiles = <int, Uint8List>{};

  /// Each stroke tile's 16-bit plane, what its dabs pile up in
  /// ([BrushDabTileBuffers], ABI 40); [_tiles] holds its 8-bit view, which
  /// is all the display and the commit read.
  final Map<int, Uint16List> _wides = <int, Uint16List>{};

  /// Each stroke tile's SECOND plane, alpha * 65535 a pixel, where a second
  /// tip's stroke piles (ABI 60, `dualViewAlpha`) — made beside the other
  /// two for every tile of a stroke that has a second tip ([_secondTip]),
  /// and for no other.
  final Map<int, Uint16List> _seconds = <int, Uint16List>{};

  /// The stroke on the engine: any on its grid, a blur's rubbing its picture
  /// where another piles its dabs. Null till its first dab, and where this
  /// grid is not the engine's, which keeps to the route here.
  GpuStroke? _engineStroke;

  bool get _onEngine => tileSize == gpuTileSide;

  /// The dabs a [blendFrom] call lays, piled together when it ends.
  final List<GpuDab> _engineDabs = [];

  /// Under a blur ([_blur]), the call's dabs in their stead, rubbed
  /// together when it ends.
  final List<GpuRub> _engineRubs = [];

  /// The call's paper and second tip, which every dab of a stroke shares.
  BrushDabPlan? _engineDabsOf;

  /// Whether the stroke has a second tip — the first dab says so, as every
  /// dab of such a stroke carries its view ([BrushDab.dual]).
  bool _secondTip = false;

  /// Tile coordinate per linear key — the promotion pass walks the
  /// touched tiles and needs their coordinates back. Its keys ARE the
  /// touched set, a paint stroke's (a tile made) and a blur's ([_touch])
  /// alike.
  final Map<int, TileCoord> _tileCoords = <int, TileCoord>{};

  /// R28 selection: strokes land only inside this region. Set before the
  /// first dab and never changed mid-stroke — the selection layer is not
  /// even mounted while a painting tool is active.
  ///
  /// The mask reaches the KERNEL (it scales the accumulated stroke's
  /// alpha), so the pre-blended result equals the base wherever the
  /// selection excludes it — which is what lets the overlay keep
  /// replacing whole coordinates instead of falling back to a clip. On the
  /// engine's grid alone ([cutOnTheEngineOnly]): the engine's stroke lands
  /// under [SelectionClip.maskOnEngine].
  SelectionClip? selectionClip;

  /// 🚨★F-12 — the stroke's opacity CEILING, in the same channel and by the
  /// same route as the selection above, because it is the same kind of
  /// thing: **a mask with no shape.**
  ///
  /// Opacity could not ride the dabs. Dabs accumulated source-over, so a
  /// per-dab factor was not a ceiling — overlap it enough and any factor
  /// below 1 still converged on opaque, which is the report (「불투명도
  /// 낮춰도 dab 겹치면 100%까지 진해진다」). It has to scale the ACCUMULATED
  /// stroke, once, which is precisely what this mask already does.
  ///
  /// ⚠️Since F-205 a dab's own opacity IS a ceiling (`settledDabAlpha`: it
  /// settles there), and a constant one settles exactly where this mask
  /// puts the stroke — in exact arithmetic. The slider stays HERE all the
  /// same: one scale of the finished stroke rounds once, the dab route
  /// rounds at every dab, and moving it would shift every stroke under
  /// 100% by a level.
  ///
  /// Folding it in here rather than adding a scalar to the dab kernel is
  /// what kept the kernel's transcriptions parity-pinned for free: none
  /// learnt a new input. Like the region it is set before the first dab and
  /// never changes mid-stroke, which is what lets one mask serve the
  /// stroke's whole life.
  double strokeOpacity = 1;

  /// I-75: the cel a BLUR stroke rewrites ([BrushBlurPicture]) — set by
  /// [blurOver] before the first dab, as [selectionClip] is; null for a
  /// stroke that paints.
  ///
  /// A blur stroke keeps no stroke tiles: its result at a coordinate is the
  /// picture's, capped by the same mask a paint stroke's is, and everything
  /// downstream — the display's tiles, their revisions, the promotion at
  /// pen-up — is this rasterizer's as it is for paint.
  BrushBlurPicture? _blur;

  /// Makes this stroke a blur over [base], the cel as the stroke finds it.
  void blurOver(BitmapSurface base) {
    assert(
      base.tileSize == tileSize,
      'a blur rewrites the cel on the cel grid, which is the stroke grid',
    );
    _blur = BrushBlurPicture(base: base, wall: pasteboard);
  }

  /// The ceiling's mask ([_maskTile]).
  ///
  /// ONE tile for the whole stroke rather than one per coordinate: every
  /// tile's coverage is the same constant, so a per-tile copy would cost
  /// 64KB per touched tile to hold identical bytes. Read-only for the
  /// stroke's whole life, which is what makes sharing it safe.
  _MaskTile? _uniformMask;

  /// How many times a dab has touched each tile. A RESULT tile
  /// ([_results]) blended at revision R is current only while the stroke
  /// tile still reads R; anything else must re-blend before it can be
  /// displayed or promoted. (Conservative: a dab that writes no pixel
  /// still bumps, costing at most one redundant re-blend.)
  final Map<int, int> _tileRevisions = <int, int>{};

  /// Resident PRE-BLENDED result tiles (base ⊕ stroke, straight alpha) in
  /// insertion/refresh order — the exact bytes the commit holds at that
  /// coordinate, kept alive so pen-up can ADOPT them instead of blending
  /// the whole stroke a second time.
  ///
  /// Budget: the LEAST recently blended results go (the ones the brush has
  /// moved past). Their coordinates simply re-blend at pen-up — the stroke
  /// tiles and the base are both still here, so nothing is lost but the
  /// work. A result is one tile's bytes, whichever path blended it.
  late final Lru<int, _ResultTile> _results = Lru(
    limit: () => residentResultByteBudget,
    costOf: (_) => tileSize * tileSize * 4,
  );

  /// Resident-result byte budget (the round's one real cost: while a
  /// stroke runs, a touched coordinate holds its stroke tile AND its
  /// result tile). Past it the LEAST RECENTLY blended results drop —
  /// they are behind the brush, and pen-up re-blends exactly those. The
  /// frontier (what the user is watching) always stays resident.
  ///
  /// 96MB ≈ 384 tiles at 256px: a full-screen scribble keeps its whole
  /// visible neighbourhood, an 8K canvas-covering stroke degrades to
  /// "re-blend the part you left behind" instead of holding 512MB.
  ///
  /// The memory tab's allowance scales it ([CacheBudgets.liveStroke]) —
  /// a production knob now, no longer one for tests alone.
  static int residentResultByteBudget = defaultResidentResultByteBudget;

  /// [residentResultByteBudget] at the automatic allowance — the memory
  /// tab scales it ([CacheBudgets.liveStroke]).
  static const int defaultResidentResultByteBudget = 96 * 1024 * 1024;

  // The linear key grid spans the PASTEBOARD (strokes reach the wall, not
  // the canvas edge), offset so keys stay non-negative.
  late final TileRange _wallTiles = pasteboard.tileRange(tileSize);
  late final int _tileXMin = _wallTiles.firstX;
  late final int _tileYMin = _wallTiles.firstY;
  late final int _tilesPerRow = _wallTiles.lastX + 1 - _tileXMin;

  int _tileKey(int tileX, int tileY) =>
      (tileY - _tileYMin) * _tilesPerRow + (tileX - _tileXMin);

  DirtyRegion? _strokeBounds;
  int _blendedDabCount = 0;

  /// Union of every blended dab's dirty region, or `null` when nothing has
  /// been painted yet.
  DirtyRegion? get strokeBounds => _strokeBounds;

  /// Number of allocated stroke tiles (test/debug oracle for sparseness).
  int get allocatedTileCount =>
      _onEngine ? _tileCoords.length : _tiles.length;

  /// Drops the stroke's tiles so the rasterizer can host the next stroke
  /// (the engine's stroke goes back to be piled on again).
  void clear() {
    final stroke = _engineStroke;
    if (stroke != null) {
      EngineStrokes.giveBack(stroke);
      _engineStroke = null;
    }
    _engineDabs.clear();
    _engineRubs.clear();
    _engineDabsOf = null;
    _viewsAt = null;
    _tiles.clear();
    _wides.clear();
    _seconds.clear();
    _secondTip = false;
    _tileCoords.clear();
    _tileRevisions.clear();
    _uniformMask = null;
    _results.clear();
    _blur?.dispose();
    _blur = null;
    _strokeBounds = null;
    _blendedDabCount = 0;
  }

  /// Resident result tiles (test/debug oracle for the memory budget).
  @visibleForTesting
  int get residentResultTileCount => _results.length;

  /// Whether the result at the coordinate is resident (test oracle for the
  /// order the budget lets results go in).
  @visibleForTesting
  bool holdsResultAt(int tileX, int tileY) =>
      _results.containsKey(_tileKey(tileX, tileY));

  /// Pre-blends the stroke tile at ([tileX], [tileY]) against [base]
  /// through the COMMIT'S OWN KERNELS and returns it for display — while
  /// the STRAIGHT result stays resident, so pen-up promotes it into the
  /// surface instead of blending the whole stroke a second time.
  ///
  /// On the engine's grid the engine lays it ([_landedOnEngine]); on
  /// another the same math runs here, through
  /// [preBlendStrokeOverlayPixels], parity-pinned to the commit.
  ///
  /// Null when the tile is untouched (nothing to show there: the base
  /// tile the painter already draws IS the result).
  PreBlendedOverlayTile? preBlendedOverlayTile({
    required int tileX,
    required int tileY,
    required BitmapSurface base,
    required BrushBlendMode mode,
    required bool erase,
  }) {
    return preBlendedOverlayTiles(
      coords: [TileCoord(x: tileX, y: tileY)],
      base: base,
      mode: mode,
      erase: erase,
    )[0];
  }

  /// The pre-blend of every [coords] tile at once — the frame's shape: a
  /// pointer move touches a whole neighbourhood of tiles.
  ///
  /// Entries are null where the tile has nothing to show: untouched by
  /// the stroke, entirely outside the selection, or left equal to the base
  /// — every stroke pixel there masked away, or landed on nothing; showing
  /// it would draw the committed tile a second time. (Such a result stays
  /// resident: it is already current, and pen-up skips it for the same
  /// reason.)
  List<PreBlendedOverlayTile?> preBlendedOverlayTiles({
    required List<TileCoord> coords,
    required BitmapSurface base,
    required BrushBlendMode mode,
    required bool erase,
  }) {
    if (_engineStroke != null) {
      return _landedOnEngine(coords, base, mode, erase);
    }
    final results = List<PreBlendedOverlayTile?>.filled(coords.length, null);
    final mask = _maskTile();
    if (mask != null && mask.allOutside) {
      // A ceiling of nothing: every result would equal the base, so there
      // is nothing to show or promote.
      return results;
    }
    for (var slot = 0; slot < coords.length; slot += 1) {
      final coord = coords[slot];
      final key = _tileKey(coord.x, coord.y);
      if (!_tileCoords.containsKey(key)) {
        continue;
      }
      final result = _blendResultTile(
        key: key,
        tileX: coord.x,
        tileY: coord.y,
        base: base,
        mode: mode,
        erase: erase,
        mask: mask,
      );
      if (result.changed) {
        results[slot] = PreBlendedOverlayTile._resident(
          result.bytes,
          tileSize,
          result.revision,
        );
      }
    }
    return results;
  }

  /// The results at [coords] on the engine: a coordinate the stroke has not
  /// reached, or the selection takes none of, has none.
  List<PreBlendedOverlayTile?> _landedOnEngine(
    List<TileCoord> coords,
    BitmapSurface base,
    BrushBlendMode mode,
    bool erase,
  ) {
    final results = List<PreBlendedOverlayTile?>.filled(coords.length, null);
    final slots = [
      for (var slot = 0; slot < coords.length; slot += 1)
        if (_lands(coords[slot])) slot,
    ];
    final landed = _landOnEngine(
      [for (final slot in slots) coords[slot]],
      base,
      engineBlendModeOf(mode, erase: erase),
      compared: false,
    );
    for (var at = 0; at < slots.length; at += 1) {
      final coord = coords[slots[at]];
      results[slots[at]] = PreBlendedOverlayTile._landed(
        landed[at].tile,
        tileSize,
        _tileRevisions[_tileKey(coord.x, coord.y)] ?? 0,
      );
    }
    return results;
  }

  /// Whether [coord] is one the stroke reached and the selection may take.
  bool _lands(TileCoord coord) {
    if (!_tileCoords.containsKey(_tileKey(coord.x, coord.y))) {
      return false;
    }
    final clip = selectionClip;
    return clip == null || clip.mayCover(_regionOf(coord));
  }

  DirtyRegion _regionOf(TileCoord coord) => DirtyRegion(
    left: coord.x * tileSize,
    top: coord.y * tileSize,
    rightExclusive: (coord.x + 1) * tileSize,
    bottomExclusive: (coord.y + 1) * tileSize,
  );

  /// What the stroke makes of [coords] over [base]: its dabs laid at the
  /// slider's ceiling in the stroke's mode, under the selection.
  List<LandedTile> _landOnEngine(
    List<TileCoord> coords,
    BitmapSurface base,
    int mode, {
    required bool compared,
  }) {
    final stroke = _engineStroke!;
    if (coords.isEmpty) {
      return const [];
    }
    final mask = _selectionMask();
    return EngineTileLedger.instance.land(
      EngineTileLedger.landedCel,
      [
        for (final coord in coords)
          (column: coord.x, row: coord.y, under: base.tileAt(coord)),
      ],
      by: (pool, cel, asked) => _blur == null
          ? stroke.land(
              appGpuComposite,
              pool,
              cel,
              asked,
              // ★F-12 — the ceiling scales the ACCUMULATED stroke, once.
              opacity: (strokeOpacity * 65535).round(),
              mode: mode,
              mask: mask,
              compared: compared,
            )
          : stroke.landBlur(
              EngineStrokes.blurs,
              appGpuComposite,
              pool,
              cel,
              asked,
              opacity: (strokeOpacity * 65535).round(),
              mask: mask,
              compared: compared,
            ),
      compared: compared,
    );
  }

  /// The selection's mask over every pixel it can select, made on the
  /// engine once for the clip and kept with it
  /// ([SelectionClip.maskOnEngine]); null with no selection. ↩️Till
  /// 2026-11-13 the CPU made the bytes over the tiles of each landing
  /// (`SelectionClip.maskFor`) and handed them up — at every move of a
  /// stroke under a selection.
  GpuMask? _selectionMask() => selectionClip?.maskOnEngine();

  /// The tile of [mask] as the engine reads a bitmap: once per mask.
  static GpuDabTexture _textureOf(BrushTipMask mask) =>
      _textures[mask] ??= GpuDabTexture(mask.alphaNormalized, mask.size);
  static final Expando<GpuDabTexture> _textures = Expando('dab textures');

  /// [plan] as the engine piles it.
  GpuDab _gpuDabOf(BrushDabPlan plan) {
    final tip = plan.tip;
    final profile = tip.profile;
    final mask = tip.tipMask;
    return GpuDab(
      centreX: plan.centerX,
      centreY: plan.centerY,
      left: plan.left,
      top: plan.top,
      right: plan.rightExclusive,
      bottom: plan.bottomExclusive,
      colour:
          plan.sourceR |
          plan.sourceG << 8 |
          plan.sourceB << 16 |
          (plan.sourceAlphaNorm * 255).round() << 24,
      opacity: plan.dabOpacity,
      flow: plan.dabFlow,
      contrast: plan.aaContrast,
      threshold: plan.aaThreshold,
      edgeHeld: plan.edgeHeld,
      erase: plan.erase,
      second: plan.second,
      round: profile == null
          ? null
          : (
              coverage: profile.coverage,
              pile: profile.pile,
              scale: profile.scale,
              reach: tip.reach,
              inner: profile.inner,
              rowLength: profile.rowLength,
            ),
      tip: mask == null ? null : _textureOf(mask),
      radius: tip.radius,
      cos: tip.tipCos,
      sin: tip.tipSin,
      roundness: 1.0 / tip.inverseRoundness,
      evening: plan.evening,
      density: plan.textureMask == null ? null : plan.textureDensity,
    );
  }

  /// The call's dabs on the engine, together: before anything reads the
  /// tiles they touched.
  void _pileOnEngine() {
    if (_engineDabs.isEmpty && _engineRubs.isEmpty) {
      return;
    }
    final first = _engineDabsOf!;
    final mask = first.textureMask;
    final paper = mask == null ? null : _textureOf(mask);
    final stroke = _engineStroke ??= EngineStrokes.take();
    final blur = _blur;
    if (blur != null) {
      _rubOnEngine(stroke, blur.base, first, paper);
    } else {
      final dual = first.dual;
      stroke.pile(
        _engineDabs,
        paper: paper,
        paperScale: first.textureScale,
        paperHeight: first.textureMode == BrushTextureMode.height,
        secondMode: dual == null
            ? null
            : separableBlendModeNativeId(dual.compositeMode),
        secondDensity: dual?.density ?? 1,
      );
    }
    _engineDabs.clear();
    _engineRubs.clear();
    _engineDabsOf = null;
  }

  /// The call's blur dabs — [first] the first of them — rubbed into
  /// [stroke]'s picture, made of [base]'s tiles where they first read it.
  void _rubOnEngine(
    GpuStroke stroke,
    BitmapSurface base,
    BrushDabPlan first,
    GpuDabTexture? paper,
  ) {
    final ledger = EngineTileLedger.instance;
    ledger.held(
      (hold) => stroke.rub(
        EngineStrokes.blurs,
        appGpuComposite,
        ledger.pool,
        _engineRubs,
        under: (met) => hold.slotsOfThose(EngineTileLedger.landedCel, [
          for (final (:column, :row) in met)
            base.tileAt(TileCoord(x: column, y: row)),
        ]),
        paper: paper,
        paperScale: first.textureScale,
        paperHeight: first.textureMode == BrushTextureMode.height,
      ),
    );
  }

  /// The stroke's coverage on a tile off the engine's grid — its opacity
  /// ceiling — built once per stroke; null at full opacity, nothing to
  /// mask. The ceiling is fixed at pen-down, so one build lasts the stroke.
  ///
  /// ↩️It folded a selection's mask in, a tile at a time, till 2026-11-14:
  /// a selection cuts on the engine alone ([cutOnTheEngineOnly]).
  _MaskTile? _maskTile() {
    final coverage = strokeOpacityCoverage(strokeOpacity);
    if (coverage >= 255) {
      return null;
    }
    return _uniformMask ??= _MaskTile(
      bytes: strokeCoverageMask(
        pixelCount: tileSize * tileSize,
        opacity: strokeOpacity,
      )!,
      allOutside: coverage == 0,
    );
  }

  /// (Re)computes the resident RESULT tile for [key] — base bytes staged
  /// fresh, then the stroke blended in place. The blend is not
  /// incremental by design: its input is always (original base,
  /// accumulated stroke), which is what makes a promoted tile impossible
  /// to double-apply — re-running it over its own output is never a
  /// state the pipeline can reach.
  _ResultTile _blendResultTile({
    required int key,
    required int tileX,
    required int tileY,
    required BitmapSurface base,
    required BrushBlendMode mode,
    required bool erase,
    _MaskTile? mask,
  }) {
    final revision = _tileRevisions[key] ?? 0;
    final existing = _results.peek(key);
    if (existing != null && existing.revision == revision) {
      // Refreshed by use: the frontier keeps its results, the tail drops
      // first when the budget bites.
      _results.use(key);
      return existing;
    }
    final blur = _blur;
    if (blur != null) {
      final made = blur.resultTile(
        TileCoord(x: tileX, y: tileY),
        mask: mask?.bytes,
      );
      final result = _ResultTile(
        bytes: made?.bytes ?? Uint8List(0),
        revision: revision,
        changed: made?.changed ?? false,
      );
      _results.keep(key, result);
      return result;
    }
    final tileLeft = tileX * tileSize;
    final tileTop = tileY * tileSize;
    final byteLength = tileSize * tileSize * 4;
    // The straight result is a fresh buffer each time (the blend is
    // functional), so the resident entry simply swaps — which is exactly
    // what the region gather returns: the base's bytes for this tile
    // rect, with missing base tiles left as zeros. The base grid is the
    // surface's own tile size; a stroke tile can overlap up to four base
    // tiles when the two grids differ, and the walk handles that.
    final staged = bitmapSurfaceRegionPixels(
      base,
      DirtyRegion(
        left: tileLeft,
        top: tileTop,
        rightExclusive: tileLeft + tileSize,
        bottomExclusive: tileTop + tileSize,
      ),
    );
    final blended = preBlendStrokeOverlayPixels(
      dst: staged,
      src: _tiles[key]!,
      mode: mode,
      erase: erase,
      pixelCount: tileSize * tileSize,
      mask: mask?.bytes,
    );
    var changed = false;
    for (var offset = 0; offset < byteLength; offset += 1) {
      if (blended[offset] != staged[offset]) {
        changed = true;
        break;
      }
    }
    final result = _ResultTile(
      bytes: blended,
      revision: revision,
      changed: changed,
    );
    _results.keep(key, result);
    return result;
  }

  /// The finished tiles of this stroke, ready to be ADOPTED by the cel
  /// surface — the pen-up commit in one move.
  ///
  /// Every touched coordinate whose resident result is stale (dropped by
  /// the budget, or touched after its last blend) re-blends here; a
  /// coordinate whose result is byte-identical to the base is left out
  /// entirely, so the dirty set stays the TRUE change set and untouched
  /// tiles keep their identity (and their decoded image).
  ///
  /// The returned tiles are the surface's from here on; [clear] afterwards
  /// lets go of what the stroke still holds.
  List<PromotedStrokeTile> promoteStrokeTiles({
    required BitmapSurface base,
    required BrushBlendMode mode,
    required bool erase,
  }) {
    assert(
      base.tileSize == tileSize,
      'promotion requires the stroke grid to be the surface grid',
    );
    if (_engineStroke != null) {
      return _promotedFromEngine(base, mode, erase);
    }
    final promoted = <PromotedStrokeTile>[];
    final mask = _maskTile();
    if (mask != null && mask.allOutside) {
      // A ceiling of nothing: the stroke contributes nothing, so every
      // committed tile must stay as it is.
      return promoted;
    }
    for (final key in _tileCoords.keys.toList()) {
      final coord = _tileCoords[key]!;
      final result = _blendResultTile(
        key: key,
        tileX: coord.x,
        tileY: coord.y,
        base: base,
        mode: mode,
        erase: erase,
        mask: mask,
      );
      if (!result.changed) {
        continue;
      }
      promoted.add(
        PromotedStrokeTile(
          coord,
          BitmapTile(size: tileSize, pixels: result.bytes),
          result.revision,
        ),
      );
    }
    return promoted;
  }

  /// The finished tiles on the engine: the same call that showed the stroke
  /// (유저 09-17), comparing each result with the tile under it. A coordinate
  /// left with no ink is a blank tile, which the commit drops.
  List<PromotedStrokeTile> _promotedFromEngine(
    BitmapSurface base,
    BrushBlendMode mode,
    bool erase,
  ) {
    final coords = _tileCoords.values.where(_lands).toList();
    final landed = _landOnEngine(
      coords,
      base,
      engineBlendModeOf(mode, erase: erase),
      compared: true,
    );
    return [
      for (var at = 0; at < landed.length; at += 1)
        if (landed[at].change != GpuChange.same)
          PromotedStrokeTile(
            coords[at],
            landed[at].tile ?? BitmapTile.blank(size: tileSize),
            _tileRevisions[_tileKey(coords[at].x, coords[at].y)] ?? 0,
          ),
    ];
  }

  /// A blur dab rewrote [region]: every tile it reaches is touched, and its
  /// resident result stale — what [_tilePlanes] does for a paint dab.
  void _touch(DirtyRegion region) {
    final range = region.tileRange(tileSize: tileSize);
    for (var tileY = range.firstY; tileY <= range.lastY; tileY += 1) {
      for (var tileX = range.firstX; tileX <= range.lastX; tileX += 1) {
        final key = _tileKey(tileX, tileY);
        _tileRevisions[key] = (_tileRevisions[key] ?? 0) + 1;
        _tileCoords[key] ??= TileCoord(x: tileX, y: tileY);
      }
    }
  }

  BrushDabTileBuffers _tilePlanes(int tileX, int tileY) {
    final key = _tileKey(tileX, tileY);
    // A dab is about to write here: the coordinate's resident result (if
    // any) is now stale. Over-bumping is safe — the counter is only ever
    // compared for equality, and a redundant re-blend costs one tile.
    _tileRevisions[key] = (_tileRevisions[key] ?? 0) + 1;
    final bytes = _tiles.putIfAbsent(key, () {
      _tileCoords[key] = TileCoord(x: tileX, y: tileY);
      final values = tileSize * tileSize * 4;
      _wides[key] = Uint16List(values);
      return Uint8List(values);
    });
    if (_secondTip) {
      _seconds[key] ??= Uint16List(tileSize * tileSize);
    }
    return (bytes: bytes, wide: _wides[key]!, second: _seconds[key]);
  }

  @override
  void copyRow(int x, int y, int count, Uint8List target, int targetOffset) {
    _viewsFromEngine();
    var remaining = count;
    var sourceX = x;
    var writeOffset = targetOffset;
    final tileY = floorDiv(y, tileSize);
    final localRowOffset = (y - tileY * tileSize) * tileSize;
    while (remaining > 0) {
      final tileX = floorDiv(sourceX, tileSize);
      final tileLeft = tileX * tileSize;
      final spanCount = math.min(remaining, tileLeft + tileSize - sourceX);
      final buffer = _tiles[_tileKey(tileX, tileY)];
      if (buffer == null) {
        target.fillRange(writeOffset, writeOffset + spanCount * 4, 0);
      } else {
        final sourceOffset = (localRowOffset + (sourceX - tileLeft)) * 4;
        target.setRange(
          writeOffset,
          writeOffset + spanCount * 4,
          buffer,
          sourceOffset,
        );
      }
      remaining -= spanCount;
      sourceX += spanCount;
      writeOffset += spanCount * 4;
    }
  }

  /// How many dabs [_tiles] held when it was last read from the engine.
  int? _viewsAt;

  /// The engine's view of the stroke as [_tiles], for what still reads it
  /// on the CPU: a host whose overlay grid is not its surface's.
  void _viewsFromEngine() {
    final stroke = _engineStroke;
    if (stroke == null || _blur != null || _viewsAt == _blendedDabCount) {
      return;
    }
    _viewsAt = _blendedDabCount;
    final coords = _tileCoords.values.toList();
    final landed = EngineTileLedger.instance.land(
      EngineTileLedger.landedCel,
      [
        for (final coord in coords)
          (column: coord.x, row: coord.y, under: null),
      ],
      by: (pool, cel, asked) =>
          stroke.land(appGpuComposite, pool, cel, asked, mode: GpuBlend.normal),
    );
    for (var at = 0; at < coords.length; at += 1) {
      final tile = landed[at].tile!;
      _tiles[_tileKey(coords[at].x, coords[at].y)] = tile.pixels;
      EngineTileLedger.instance.retire(tile);
    }
  }

  /// Materializes the stroke's pixels within [strokeBounds] as one
  /// row-major straight-alpha buffer (stride = bounds width) — the pen-up
  /// commit fast path's input. Allocation scales with the STROKE, not the
  /// canvas.
  Uint8List? strokePixelsWithinBounds() {
    final bounds = _strokeBounds;
    if (bounds == null) {
      return null;
    }
    final boundsWidth = bounds.rightExclusive - bounds.left;
    final boundsHeight = bounds.bottomExclusive - bounds.top;
    final buffer = Uint8List(boundsWidth * boundsHeight * 4);
    for (var row = 0; row < boundsHeight; row += 1) {
      copyRow(
        bounds.left,
        bounds.top + row,
        boundsWidth,
        buffer,
        row * boundsWidth * 4,
      );
    }
    return buffer;
  }

  /// Blends `dabs[from..]` into the stroke tiles and returns the union of
  /// the newly touched region (clamped to the canvas), or `null` if nothing
  /// changed.
  DirtyRegion? blendFrom(List<BrushDab> dabs, {int? from}) {
    final start = from ?? _blendedDabCount;
    DirtyRegion? touched;

    try {
      for (var index = start; index < dabs.length; index += 1) {
        final region = _blendDab(dabs[index]);
        if (region != null) {
          touched = touched == null ? region : touched.union(region);
        }
      }
    } finally {
      // The call's dabs on the engine land here, together — and before
      // anything reads the tiles they touched.
      _pileOnEngine();
    }
    _blendedDabCount = math.max(_blendedDabCount, dabs.length);
    if (touched != null) {
      _strokeBounds = _strokeBounds == null
          ? touched
          : _strokeBounds!.union(touched);
    }
    return touched;
  }

  /// [dab], a blur's, rubbed with the rest of its call ([_pileOnEngine]).
  DirtyRegion? _rubbedOnEngine(BrushDab dab) {
    final plan = BrushBlurPicture.coverageOf(
      dab,
      wall: pasteboard,
      tileSize: tileSize,
    );
    if (plan == null) {
      return null;
    }
    _engineRubs.add((
      dab: _gpuDabOf(plan),
      radius: BrushBlurPicture.blurRadiusOf(dab),
    ));
    _engineDabsOf ??= plan;
    _touch(plan.clip);
    return plan.clip;
  }

  DirtyRegion? _blendDab(BrushDab dab) {
    // Stamp dabs never reach the LIVE rasterizer: they only enter through
    // programmatic commits (fill, lift, paste, the stroke-blend landing),
    // which call the materializer directly and route stamps to the
    // dedicated 1:1 blend. There is no live stamp path, so refuse rather
    // than fall through — the tip kernel would paint the dab's flat
    // COLOUR where the stamp's bitmap belongs, and the overlay would show
    // a solid blob until pen-up corrected it.
    if (dab.stamp != null) {
      assert(false, 'the live rasterizer has no stamp path');
      return null;
    }

    final selection = selectionClip;
    if (!_onEngine) {
      cutOnTheEngineOnly(selection);
    }
    // A dab the selection cannot reach is never accumulated: the mask
    // would zero every pixel of it, so the tiles it would touch hold
    // exactly what they hold without it. That is what keeps one stroke
    // over a sheet's windows (each hearing it, each confined to its own
    // slice) at the cost of one stroke rather than one per window.
    final reach = selection == null ? null : dirtyRegionForBrushDab(dab);
    if (selection != null && (reach == null || !selection.mayCover(reach))) {
      return null;
    }

    if (dab.blurs) {
      final blur = _blur;
      if (blur == null) {
        assert(false, 'a blur dab needs the cel it blurs ([blurOver])');
        return null;
      }
      if (_onEngine) {
        return _rubbedOnEngine(dab);
      }
      final rewritten = blur.blurDab(dab);
      if (rewritten != null) {
        _touch(rewritten);
      }
      return rewritten;
    }

    // ONE dab kernel (see brush_dab_kernel.dart) — the same hoists,
    // lattices and clip the commit resolves. erase is false always: the
    // live overlay never carries the erase flag, because erase strokes
    // composite at display time.
    final plan = BrushDabPlan.of(
      dab,
      wall: pasteboard,
      tileSize: tileSize,
      erase: false,
    );
    if (plan == null) {
      return null;
    }
    if (dab.dual != null) {
      _secondTip = true;
    }
    if (_onEngine) {
      _engineDabs.add(_gpuDabOf(plan));
      _engineDabsOf ??= plan;
      for (var tileY = plan.tileYStart; tileY <= plan.tileYEnd; tileY += 1) {
        for (var tileX = plan.tileXStart; tileX <= plan.tileXEnd; tileX += 1) {
          final key = _tileKey(tileX, tileY);
          _tileRevisions[key] = (_tileRevisions[key] ?? 0) + 1;
          _tileCoords[key] ??= TileCoord(x: tileX, y: tileY);
        }
      }
      return plan.clip;
    }

    // Not the engine's grid: the dab kernel here, the same one the commit
    // runs on such a grid. _tilePlanes creates the tile and bumps its
    // revision, which is exactly what the old inline loop did per (row,
    // tile).
    blendDabTilesDart(plan, tileSize: tileSize, bufferFor: _tilePlanes);

    return DirtyRegion(
      left: plan.left,
      top: plan.top,
      rightExclusive: plan.rightExclusive,
      bottomExclusive: plan.bottomExclusive,
    );
  }
}
