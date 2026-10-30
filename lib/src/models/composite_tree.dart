import '../core/tree_nodes.dart';
import 'cel_number_letters.dart';
import 'layer_blend_mode.dart';
import 'layer_effect.dart';
import 'layer_id.dart';

/// One node of a composite TREE, bottom → top: something that PAINTS
/// (whatever [L] is on this route), a FOLDER's group buffer, an
/// ADJUSTMENT row's scope, or a row composed over its BACKDROP.
///
/// ⛔THE STRUCTURE IS THE SAME ON EVERY ROUTE; ONLY THE PAINTED THING
/// DIFFERS. The plan resolves entries, then surfaces; the editing canvas
/// resolves stack requests, then paint records. Those are four payloads,
/// not four trees: when each route restated Group and Adjustment for
/// itself, a new structural node kind had to be added four times and the
/// fold below had to be written four times to match. With one structural
/// set, a new kind is added once and every switch over
/// [CompositeNode] fails to compile until it answers.
sealed class CompositeNode<L> implements TreeNode<CompositeNode<L>> {
  const CompositeNode();
}

/// The thing that paints: [payload] is this route's answer to "what draws
/// here" — an entry, a surface, an image request, a paint record.
final class CompositeLeaf<L> extends CompositeNode<L> {
  const CompositeLeaf(this.payload);

  final L payload;

  @override
  List<CompositeNode<L>> get children => const [];
}

/// A FOLDER's GROUP BUFFER (R27 #29, 유저 확정: "그룹 한번합쳐서 한번
/// 블렌드"). [children] compose into one buffer, and only then does the
/// folder's [opacity] and [blendMode] apply — once, to that buffer. So
/// overlapping members inside a multiply folder read as one picture
/// instead of darkening where they cross.
///
/// Only a folder that NEEDS a buffer becomes one of these
/// ([folderNeedsCompositeBuffer]); a plain pass-through folder leaves no
/// node at all and its members sit directly in the parent's list.
final class CompositeGroup<L> extends CompositeNode<L> {
  const CompositeGroup({
    required this.children,
    required this.opacity,
    required this.blendMode,
    this.effects = const [],
  });

  /// Bottom → top; may hold nested groups.
  @override
  final List<CompositeNode<L>> children;

  /// The FOLDER's effective opacity (static × animated sample).
  final double opacity;

  /// The FOLDER's blend against everything below the group.
  final LayerBlendMode blendMode;

  /// The FOLDER's effect chain sampled at this frame (R6), applied ONCE to
  /// the composed buffer — which is the whole reason effects force a folder
  /// to buffer ([folderNeedsCompositeBuffer]): a blur over the group is not
  /// the same picture as a blur over each member.
  final List<ResolvedLayerEffect> effects;
}

/// An ADJUSTMENT layer's SCOPE (R6b): everything composited below the row,
/// composed into one buffer so the row's [effects] can filter it as the
/// single picture it is.
///
/// The scope is decided by the folder rules Photoshop and CSP already
/// taught the stack (§6-z3): the walk collects every sibling below the
/// adjustment, keeps going OUT through pass-through folders (통과 — the
/// adjustment leaks past them, filtering what lies below the folder too)
/// and stops at the first BUFFERING one, whose buffer is a picture of its
/// own that nothing inside it can reach past.
///
/// [mix] is the row's opacity, and it means MIX, not fade: 0.5 is a
/// half-strength grade, never a half-transparent stack. See
/// [resolveAdjustmentScopePass] for how a route paints that.
final class CompositeAdjustment<L> extends CompositeNode<L> {
  const CompositeAdjustment({
    required this.children,
    required this.effects,
    required this.mix,
  });

  /// Everything in scope, bottom → top; may hold nested groups.
  @override
  final List<CompositeNode<L>> children;

  /// The row's chain sampled at this frame — never empty (an adjustment
  /// that resolves to nothing leaves no node at all).
  final List<ResolvedLayerEffect> effects;

  /// The effect MIX, 0…1 (the row's static opacity).
  final double mix;
}

/// A row in an advanced blend — multiply, linear burn, hue … every mode but
/// normal and add ([LayerBlendMode.needsItsBackdrop]) — with its [backdrop]:
/// everything composited below it in its scope, as one picture, which
/// [source] is composed over by the blend's own formula.
///
/// 🗣️brush-fidelity-Q4 (유저 2026-10-17 「레이어까지 같이」): a layer takes
/// every mode the brush does, and the ones the GPU had no blend for got a
/// road of their own; Q4 of a-blurred-folder-cut-by-the-view-moves-on-vulkan
/// (유저 2026-10-22) sent the GPU's own down it too. A GPU blend reads
/// whatever its render target holds below it as it draws; a shader cannot
/// read its target, so the tree hands it the backdrop as a picture instead
/// ([composeOverTheirBackdrops]).
///
/// [source] is the row itself — a leaf or a buffering folder — painting
/// NORMAL: its opacity and effects stay on it, and [blendMode] applies
/// once, between the two pictures.
final class CompositeBackdropBlend<L> extends CompositeNode<L> {
  const CompositeBackdropBlend({
    required this.backdrop,
    required this.source,
    required this.blendMode,
  });

  /// Everything below the row in its scope, bottom → top — empty when the
  /// row is the lowest thing there.
  final List<CompositeNode<L>> backdrop;

  /// The row itself, painting normal.
  final CompositeNode<L> source;

  /// The row's blend — an advanced one ([LayerBlendMode.needsItsBackdrop]).
  final LayerBlendMode blendMode;

  /// Bottom → top: the backdrop, then the row over it.
  @override
  List<CompositeNode<L>> get children => [...backdrop, source];
}

/// A CLIPPING GROUP (I-92 — Photoshop's clipping mask, Clip Studio's
/// 「下のレイヤーでクリッピング」): the rows that clip to the layer below,
/// and the row they clip to, the [base].
///
/// 🗣️유저 2026-10-24: I-92-Q1 a (clipping), Q2 a (a run of clipped rows
/// all clip to the first row under them that does not), Q3 a (a folder
/// clips, and is clipped to, as a row does).
///
/// ONE picture: [base], and [scope] laid over it by the base's alpha
/// (`srcATop` — what lands where the base is not, is not there). The
/// group's [opacity] and [blendMode] are the BASE's, and apply once, to
/// that picture — Photoshop: the clipped layers assume the base's opacity
/// and blend.
final class CompositeClip<L> extends CompositeNode<L> {
  const CompositeClip({
    required this.base,
    required this.scope,
    required this.opacity,
    required this.blendMode,
  });

  /// The row clipped to, painting normal at full strength — its strength
  /// and blend are the group's.
  final CompositeNode<L> base;

  /// What the base's alpha cuts, bottom → top: the rows clipped to it, over
  /// the base made opaque ([CompositeOpaque]) where one of them blends in
  /// other than normal — a multiply reads the base it multiplies.
  final List<CompositeNode<L>> scope;

  /// The BASE's strength.
  final double opacity;

  /// The BASE's blend against everything below the group.
  final LayerBlendMode blendMode;

  @override
  List<CompositeNode<L>> get children => [base, ...scope];
}

/// [of] with its alpha made 1 — a clip's base as the rows clipped to it
/// blend with it ([CompositeClip]). Where the base is half there, a row
/// over it composes with the base's whole colour, and the base's alpha
/// then cuts the two once: the clipping group's soft edge comes out as
/// Photoshop's `srcATop` does, never thinned twice.
final class CompositeOpaque<L> extends CompositeNode<L> {
  const CompositeOpaque(this.of);

  /// The clip's base — ⚠️THE SAME NODE as [CompositeClip.base], not a copy:
  /// a route that keeps one picture per row (the camera's) finds the base's
  /// here. The folds keep it so ([mapCompositeLeaves],
  /// [composeOverTheirBackdrops]).
  final CompositeNode<L> of;

  /// ⛔EMPTY: [of] already stands in the tree, as its clip's base — this
  /// paints it a second time, it is not a second place of it. A walk over
  /// every row ([preorderNodes]) meets the base once.
  @override
  List<CompositeNode<L>> get children => const [];
}

/// A row's CEL NUMBER (I-65): [letters] written over the row's picture, where
/// [on] — the row's own leaf, laid just before it, in their group where the
/// two are one picture — lies, so they move
/// with it. It paints nothing of [on]'s: the row's picture is that leaf's
/// (`celNumberedRow` makes the two).
final class CompositeCelNumber<L> extends CompositeNode<L> {
  const CompositeCelNumber({required this.on, required this.letters});

  /// The row the letters are written on — ⚠️THE SAME NODE as the leaf that
  /// paints it, as [CompositeOpaque.of] is its base: a route asks the row's
  /// payload where it lies. The folds keep it so ([mapCompositeLeaves]);
  /// where the row has no picture it is the row standing bare, in no other
  /// place in the tree (F-481).
  final CompositeLeaf<L> on;

  final CelNumberLetters letters;

  /// ⛔EMPTY: [on] stands in the tree as its own leaf, or nowhere.
  @override
  List<CompositeNode<L>> get children => const [];
}

/// [node], whose chain reads other rows' pictures — a camera lens blur's
/// blur map ([ResolvedLayerEffect.layers], 🗣️I-132-Q16 a): [rows] holds
/// each row of the cut its effects name, as the nodes that draw it.
///
/// A row is read as it shows by itself — 🗣️I-132-Q21 a where it lies,
/// 🗣️I-132-Q23 a with its eye not asked and 🗣️I-132-Q24 b at its own
/// strength — and 🗣️I-132-Q22 a reads no row of its own: what [rows] draw
/// holds no node of this kind. A row the effects name that [rows] does not
/// hold is no row of the cut, and reads as none.
///
/// Its [children] are [node] and every node [rows] draw: a walk over the
/// rows it paints ([preorderNodes]) meets them — what is drawn on, what is
/// read in and what is signed of a node that reads a row is that row too.
final class CompositeReadsRows<L> extends CompositeNode<L> {
  const CompositeReadsRows({required this.node, required this.rows});

  /// The node — a row, a folder's buffer or an adjustment's scope — whose
  /// chain reads [rows].
  final CompositeNode<L> node;

  /// Row id → the nodes that draw it, bottom → top; empty where it draws
  /// nothing at this frame, which reads as a picture with nothing on it.
  final Map<LayerId, List<CompositeNode<L>>> rows;

  @override
  List<CompositeNode<L>> get children => [
    node,
    for (final drawn in rows.values) ...drawn,
  ];
}

/// THE CLIP LAW (I-92): [clipped] joined to the clipping group [standing]
/// is the base of, or that [standing] — a row, or a folder's buffer —
/// becomes the base of ([CompositeClip]).
///
/// [blendOf] asks a route's own row its blend; [asClipBase] for the same
/// row painting normal at full strength, with the strength and blend it
/// hands the group.
CompositeNode<L> clippedOnto<L>(
  CompositeNode<L> standing,
  CompositeNode<L> clipped, {
  required LayerBlendMode Function(L payload) blendOf,
  required ({L base, double opacity, LayerBlendMode blendMode}) Function(
    L payload,
  )
  asClipBase,
}) {
  // A row that blends with the base in other than normal reads the base's
  // whole colour ([CompositeOpaque]); in normal alone, the base's alpha
  // laid over it once is the same picture, and costs no second paint.
  final readsTheBase =
      switch (clipped) {
        CompositeLeaf<L>(:final payload) => blendOf(payload),
        CompositeGroup<L>(:final blendMode) => blendMode,
        CompositeAdjustment<L>() ||
        CompositeBackdropBlend<L>() ||
        CompositeClip<L>() ||
        CompositeOpaque<L>() ||
        CompositeCelNumber<L>() ||
        CompositeReadsRows<L>() => throw StateError(
          'only a row or a folder clips to the layer below, not $clipped',
        ),
      } !=
      LayerBlendMode.normal;
  if (standing case CompositeClip<L>(
    :final base,
    :final scope,
    :final opacity,
    :final blendMode,
  )) {
    return CompositeClip<L>(
      base: base,
      scope: List.unmodifiable([
        if (readsTheBase && scope.first is! CompositeOpaque<L>)
          CompositeOpaque<L>(base),
        ...scope,
        clipped,
      ]),
      opacity: opacity,
      blendMode: blendMode,
    );
  }
  final (base, opacity, blendMode) = switch (standing) {
    CompositeLeaf<L>(:final payload) => switch (asClipBase(payload)) {
      (:final base, :final opacity, :final blendMode) => (
        CompositeLeaf<L>(base),
        opacity,
        blendMode,
      ),
    },
    CompositeGroup<L>(
      :final children,
      :final opacity,
      :final blendMode,
      :final effects,
    ) =>
      (
        CompositeGroup<L>(
          children: children,
          opacity: 1,
          blendMode: LayerBlendMode.normal,
          effects: effects,
        ),
        opacity,
        blendMode,
      ),
    CompositeAdjustment<L>() ||
    CompositeBackdropBlend<L>() ||
    CompositeClip<L>() ||
    CompositeOpaque<L>() ||
    CompositeCelNumber<L>() ||
    CompositeReadsRows<L>() => throw StateError(
      'only a row or a folder is clipped to, not $standing',
    ),
  };
  return CompositeClip<L>(
    base: base,
    scope: List.unmodifiable([
      if (readsTheBase) CompositeOpaque<L>(base),
      clipped,
    ]),
    opacity: opacity,
    blendMode: blendMode,
  );
}

/// THE BACKDROP LAW: [nodes] with every row in an advanced blend
/// ([LayerBlendMode.needsItsBackdrop]) composed over everything below it in
/// its scope ([CompositeBackdropBlend]), at every depth.
///
/// ★A LIST IS A SCOPE — the one an adjustment row reads
/// ([CompositeAdjustment]): a pass-through folder leaves no node, so its
/// members already stand among what lies below the folder, and a
/// buffering folder's members are a list of their own that nothing inside
/// reaches past. So "below it in its scope" is "before it in its list".
///
/// [blendOf] and [paintedNormal] ask a route's own row its blend and for
/// the same row painting normal — what a [CompositeBackdropBlend]'s source
/// is.
List<CompositeNode<L>> composeOverTheirBackdrops<L>(
  List<CompositeNode<L>> nodes, {
  required LayerBlendMode Function(L payload) blendOf,
  required L Function(L payload) paintedNormal,
}) => _composeOverTheirBackdrops<L>(
  nodes,
  blendOf: blendOf,
  paintedNormal: paintedNormal,
  bases: Map.identity(),
);

/// [composeOverTheirBackdrops], with [bases] the clip bases composed so far
/// — each source base to what it became, for its [CompositeOpaque].
List<CompositeNode<L>> _composeOverTheirBackdrops<L>(
  List<CompositeNode<L>> nodes, {
  required LayerBlendMode Function(L payload) blendOf,
  required L Function(L payload) paintedNormal,
  required Map<CompositeNode<L>, CompositeNode<L>> bases,
}) {
  List<CompositeNode<L>> scopeOf(List<CompositeNode<L>> list) =>
      _composeOverTheirBackdrops(
        list,
        blendOf: blendOf,
        paintedNormal: paintedNormal,
        bases: bases,
      );
  final out = <CompositeNode<L>>[];
  for (final node in nodes) {
    final (CompositeNode<L> composed, LayerBlendMode? blend) = switch (node) {
      CompositeLeaf<L>(:final payload) => (node, blendOf(payload)),
      CompositeGroup<L>(
        :final children,
        :final opacity,
        :final blendMode,
        :final effects,
      ) =>
        (
          CompositeGroup<L>(
            children: List.unmodifiable(scopeOf(children)),
            opacity: opacity,
            blendMode: blendMode,
            effects: effects,
          ),
          blendMode,
        ),
      CompositeAdjustment<L>(:final children, :final effects, :final mix) => (
        CompositeAdjustment<L>(
          children: List.unmodifiable(scopeOf(children)),
          effects: effects,
          mix: mix,
        ),
        null,
      ),
      CompositeBackdropBlend<L>() => (node, null),
      // ★The scope is a list like any other: a clipped row in an advanced
      // blend composes over the opaque base and the rows clipped under it.
      CompositeClip<L>(
        :final base,
        :final scope,
        :final opacity,
        :final blendMode,
      ) =>
        (
          CompositeClip<L>(
            base: bases[base] = scopeOf([base]).single,
            scope: List.unmodifiable(scopeOf(scope)),
            opacity: opacity,
            blendMode: blendMode,
          ),
          blendMode,
        ),
      CompositeOpaque<L>(:final of) => (
        CompositeOpaque<L>(bases[of] ?? scopeOf([of]).single),
        null,
      ),
      // ⛔As it stands: its row is a leaf painting normal (`celNumberedRow`
      // gives any other blend to their group), which this fold hands on as
      // the very node it was — the one [CompositeCelNumber.on] names.
      CompositeCelNumber<L>() => (node, null),
      // ⛔Rows are read once every other law has laid the tree
      // (`resolveCutFrameCompositeTree`): a blend never meets one.
      CompositeReadsRows<L>() => throw StateError(
        'the rows a chain reads are laid after its blend, not before: $node',
      ),
    };
    if (blend == null || !blend.needsItsBackdrop) {
      out.add(composed);
      continue;
    }
    final source = switch (composed) {
      CompositeLeaf<L>(:final payload) => CompositeLeaf<L>(
        paintedNormal(payload),
      ),
      CompositeGroup<L>(:final children, :final opacity, :final effects) =>
        CompositeGroup<L>(
          children: children,
          opacity: opacity,
          blendMode: LayerBlendMode.normal,
          effects: effects,
        ),
      CompositeClip<L>(:final base, :final scope, :final opacity) =>
        CompositeClip<L>(
          base: base,
          scope: scope,
          opacity: opacity,
          blendMode: LayerBlendMode.normal,
        ),
      _ => composed,
    };
    final below = List<CompositeNode<L>>.unmodifiable(out);
    out
      ..clear()
      ..add(
        CompositeBackdropBlend<L>(
          backdrop: below,
          source: source,
          blendMode: blend,
        ),
      );
  }
  return out;
}

/// THE UNDERLAY LAW: [nodes] laid on [underlay] — what a route lays under
/// its rows at the root: the editing canvas's paper, the camera's ground and
/// paper — as the bottom row of their scope.
///
/// 🚨IT GOES IN ONCE, WHERE THE ROWS READ IT. A GPU blend at the root reads
/// the underlay off the target it draws on; a [CompositeBackdropBlend] at
/// the bottom of the list reads its backdrop instead, so the underlay goes
/// to the bottom of that backdrop, at every depth a blend sits at the
/// bottom, and nowhere else. Laid under the list too, it would lie twice:
/// the blend's picture already holds it, and that picture over a second
/// copy doubles every pixel of its edge that is not opaque.
///
/// A blend only ever sits at the bottom of its list
/// ([composeOverTheirBackdrops] gathers everything below it into it), so
/// the bottom is the only place this looks.
List<CompositeNode<L>> onUnderlay<L>(
  List<CompositeNode<L>> nodes,
  L underlay,
) => switch (nodes.firstOrNull) {
  CompositeBackdropBlend<L>(
    :final backdrop,
    :final source,
    :final blendMode,
  ) =>
    [
      CompositeBackdropBlend<L>(
        backdrop: List.unmodifiable(onUnderlay(backdrop, underlay)),
        source: source,
        blendMode: blendMode,
      ),
      ...nodes.skip(1),
    ],
  _ => [CompositeLeaf<L>(underlay), ...nodes],
};

/// [nodes] with each node whose own chain reads rows — a row's
/// ([effectsOf]), a folder's or an adjustment's — standing in a
/// [CompositeReadsRows] with each row its chain names as [drawnOf] draws
/// it: asked with the row whose chain reads it, null for a folder's or an
/// adjustment's, and answering null for no row there, which reads as none.
///
/// Laid once every other law has laid the tree: the node that reads stands
/// where it stood — in its clip, over its backdrop — and what points back
/// at it ([CompositeOpaque.of]) points at it still. A cel number's row
/// ([CompositeCelNumber.on]) stays the leaf: the letters lie where it does.
List<CompositeNode<L>> withTheRowsTheyRead<L>(
  List<CompositeNode<L>> nodes, {
  required List<ResolvedLayerEffect> Function(L row) effectsOf,
  required List<CompositeNode<L>>? Function(LayerId row, L? by) drawnOf,
}) {
  final laid = Map<CompositeNode<L>, CompositeNode<L>>.identity();
  CompositeNode<L> reading(
    CompositeNode<L> node,
    List<ResolvedLayerEffect> effects,
    L? by,
  ) {
    final named = {
      for (final effect in effects) ...effect.layers.values.nonNulls,
    };
    final rows = <LayerId, List<CompositeNode<L>>>{
      for (final row in named)
        if (drawnOf(row, by) case final drawn?) row: List.unmodifiable(drawn),
    };
    return rows.isEmpty
        ? node
        : CompositeReadsRows<L>(node: node, rows: Map.unmodifiable(rows));
  }

  CompositeNode<L> lay(CompositeNode<L> node) => laid[node] ??= switch (node) {
    CompositeLeaf<L>(:final payload) => reading(
      node,
      effectsOf(payload),
      payload,
    ),
    CompositeGroup<L>(
      :final children,
      :final opacity,
      :final blendMode,
      :final effects,
    ) =>
      reading(
        CompositeGroup<L>(
          children: List.unmodifiable(children.map(lay)),
          opacity: opacity,
          blendMode: blendMode,
          effects: effects,
        ),
        effects,
        null,
      ),
    CompositeAdjustment<L>(:final children, :final effects, :final mix) =>
      reading(
        CompositeAdjustment<L>(
          children: List.unmodifiable(children.map(lay)),
          effects: effects,
          mix: mix,
        ),
        effects,
        null,
      ),
    CompositeBackdropBlend<L>(:final backdrop, :final source, :final blendMode) =>
      CompositeBackdropBlend<L>(
        backdrop: List.unmodifiable(backdrop.map(lay)),
        source: lay(source),
        blendMode: blendMode,
      ),
    CompositeClip<L>(:final base, :final scope, :final opacity, :final blendMode) =>
      CompositeClip<L>(
        base: lay(base),
        scope: List.unmodifiable(scope.map(lay)),
        opacity: opacity,
        blendMode: blendMode,
      ),
    CompositeOpaque<L>(:final of) => CompositeOpaque<L>(lay(of)),
    // Already laid: what it reads is beside it.
    CompositeCelNumber<L>() || CompositeReadsRows<L>() => node,
  };
  return List.unmodifiable(nodes.map(lay));
}

/// THE FOLD: [nodes] with every leaf run through [map], keeping the
/// structure around them.
///
/// A leaf that maps to null DROPS, and a group or adjustment that mapping
/// left empty drops with it — an empty buffer is a wasted `saveLayer`. A
/// clip whose base maps to nothing drops whole: what clips to nothing is
/// nowhere ([CompositeClip]).
///
/// ⛔EQUIVALENT ON THE EDITING ROUTE TODAY — the shared tree already drops
/// a folder whose members are all skipped, so an empty list never reaches
/// there, and mutating it away left the suite green (2026-09-05). Kept as
/// the statement of what a group node MEANS: a buffer around nothing is a
/// `saveLayer` for nothing. On the surface and paint routes it is load
/// bearing: a cel with no artwork and an image the cache has not decoded
/// yet both drop here.
///
/// 🚨A ROW A CEL NUMBER IS WRITTEN ON STANDS though it maps to null: the
/// number draws a picture of its own, and a block exposed with nothing
/// drawn on it is there all the same (F-481, 유저 2026-10-26 「빈블록이라도
/// 존재하면 보이도록 고정 … 이 규칙을 공용화해서 다른곳에서도 적용할예정」).
/// [bare] is the row as it stands with nothing drawn — the letters are
/// written on that, and it stands for the row there alone
/// ([CompositeCelNumber.on]), as nothing of it paints. A route whose [map]
/// drops no row that is there leaves [bare] out; where it answers null,
/// the letters go with the row.
///
/// [chains] is what a folder's or an adjustment's chain becomes on this
/// route, as [map] says what a row's does — its plugins bound to their runs
/// (🗣️I-132-Q34 a 「어디에 걸어도 돌고」); each as it stands where null.
///
/// Perf: one pass per node per frame — tens of nodes, never per pixel.
List<CompositeNode<M>> mapCompositeLeaves<L, M>(
  List<CompositeNode<L>> nodes,
  M? Function(L payload) map, {
  M? Function(L payload)? bare,
  List<ResolvedLayerEffect> Function(List<ResolvedLayerEffect> chain)? chains,
}) => _mapCompositeLeaves<L, M>(
  nodes,
  map,
  bare: bare,
  chains: chains ?? _asItStands,
  kept: Map.identity(),
);

List<ResolvedLayerEffect> _asItStands(List<ResolvedLayerEffect> chain) =>
    chain;

/// [mapCompositeLeaves], with [kept] the nodes a later node points back at
/// — a clip's base ([CompositeOpaque.of]), a row a cel number is written on
/// ([CompositeCelNumber.on]) — each to what it became, null where it
/// dropped.
List<CompositeNode<M>> _mapCompositeLeaves<L, M>(
  List<CompositeNode<L>> nodes,
  M? Function(L payload) map, {
  required M? Function(L payload)? bare,
  required List<ResolvedLayerEffect> Function(List<ResolvedLayerEffect>)
  chains,
  required Map<CompositeNode<L>, CompositeNode<M>?> kept,
}) {
  List<CompositeNode<M>> fold(List<CompositeNode<L>> list) =>
      _mapCompositeLeaves(list, map, bare: bare, chains: chains, kept: kept);
  CompositeLeaf<M>? bareOf(CompositeLeaf<L> row) =>
      switch (bare?.call(row.payload)) {
        final payload? => CompositeLeaf<M>(payload),
        null => null,
      };
  CompositeNode<M>? keptOf(CompositeNode<L> node) =>
      kept.containsKey(node) ? kept[node] : fold([node]).singleOrNull;
  final out = <CompositeNode<M>>[];
  for (final node in nodes) {
    switch (node) {
      case CompositeLeaf<L>(:final payload):
        final mapped = map(payload);
        final leaf = mapped == null ? null : CompositeLeaf<M>(mapped);
        kept[node] = leaf;
        if (leaf != null) {
          out.add(leaf);
        }
      case CompositeGroup<L>(
        :final children,
        :final opacity,
        :final blendMode,
        :final effects,
      ):
        final mapped = fold(children);
        if (mapped.isEmpty) {
          continue;
        }
        out.add(
          CompositeGroup<M>(
            children: List.unmodifiable(mapped),
            opacity: opacity,
            blendMode: blendMode,
            effects: chains(effects),
          ),
        );
      case CompositeAdjustment<L>(:final children, :final effects, :final mix):
        final mapped = fold(children);
        if (mapped.isEmpty) {
          continue; // Every row in scope turned out to have no artwork.
        }
        out.add(
          CompositeAdjustment<M>(
            children: List.unmodifiable(mapped),
            effects: chains(effects),
            mix: mix,
          ),
        );
      case CompositeBackdropBlend<L>(
        :final backdrop,
        :final source,
        :final blendMode,
      ):
        final below = fold(backdrop);
        final row = fold([source]);
        if (row.isEmpty) {
          // Nothing to compose: what lay below stays where it was.
          out.addAll(below);
          continue;
        }
        out.add(
          CompositeBackdropBlend<M>(
            backdrop: List.unmodifiable(below),
            source: row.single,
            blendMode: blendMode,
          ),
        );
      case CompositeClip<L>(
        :final base,
        :final scope,
        :final opacity,
        :final blendMode,
      ):
        final mappedBase = fold([base]).singleOrNull;
        kept[base] = mappedBase;
        if (mappedBase == null) {
          // Nothing to clip to: the rows clipped to it show nowhere.
          continue;
        }
        out.add(
          CompositeClip<M>(
            base: mappedBase,
            scope: List.unmodifiable(fold(scope)),
            opacity: opacity,
            blendMode: blendMode,
          ),
        );
      case CompositeOpaque<L>(:final of):
        if (keptOf(of) case final base?) {
          out.add(CompositeOpaque<M>(base));
        }
      case CompositeCelNumber<L>(:final on, :final letters):
        if (keptOf(on) ?? bareOf(on) case final CompositeLeaf<M> row) {
          out.add(CompositeCelNumber<M>(on: row, letters: letters));
        }
      // A row read that draws nothing here is read as a picture with
      // nothing on it — still a row of the cut, not none.
      case CompositeReadsRows<L>(node: final reader, :final rows):
        if (fold([reader]).singleOrNull case final mapped?) {
          out.add(
            CompositeReadsRows<M>(
              node: mapped,
              rows: {
                for (final MapEntry(key: row, value: drawn) in rows.entries)
                  row: List.unmodifiable(fold(drawn)),
              },
            ),
          );
        }
    }
  }
  return out;
}

/// Whether [node] holds a row [test] answers for — itself, or one anywhere
/// inside it, as a walk over every row meets it ([preorderNodes]: a clip's
/// base made opaque and the row a cel number is written on are not second
/// places of a row).
///
/// ⛔ONE SPELLING of "the node a row is in": the live row a stroke's step
/// is told by, the row a pen draws into, a row drawn afresh — each wrote
/// the walk out for itself.
bool holdsRow<L>(CompositeNode<L> node, bool Function(L row) test) =>
    preorderNodes([node]).any(
      (each) => each is CompositeLeaf<L> && test(each.payload),
    );
