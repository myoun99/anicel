import 'dart:math' as math;
import 'dart:typed_data';

import 'package:gpu_engine/gpu_engine.dart';

import '../core/argb_channels.dart';
import '../core/floor_math.dart';
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
    show engineBlendModeOf, separableBlendModeNativeId;

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
  PreBlendedOverlayTile._landed(this.landed, this.size, this.revision);

  /// The tile the engine laid this result in.
  final BitmapTile landed;
  final int size;
  final int revision;

  @override
  int get width => size;

  @override
  int get height => size;

  @override
  T readStraight<T>(T Function(Uint8List straight) use) =>
      landed.readPixels((_, straight) => use(straight));

  @override
  T readPremultiplied<T>(T Function(Uint8List premultiplied) use) =>
      landed.readPixels((_, straight) => use(premultipliedRgbaCopy(straight)));
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

/// The in-progress stroke, piled on the engine ([GpuStroke]) a tile at a
/// time as it reaches them, and laid over the cel by the very call that
/// lands it at pen-up — what the user watched is what lands (유저 09-17
/// 「보이는 중이랑 결과랑 절대로 다르면 안 되」). A cel off the engine's
/// grid is refused ([drawnByTheEngineAlone]).
///
/// Its tiles are sparse so the cost of a stroke scales with the region it
/// actually paints, never with the canvas: the old canvas-sized buffer
/// made big logical surfaces (the timesheet ink planes at high resolution)
/// pay tens/hundreds of MB per stroke.
///
/// ↩️Till 2026-11-14 a grid off the engine's ran the commit's own Dart
/// kernels here, byte for byte the commit's (board
/// `the-off-engine-cpu-commit-lives-only-for-tests`): asked by tests alone.
class BrushLiveStrokeRasterizer implements ActiveStrokePixelSource {
  BrushLiveStrokeRasterizer({
    required this.pasteboard,
    this.tileSize = defaultTileSize,
  }) {
    drawnByTheEngineAlone(tileSize);
  }

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

  /// The stroke's straight-alpha RGBA tiles as the engine reads them back,
  /// keyed by `tileY * tilesPerRow + tileX` ([_viewsFromEngine]): for what
  /// reads the stroke on the CPU ([copyRow]).
  ///
  /// ↩️R21, till 2026-11-12: with the C engine loaded these were its
  /// buffers and a call's dabs went through its kernel — a 1000px dab is
  /// ~1M pixels, and this loop was the reported big-brush stall on the UI
  /// thread. Till 2026-11-14 a grid off the engine's piled them here, in
  /// the Dart kernel (`blendDabTilesDart`), with a 16-bit plane and a
  /// second tip's beside each.
  final Map<int, Uint8List> _tiles = <int, Uint8List>{};

  /// The stroke on the engine: a blur's rubbing its picture where another
  /// piles its dabs. Null till its first dab.
  GpuStroke? _engineStroke;

  /// The dabs a [blendFrom] call lays, piled together when it ends.
  final List<GpuDab> _engineDabs = [];

  /// Under a blur ([_blurBase]), the call's dabs in their stead, rubbed
  /// together when it ends.
  final List<GpuRub> _engineRubs = [];

  /// The call's paper and second tip, which every dab of a stroke shares.
  BrushDabPlan? _engineDabsOf;

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
  /// replacing whole coordinates instead of falling back to a clip: the
  /// engine's stroke lands under [SelectionClip.maskOnEngine].
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

  /// I-75: the cel a BLUR stroke rewrites — set by [blurOver] before the
  /// first dab, as [selectionClip] is; null for a stroke that paints. The
  /// engine rubs the stroke's picture, made of this cel's tiles where it
  /// first reads them ([_rubOnEngine]).
  ///
  /// A blur stroke keeps no stroke tiles: its result at a coordinate is the
  /// picture's, capped by the same mask a paint stroke's is, and everything
  /// downstream — the display's tiles, their revisions, the promotion at
  /// pen-up — is this rasterizer's as it is for paint.
  BitmapSurface? _blurBase;

  /// Makes this stroke a blur over [base], the cel as the stroke finds it.
  void blurOver(BitmapSurface base) {
    assert(
      base.tileSize == tileSize,
      'a blur rewrites the cel on the cel grid, which is the stroke grid',
    );
    _blurBase = base;
  }

  /// The cel a MIXING brush's steps read under their dabs — set by
  /// [mixOver] before the first dab, as [_blurBase] is; null for a brush
  /// that lays its own colour flat. The engine reads it where a step's
  /// points are ([_pileOnEngine]).
  BitmapSurface? _mixBase;

  /// The steps the call's dabs named that no pile has run, in their
  /// order ([BrushDab.mix]).
  final List<GpuMixStep> _mixSteps = [];

  /// How many of the stroke's steps have been handed to the engine.
  int _mixStepsTaken = 0;

  /// Makes this stroke a mixing brush's over [base], the cel as the
  /// stroke finds it: the ground its steps read.
  void mixOver(BitmapSurface base) {
    assert(
      base.tileSize == tileSize,
      'the ground is read on the cel grid, which is the stroke grid',
    );
    _mixBase = base;
  }

  /// [dabs] — this stroke's, as they were laid — each laying the colour
  /// the engine resolved for its mixing step as its own
  /// ([BrushDab.mixedAs]); a copy of them where none names one. Reads the
  /// steps' colours back: the caller waits for all the GPU was handed —
  /// as pen-up does already, for the landing it compares.
  List<BrushDab> mixedAsResolved(List<BrushDab> dabs) {
    final stroke = _engineStroke;
    if (stroke == null || _mixStepsTaken == 0) {
      return List.of(dabs);
    }
    final colours = stroke.mixed(_mixStepsTaken);
    return [
      for (final dab in dabs)
        switch (dab.mix) {
          null => dab,
          final mix => dab.mixedAs(colours[mix.step]),
        },
    ];
  }

  /// [mix]'s step, handed to the engine with the call's pile where none
  /// before it has been: a step's dabs — its own and a symmetry's
  /// copies — come in its order, and every one runs, whether its dabs
  /// lay anything or not: the reservoir is a chain.
  void _takeStep(BrushDabMix? mix) {
    if (mix == null || mix.step < _mixStepsTaken) {
      return;
    }
    assert(mix.step == _mixStepsTaken, 'a mixing step was skipped');
    _mixSteps.add(
      GpuMixStep(
        centreX: mix.center.x,
        centreY: mix.center.y,
        radius: mix.radius,
        colour:
            argbRed(mix.color) |
            argbGreen(mix.color) << 8 |
            argbBlue(mix.color) << 16 |
            argbAlpha(mix.color) << 24,
        refill: mix.refill,
        laid: mix.laid,
        density: mix.density,
        take: mix.take,
        share: mix.share,
        pick: mix.pick,
        dry: mix.dry,
      ),
    );
    _mixStepsTaken += 1;
  }

  /// How many times a dab has touched each tile: the revision a tile shown
  /// at a coordinate carries, which pen-up matches to hand the screen's
  /// picture to the committed tile. (Conservative: a dab that writes no
  /// pixel still bumps, and a picture of the tile not put ([_unput]).)
  ///
  /// ↩️Till 2026-11-14 it also told a resident Dart result (`_results`,
  /// under `residentResultByteBudget` — the memory allowance's
  /// `liveStroke` line) whether it had to blend again: off the engine's
  /// grid alone, where that route is gone.
  final Map<int, int> _tileRevisions = <int, int>{};

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
  int get allocatedTileCount => _tileCoords.length;

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
    _tileCoords.clear();
    _tileRevisions.clear();
    _blurBase = null;
    _mixBase = null;
    _mixSteps.clear();
    _mixStepsTaken = 0;
    _strokeBounds = null;
    _blendedDabCount = 0;
  }

  /// Pre-blends the stroke tile at ([tileX], [tileY]) against [base] and
  /// returns it for display: the engine lays it as pen-up lands it
  /// ([_landedOnEngine]).
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
  /// the stroke, or one the selection takes none of ([_lands]).
  List<PreBlendedOverlayTile?> preBlendedOverlayTiles({
    required List<TileCoord> coords,
    required BitmapSurface base,
    required BrushBlendMode mode,
    required bool erase,
  }) {
    if (_engineStroke == null) {
      return List.filled(coords.length, null);
    }
    return _landedOnEngine(coords, base, mode, erase);
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
      _asksOf([for (final slot in slots) coords[slot]], base),
      engineBlendModeOf(mode, erase: erase),
      compared: false,
    );
    for (var at = 0; at < slots.length; at += 1) {
      final coord = coords[slots[at]];
      // A tile the landing left empty is the stroke's nothing, shown as one.
      results[slots[at]] = PreBlendedOverlayTile._landed(
        landed[at].tile ?? BitmapTile.blank(size: tileSize),
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

  /// [coords] as a landing asks for them: each over [base]'s tile there.
  static List<TileAsk> _asksOf(List<TileCoord> coords, BitmapSurface base) => [
    for (final coord in coords)
      (column: coord.x, row: coord.y, under: base.tileAt(coord)),
  ];

  /// What the stroke makes of [asks], each over the tile it names: its
  /// dabs laid at the slider's ceiling in the stroke's mode, under the
  /// selection — [again] how, where the landing can be made once more.
  List<LandedTile> _landOnEngine(
    List<TileAsk> asks,
    int mode, {
    required bool compared,
    LandsAgain? again,
  }) {
    final stroke = _engineStroke!;
    if (asks.isEmpty) {
      return const [];
    }
    return EngineTileLedger.instance.land(
      EngineTileLedger.landedCel,
      asks,
      // A stroke on its way waits for no turn of the engine's: its frame
      // waits for nothing (`GpuStroke.landOnItsWay`, a blur's
      // `GpuStroke.landBlurOnItsWay`). The finished one compares, which
      // waits for the GPU.
      by: _blurBase == null
          ? _landsLaid(stroke, mode, compared: compared)
          : _landsBlurred(stroke, compared: compared),
      compared: compared,
      again: again,
    );
  }

  /// The stroke's ceiling, as the engine takes it: ★F-12 — it scales the
  /// ACCUMULATED stroke, once.
  int get _ceiling => (strokeOpacity * 65535).round();

  /// How [_landOnEngine] lands a stroke that lays its dabs.
  LandedBy _landsLaid(GpuStroke stroke, int mode, {required bool compared}) {
    final opacity = _ceiling;
    final mask = _selectionMask();
    return (pool, cel, asked) => compared
        ? stroke.land(
            appGpuComposite,
            pool,
            cel,
            asked,
            opacity: opacity,
            mode: mode,
            mask: mask,
            compared: true,
          )
        : stroke.landOnItsWay(
            appGpuComposite,
            pool,
            cel,
            asked,
            opacity: opacity,
            mode: mode,
            mask: mask,
            unput: () => _unput(asked),
          );
  }

  /// How [_landOnEngine] lands a blur.
  LandedBy _landsBlurred(GpuStroke stroke, {required bool compared}) {
    final opacity = _ceiling;
    final mask = _selectionMask();
    return (pool, cel, asked) => compared
        ? stroke.landBlur(
            EngineStrokes.blurs,
            appGpuComposite,
            pool,
            cel,
            asked,
            opacity: opacity,
            mask: mask,
            compared: true,
          )
        : stroke.landBlurOnItsWay(
            EngineStrokes.blurs,
            appGpuComposite,
            pool,
            cel,
            asked,
            opacity: opacity,
            mask: mask,
            unput: () => _unput(asked),
          );
  }

  /// What a landing on its way did not put ([GpuStroke.landOnItsWay]):
  /// each tile [asked] forgotten as shown — at a revision past the one its
  /// picture carries, which pen-up then hands to no committed tile — and
  /// landed again where a dab next moves it, as the letters' plate not put
  /// is made again (`EngineLetters._plateOf`). Why it was not is the
  /// engine's to tell, by the next done (`Pool::lands_unwaited`).
  void _unput(List<GpuTileAsk> asked) {
    for (final (:column, :row, under: _) in asked) {
      final key = _tileKey(column, row);
      // A stroke cleared since holds no revision to move past.
      final revision = _tileRevisions[key];
      if (revision != null) {
        _tileRevisions[key] = revision + 1;
      }
    }
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

  /// [plan] as the engine piles it — laying the colour of [mixStep] where
  /// it names one.
  GpuDab _gpuDabOf(BrushDabPlan plan, {int? mixStep}) {
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
      mixStep: mixStep,
    );
  }

  /// The call's dabs on the engine, together: before anything reads the
  /// tiles they touched.
  void _pileOnEngine() {
    if (_engineDabs.isEmpty && _engineRubs.isEmpty && _mixSteps.isEmpty) {
      return;
    }
    final first = _engineDabsOf;
    final mask = first?.textureMask;
    final paper = mask == null ? null : _textureOf(mask);
    final stroke = _engineStroke ??= EngineStrokes.take();
    final blurBase = _blurBase;
    if (blurBase != null) {
      _rubOnEngine(stroke, blurBase, first!, paper);
    } else {
      final mixBase = _mixBase;
      final ledger = EngineTileLedger.instance;
      ledger.held((hold) {
        final dual = first?.dual;
        stroke.pile(
          _engineDabs,
          paper: paper,
          paperScale: first?.textureScale ?? 1,
          paperHeight: first?.textureMode == BrushTextureMode.height,
          secondMode: dual == null
              ? null
              : separableBlendModeNativeId(dual.compositeMode),
          secondDensity: dual?.density ?? 1,
          mixing: mixBase == null
              ? null
              : (
                  composite: appGpuComposite,
                  pool: ledger.pool,
                  steps: _mixSteps,
                  first: _mixStepsTaken - _mixSteps.length,
                  under: (ground) => hold.slotsOfThose(
                    EngineTileLedger.landedCel,
                    [
                      for (final (:column, :row) in ground)
                        mixBase.tileAt(TileCoord(x: column, y: row)),
                    ],
                  ),
                ),
        );
      });
    }
    _engineDabs.clear();
    _engineRubs.clear();
    _mixSteps.clear();
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
        under: (read) => hold.slotsOfThose(EngineTileLedger.landedCel, [
          for (final (:column, :row) in read)
            base.tileAt(TileCoord(x: column, y: row)),
        ]),
        paper: paper,
        paperScale: first.textureScale,
        paperHeight: first.textureMode == BrushTextureMode.height,
      ),
    );
  }

  /// The finished tiles of this stroke, ready to be ADOPTED by the cel
  /// surface — the pen-up commit in one move.
  ///
  /// Every coordinate the stroke reached is laid again on the engine,
  /// compared with the tile under it ([_promotedFromEngine]); one left
  /// byte-identical to the base is left out entirely, so the dirty set
  /// stays the TRUE change set and untouched tiles keep their identity (and
  /// their decoded image).
  ///
  /// The returned tiles are the surface's from here on; [clear] afterwards
  /// lets go of what the stroke still holds.
  ///
  /// [dabs] are the stroke's, as they lay again ([mixedAsResolved]): what
  /// each tile is made of once more, should the engine's device go before
  /// the tile's bytes are kept anywhere else ([StrokeLandsAgain]).
  List<PromotedStrokeTile> promoteStrokeTiles({
    required BitmapSurface base,
    required BrushBlendMode mode,
    required bool erase,
    List<BrushDab>? dabs,
  }) {
    assert(
      base.tileSize == tileSize,
      'promotion requires the stroke grid to be the surface grid',
    );
    if (_engineStroke == null) {
      return [];
    }
    return _promotedFromEngine(base, mode, erase, dabs);
  }

  /// The finished tiles on the engine: the same call that showed the stroke
  /// (유저 09-17), comparing each result with the tile under it. A coordinate
  /// left with no ink is a blank tile, which the commit drops.
  List<PromotedStrokeTile> _promotedFromEngine(
    BitmapSurface base,
    BrushBlendMode mode,
    bool erase,
    List<BrushDab>? dabs,
  ) {
    final coords = _tileCoords.values.where(_lands).toList();
    final laid = engineBlendModeOf(mode, erase: erase);
    final landed = _landOnEngine(
      _asksOf(coords, base),
      laid,
      compared: true,
      // ⏳A blur's reads the cel all round each tile it lands
      // ([_rubOnEngine]): not made of the tile under it alone, and not
      // made again yet.
      again: dabs == null || _blurBase != null
          ? null
          : StrokeLandsAgain._(this, dabs, laid),
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

  /// A blur dab rewrote [region]: every tile it reaches is touched, at a
  /// revision past what it showed — what a paint dab's tiles get
  /// ([_blendDab]).
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
    if (stroke == null || _blurBase != null || _viewsAt == _blendedDabCount) {
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
    // which call the materializer directly, and it lays each stamp by
    // itself. There is no live stamp path, so refuse rather than fall
    // through — the tip would paint the dab's flat COLOUR where the
    // stamp's bitmap belongs, and the overlay would show a solid blob until
    // pen-up corrected it.
    if (dab.stamp != null) {
      assert(false, 'the live rasterizer has no stamp path');
      return null;
    }

    // Before anything leaves it out: its step runs all the same.
    _takeStep(dab.mix);

    // A dab the selection cannot reach is never accumulated: the mask
    // would zero every pixel of it, so the tiles it would touch hold
    // exactly what they hold without it. That is what keeps one stroke
    // over a sheet's windows (each hearing it, each confined to its own
    // slice) at the cost of one stroke rather than one per window.
    final selection = selectionClip;
    final reach = selection == null ? null : dirtyRegionForBrushDab(dab);
    if (selection != null && (reach == null || !selection.mayCover(reach))) {
      return null;
    }

    if (dab.blurs) {
      if (_blurBase == null) {
        assert(false, 'a blur dab needs the cel it blurs ([blurOver])');
        return null;
      }
      return _rubbedOnEngine(dab);
    }

    // ONE dab plan (see brush_dab_kernel.dart) — the same hoists, lattices
    // and clip the commit resolves. erase is false always: the live overlay
    // never carries the erase flag, because erase strokes composite at
    // display time.
    final plan = BrushDabPlan.of(
      dab,
      wall: pasteboard,
      tileSize: tileSize,
      erase: false,
    );
    if (plan == null) {
      return null;
    }
    _engineDabs.add(_gpuDabOf(plan, mixStep: dab.mix?.step));
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
}

/// A stroke's landing as it is made again ([LandsAgain]): its dabs piled
/// on a stroke of the engine the app stands on now, as the pen piled them,
/// and laid once over the tiles asked — by the rasterizer that showed the
/// stroke and landed it, as a stroke with nothing but its dabs is laid
/// (`strokeLandedOn`).
///
/// 🗣️유저 2026-11-19 (cel-originals-are-held-twice-in-ram-and-on-the-gpu-Q2):
/// 「픽셀 대신 「한 일의 기록」을 들고, 잃으면 다시 그린다」. What it holds is
/// what the stroke was made of and nothing of an engine's: its dabs — a
/// mixing brush's with the colours its steps resolved
/// ([BrushLiveStrokeRasterizer.mixedAsResolved]) —, its ceiling, its mode,
/// the selection that cut it, and the wall it stopped at.
///
/// 🔬What it weighs beside the tiles it stands for (2026-11-19, the app
/// with no window, the default pen): a line of 1,424 px is 1,428 dabs over
/// 12 tiles — 251 KB as the engine is handed them, 786 KB as the tiles'
/// bytes; forty lines hatched in one place are 5,419 dabs over 4 tiles —
/// 954 KB and 262 KB. ⏳So it is kept only as long as the tile it landed on
/// is (`EngineTileLedger`), and what keeps it longer weighs it first.
final class StrokeLandsAgain implements LandsAgain {
  StrokeLandsAgain._(
    BrushLiveStrokeRasterizer stroke,
    List<BrushDab> dabs,
    this._mode,
  ) : _pasteboard = stroke.pasteboard,
      _tileSize = stroke.tileSize,
      _selection = stroke.selectionClip,
      _opacity = stroke.strokeOpacity,
      _dabs = dabs;

  final PasteboardWall _pasteboard;
  final int _tileSize;
  final SelectionClip? _selection;
  final double _opacity;
  final List<BrushDab> _dabs;

  /// The engine's mode the stroke was laid in (`engineBlendModeOf`).
  final int _mode;

  @override
  List<LandedTile> again(List<TileAsk> asks) {
    final stroke =
        BrushLiveStrokeRasterizer(pasteboard: _pasteboard, tileSize: _tileSize)
          ..selectionClip = _selection
          ..strokeOpacity = _opacity;
    try {
      stroke.blendFrom(_dabs, from: 0);
      // Dabs that pile nothing lay nothing: each tile as it was.
      if (stroke._engineStroke == null) {
        return [for (final _ in asks) (change: GpuChange.same, tile: null)];
      }
      return stroke._landOnEngine(asks, _mode, compared: true);
    } finally {
      stroke.clear();
    }
  }
}
