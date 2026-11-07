import 'dart:ui' as ui;

import 'package:gpu_engine/gpu_engine.dart';

import '../core/color_matrix.dart';
import '../core/display_filter.dart';
import '../models/bitmap_surface.dart';
import '../models/bitmap_tile.dart';
import '../models/composite_tree.dart';
import '../models/dirty_region.dart';
import '../models/layer_blend_mode.dart';
import '../models/layer_effect.dart';
import '../models/tile_coord.dart';
import '../services/brush_stroke_blend.dart'
    show nonSeparableBlendModeNativeId, separableBlendModeNativeId;
import '../services/composite_effect_paint.dart'
    show onionTintColorMatrix, resolveColorOnlyMatrix;
import '../services/layer_pose_matrix.dart'
    show LayerPlacement, canvasToArtwork;
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

  void _lay(List<CompositeNode<EngineRow>> nodes) {
    for (final node in nodes) {
      _node(node);
    }
  }

  /// [node]'s steps, its picture laid in [mode] where one is named — the
  /// blend a [CompositeBackdropBlend] lays its source in, which paints
  /// normal itself — else in its own.
  void _node(CompositeNode<EngineRow> node, {int? mode}) {
    switch (node) {
      case CompositeLeaf(payload: final EngineTiles row):
        _row(row, mode ?? _blendOf(row.blendMode));
      case CompositeLeaf(payload: EngineSolid(:final argb, :final rect)):
        plan.solid(
          _rgbaOf(argb),
          rect.left,
          rect.top,
          rect.rightExclusive,
          rect.bottomExclusive,
        );
      case final CompositeGroup<EngineRow> group:
        _group(group, mode ?? _blendOf(group.blendMode));
      case final CompositeAdjustment<EngineRow> adjustment:
        _adjustment(adjustment);
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
      // ⏳screen-on-the-engine c5c: a lens blur's map drawn from its rows.
      case CompositeReadsRows():
        throw UnsupportedError('a chain reading rows on the engine: $node');
    }
  }

  /// [group]'s buffer, closed at its strength in [mode] through its colour.
  void _group(CompositeGroup<EngineRow> group, int mode) {
    plan.open();
    _lay(group.children);
    plan.close(
      opacity: _strengthOf(group.opacity),
      mode: mode,
      matrix: _matrixOf(_colourOf(group.effects)),
    );
  }

  /// [adjustment]'s scope, closed through its grade at its mix.
  void _adjustment(CompositeAdjustment<EngineRow> adjustment) {
    final CompositeAdjustment(:children, :effects, :mix) = adjustment;
    plan.open();
    _lay(children);
    // A mix is no fade: a colour's is folded into its matrix, a grade of
    // that strength (resolveAdjustmentScopePass).
    final colour = _colourOf(effects);
    plan.close(
      mode: GpuBlend.normal,
      matrix: _matrixOf(
        colour == null || mix >= 1
            ? colour
            : lerpColorMatrixFromIdentity(colour, mix),
      ),
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
  void _row(EngineTiles row, int mode) {
    final back = switch (row.placement) {
      null => const (1.0, 0.0, 0.0, 1.0, 0.0, 0.0),
      final placement => switch (canvasToArtwork(placement)) {
        null => null,
        final inverse => (
          inverse.a,
          inverse.b,
          inverse.c,
          inverse.d,
          inverse.tx,
          inverse.ty,
        ),
      },
    };
    final tiles = row.surface.tiles;
    if (back == null || tiles.isEmpty) {
      return;
    }
    final colour = _colourOf(row.effects);
    final tint = row.tint;
    final (a, b, c, d, tx, ty) = back;
    plan.row(
      set: _setOf(row.lineage, tiles),
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
}

/// The colour [effects] fold into, null where none changes a colour.
///
/// ⏳screen-on-the-engine c5b: a chain the engine runs — a key, a blur, a
/// lens — on the row's own tiles, a folder's or a scope's buffer.
List<double>? _colourOf(List<ResolvedLayerEffect> effects) {
  if (effects.every((effect) => effect.isNoOp)) {
    return null;
  }
  return resolveColorOnlyMatrix(effects) ??
      (throw UnsupportedError('a chain past colour on the engine: $effects'));
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
