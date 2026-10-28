import 'dart:ui';

import '../../core/collection_equality.dart';
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
/// nodes are drawn into are held ([held]) — and where the canvas the rows
/// are laid on lies ([paper]), the edge a folder's blur that repeats it
/// reads past (I-132-Q14 a).
typedef CompositeRoute<L> = ({
  void Function(Canvas canvas, L row, double rasterScale) paintRow,
  Rect Function(L row) extentOf,
  LayerPlacement? Function(L row) placementOf,
  Rect? shownWithin,
  SubtreeHolding<L>? held,
  Rect paper,
});

/// Where a route holds the pictures of its nodes ([HeldSubtreeRasters]):
/// what a node draws ([keyOf] — null for one drawn afresh each time), the
/// row a pen draws on ([drawnOn]) — what lies below it is held as one
/// picture ([_CompositeTreeWalk._belowThePen]) — and whether one drawn
/// whole here is kept ([keeps]).
typedef SubtreeHolding<L> = ({
  HeldSubtreeRasters rasters,
  Object? Function(CompositeNode<L> node) keyOf,
  bool Function(L row) drawnOn,
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
  _CompositeTreeWalk(this.route, {this.keeps = true});

  final CompositeRoute<L> route;

  /// Whether a picture drawn whole here may be kept where the route keeps
  /// them — not inside the one picture of what lies below a pen, which is
  /// kept itself ([_belowThePen]).
  final bool keeps;

  void paint(
    Canvas canvas,
    List<CompositeNode<L>> nodes,
    double rasterScale,
    Rect within,
  ) {
    final pen = nodes.indexWhere(_holdsThePen);
    final below = pen < 0 ? 0 : pen;
    _belowThePen(canvas, nodes.sublist(0, below), rasterScale, within);
    for (final node in nodes.skip(below)) {
      _paintNode(canvas, node, rasterScale, within);
    }
  }

  void _paintNode(
    Canvas canvas,
    CompositeNode<L> node,
    double rasterScale,
    Rect within,
  ) {
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

  /// 🚨★WHAT LIES BELOW THE ROW A PEN DRAWS ON IS ONE PICTURE (card
  /// paint-walk-redoes-the-same-work-each-step, 🗣️유저 2026-10-27, Q2 = c
  /// 「그리는 행 아래 · 위를 한 장씩 묶어 든다」): [run], the nodes laid in
  /// their list before the one the pen is in, drawn into one picture held
  /// while the pen draws — a stroke's step patched into the frame is cut
  /// from it however many folders, rows and letters lie there. A list is
  /// laid onto nothing (the frame's picture, a patch of its own, a buffer),
  /// so a picture of what it lays first is the same pixels as those nodes
  /// drawn in place.
  ///
  /// Drawn in place, each node held as it was ([_holdOf]), where no picture
  /// of them is held and none drawn here would be kept
  /// ([SubtreeHold.findsOrKeeps]) — a picture of them for one draw is a
  /// draw for nothing. ⚖️And where none of them is a picture of its own
  /// ([_isAPicture]): rows, letters and the paper are drawn straight, a
  /// draw each, and a picture of them cuts no work. 🔬Held all the same,
  /// a page of the canvas was the paper's alone under a pen on the bottom
  /// row (1920×1080, 8.3 MB, the whole app on Windows, 2026-10-27), and a
  /// step over rows with no folder among them was the same either way.
  void _belowThePen(
    Canvas canvas,
    List<CompositeNode<L>> run,
    double rasterScale,
    Rect within,
  ) {
    final held = route.held;
    final keys = [for (final node in run) held?.keyOf(node)];
    final bounds = within.intersect(canvas.getLocalClipBounds());
    final hold = held == null || !run.any(_isAPicture) || keys.contains(null)
        ? null
        : SubtreeHold(
            held.rasters,
            key: _Below(keys),
            keeps:
                held.keeps &&
                keeps &&
                run.every((node) => _isWhole(node, within)),
            below: true,
          );
    if (hold == null || !hold.findsOrKeeps(bounds, rasterScale)) {
      for (final node in run) {
        _paintNode(canvas, node, rasterScale, within);
      }
      return;
    }
    final inside = _CompositeTreeWalk(route, keeps: false);
    drawSubtreeAsImage(
      canvas: canvas,
      bounds: bounds,
      rasterScale: rasterScale,
      paper: route.paper,
      paintSubtree: (into, scale) {
        for (final node in run) {
          inside._paintNode(into, node, scale, within);
        }
      },
      compose: (blit) => blit(Paint()),
      held: hold,
    );
  }

  /// Whether [node] is drawn as a picture of its own — a buffer the walk
  /// rasters — rather than straight onto what it lies on.
  static bool _isAPicture(CompositeNode<Object?> node) => switch (node) {
    CompositeLeaf() || CompositeCelNumber() => false,
    CompositeGroup() ||
    CompositeAdjustment() ||
    CompositeBackdropBlend() ||
    CompositeClip() ||
    CompositeOpaque() => true,
  };

  /// Whether [node] holds the row a pen draws on ([SubtreeHolding.drawnOn]).
  bool _holdsThePen(CompositeNode<L> node) {
    final held = route.held;
    return held != null && holdsRow(node, held.drawnOn);
  }

  /// The rect a buffer for [node] covers ([subtreeBufferBounds]).
  Rect _bufferBoundsOf(CompositeNode<L> node, Rect within) =>
      subtreeBufferBounds(
        node,
        within: within,
        extentOf: route.extentOf,
        placementOf: route.placementOf,
      );

  /// Whether [within] cuts none of [node].
  bool _isWhole(CompositeNode<L> node, Rect within) =>
      _bufferBoundsOf(node, within) == _bufferBoundsOf(node, Rect.largest);

  /// Where [node]'s picture is held, where the route holds them and knows
  /// what [node] draws — kept where [within] cuts none of it.
  ///
  /// ⛔Not a node the pen draws in: what it draws changes with each step,
  /// and a picture of it kept as the frame is laid is cut from by none of
  /// them.
  SubtreeHold? _holdOf(CompositeNode<L> node, Rect within) {
    final held = route.held;
    final key = held?.keyOf(node);
    if (held == null || key == null || _holdsThePen(node)) {
      return null;
    }
    return SubtreeHold(
      held.rasters,
      key: key,
      keeps: held.keeps && keeps && _isWhole(node, within),
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
      paper: route.paper,
      paintSubtree: (into, scale) => paint(into, children, scale, groupRect),
      compose: (blit) => blit(groupPaint),
      steps: groupPlan.preSteps,
      held: _holdOf(node, within),
      cell: rasterCellFor(groupPlan.outsetPixels),
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
      paper: route.paper,
      paintSubtree: (into, scale) =>
          paint(into, children, scale, pass.bufferBounds),
      compose: composeAdjustmentScope(canvas, pass),
      steps: pass.preSteps,
      held: _holdOf(node, within),
      cell: rasterCellFor(pass.outsetPixels),
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
    // Under a row a pen draws on, its backdrop is all below the pen.
    final drawnOn = _holdsThePen(source);
    drawBlendOverBackdrop(
      canvas: canvas,
      bounds: bounds,
      rasterScale: rasterScale,
      paintBackdrop: (into, scale) => drawnOn
          ? _belowThePen(into, backdrop, scale, bounds)
          : paint(into, backdrop, scale, bounds),
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
      paper: route.paper,
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

/// What the nodes below a pen draw, in their order ([SubtreeHolding.keyOf])
/// — the key of their one picture.
final class _Below {
  _Below(this.keys);

  final List<Object?> keys;

  @override
  bool operator ==(Object other) =>
      other is _Below && listEquals(other.keys, keys);

  @override
  int get hashCode => Object.hashAll(keys);
}
