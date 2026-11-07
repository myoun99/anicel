import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:gpu_engine/gpu_engine.dart';

import '../core/color_matrix.dart';
import '../core/display_filter.dart';
import '../core/draw_space.dart';
import '../models/bitmap_surface.dart';
import '../models/bitmap_tile.dart';
import '../models/composite_tree.dart';
import '../models/dirty_region.dart';
import '../models/layer_blend_mode.dart';
import '../models/layer_effect.dart';
import '../models/layer_id.dart';
import '../models/tile_coord.dart';
import '../services/brush_stroke_blend.dart'
    show nonSeparableBlendModeNativeId, separableBlendModeNativeId;
import '../services/cel_source_effect_pass.dart'
    show CelColorKey, keyRgbaTablesOf;
import '../services/composite_effect_paint.dart'
    show
        CompositeEffectPlan,
        EffectStepLead,
        KeyRun,
        PaperEdgeEffect,
        PluginEffect,
        ShadedEffect,
        effectBufferBounds,
        effectReadsRow,
        onionTintColorMatrix,
        resolveColorOnlyMatrix,
        resolveCompositeEffectPlan,
        shadedPassesOf;
import '../services/guide_geometry.dart' show GuideTransform;
import '../services/layer_pose_matrix.dart'
    show LayerPlacement, canvasToArtwork;
import '../services/shaded_passes.dart'
    show IrisGatherPass, IrisMap, IrisMapChannel, LineBoxPass, irisTurnsOf;
import '../ui/canvas/subtree_image_composite.dart' show subtreeBufferBounds;
import '../ui/canvas/tiled_surface_compose.dart' show surfaceContentWorldRect;
import 'engine_tile_ledger.dart';

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
}

/// [argb] laid over [rect] in normal: the paper under a cut's rows, a
/// camera's ground.
final class EngineSolid extends EngineRow {
  const EngineSolid({required this.argb, required this.rect});

  final int argb;
  final DirtyRegion rect;
}

/// The engine's sampling for [quality], the display's law's answer
/// ([filterQualityForDisplayScale]): `none` is its Nearest, the rest its
/// Blend (브러시/렌더링, I-120 11-08 00:00).
GpuSampling gpuSamplingOf(ui.FilterQuality quality) =>
    quality == ui.FilterQuality.none ? GpuSampling.nearest : GpuSampling.blend;

/// Lays [nodes] on [plan] bottom to top, over the canvas [paper] lies on —
/// their rows' tiles held by [hold] ([EngineTileLedger.held]), inside which
/// the plan runs.
///
/// Each node takes the steps that are its picture: a row a `Row` and a
/// solid a `Solid`; a folder, an adjustment and a clip a buffer of their
/// own, opened and closed onto the one under them. A blend over a backdrop
/// lays the backdrop where it stands and the row over it in its blend — a
/// row reads what it is laid on, so the backdrop needs no picture of its
/// own ([CompositeBackdropBlend]).
// ⏳Tests alone lay a tree till the screen does (screen-on-the-engine c6).
void planCompositeTree(
  GpuPlan plan,
  List<CompositeNode<EngineRow>> nodes, {
  required TileHold hold,
  required ui.Rect paper,
}) => _TreePlan(plan, hold, paper)._lay(nodes);

class _TreePlan {
  _TreePlan(this.plan, this.hold, this.paper);

  final GpuPlan plan;
  final TileHold hold;
  final ui.Rect paper;

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
  /// draw ([CompositeReadsRows]), none of its children's.
  void _node(
    CompositeNode<EngineRow> node, {
    int? mode,
    _Reads reads = const {},
  }) {
    switch (node) {
      case CompositeLeaf(payload: final EngineTiles row):
        _row(row, mode ?? _blendOf(row.blendMode), reads);
      case CompositeLeaf(payload: EngineSolid(:final argb, :final rect)):
        plan.solid(
          _rgbaOf(argb),
          rect.left,
          rect.top,
          rect.rightExclusive,
          rect.bottomExclusive,
        );
      case final CompositeGroup<EngineRow> group:
        _group(group, mode ?? _blendOf(group.blendMode), reads);
      case final CompositeAdjustment<EngineRow> adjustment:
        _adjustment(adjustment, reads);
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
      // ⏳The letters are a plate Flutter draws (`celNumberPlate`) till the
      // engine's own letters lay them (공통, engine-canvas-letters).
      case CompositeCelNumber():
        throw UnsupportedError('a cel number on the engine: $node');
      case CompositeReadsRows(:final node, :final rows):
        _node(node, mode: mode, reads: rows);
    }
  }

  /// [group]'s buffer, closed at its strength in [mode] through its chain
  /// and its colour.
  void _group(CompositeGroup<EngineRow> group, int mode, _Reads reads) {
    plan.open();
    _lay(group.children);
    final (:chain, :colour) = _chainOf(
      group.effects,
      over: (outset) => _bufferOf(group, outset),
      space: _space,
      reads: reads,
    );
    plan.close(
      opacity: _strengthOf(group.opacity),
      mode: mode,
      chain: chain,
      matrix: _matrixOf(colour),
    );
  }

  /// [adjustment]'s scope, closed through its grade at its mix.
  void _adjustment(CompositeAdjustment<EngineRow> adjustment, _Reads reads) {
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
    final (:chain, :colour) = _chainOf(
      effects,
      over: (outset) => _bufferOf(adjustment, outset),
      space: _space,
      reads: reads,
    );
    plan.close(
      mode: GpuBlend.normal,
      chain: chain,
      mix: _strengthOf(mix),
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
    plan.close(opacity: _strengthOf(clip.opacity), mode: mode);
  }

  /// [row] laid in [mode] — none where its pose collapses it.
  void _row(EngineTiles row, int mode, _Reads reads) {
    final placement = _inSpace(row.placement);
    final inverse = switch (placement) {
      null => const GuideTransform.identity(),
      final placement => canvasToArtwork(placement),
    };
    final tiles = row.surface.tiles;
    if (inverse == null || tiles.isEmpty) {
      return;
    }
    // Its chain runs on its own picture, the whole of what it stands for,
    // and is cut there — as the walk steps the image it lays, before its
    // pose (steppedForChain); the rows it reads drawn there too, under
    // its pose undone (rowsUnderPlacement).
    final (:chain, :colour) = _chainOf(
      row.effects,
      over: (_) => surfaceContentWorldRect(row.surface),
      space: placement == null ? null : inverse,
      reads: reads,
    );
    final tint = row.tint;
    final GuideTransform(:a, :b, :c, :d, :tx, :ty) = inverse;
    plan.row(
      set: _setOf(row.lineage, tiles),
      chain: chain,
      inverse: [a, c, tx, b, d, ty, 0, 0, 1],
      // A row is laid at the canvas's own resolution, one of its pixels a
      // canvas pixel, whatever its pose (🗣️I-120-Q26 · Q28 — a picture
      // baked as the canvas shows it).
      sampling: gpuSamplingOf(filterQualityForDisplayScale(1)),
      // A placement is affine: no corner of what the plan lays says how
      // far a pixel lies, as a homography's would.
      columns: paper.width.ceil(),
      rows: paper.height.ceil(),
      mode: mode,
      // The tint LAST, over the finished pixel: the ghost is the row as the
      // screen shows it, in the peg's colour (resolveCompositeEffectPaint).
      matrix: _matrixOf(switch ((colour, tint)) {
        (_, null) => colour,
        (null, final tint?) => onionTintColorMatrix(tint),
        (final colour?, final tint?) => composeColorMatrices(
          onionTintColorMatrix(tint),
          colour,
        ),
      }),
      opacity: _strengthOf(row.opacity),
    );
  }

  /// The tile set of [tiles], held as [lineage]'s: the box their
  /// coordinates span, row by row, an empty place where none is.
  int _setOf(Object lineage, Map<TileCoord, BitmapTile> tiles) {
    final coords = tiles.keys;
    final left = coords.map((coord) => coord.x).reduce(_least);
    final top = coords.map((coord) => coord.y).reduce(_least);
    final right = coords.map((coord) => coord.x).reduce(_most);
    final bottom = coords.map((coord) => coord.y).reduce(_most);
    final columns = right - left + 1;
    final rows = bottom - top + 1;
    final entries = tiles.entries.toList();
    final slots = hold.slotsOf(lineage, [
      for (final entry in entries) entry.value,
    ]);
    final grid = List<GpuTile?>.filled(columns * rows, null);
    for (final (at, entry) in entries.indexed) {
      grid[(entry.key.y - top) * columns + entry.key.x - left] = slots[at];
    }
    return plan.set(left, top, columns, rows, grid);
  }

  /// [matrix] added to the plan, or none.
  int? _matrixOf(List<double>? matrix) =>
      matrix == null || colorMatrixIsIdentity(matrix)
      ? null
      : plan.matrix(matrix);

  /// What [effects] lay where a draw takes them, its picture standing for
  /// the rect [over] answers for how far they reach past it, in [space]:
  /// the chain their steps run on that picture, reading the rows [reads]
  /// draw — none where no step changes a pixel — and the colour the draw
  /// lays it through after them.
  ({int? chain, List<double>? colour}) _chainOf(
    List<ResolvedLayerEffect> effects, {
    required ui.Rect Function(double outset) over,
    required LayerPlacement? space,
    required _Reads reads,
  }) {
    final steps = resolveCompositeEffectPlan(effects, paper: paper);
    final colour = _colourOf(steps.finalEffects);
    if (steps.preSteps.isEmpty) {
      return (chain: null, colour: colour);
    }
    final picture = _pixelsOf(over(steps.outsetPixels));
    final ops = [
      for (final step in steps.preSteps) ...[
        ..._opsOf(step.lead, picture, space: space, reads: reads),
        if (_colourOf(step.then) case final then?)
          (int chain) => plan.chainMatrix(chain, then),
      ],
    ];
    if (ops.isEmpty) {
      return (chain: null, colour: colour);
    }
    final (left, top, right, bottom) = picture;
    final x0 = (left / gpuTileSide).floor();
    final y0 = (top / gpuTileSide).floor();
    final chain = plan.chain(
      x0,
      y0,
      (right / gpuTileSide).ceil() - x0,
      (bottom / gpuTileSide).ceil() - y0,
    );
    for (final op in ops) {
      op(chain);
    }
    return (chain: chain, colour: colour);
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
          drawn: switch (effectReadsRow(effect)) {
            null => null,
            final row => reads[row],
          },
          space: space,
        ),
      ],
      final passes => [
        (chain) => plan.chainLine(chain, picture, [
          for (final pass in passes.cast<LineBoxPass>()) _lineOf(pass),
        ]),
      ],
    },
    // ⏳gpu-canonical-store-Q2: the blur the engine's Gaussian lays.
    PaperEdgeEffect(:final effect) => throw UnsupportedError(
      'a Gaussian on the engine: $effect',
    ),
    // ⏳A plug-in's step is the host's: a plan cuts its chain there
    // (rust/src/kernels/chain/mod.rs).
    PluginEffect(:final effect) => throw UnsupportedError(
      'a plug-in on the engine: $effect',
    ),
  };

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

  /// [gather] — a camera lens blur's iris gathered out of its row sums —
  /// on [chain] over [picture], the paper it repeats past it cut to the
  /// picture, as its shader cuts it (iris_blur_shader.dart): where none of
  /// the paper is there, the cut leaves nothing. Its blur map is the row
  /// [drawn] draw, in [space]; where none draw it, the row it names is
  /// none of the cut's, and it blurs at its whole radius
  /// ([IrisGatherPass.unmapped]).
  void _lens(
    int chain,
    IrisGatherPass gather,
    (int, int, int, int) picture, {
    required List<CompositeNode<EngineRow>>? drawn,
    required LayerPlacement? space,
  }) {
    final (left, top, right, bottom) = picture;
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
      (final map?, final drawn?) => _mapDrawn(drawn, map, space: space),
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
  /// shows by itself, in [space] — the steps laid for it taken from the
  /// plan as the map's (`GpuPlan.mapDrawn`).
  int _mapDrawn(
    List<CompositeNode<EngineRow>> drawn,
    IrisMap map, {
    required LayerPlacement? space,
  }) {
    final first = plan.steps;
    final outer = _space;
    _space = space;
    try {
      _lay(drawn);
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
        extentOf: _extentOf,
        placementOf: _placementOf,
      ),
      outset,
    );
  }
}

/// Row id → the nodes that draw the row, as a node whose chain reads rows
/// holds them ([CompositeReadsRows.rows]).
typedef _Reads = Map<LayerId, List<CompositeNode<EngineRow>>>;

/// [channel] by the engine's id.
GpuMapChannel _channelOf(IrisMapChannel channel) => switch (channel) {
  IrisMapChannel.luminance => GpuMapChannel.luminance,
  IrisMapChannel.red => GpuMapChannel.red,
  IrisMapChannel.green => GpuMapChannel.green,
  IrisMapChannel.blue => GpuMapChannel.blue,
  IrisMapChannel.alpha => GpuMapChannel.alpha,
};

/// The rect [row] stands for, as a buffer holding it covers it: a row's
/// content — the canvas with every tile it holds — and a solid's own.
ui.Rect _extentOf(EngineRow row) => switch (row) {
  EngineTiles(:final surface) => surfaceContentWorldRect(surface),
  EngineSolid(:final rect) => rect.rect,
};

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

/// The colour [effects] — a run of a chain's painted effects, which a draw
/// carries ([CompositeEffectPlan.finalEffects], a step's `then`) — fold
/// into, null where there are none: a tree holds no effect that changes no
/// pixel ([resolveLayerEffectsAt] drops them).
///
/// ⏳gpu-canonical-store-Q2: the Gaussian, the one such effect past colour.
List<double>? _colourOf(List<ResolvedLayerEffect> effects) {
  if (effects.isEmpty) {
    return null;
  }
  return resolveColorOnlyMatrix(effects) ??
      (throw UnsupportedError('a Gaussian on the engine: $effects'));
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

/// [opacity] as the engine lays it, 65535 whole.
int _strengthOf(double opacity) => (opacity * 65535).round();

/// [argb] — a `Color`'s — as the engine's solid takes it: straight RGBA8,
/// A<<24|B<<16|G<<8|R.
int _rgbaOf(int argb) =>
    argb & 0xFF00FF00 | (argb >> 16 & 0xFF) | (argb & 0xFF) << 16;

int _least(int a, int b) => a < b ? a : b;
int _most(int a, int b) => a > b ? a : b;
