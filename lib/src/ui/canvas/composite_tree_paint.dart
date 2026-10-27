import 'dart:ui';

import '../../models/composite_tree.dart';
import '../../services/composite_effect_paint.dart';
import '../../services/layer_pose_matrix.dart' show LayerPlacement;
import '../text/cel_number_paint.dart';
import 'layer_image_draw.dart' show withLayerPlacement;
import 'subtree_image_composite.dart';

/// What a walk of a composite tree asks of its route — the only things the
/// routes do differently: how a row ([L]) is drawn, at the scale the CTM
/// is at, where it lies on its own ([paintRow] lays it there), the rect it
/// stands for ([extentOf]) and where it lies ([placementOf]) — what a
/// buffer around it covers, and where the letters on it lie — and what of
/// the canvas is shown, where a blend can read the frame
/// ([drawBlendOverBackdrop]'s `shownWithin`) — and where the pictures its
/// nodes are drawn into are held ([held]).
typedef CompositeRoute<L> = ({
  void Function(Canvas canvas, L row, double rasterScale) paintRow,
  Rect Function(L row) extentOf,
  LayerPlacement? Function(L row) placementOf,
  Rect? shownWithin,
  SubtreeHolding<L>? held,
});

/// Where a route holds the pictures of its nodes ([HeldSubtreeRasters]):
/// what a node draws ([keyOf] — null for one drawn afresh each time), and
/// whether one drawn whole here is kept ([keeps]).
typedef SubtreeHolding<L> = ({
  HeldSubtreeRasters rasters,
  Object? Function(CompositeNode<L> node) keyOf,
  bool keeps,
});

/// Paints [nodes] onto [canvas] at [rasterScale] — the scale the CTM this
/// walk draws under is at: a group that rasterises ITSELF needs it, and a
/// `Canvas` will not tell anyone — what of them lies [within] what reads
/// them ([subtreeBufferBounds]).
///
/// 🚨★★★ONE WALK OF A COMPOSITE TREE (card one-walk-of-the-composite-tree,
/// 유저 2026-10-25 「3번은 합치는거 하고싶고」) for the editing stack — and
/// so the frame's one picture and playback — and the camera's render. Each
/// held this switch of its own, every node but a row the same parts called
/// the same way; [route] is what they do apart.
void paintCompositeTree<L>(
  Canvas canvas,
  List<CompositeNode<L>> nodes, {
  required double rasterScale,
  required Rect within,
  required CompositeRoute<L> route,
}) => _CompositeTreeWalk(route).paint(canvas, nodes, rasterScale, within);

class _CompositeTreeWalk<L> {
  _CompositeTreeWalk(this.route);

  final CompositeRoute<L> route;

  void paint(
    Canvas canvas,
    List<CompositeNode<L>> nodes,
    double rasterScale,
    Rect within,
  ) {
    for (final node in nodes) {
      switch (node) {
        case CompositeLeaf(:final payload):
          route.paintRow(canvas, payload, rasterScale);
        // A row's letters lie where the row does (I-65).
        case CompositeCelNumber(
          on: CompositeLeaf(:final payload),
          :final letters,
        ):
          withLayerPlacement(
            canvas,
            placement: route.placementOf(payload),
            body: () => paintCelNumber(canvas, letters),
          );
        case final CompositeGroup<L> group:
          _group(canvas, group, rasterScale, within);
        case final CompositeAdjustment<L> adjustment:
          _adjustment(canvas, adjustment, rasterScale, within);
        case final CompositeBackdropBlend<L> blend:
          _backdropBlend(canvas, blend, rasterScale, within);
        case final CompositeClip<L> clip:
          _clip(canvas, clip, rasterScale, within);
        case CompositeOpaque(:final of):
          drawOpaque(
            canvas: canvas,
            bounds: _bufferBoundsOf(node, within),
            paintOf: (into) => paint(into, [of], rasterScale, within),
          );
      }
    }
  }

  /// The rect a buffer for [node] covers ([subtreeBufferBounds]).
  Rect _bufferBoundsOf(CompositeNode<L> node, Rect within) =>
      subtreeBufferBounds(
        node,
        within: within,
        extentOf: route.extentOf,
        placementOf: route.placementOf,
      );

  /// Where [node]'s picture is held, where the route holds them and knows
  /// what [node] draws — kept where [within] cuts none of it.
  SubtreeHold? _holdOf(CompositeNode<L> node, Rect within) {
    final held = route.held;
    final key = held?.keyOf(node);
    if (held == null || key == null) {
      return null;
    }
    return SubtreeHold(
      held.rasters,
      key: key,
      keeps:
          held.keeps &&
          _bufferBoundsOf(node, within) == _bufferBoundsOf(node, Rect.largest),
    );
  }

  /// A folder: its children buffered as one image, blended once with the
  /// folder's paint.
  void _group(
    Canvas canvas,
    CompositeGroup<L> node,
    double rasterScale,
    Rect within,
  ) {
    final CompositeGroup<L>(:children, :opacity, :blendMode, :effects) = node;
    // R27 #29: one buffer for the group, one blend on it — and
    // because the ACTIVE layer is a node in here, a stroke drawn
    // inside a blended folder finally reads the way it will play
    // back. R6: the folder's effect chain lands on the same buffer, in
    // CANVAS units (the camera projection is a canvas transform, so the
    // engine maps a blur's sigma through the CTM for us).
    final groupPlan = resolveCompositeEffectPlan(effects);
    final groupPaint = layerCompositePaint(
      opacity: opacity,
      blendMode: blendMode,
      effects: groupPlan.finalPaint,
    );
    // 🚨A GROUP'S BUFFER CANNOT EXCEED THE ONE THAT HOLDS IT.
    // Bounded by the view, a folder asked Skia for the whole
    // pasteboard (9× the page) at far zoom-out — an offscreen
    // that the enclosing canvas-resolution buffer then clipped
    // away. Content bounds keep it inside by construction, and
    // this says so where it can fail.
    //
    // ⚠️It is the CONTENT that must sit inside, before the effect
    // grows it. The spread the size hint adds below is deliberate
    // — artwork just outside the view has to reach the blur at the
    // view's edge — so there the buffer lies past what reads it by
    // exactly that spread, off screen. ↩️This asserted the grown
    // rect, and a blurred folder whose ink crossed the view's edge
    // stopped every debug build at any zoom (board
    // `a-blurred-folder-outgrows-the-composite`). ↩️And it asserted
    // the display buffer, which a folder inside a blurred one lies
    // past by the outer one's spread (card
    // nested-folder-buffers-read-past-the-view).
    final contentRect = _bufferBoundsOf(node, within);
    assert(
      within.expandToInclude(contentRect) == within,
      'a group buffer must sit inside the buffer that reads it: '
      '$contentRect is not within $within',
    );
    final groupRect = effectBufferBounds(
      contentRect,
      groupPlan.outsetPixels,
    );
    // 🚨★★★ONE PICTURE PER NODE — a group IS an image, not a
    // `saveLayer`. [drawSubtreeAsImage] holds the arithmetic and
    // the reason, and the test that certifies it against the
    // saveLayer it replaced calls THAT function, not a copy. ↩️Each walk
    // said so of its own (the camera's: 「if one of them kept a
    // `saveLayer` the folder would be samplable on screen and not in the
    // file」) until they were one.
    drawSubtreeAsImage(
      canvas: canvas,
      // The size hint grows by the blur's spread, so artwork just
      // OUTSIDE the visible rect still bleeds in — without this the
      // blur at the screen edge would change as you scroll. It is
      // what reads the children, so a folder among them holds its
      // artwork out there too.
      bounds: groupRect,
      rasterScale: rasterScale,
      paintSubtree: (into, scale) => paint(into, children, scale, groupRect),
      compose: (blit) => blit(groupPaint),
      steps: groupPlan.preSteps,
      held: _holdOf(node, within),
    );
  }

  /// An adjustment scope: the rows under it buffered and graded as one.
  void _adjustment(
    Canvas canvas,
    CompositeAdjustment<L> node,
    double rasterScale,
    Rect within,
  ) {
    final CompositeAdjustment<L>(:children, :effects, :mix) = node;
    // R6b: the scope into one buffer, the row's chain onto it —
    // which is what lets a stroke drawn UNDER an adjustment read
    // through the grade while you draw it.
    final pass = resolveAdjustmentScopePass(
      bounds: _bufferBoundsOf(node, within),
      effects: effects,
      mix: mix,
    );
    // 🚨★★★ONE RASTER, TWO BLITS. The scope used to be PAINTED
    // twice below full strength — a mix is a crossfade, not a
    // fade-out — and it is the same picture both times. The
    // passes keep their layers; what changed is that they now
    // contain a blit of one raster instead of a second walk of
    // the scope. The outer `saveLayer` stays: it is an alpha group
    // over two draws of one image, not a buffer anything needs to
    // sample.
    drawSubtreeAsImage(
      canvas: canvas,
      bounds: pass.bufferBounds,
      rasterScale: rasterScale,
      paintSubtree: (into, scale) =>
          paint(into, children, scale, pass.bufferBounds),
      compose: composeAdjustmentScope(canvas, pass),
      steps: pass.preSteps,
      held: _holdOf(node, within),
    );
  }

  /// A row in an advanced blend, composed over a picture of what lies
  /// below it in its scope ([drawBlendOverBackdrop], brush-fidelity-Q4).
  void _backdropBlend(
    Canvas canvas,
    CompositeBackdropBlend<L> node,
    double rasterScale,
    Rect within,
  ) {
    final CompositeBackdropBlend<L>(:backdrop, :source, :blendMode) = node;
    final bounds = _bufferBoundsOf(node, within);
    drawBlendOverBackdrop(
      canvas: canvas,
      bounds: bounds,
      rasterScale: rasterScale,
      paintBackdrop: (into, scale) => paint(into, backdrop, scale, bounds),
      paintSource: (into, scale) => paint(into, [source], scale, bounds),
      blendMode: blendMode,
      shownWithin: route.shownWithin,
    );
  }

  /// A clipping group (I-92): the base and what clips to it as one image,
  /// laid once with the base's strength and blend ([drawClipAsImage]).
  void _clip(
    Canvas canvas,
    CompositeClip<L> node,
    double rasterScale,
    Rect within,
  ) {
    final CompositeClip<L>(:base, :scope, :opacity, :blendMode) = node;
    final bounds = _bufferBoundsOf(node, within);
    drawClipAsImage(
      canvas: canvas,
      bounds: bounds,
      rasterScale: rasterScale,
      paintBase: (into, scale) => paint(into, [base], scale, bounds),
      paintScope: (into, scale) => paint(into, scope, scale, bounds),
      paint: layerCompositePaint(
        opacity: opacity,
        blendMode: blendMode,
        effects: CompositeEffectPaint.none,
      ),
      held: _holdOf(node, within),
    );
  }
}
