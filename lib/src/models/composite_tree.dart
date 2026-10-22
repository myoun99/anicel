import '../core/tree_nodes.dart';
import 'layer_blend_mode.dart';
import 'layer_effect.dart';

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

  /// The row's blend — one the GPU has none for.
  final LayerBlendMode blendMode;

  /// Bottom → top: the backdrop, then the row over it.
  @override
  List<CompositeNode<L>> get children => [...backdrop, source];
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
}) {
  List<CompositeNode<L>> scope(List<CompositeNode<L>> list) =>
      composeOverTheirBackdrops(
        list,
        blendOf: blendOf,
        paintedNormal: paintedNormal,
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
            children: List.unmodifiable(scope(children)),
            opacity: opacity,
            blendMode: blendMode,
            effects: effects,
          ),
          blendMode,
        ),
      CompositeAdjustment<L>(:final children, :final effects, :final mix) => (
        CompositeAdjustment<L>(
          children: List.unmodifiable(scope(children)),
          effects: effects,
          mix: mix,
        ),
        null,
      ),
      CompositeBackdropBlend<L>() => (node, null),
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

/// THE FOLD: [nodes] with every leaf run through [map], keeping the
/// structure around them.
///
/// A leaf that maps to null DROPS, and a group or adjustment that mapping
/// left empty drops with it — an empty buffer is a wasted `saveLayer`.
///
/// ⛔EQUIVALENT ON THE EDITING ROUTE TODAY — the shared tree already drops
/// a folder whose members are all skipped, so an empty list never reaches
/// there, and mutating it away left the suite green (2026-09-05). Kept as
/// the statement of what a group node MEANS: a buffer around nothing is a
/// `saveLayer` for nothing. On the surface and paint routes it is load
/// bearing: a cel with no artwork and an image the cache has not decoded
/// yet both drop here.
///
/// Perf: one pass per node per frame — tens of nodes, never per pixel.
List<CompositeNode<M>> mapCompositeLeaves<L, M>(
  List<CompositeNode<L>> nodes,
  M? Function(L payload) map,
) {
  final out = <CompositeNode<M>>[];
  for (final node in nodes) {
    switch (node) {
      case CompositeLeaf<L>(:final payload):
        final mapped = map(payload);
        if (mapped == null) {
          continue;
        }
        out.add(CompositeLeaf<M>(mapped));
      case CompositeGroup<L>(
        :final children,
        :final opacity,
        :final blendMode,
        :final effects,
      ):
        final mapped = mapCompositeLeaves(children, map);
        if (mapped.isEmpty) {
          continue;
        }
        out.add(
          CompositeGroup<M>(
            children: List.unmodifiable(mapped),
            opacity: opacity,
            blendMode: blendMode,
            effects: effects,
          ),
        );
      case CompositeAdjustment<L>(:final children, :final effects, :final mix):
        final mapped = mapCompositeLeaves(children, map);
        if (mapped.isEmpty) {
          continue; // Every row in scope turned out to have no artwork.
        }
        out.add(
          CompositeAdjustment<M>(
            children: List.unmodifiable(mapped),
            effects: effects,
            mix: mix,
          ),
        );
      case CompositeBackdropBlend<L>(
        :final backdrop,
        :final source,
        :final blendMode,
      ):
        final below = mapCompositeLeaves(backdrop, map);
        final row = mapCompositeLeaves([source], map);
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
    }
  }
  return out;
}
