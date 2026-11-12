import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:gpu_engine/gpu_engine.dart';

import '../core/color_matrix.dart';
import '../core/draw_space.dart';
import '../core/on_a_worker.dart';
import '../models/bitmap_surface.dart';
import '../models/bitmap_tile.dart';
import '../models/composite_tree.dart';
import '../models/dirty_region.dart';
import '../models/layer_blend_mode.dart';
import '../models/layer_effect.dart';
import '../models/layer_id.dart';
import '../models/pasteboard_bounds.dart' show PasteboardWall;
import '../models/tile_coord.dart';
import '../services/brush_stroke_blend.dart'
    show nonSeparableBlendModeNativeId, separableBlendModeNativeId;
import '../services/cel_source_effect_pass.dart'
    show CelColorKey, keyRgbaTablesOf;
import '../services/composite_effect_paint.dart'
    show
        CompositeEffectStep,
        EffectStepLead,
        GaussianBlur,
        KeyRun,
        PaintedColour,
        PaintedEffect,
        PaperEdgeEffect,
        PluginEffect,
        ShadedEffect,
        effectBufferBounds,
        effectReadsRow,
        onionTintColorMatrix,
        paintedEffectsOf,
        paperEdgeBlurOf,
        paperOnWholePixels,
        resolveColorOnlyMatrix,
        resolveCompositeEffectPlan,
        rowExtentWithItsReach,
        shadedPassesOf;
import '../services/guide_geometry.dart' show GuideTransform;
import '../services/layer_pose_matrix.dart'
    show LayerPlacement, canvasToArtwork, placedRectBounds;
import '../services/shaded_passes.dart'
    show IrisGatherPass, IrisMap, IrisMapChannel, LineBoxPass, irisTurnsOf;
import '../ui/canvas/landing_preview.dart';
import '../ui/canvas/subtree_image_composite.dart' show subtreeBufferBounds;
import '../ui/canvas/tile_origin.dart'
    show surfaceContentWorldRect, tileCoordsWorldRect;
import 'engine_letters.dart';
import 'engine_row_pose.dart';
import 'engine_tile_ledger.dart';
import 'plan_plugins.dart';

/// What a row of a composite tree lays on the engine. Each route folds its
/// own rows into these ([mapCompositeLeaves]) and [planCompositeTree] lays
/// the tree: the one translator the screen, a frame's picture, the panels
/// and the export go through (screen-on-the-engine c5, 관제 2026-11-07
/// 17:0x — 「계획 번역기 하나」).
///
/// What a route reads is the tree it folds — every row for the screen, the
/// rows a source names for the eyedropper and the fill — and the paper is
/// a row of that tree, its bottom one ([onUnderlay]), where the route lays
/// one (캔버스 베이스 ❓c, 11-07 22:30).
sealed class EngineRow {
  const EngineRow();
}

/// A row of [surface]'s tiles, kept in the engine's pool as [lineage]'s
/// ([TileHold.slotsOf]): laid where [placement] carries them, at [opacity]
/// in [blendMode], through [effects] and then [tint] — the onion skin's.
final class EngineTiles extends EngineRow {
  const EngineTiles({
    required this.lineage,
    required this.surface,
    this.placement,
    this.opacity = 1,
    this.blendMode = LayerBlendMode.normal,
    this.effects = const [],
    this.tint,
    this.held = const [],
    this.mark,
  });

  /// What the row's tiles are kept under, one cel a lineage — the row and
  /// the frame it shows: the pages a cel's tiles share outlive its edits.
  final Object lineage;

  final BitmapSurface surface;
  final LayerPlacement? placement;
  final double opacity;
  final LayerBlendMode blendMode;
  final List<ResolvedLayerEffect> effects;
  final int? tint;

  /// What a hand holds over the row, bottom to top: laid over its tiles in
  /// its own space before its chain and its pose, as they are once they
  /// land — a float at its layer's depth, through its filters (TS1 ·
  /// F-240).
  final List<EngineHeld> held;

  /// The range a fill held down will cover, marked over the row — after
  /// it, outside its opacity and its chain, under its pose — none where no
  /// fill is held on it (`FillRangeMark`, I-160).
  final EngineMark? mark;
}

/// A fill range's mark ([EngineTiles.mark]): its checker laid under [mask]
/// — the range's cover, in its row's pixels — inside [bounds] there, its
/// cells pushed [shift] of them.
final class EngineMark {
  const EngineMark({
    required this.mask,
    required this.bounds,
    this.shift = ui.Offset.zero,
  });

  final GpuMask mask;
  final ui.Rect bounds;
  final ui.Offset shift;
}

/// Pixels a hand holds over a row ([EngineTiles.held]) — a float, a text
/// in hand, a landing shown before it lands — as [tiles] kept as
/// [lineage]'s, read where [toHeld] takes a pixel of the row to one of
/// theirs (none where the two are one), laid as [laying] says, its region
/// in the row's pixels.
final class EngineHeld {
  const EngineHeld({
    required this.lineage,
    required this.tiles,
    this.toHeld,
    this.laying = const LaidOver(),
  });

  final Object lineage;
  final Map<TileCoord, BitmapTile> tiles;
  final GuideTransform? toHeld;
  final HeldLaying laying;
}

/// [argb] laid over [rect] in normal: the paper under a cut's rows, a
/// camera's ground.
final class EngineSolid extends EngineRow {
  const EngineSolid({required this.argb, required this.rect});

  final int argb;
  final DirtyRegion rect;
}

/// Lays [nodes] on [plan] bottom to top, over the canvas [paper] lies on —
/// their rows' tiles held by [hold] ([EngineTileLedger.held]), inside which
/// the plan runs; a cel number's letters set by [letters].
///
/// Each node takes the steps that are its picture: a row a `Row` and a
/// solid a `Solid`; a folder, an adjustment and a clip a buffer of their
/// own, opened and closed onto the one under them. A blend over a backdrop
/// lays the backdrop where it stands and the row over it in its blend — a
/// row reads what it is laid on, so the backdrop needs no picture of its
/// own ([CompositeBackdropBlend]).
///
/// 🗣️a-blurred-folder-cut-by-the-view-moves-on-vulkan (유저 2026-10-22
/// 「골은 b」): the backdrop is read where the frame is drawn, the way the
/// GPU's own blend reads its target. 🔬On the Windows app (10-22, r12) a
/// stroke under a multiply row came to the screen 21.3ms after its input,
/// against 30.0 with the backdrop rasterised and 22.5 with the GPU's own
/// multiply; the whole canvas composed both ways was the same bytes. An
/// off-screen raster cost about 6.5ms of the raster thread whatever its
/// size (r10), which is what the backdrop's route paid three times a step.
/// (Moved here from the walk's `_composeInTheFrame` when the exports went
/// on the engine — 7′.)
///
/// Under [holding], a node's chain is held by the number it gives the node
/// ([ChainHolding]).
// ⏳Tests alone lay a tree till the screen does (screen-on-the-engine c6).
void planCompositeTree(
  GpuPlan plan,
  List<CompositeNode<EngineRow>> nodes, {
  required TileHold hold,
  required ui.Rect paper,
  required EngineLetters letters,
  ChainHolding? holding,
  PlanPlugins? plugins,
}) => _TreePlan(
  _TileLaying(plan, hold, paper),
  letters,
  holding,
  plugins,
)._lay(nodes);

/// Where the chains a plan runs are held past it ([GpuHeldChains]): the
/// hold, and the number [idOf] gives the chain of a node — null for one
/// that runs each time.
///
/// ⛔NO SPACE IN THE NUMBER: a chain puts its node's own pixels wherever
/// the node is laid, and the one op that reads the space it runs in — a
/// lens drawing its map there — is refused in a map (the engine's 「a
/// chain reads a map whose rows read a map」), as a buffer's chain is in a
/// posed row's ([_TreePlan._bufferOf]). So a row a posed lens reads as its
/// map lays what its chain put on the canvas, and runs it once. 🔜Where a
/// map's rows may read maps, the space a chain runs in joins the number.
typedef ChainHolding = ({
  GpuHeldChains held,
  int? Function(CompositeNode<EngineRow> node) idOf,
});

/// [picture] as a chain had come to it, read back ([GpuChainRead]) on a
/// worker ([onAWorker]): the wait for the plan that ran through it is that
/// worker's, so the isolate that asks goes on meanwhile.
///
/// 🧭관제 2026-11-12 08:5x (float-warp-resamples-in-the-c-engine), with the
/// plugin's run (`GpuFxPlugin.render`): 🔬Surface Pro 11, profile, S5_BA
/// cut 352, a box dragged over a row under a device plugin — this read
/// 56–60 ms p50 on the UI thread each time the box moved.
///
/// ⚠️Freed only once its read has ended: a recording's stages are let go
/// of after their runs (`FxPluginStages._recordedOnce`).
final class _ChainPicture implements PluginStepInput {
  _ChainPicture(this._read, this._picture);

  final GpuChainRead _read;
  final (int, int, int, int) _picture;

  @override
  Future<Uint8List?> straight() => _readOnAWorker(_read.reader, _picture);

  @override
  void free() => _read.free();
}

/// [reader]'s pixels of [picture] on a worker ([onAWorker]). Made here, of
/// plain values, so the job crosses with them alone.
Future<Uint8List?> _readOnAWorker(
  GpuChainReader reader,
  (int, int, int, int) picture,
) => onAWorker(() => reader.pixels(picture));

class _TreePlan {
  _TreePlan(this._tiles, this.letters, this.holding, this.plugins);

  final _TileLaying _tiles;
  final EngineLetters letters;
  final ChainHolding? holding;

  /// What the plug-ins' steps are run through — none where no route waits
  /// for them, each drawn as if off.
  final PlanPlugins? plugins;

  /// Whether the chain last asked for ([_chainOf]) has a plug-in's step
  /// drawn as if off: no picture to hold ([_hold]).
  bool _chainHasAStepOff = false;

  GpuPlan get plan => _tiles.plan;
  ui.Rect get paper => _tiles.paper;

  /// Where the steps being laid lie: the canvas, or — while a blur map a
  /// posed row's chain reads is drawn — that row's own space, canvas to it
  /// ([_mapDrawn]).
  LayerPlacement? _space;

  void _lay(List<CompositeNode<EngineRow>> nodes) {
    for (final node in nodes) {
      _node(node);
    }
  }

  /// [node]'s steps, its picture laid in [mode] where one is named — the
  /// blend a [CompositeBackdropBlend] lays its source in, which paints
  /// normal itself — else in its own; its chain reading the rows [reads]
  /// draw ([CompositeReadsRows]), none of its children's, and held as what
  /// [heldAs] shows — itself where null — is ([ChainHolding]): the rows it
  /// reads are of the node it is read by.
  void _node(
    CompositeNode<EngineRow> node, {
    int? mode,
    _Reads reads = const {},
    CompositeNode<EngineRow>? heldAs,
  }) {
    final shows = heldAs ?? node;
    switch (node) {
      case CompositeLeaf(payload: final EngineTiles row):
        _row(row, mode ?? _blendOf(row.blendMode), reads, shows);
      case CompositeLeaf(payload: EngineSolid(:final argb, :final rect)):
        plan.solid(
          gpuColourOf(argb),
          rect.left,
          rect.top,
          rect.rightExclusive,
          rect.bottomExclusive,
        );
      case final CompositeGroup<EngineRow> group:
        _group(group, mode ?? _blendOf(group.blendMode), reads, shows);
      case final CompositeAdjustment<EngineRow> adjustment:
        _adjustment(adjustment, reads, shows);
      case CompositeBackdropBlend(
        :final backdrop,
        :final source,
        :final blendMode,
      ):
        _lay(backdrop);
        _node(source, mode: _blendOf(blendMode));
      case final CompositeClip<EngineRow> clip:
        _clip(clip, mode ?? _blendOf(clip.blendMode));
      case CompositeOpaque():
        throw StateError(
          'a base made opaque lies at the bottom of its clip\'s scope, where '
          'the scope is opened on it — not $node',
        );
      // A row's letters lie where the row does (I-65), a plate on its paper
      // laid as the row's picture is — the engine's own raster of them
      // ([EngineLetters]), as the walk lays the app's (`celNumberPlate`).
      case CompositeCelNumber(
        on: CompositeLeaf(payload: final EngineTiles row),
        letters: final number,
      ):
        final plate = letters.celNumberPlate(number, row.surface);
        _row(
          EngineTiles(
            lineage: plate,
            surface: plate,
            placement: row.placement,
          ),
          GpuBlend.normal,
          const {},
          null,
        );
      case CompositeCelNumber():
        throw StateError('a cel number on a row of no tiles: $node');
      case CompositeReadsRows(node: final reader, :final rows):
        _node(reader, mode: mode, reads: rows, heldAs: shows);
    }
  }

  /// [group]'s buffer, closed at its strength in [mode] through its chain
  /// and its colour, held as what [shows] is.
  void _group(
    CompositeGroup<EngineRow> group,
    int mode,
    _Reads reads,
    CompositeNode<EngineRow> shows,
  ) {
    plan.open();
    _lay(group.children);
    final (:chain, keys: _, :colour) = _chainOf(
      group.effects,
      over: (outset) => _bufferOf(group, outset),
      space: _space,
      reads: reads,
    );
    _hold(chain, shows);
    plan.close(
      opacity: strengthOf(group.opacity),
      mode: mode,
      chain: chain,
      matrix: _matrixOf(colour),
    );
  }

  /// [adjustment]'s scope, closed through its grade at its mix, held as
  /// what [shows] is.
  void _adjustment(
    CompositeAdjustment<EngineRow> adjustment,
    _Reads reads,
    CompositeNode<EngineRow> shows,
  ) {
    final CompositeAdjustment(:children, :effects, :mix) = adjustment;
    plan.open();
    _lay(children);
    // A mix is no fade: a colour's is folded into its matrix, a grade of
    // that strength, and a chain's lays the scope under what the chain
    // puts, graded (resolveAdjustmentScopePass).
    if (resolveColorOnlyMatrix(effects) case final colour? when mix < 1) {
      plan.close(
        mode: GpuBlend.normal,
        matrix: _matrixOf(lerpColorMatrixFromIdentity(colour, mix)),
      );
      return;
    }
    final (:chain, keys: _, :colour) = _chainOf(
      effects,
      over: (outset) => _bufferOf(adjustment, outset),
      space: _space,
      reads: reads,
    );
    _hold(chain, shows);
    plan.close(
      mode: GpuBlend.normal,
      chain: chain,
      mix: strengthOf(mix),
      matrix: _matrixOf(colour),
    );
  }

  /// [clip]'s base and its scope opened on it, closed atop it, the two
  /// closed at the base's strength in [mode].
  void _clip(CompositeClip<EngineRow> clip, int mode) {
    plan.open();
    _node(clip.base);
    final (:opaque, :rows) = _onTheBase(clip.scope);
    plan.open(opaque: opaque);
    _lay(rows);
    plan.closeAtop();
    plan.close(opacity: strengthOf(clip.opacity), mode: mode);
  }

  /// [row] laid in [mode] — none where its pose collapses it: its tiles,
  /// and what a hand holds over them ([EngineTiles.held]) laid there first,
  /// in its own space, as one picture — what they are once they land —,
  /// then the range a fill holds on it ([EngineTiles.mark]). Its chain is
  /// held as what [shows] is, where it names one.
  void _row(
    EngineTiles row,
    int mode,
    _Reads reads,
    CompositeNode<EngineRow>? shows,
  ) {
    final pose = _poseOf(row);
    if (pose == null) {
      return;
    }
    if (row.surface.tiles.isNotEmpty || row.held.isNotEmpty) {
      _hold(_picture(row, mode, reads, pose), shows);
    }
    if (row.mark case final mark?) {
      _mark(mark, pose.posed);
    }
  }

  /// How [row] is laid ([_RowPose]) — none where its pose has no inverse.
  _RowPose? _poseOf(EngineTiles row) {
    final placement = _inSpace(row.placement);
    final inverse = switch (placement) {
      null => const GuideTransform.identity(),
      final placement => canvasToArtwork(placement),
    };
    if (inverse == null) {
      return null;
    }
    return (
      posed: gpuRowInverse(inverse),
      space: placement == null ? null : inverse,
    );
  }

  /// [mark] over the row just laid, posed by [posed] as the row is, under
  /// its mask — the plan's one ([GpuPlan.mask]): a range is held on the
  /// pen's row alone, the one row a hand's overlay is drawn over.
  void _mark(EngineMark mark, List<double> posed) {
    plan
      ..mask(mark.mask)
      ..mark(
        inverse: posed,
        sampling: _tiles.sampling,
        columns: _tiles.columns,
        rows: _tiles.rows,
        shift: (mark.shift.dx, mark.shift.dy),
      );
  }

  /// [row]'s picture — its tiles and what a hand holds over them — laid as
  /// the row is, by [pose], through its chain on what it stands for, in
  /// [mode]: that chain, if any.
  int? _picture(EngineTiles row, int mode, _Reads reads, _RowPose pose) {
    final tiles = row.surface.tiles;
    final picture = _rowExtentOf(row, paper);
    // Its chain runs on its own picture, the whole of what it stands for —
    // as far as the chain paints past what it holds — and is cut there,
    // before its pose (steppedForChain); the rows it reads drawn there
    // too, under its pose undone (rowsUnderPlacement).
    final (:chain, :keys, :colour) = _chainOf(
      row.effects,
      over: (_) => picture,
      space: pose.space,
      reads: reads,
      keysOnTheRow: row.held.isEmpty,
      // The range a fill holds is laid after the row, never into its
      // picture ([_row]): only what a hand holds goes in with the cel.
      source: row.held.isEmpty ? row.surface : null,
    );
    final tint = row.tint;
    // The tint LAST, over the finished pixel: the ghost is the row as the
    // screen shows it, in the peg's colour (resolveCompositeEffectPaint).
    final matrix = _matrixOf(switch ((colour, tint)) {
      (_, null) => colour,
      (null, final tint?) => onionTintColorMatrix(tint),
      (final colour?, final tint?) => composeColorMatrices(
        onionTintColorMatrix(tint),
        colour,
      ),
    });
    final opacity = strengthOf(row.opacity);
    if (row.held.isEmpty) {
      plan.row(
        set: _tiles.setOf(row.lineage, tiles),
        keys: keys,
        chain: chain,
        inverse: pose.posed,
        sampling: _tiles.sampling,
        columns: _tiles.columns,
        rows: _tiles.rows,
        mode: mode,
        matrix: matrix,
        opacity: opacity,
      );
      return chain;
    }
    plan.open();
    if (tiles.isNotEmpty) {
      _tiles.lay(_tiles.setOf(row.lineage, tiles), null, GpuBlend.normal);
    }
    for (final held in row.held) {
      _tiles.layHeld(held, row.surface.pasteboard);
    }
    plan.closeRow(
      chain: chain,
      tiles: chain == null ? _tilesOf(_pixelsOf(picture)) : null,
      inverse: pose.posed,
      sampling: _tiles.sampling,
      columns: _tiles.columns,
      rows: _tiles.rows,
      mode: mode,
      matrix: matrix,
      opacity: opacity,
    );
    return chain;
  }

  /// [matrix] added to the plan, or none.
  int? _matrixOf(List<double>? matrix) =>
      matrix == null || colorMatrixIsIdentity(matrix)
      ? null
      : plan.matrix(matrix);

  /// What [effects] lay where a draw takes them, its picture standing for
  /// the rect [over] answers for how far they reach past it, in [space]:
  /// the chain their steps run on that picture, reading the rows [reads]
  /// draw, then the Gaussians the draw carries — none where nothing past
  /// colour changes a pixel — and the colour the draw lays it through
  /// after them.
  ///
  /// A step rasters on the picture, so what it blurs is the picture and is
  /// cut there. The draw's filter paints past the image it is drawn from:
  /// each of its Gaussians reads what the one before put and puts as far
  /// past it as it reaches — a row's picture, its own, is no larger for
  /// them (its [over]).
  ///
  /// A chain that is one run of keys, [keysOnTheRow], is the row's own
  /// keys instead — keyed on its stored bytes as the chain's op keys them,
  /// with no chain's picture between (kernels/chain): a row's leading keys,
  /// its whole chain or before its colour (`celSourceKeys`).
  ///
  /// [source] is what the picture is made of where nothing else goes into
  /// it — a row's surface, nothing held over it — and so what its first
  /// plug-in's step reads is made of ([PluginStepSource]).
  ({int? chain, int? keys, List<double>? colour}) _chainOf(
    List<ResolvedLayerEffect> effects, {
    required ui.Rect Function(double outset) over,
    required LayerPlacement? space,
    required _Reads reads,
    bool keysOnTheRow = false,
    Object? source,
  }) {
    _chainHasAStepOff = false;
    final steps = resolveCompositeEffectPlan(effects, paper: paper);
    final carried = paintedEffectsOf(steps.finalEffects);
    final last = carried.lastIndexWhere((painted) => painted is GaussianBlur);
    final colour = switch (carried.sublist(last + 1)) {
      [PaintedColour(:final matrix)] => matrix,
      _ => null,
    };
    if (steps.preSteps.isEmpty && last < 0) {
      return (chain: null, keys: null, colour: colour);
    }
    if (steps.preSteps case [
      CompositeEffectStep(lead: KeyRun(:final keys), then: []),
    ] when keysOnTheRow && last < 0) {
      return (chain: null, keys: _keysOf(keys), colour: colour);
    }
    final picture = _pixelsOf(over(steps.outsetPixels));
    // What the next plug-in's step reads is made of, while the plan can
    // say: the source, then what the plug-in before it made, and the
    // effects of the chain since — none once a step reads another row.
    var from = source;
    var since = 0;
    final ops = <void Function(int chain)>[];
    for (final step in steps.preSteps) {
      switch (step.lead) {
        case PluginEffect(:final effect):
          // The step's effect is the chain's own, met in its order.
          final at = effects.indexWhere(
            (each) => identical(each, effect),
            since,
          );
          final made = _pluginStep(
            effect,
            picture,
            from: from == null
                ? null
                : (source: from, before: effects.sublist(since, at)),
          );
          ops.addAll(made.ops);
          from = made.straight;
          since = at + 1;
        case final lead:
          if (lead case ShadedEffect(:final effect)
              when effectReadsRow(effect) != null) {
            from = null;
          }
          ops.addAll(_opsOf(lead, picture, space: space, reads: reads));
      }
      for (final painted in paintedEffectsOf(step.then)) {
        ops.add(_paintedOp(painted, reads: picture, puts: picture));
      }
    }
    final chain = _chainLaid(ops, carried.take(last + 1), picture);
    return (chain: chain, keys: null, colour: colour);
  }

  /// [ops], then the Gaussians [carried], each putting as far past what
  /// the one before put as it reaches from [picture], on a chain of the
  /// plan — none where there is nothing to lay.
  int? _chainLaid(
    List<void Function(int chain)> ops,
    Iterable<PaintedEffect> carried,
    (int, int, int, int) picture,
  ) {
    var extent = picture;
    for (final painted in carried) {
      final read = extent;
      extent = _grown(extent, painted);
      ops.add(_paintedOp(painted, reads: read, puts: extent));
    }
    if (ops.isEmpty) {
      return null;
    }
    final (x0, y0, columns, rows) = _tilesOf(extent);
    final chain = plan.chain(x0, y0, columns, rows);
    for (final op in ops) {
      op(chain);
    }
    return chain;
  }

  /// [chain], if any, held as what [shows] is, where [holding] gives it a
  /// number.
  void _hold(int? chain, CompositeNode<EngineRow>? shows) {
    final holding = this.holding;
    if (chain == null ||
        shows == null ||
        holding == null ||
        _chainHasAStepOff) {
      return;
    }
    if (holding.idOf(shows) case final id?) {
      plan.chainHeld(chain, holding.held, id);
    }
  }

  /// The op [painted] lays on a chain: a colour over its tiles, or a
  /// Gaussian reading [reads] and putting [puts].
  void Function(int chain) _paintedOp(
    PaintedEffect painted, {
    required (int, int, int, int) reads,
    required (int, int, int, int) puts,
  }) => switch (painted) {
    PaintedColour(:final matrix) => (chain) => plan.chainMatrix(chain, matrix),
    GaussianBlur() => (chain) => _gaussian(
      chain,
      painted,
      reads: reads,
      puts: puts,
    ),
  };

  /// [blur] on [chain] — the Gaussian itself over the whole pixels each
  /// way reaches — reading [reads] and putting [puts].
  void _gaussian(
    int chain,
    GaussianBlur blur, {
    required (int, int, int, int) reads,
    required (int, int, int, int) puts,
  }) {
    final (x, y) = blur.wholeReach;
    plan.chainGaussian(
      chain,
      across: (sigma: blur.sigmaX, reach: x),
      down: (sigma: blur.sigmaY, reach: y),
      picture: reads,
      repeats: blur.repeatsTheEdge,
      puts: puts,
    );
  }

  /// The ops [lead] lays on a chain whose picture is [picture], in
  /// [space], reading the rows [reads] draw — none for none, nor where it
  /// changes no pixel there.
  List<void Function(int chain)> _opsOf(
    EffectStepLead? lead,
    (int, int, int, int) picture, {
    required LayerPlacement? space,
    required _Reads reads,
  }) => switch (lead) {
    null => const [],
    KeyRun(:final keys) => [(chain) => plan.chainKeys(chain, _keysOf(keys))],
    // In the chain's own pixels, as its plate and its paper are.
    ShadedEffect(:final effect) => switch (shadedPassesOf(
      effect,
      DrawSpace.canvas,
      paper: paper,
      rasterWidth: picture.$3 - picture.$1,
    )) {
      [] => const [],
      // The sums before it are the engine lens blur's own.
      [..., final IrisGatherPass gather] => [
        (chain) => _lens(
          chain,
          gather,
          picture,
          drawn: switch (reads[effectReadsRow(effect)]) {
            null => null,
            final nodes => (nodes: nodes, space: space),
          },
        ),
      ],
      final passes => [
        (chain) => plan.chainLine(chain, picture, [
          for (final pass in passes.cast<LineBoxPass>()) _lineOf(pass),
        ]),
      ],
    },
    PaperEdgeEffect(:final effect) => switch (paperEdgeBlurOf(
      effect,
      DrawSpace.canvas,
    )) {
      null => const [],
      final blur => [(chain) => _onThePaper(chain, blur, picture)],
    },
    PluginEffect(:final effect) => _pluginStep(effect, picture).ops,
  };

  /// [effect]'s step: the host's, run over [picture] as the chain has come
  /// to it, a round of the plan each ([plugins], 🗣️I-132-Q34 a) — what it
  /// made laid in place of what came before it once it has, and the chain
  /// read there until. As if off where no route waits for it. [from] says
  /// what the picture is made of, where the plan can say; `straight` is
  /// what it made, once it has.
  ({List<void Function(int chain)> ops, Uint8List? straight}) _pluginStep(
    ResolvedLayerEffect effect,
    (int, int, int, int) picture, {
    PluginStepSource? from,
  }) {
    final plugins = this.plugins;
    if (plugins == null) {
      _chainHasAStepOff = true;
      return (ops: const [], straight: null);
    }
    final (left, top, right, bottom) = picture;
    final read = GpuChainRead(plugins.engine);
    final step = plugins.steps.stepOf(
      effect,
      _ChainPicture(read, picture),
      width: right - left,
      height: bottom - top,
      paper: paper.shift(ui.Offset(-left.toDouble(), -top.toDouble())),
      from: from,
    );
    if (!step.ran) {
      _chainHasAStepOff = true;
      return (ops: [(chain) => plan.chainRead(chain, read)], straight: null);
    }
    return switch (step.straight) {
      null => (ops: const [], straight: null),
      final made => (
        ops: [(chain) => plan.chainPut(chain, picture, made)],
        straight: made,
      ),
    };
  }

  /// A key chain of [keys], one run of them: the tables the CPU walks
  /// them by, a set at a time ([keyRgbaTablesOf]).
  int _keysOf(List<CelColorKey> keys) {
    final run = plan.keys();
    for (final (:red, :green, :blue, :restores, :alphaMaps)
        in keyRgbaTablesOf(keys)) {
      plan.keyRun(
        run,
        red: red,
        green: green,
        blue: blue,
        restores: restores,
        maps: alphaMaps,
      );
    }
    return run;
  }

  /// [blur] on [chain] over the paper on whole pixels cut out of
  /// [picture], its edge repeated past it and nothing put outside it, as
  /// the walk draws it over the paper cut out alone (`cutAndBlurred`):
  /// where none of the paper is there, the cut leaves nothing.
  // The second cut of the paper out of a chain's picture — the lens's the
  // other ([_lens]): a third joins them (rule of three).
  void _onThePaper(
    int chain,
    GaussianBlur blur,
    (int, int, int, int) picture,
  ) {
    final (left, top, right, bottom) = picture;
    final whole = paperOnWholePixels(paper);
    final cut = (
      math.max(whole.left.toInt(), left),
      math.max(whole.top.toInt(), top),
      math.min(whole.right.toInt(), right),
      math.min(whole.bottom.toInt(), bottom),
    );
    if (cut case (final l, final t, final r, final b) when l >= r || t >= b) {
      plan.chainMatrix(chain, List.filled(20, 0));
      return;
    }
    _gaussian(chain, blur, reads: cut, puts: cut);
  }

  /// [gather] — a camera lens blur's iris gathered out of its row sums —
  /// on [chain] over [picture], the paper it repeats past it cut to the
  /// picture, as its shader cuts it (iris_blur_shader.dart): where none of
  /// the paper is there, the cut leaves nothing. Its blur map is the row
  /// [drawn] draw; where none draw it, the row it names is none of the
  /// cut's, and it blurs at its whole radius ([IrisGatherPass.unmapped]).
  void _lens(
    int chain,
    IrisGatherPass gather,
    (int, int, int, int) picture, {
    required _Drawn? drawn,
  }) {
    final (left, top, right, bottom) = picture;
    // The first cut of the paper out of a chain's picture — the Gaussian's
    // the second ([_onThePaper]).
    final cut = switch (gather.paper) {
      null => null,
      final paper => (
        math.max(paper.left.toInt(), left),
        math.max(paper.top.toInt(), top),
        math.min(paper.right.toInt(), right),
        math.min(paper.bottom.toInt(), bottom),
      ),
    };
    if (cut case (final l, final t, final r, final b) when l >= r || t >= b) {
      plan.chainMatrix(chain, List.filled(20, 0));
      return;
    }
    final IrisGatherPass(:iris, :light, :map) = drawn == null
        ? gather.unmapped
        : gather;
    final read = switch ((map, drawn)) {
      (final map?, final drawn?) => _mapDrawn(drawn, map),
      _ => null,
    };
    final (:rotation, :halfSide, :side) = irisTurnsOf(
      sides: iris.sides,
      rotation: iris.rotation,
    );
    plan.chainLens(chain, picture, (
      sides: iris.sides,
      roundness: iris.roundness,
      aspect: iris.aspect,
      turn: rotation,
      halfSide: halfSide,
      side: side,
      radius: gather.radius,
      fringe: iris.fringe,
      // Read as the picture is stored, nothing boosted, where it reads no
      // light of its own (cameraLensBlurPasses).
      gain: light?.gain ?? 0,
      threshold: light?.threshold ?? 1,
      saturation: light?.saturation ?? 0,
      linear: light?.linear ?? false,
      paper: cut,
    ), map: read);
  }

  /// The blur map [map] reads of the row [drawn] draw: drawn alone, as it
  /// shows by itself, in their space — the steps laid for it taken from
  /// the plan as the map's (`GpuPlan.mapDrawn`).
  int _mapDrawn(_Drawn drawn, IrisMap map) {
    final (:nodes, :space) = drawn;
    final first = plan.steps;
    final outer = _space;
    _space = space;
    try {
      _lay(nodes);
    } finally {
      _space = outer;
    }
    return plan.mapDrawn(
      first,
      channel: _channelOf(map.channel),
      focal: map.focal,
      inverts: map.inverts,
    );
  }

  /// [placement] as it lies in the space the steps are laid in ([_space]).
  LayerPlacement? _inSpace(LayerPlacement? placement) => switch (_space) {
    null => placement,
    final space => space.compose(
      placement ?? const GuideTransform.identity(),
    ),
  };

  /// The rect [node]'s buffer covers in the space it is laid in: all its
  /// rows stand for ([subtreeBufferBounds]), grown by [outset], how far
  /// its chain reaches past them.
  // ⏳Uncut by what reads it, as the walk cuts it to the view (screen-on-
  // the-engine c6): what of it lies past the view changes no pixel a run
  // puts there, only how much the chain runs over.
  ui.Rect _bufferOf(CompositeNode<EngineRow> node, double outset) {
    // ⏳A folder's chain in the blur map a posed row reads: the walk rasters
    // it on the canvas's grid, its spread in canvas pixels, and lays that
    // under the row's pose undone — a buffer in the row's own space would
    // spread it in the row's.
    if (_space != null) {
      throw UnsupportedError('a chain of a buffer a posed row reads: $node');
    }
    return effectBufferBounds(
      subtreeBufferBounds(
        node,
        within: ui.Rect.largest,
        extentOf: (row) => _extentOf(row, paper),
        placementOf: _placementOf,
      ),
      outset,
    );
  }
}

/// How a row is laid ([_TreePlan._poseOf]): [posed], the plan's inverse of
/// its pose — canvas pixel to the row's own, row-major —, and [space], the
/// guide's where the row is read in its own space under its pose undone —
/// none for a row in the space it is laid in.
typedef _RowPose = ({List<double> posed, GuideTransform? space});

/// What lays tile sets on [plan] — their tiles kept in the pool by [hold]
/// — at the canvas's own resolution over [paper]: a row's tiles, and what
/// a hand holds over them.
final class _TileLaying {
  _TileLaying(this.plan, this.hold, this.paper);

  final GpuPlan plan;
  final TileHold hold;
  final ui.Rect paper;

  /// The canvas's own: [canvasResolutionSampling].
  GpuSampling get sampling => canvasResolutionSampling;

  // A placement is affine: no corner of what the plan lays says how far a
  // pixel lies, as a homography's would.
  int get columns => paper.width.ceil();
  int get rows => paper.height.ceil();

  /// [held] in the open buffer of its row, as its laying says, and cut at
  /// [wall] — its row's pasteboard — where it reaches past it, as its
  /// landing is cut there.
  void layHeld(EngineHeld held, PasteboardWall wall) {
    final reach = _reachOf(held);
    if (reach == null) {
      return;
    }
    final set = setOf(held.lineage, held.tiles);
    final (left, top, right, bottom) = _pixelsOf(reach);
    final outside = [
      (left, top, right, wall.top),
      (left, wall.bottomExclusive, right, bottom),
      (left, wall.top, wall.left, wall.bottomExclusive),
      (wall.rightExclusive, wall.top, right, wall.bottomExclusive),
    ].where((band) => band.$1 < band.$3 && band.$2 < band.$4).toList();
    void laid(int mode) {
      if (outside.isEmpty) {
        lay(set, held.toHeld, mode);
        return;
      }
      plan.open();
      lay(set, held.toHeld, GpuBlend.normal);
      plan.open();
      for (final (l, t, r, b) in outside) {
        plan.solid(_opaque, l, t, r, b);
      }
      plan.close(mode: GpuBlend.erase);
      plan.close(mode: mode);
    }

    switch (held.laying) {
      case LaidOver():
        laid(GpuBlend.normal);
      case LaidErasing():
        laid(GpuBlend.erase);
      case LaidReplacing(:final region):
        final (l, t, r, b) = _pixelsOf(region);
        final cut = (
          math.max(l, wall.left),
          math.max(t, wall.top),
          math.min(r, wall.rightExclusive),
          math.min(b, wall.bottomExclusive),
        );
        if (cut case (final l, final t, final r, final b) when l < r && t < b) {
          plan.open();
          plan.solid(_opaque, l, t, r, b);
          plan.close(mode: GpuBlend.erase);
        }
        laid(GpuBlend.normal);
    }
  }

  /// Tile set [set] laid whole in [mode] where [toOwn] — a pixel of the
  /// space the steps are laid in to the set's own, none where they are
  /// one — reads it.
  void lay(int set, GuideTransform? toOwn, int mode) {
    plan.row(
      set: set,
      inverse: gpuRowInverse(toOwn ?? const GuideTransform.identity()),
      sampling: sampling,
      columns: columns,
      rows: rows,
      mode: mode,
    );
  }

  /// Opaque white, as a solid takes it.
  static final int _opaque = gpuColourOf(0xFFFFFFFF);

  /// The tile set of [tiles], held as [lineage]'s: the box their
  /// coordinates span, row by row, an empty place where none is.
  int setOf(Object lineage, Map<TileCoord, BitmapTile> tiles) {
    final grid = hold.gridOf(lineage, tiles);
    return plan.set(grid.x0, grid.y0, grid.columns, grid.rows, grid.tiles);
  }
}

/// Row id → the nodes that draw the row, as a node whose chain reads rows
/// holds them ([CompositeReadsRows.rows]).
typedef _Reads = Map<LayerId, List<CompositeNode<EngineRow>>>;

/// The nodes that draw a row a chain reads, and the space the chain runs
/// in, where they are drawn.
typedef _Drawn = ({
  List<CompositeNode<EngineRow>> nodes,
  LayerPlacement? space,
});

/// [channel] by the engine's id.
GpuMapChannel _channelOf(IrisMapChannel channel) => switch (channel) {
  IrisMapChannel.luminance => GpuMapChannel.luminance,
  IrisMapChannel.red => GpuMapChannel.red,
  IrisMapChannel.green => GpuMapChannel.green,
  IrisMapChannel.blue => GpuMapChannel.blue,
  IrisMapChannel.alpha => GpuMapChannel.alpha,
};

/// The rect [row] stands for over [paper], as a buffer holding it covers
/// it: a row's ([_rowExtentOf]) and a solid's own.
ui.Rect _extentOf(EngineRow row, ui.Rect paper) => switch (row) {
  final EngineTiles row => _rowExtentOf(row, paper),
  EngineSolid(:final rect) => rect.rect,
};

/// What [row] stands for over [paper], in its own space: its content, as
/// far as its own chain paints past it ([rowExtentWithItsReach]).
ui.Rect _rowExtentOf(EngineTiles row, ui.Rect paper) =>
    rowExtentWithItsReach(_rowContentOf(row), row.effects, paper: paper);

/// What [row] holds and draws, in its own space: the canvas with every
/// tile it holds, what is held over it and the range marked over it, as
/// the walk's slot draws them (`_SurfaceSlot.extent`).
ui.Rect _rowContentOf(EngineTiles row) {
  final extent = row.held.fold(
    surfaceContentWorldRect(row.surface),
    (extent, held) => switch (_reachOf(held)) {
      null => extent,
      final reach => extent.expandToInclude(reach),
    },
  );
  return switch (row.mark) {
    null => extent,
    final mark => extent.expandToInclude(mark.bounds),
  };
}

/// The row's pixels [held] reaches, the tiles it holds where the row's
/// pixels read them — none for no tile, or a map that reads them from no
/// pixel of the row.
ui.Rect? _reachOf(EngineHeld held) {
  final tiles = tileCoordsWorldRect(held.tiles.keys, gpuTileSide);
  final back = canvasToArtwork(
    held.toHeld ?? const GuideTransform.identity(),
  );
  return tiles == null || back == null ? null : placedRectBounds(back, tiles);
}

/// The tiles [pixels] lie on, as the engine takes a box of them: (x0, y0,
/// columns, rows).
(int, int, int, int) _tilesOf((int, int, int, int) pixels) {
  final (left, top, right, bottom) = pixels;
  final x0 = (left / gpuTileSide).floor();
  final y0 = (top / gpuTileSide).floor();
  return (
    x0,
    y0,
    (right / gpuTileSide).ceil() - x0,
    (bottom / gpuTileSide).ceil() - y0,
  );
}

LayerPlacement? _placementOf(EngineRow row) => switch (row) {
  EngineTiles(:final placement) => placement,
  EngineSolid() => null,
};

/// [rect] on whole pixels, grown out to them: a chain's picture.
(int, int, int, int) _pixelsOf(ui.Rect rect) => (
  rect.left.floor(),
  rect.top.floor(),
  rect.right.ceil(),
  rect.bottom.ceil(),
);

/// [pass] as the engine's line blur takes it.
GpuLinePass _lineOf(LineBoxPass pass) => (
  taps: pass.taps,
  step: (pass.stepX, pass.stepY),
  centre: (pass.centerX, pass.centerY),
  first: pass.firstMap,
  each: pass.eachMap,
);

/// [extent] grown by how far [painted] paints past it: a Gaussian's whole
/// pixels each way, nothing for a colour.
(int, int, int, int) _grown(
  (int, int, int, int) extent,
  PaintedEffect painted,
) {
  if (painted is! GaussianBlur) {
    return extent;
  }
  final (left, top, right, bottom) = extent;
  final (x, y) = painted.wholeReach;
  return (left - x, top - y, right + x, bottom + y);
}

/// Whether [scope] is laid on its clip's base made opaque — its bottom node
/// that base ([CompositeOpaque]), at the bottom of a backdrop too, where a
/// blend gathered it ([composeOverTheirBackdrops]) — and the rows laid over
/// that.
({bool opaque, List<CompositeNode<EngineRow>> rows}) _onTheBase(
  List<CompositeNode<EngineRow>> scope,
) => switch (scope.firstOrNull) {
  CompositeOpaque() => (opaque: true, rows: scope.sublist(1)),
  CompositeBackdropBlend(:final backdrop, :final source, :final blendMode) =>
    switch (_onTheBase(backdrop)) {
      (opaque: true, :final rows) => (
        opaque: true,
        rows: [
          CompositeBackdropBlend(
            backdrop: rows,
            source: source,
            blendMode: blendMode,
          ),
          ...scope.skip(1),
        ],
      ),
      _ => (opaque: false, rows: scope),
    },
  _ => (opaque: false, rows: scope),
};

/// The engine's id for [mode]: the app's table where it has one, normal
/// beside it ([GpuBlend]). A pass-through folder is no node, and answers
/// normal where one is asked of it (`LayerBlendMode.paintBlendMode`).
int _blendOf(LayerBlendMode mode) => switch (mode) {
  LayerBlendMode.passThrough || LayerBlendMode.normal => GpuBlend.normal,
  _ => switch ((mode.separable, mode.nonSeparable)) {
    (final separable?, _) => separableBlendModeNativeId(separable),
    (_, final nonSeparable?) => nonSeparableBlendModeNativeId(nonSeparable),
    _ => throw StateError('$mode has no blend'),
  },
};

/// [opacity] as the engine lays it, 65535 whole: a plan's rows, and what
/// an export lays over a frame ([GpuExport.lay]).
int strengthOf(double opacity) => (opacity * 65535).round();
