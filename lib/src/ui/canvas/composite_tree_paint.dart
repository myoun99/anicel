import 'dart:math' as math;
import 'dart:ui';

import '../../core/collection_equality.dart';
import '../../models/composite_tree.dart';
import '../../models/layer_effect.dart' show ResolvedLayerEffect;
import '../../models/layer_id.dart';
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
/// reads past (I-132-Q14 a). A row's own chain may read rows of the cut
/// ([CompositeReadsRows]): [paintRow] is handed what paints them in the
/// walk's space, null where it reads none.
typedef CompositeRoute<L> = ({
  void Function(Canvas canvas, L row, double rasterScale, RowPainter? rows)
  paintRow,
  Rect Function(L row) extentOf,
  LayerPlacement? Function(L row) placementOf,
  Rect? shownWithin,
  SubtreeHolding<L>? held,
  Rect paper,
});

/// Where a route holds the pictures of its nodes ([HeldSubtreeRasters]):
/// what a node draws ([keyOf] — null for one drawn afresh each time), the
/// row a pen draws on ([drawnOn]) — what lies below it held as one picture
/// or in cells, as [below] says ([_CompositeTreeWalk._belowThePen]) — and
/// whether a node over it drawn whole here is kept ([keeps]). [cells] is
/// what [BelowThePen.cellsOnly] draws: the cells under a rect, each read
/// as far past it as the frame's chains read ([readsPastOf]).
typedef SubtreeHolding<L> = ({
  HeldSubtreeRasters rasters,
  Object? Function(CompositeNode<L> node) keyOf,
  bool Function(L row) drawnOn,
  bool keeps,
  BelowThePen below,
  ({Rect over, double readsPast})? cells,
});

/// What a frame's drawing does with what lies below the row a pen draws
/// on ([_CompositeTreeWalk._belowThePen]).
///
/// 🚨★★★WHAT LIES BELOW A PEN IS HELD IN CELLS, WHERE A STEP NEEDS IT
/// (card a-scrub-prepares-every-frame-it-crosses, 유저 2026-10-28 「최대한
/// 근본적인 해결쪽으로」): its one picture was the frame's size, so a canvas
/// come to a frame laid ahead drew all of it again before a stroke could
/// cut from it — 🔬on the Surface Pro 11, S5_BA cut 352, a ruler scrub's
/// step reached the screen p50 200–267 ms with it and 49–50 ms without
/// it, and a stroke begun 0.05 s after one frame on drew its first ink p50
/// 109 ms against 25–33 ms once a stroke is going (10-28). A cell
/// ([belowCellSide]) is drawn the first time a step lands in it, and only
/// it; a frame come to draws none.
enum BelowThePen {
  /// Cut from its one picture where one is held, or is kept here
  /// ([SubtreeHolding.keeps]: the frame laid for a canvas that stands on
  /// it, which composes it anyway) — else from its cells, where each under
  /// the draw is held — else drawn in place.
  whole,

  /// Not drawn: what is held of it, whole or in cells, stays held as the
  /// frame is drawn ([HeldSubtreeRasters.holdOnly]) — the frame a canvas
  /// comes to, drawn for the nodes over its pen alone.
  asHeld,

  /// As [whole], each cell under the draw that is not held drawn first and
  /// kept ([cellsOnly]): a stroke's step.
  inCells,

  /// The cells under [SubtreeHolding.cells] that are not held drawn and
  /// kept, and nothing else drawn — [inCells]' first walk.
  cellsOnly,
}

/// The side, in canvas pixels, of a cell what lies below a pen is held in
/// ([BelowThePen]) — a step's patch no wider cuts from one to four.
///
/// ⛔Only at a raster pixel a canvas pixel, where a frame's picture is
/// drawn: a cell's edge at any other scale is no edge of the raster's grid
/// (`rectOutwardOnGrid` snaps it outward), and two cells side by side would
/// lay the pixel between them twice.
const int belowCellSide = 256;

/// The cells ([belowCellSide]) [rect] lies in, as one rect.
Rect belowCellsCovering(Rect rect) => rect.isEmpty
    ? Rect.zero
    : Rect.fromLTRB(
        (rect.left / belowCellSide).floorToDouble() * belowCellSide,
        (rect.top / belowCellSide).floorToDouble() * belowCellSide,
        (rect.right / belowCellSide).ceilToDouble() * belowCellSide,
        (rect.bottom / belowCellSide).ceilToDouble() * belowCellSide,
      );

/// The cells ([belowCellSide]) [rect] lies in, a row at a time.
Iterable<({int column, int row, Rect rect})> _cellsOver(Rect rect) sync* {
  if (rect.isEmpty) {
    return;
  }
  const side = belowCellSide;
  for (var row = (rect.top / side).floor(); row * side < rect.bottom; row++) {
    for (
      var column = (rect.left / side).floor();
      column * side < rect.right;
      column++
    ) {
      yield (
        column: column,
        row: row,
        rect: Rect.fromLTWH(
          (column * side).toDouble(),
          (row * side).toDouble(),
          side.toDouble(),
          side.toDouble(),
        ),
      );
    }
  }
}

/// How far past a pixel [nodes] read to draw it, at the most: the spreads
/// of the folders and adjustments over each row, added down the tree — a
/// pixel of a folder's picture reads its rows that far off, and a row's own
/// buffer grows by its own spread past what it is asked for.
double readsPastOf<L>(List<CompositeNode<L>> nodes, {required Rect paper}) {
  double spreadOf(List<ResolvedLayerEffect> effects) =>
      resolveCompositeEffectPlan(effects, paper: paper).outsetPixels;
  var most = 0.0;
  for (final node in nodes) {
    final reads = switch (node) {
      CompositeLeaf() || CompositeCelNumber() => 0.0,
      CompositeGroup(:final children, :final effects) ||
      CompositeAdjustment(
        :final children,
        :final effects,
      ) => spreadOf(effects) + readsPastOf(children, paper: paper),
      CompositeBackdropBlend(:final backdrop, :final source) => math.max(
        readsPastOf(backdrop, paper: paper),
        readsPastOf([source], paper: paper),
      ),
      CompositeClip(:final base, :final scope) => math.max(
        readsPastOf([base], paper: paper),
        readsPastOf(scope, paper: paper),
      ),
      CompositeOpaque(:final of) => readsPastOf([of], paper: paper),
      // The rows it reads are drawn over all its raster reads
      // ([_CompositeTreeWalk._painterOf]): it reads as far as it does.
      CompositeReadsRows(:final node) => readsPastOf([node], paper: paper),
    };
    most = math.max(most, reads);
  }
  return most;
}

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
}) {
  final walk = _CompositeTreeWalk(route);
  switch (route.held?.below) {
    case BelowThePen.asHeld || BelowThePen.cellsOnly:
      walk._alongThePen(canvas, nodes, rasterScale, within);
    case _:
      walk.paint(canvas, nodes, rasterScale, within);
  }
}

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
    final (:below, :over) = _atThePen(nodes);
    _belowThePen(canvas, below, rasterScale, within);
    for (final node in over) {
      _paintNode(canvas, node, rasterScale, within);
    }
  }

  /// [nodes] walked as [paint] walks them for what a frame holds alone
  /// ([BelowThePen.asHeld], [BelowThePen.cellsOnly]): what lies below the
  /// pen as [_belowThePen] has it, the nodes that hold the pen entered
  /// ([_intoThePen]) — and the nodes over it drawn to be held, where the
  /// frame holds them ([BelowThePen.asHeld]); there is no cell of them.
  void _alongThePen(
    Canvas canvas,
    List<CompositeNode<L>> nodes,
    double rasterScale,
    Rect within,
  ) {
    final (:below, :over) = _atThePen(nodes);
    _belowThePen(canvas, below, rasterScale, within);
    for (final node in over) {
      if (_holdsThePen(node)) {
        _intoThePen(canvas, node, rasterScale, within);
      } else if (route.held?.below == BelowThePen.asHeld) {
        _paintNode(canvas, node, rasterScale, within);
      }
    }
  }

  /// [nodes] parted where the pen is: those laid before the one it is in
  /// — all below it — and the rest; none below where no node holds it.
  ({List<CompositeNode<L>> below, Iterable<CompositeNode<L>> over})
  _atThePen(List<CompositeNode<L>> nodes) {
    final pen = math.max(nodes.indexWhere(_holdsThePen), 0);
    return (below: nodes.sublist(0, pen), over: nodes.skip(pen));
  }

  /// [node], which holds the row a pen draws on, entered as [_alongThePen]
  /// walks a list — and not drawn as itself: no step cuts from a picture
  /// of it ([_holdOf]). Each list in it is read [within] what the node
  /// reads it in, as [_paintNode] draws it.
  void _intoThePen(
    Canvas canvas,
    CompositeNode<L> node,
    double rasterScale,
    Rect within,
  ) {
    switch (node) {
      case CompositeLeaf() || CompositeCelNumber():
        return;
      case final CompositeGroup<L> group:
        _alongThePen(
          canvas,
          group.children,
          rasterScale,
          _groupRectOf(
            group,
            within,
            resolveCompositeEffectPlan(group.effects, paper: route.paper),
          ),
        );
      case final CompositeAdjustment<L> adjustment:
        _alongThePen(
          canvas,
          adjustment.children,
          rasterScale,
          _adjustmentPassOf(adjustment, within).bufferBounds,
        );
      case CompositeBackdropBlend(:final backdrop, :final source):
        final bounds = _bufferBoundsOf(node, within);
        // Under a row a pen draws on, its backdrop is all below the pen
        // ([_backdropBlend]).
        if (_holdsThePen(source)) {
          _belowThePen(canvas, backdrop, rasterScale, bounds);
          _intoThePen(canvas, source, rasterScale, bounds);
        } else {
          _alongThePen(canvas, backdrop, rasterScale, bounds);
          _alongThePen(canvas, [source], rasterScale, bounds);
        }
      case CompositeClip(:final base, :final scope):
        final bounds = _bufferBoundsOf(node, within);
        _alongThePen(canvas, [base], rasterScale, bounds);
        _alongThePen(canvas, scope, rasterScale, bounds);
      case CompositeOpaque(:final of):
        _alongThePen(canvas, [of], rasterScale, within);
      // A pen on a row it reads alone is no pen in it: it is drawn afresh,
      // as what it reads changes.
      case CompositeReadsRows(:final node):
        if (_holdsThePen(node)) {
          _intoThePen(canvas, node, rasterScale, within);
        }
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
        route.paintRow(canvas, payload, rasterScale, null);
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
      case CompositeReadsRows(node: final reader, :final rows):
        _reading(
          canvas,
          reader,
          rasterScale,
          within,
          rows: _painterOf(rows),
          heldAs: node,
        );
    }
  }

  /// [reader] — a row, a folder's buffer or an adjustment's scope — its
  /// own steps reading the rows [rows] paint, its picture held as
  /// [heldAs]'s: what it draws is the rows it reads too.
  void _reading(
    Canvas canvas,
    CompositeNode<L> reader,
    double rasterScale,
    Rect within, {
    required RowPainter rows,
    required CompositeNode<L> heldAs,
  }) {
    switch (reader) {
      case CompositeLeaf(:final payload):
        route.paintRow(canvas, payload, rasterScale, rows);
      case final CompositeGroup<L> group:
        _group(canvas, group, rasterScale, within, rows: rows, heldAs: heldAs);
      case final CompositeAdjustment<L> adjustment:
        _adjustment(
          canvas,
          adjustment,
          rasterScale,
          within,
          rows: rows,
          heldAs: heldAs,
        );
      case _:
        throw StateError(
          'only a row, a folder or an adjustment reads rows, not $reader',
        );
    }
  }

  /// What paints [rows] in this walk's space, where they show by
  /// themselves (🗣️I-132-Q21 a) — each drawn afresh, and kept nowhere: a
  /// raster a step reads is no picture of the frame — over all the raster
  /// that reads them: a folder's reaches past what reads the folder.
  RowPainter _painterOf(Map<LayerId, List<CompositeNode<L>>> rows) =>
      (into, row, scale) {
        final drawn = rows[row];
        if (drawn == null) {
          return false;
        }
        _CompositeTreeWalk(
          route,
          keeps: false,
        ).paint(into, drawn, scale, into.getLocalClipBounds());
        return true;
      };

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
  ///
  /// ↩️HELD IN CELLS TOO ([BelowThePen]): each the same pixels as the one
  /// picture holds there ([_fillCells]), and a draw cut from them where it
  /// is not ([_cutFromCells]) — a frame a canvas came to drew its one
  /// picture whole for the steps to come until 2026-10-28.
  void _belowThePen(
    Canvas canvas,
    List<CompositeNode<L>> nodes,
    double rasterScale,
    Rect within,
  ) {
    final held = route.held;
    final keys = [for (final node in nodes) held?.keyOf(node)];
    final bounds = within.intersect(canvas.getLocalClipBounds());
    if (held == null || !nodes.any(_isAPicture) || keys.contains(null)) {
      // There is no cell of what is drawn in place.
      if (held?.below != BelowThePen.cellsOnly) {
        _inPlace(canvas, nodes, rasterScale, within);
      }
      return;
    }
    final run = (
      nodes: nodes,
      key: _Below(keys),
      rasterScale: rasterScale,
      within: within,
    );
    final whole = SubtreeHold(
      held.rasters,
      key: run.key,
      keeps:
          held.keeps && keeps && nodes.every((node) => _isWhole(node, within)),
      below: true,
    );
    switch (held.below) {
      case BelowThePen.asHeld:
        held.rasters.keepHeldWhere(
          (key) => key == run.key || key is _BelowCell && key.below == run.key,
        );
      case BelowThePen.cellsOnly:
        final under = held.cells!.over.intersect(bounds);
        if (!whole.finds(under, rasterScale)) {
          _fillCells(canvas, run, under);
        }
      case BelowThePen.whole || BelowThePen.inCells:
        if (whole.findsOrKeeps(bounds, rasterScale)) {
          _cutFrom(canvas, run, bounds, whole);
        } else if (!_cutFromCells(canvas, run, bounds)) {
          _inPlace(canvas, nodes, rasterScale, within);
        }
    }
  }

  /// [nodes] drawn in place, each node held as it was ([_holdOf]).
  void _inPlace(
    Canvas canvas,
    List<CompositeNode<L>> nodes,
    double rasterScale,
    Rect within,
  ) {
    for (final node in nodes) {
      _paintNode(canvas, node, rasterScale, within);
    }
  }

  /// [run]'s picture over [bounds], cut from [hold] — drawn there first
  /// where it is not held.
  void _cutFrom(Canvas canvas, _Run<L> run, Rect bounds, SubtreeHold hold) =>
      drawSubtreeAsImage(
        canvas: canvas,
        bounds: bounds,
        rasterScale: run.rasterScale,
        paper: route.paper,
        paintSubtree: _ontoNothing(run.nodes, run.within),
        compose: (blit) => blit(Paint()),
        held: hold,
      );

  /// [nodes] laid onto nothing, [within] what reads them — as their one
  /// picture lays them: none of them is kept on its own in it.
  void Function(Canvas into, double scale) _ontoNothing(
    List<CompositeNode<L>> nodes,
    Rect within,
  ) {
    final inside = _CompositeTreeWalk(route, keeps: false);
    return (into, scale) {
      for (final node in nodes) {
        inside._paintNode(into, node, scale, within);
      }
    };
  }

  /// Draws and keeps each cell under [under] of [run]'s picture that is not
  /// held, where it can be kept: [run] laid onto nothing, as its one
  /// picture is, within what reads it and as far past the cell as the
  /// frame's chains read ([SubtreeHolding.cells]) — the walk that draws the
  /// cells stands in the world that far past them too
  /// (`_LayerStackPaintPass`) — so it is the pixels its one picture holds
  /// in the cell.
  void _fillCells(Canvas canvas, _Run<L> run, Rect under) {
    if (run.rasterScale != 1) {
      return;
    }
    final held = route.held!;
    for (final (:column, :row, :rect) in _cellsOver(under)) {
      final bounds = rect.intersect(run.within);
      final hold = SubtreeHold(
        held.rasters,
        key: _BelowCell(run.key, column, row),
        keeps: true,
        below: true,
      );
      if (!hold.keepsAnew(bounds, run.rasterScale)) {
        continue;
      }
      drawSubtreeAsImage(
        canvas: canvas,
        bounds: bounds,
        rasterScale: run.rasterScale,
        paper: route.paper,
        paintSubtree: _ontoNothing(
          run.nodes,
          rect.inflate(held.cells!.readsPast).intersect(run.within),
        ),
        // Kept, and laid nowhere: the walk that draws the cells draws
        // nothing else.
        compose: (_) {},
        held: hold,
      );
    }
  }

  /// [run]'s picture under [bounds] cut from its cells ([_fillCells]) where
  /// each is held; false, and nothing drawn, where one is not.
  bool _cutFromCells(Canvas canvas, _Run<L> run, Rect bounds) {
    if (run.rasterScale != 1) {
      return false;
    }
    final pieces = [
      for (final (:column, :row, :rect) in _cellsOver(bounds))
        (
          bounds: rect.intersect(bounds),
          hold: SubtreeHold(
            route.held!.rasters,
            key: _BelowCell(run.key, column, row),
            keeps: false,
            below: true,
          ),
        ),
    ];
    if (pieces.isEmpty ||
        !pieces.every(
          (piece) => piece.hold.finds(piece.bounds, run.rasterScale),
        )) {
      return false;
    }
    for (final piece in pieces) {
      _cutFrom(canvas, run, piece.bounds, piece.hold);
    }
    return true;
  }

  /// Whether [node] is drawn as a picture of its own — a buffer the walk
  /// rasters — rather than straight onto what it lies on.
  static bool _isAPicture(CompositeNode<Object?> node) => switch (node) {
    CompositeLeaf() || CompositeCelNumber() => false,
    CompositeReadsRows(:final node) => _isAPicture(node),
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
    Rect within, {
    RowPainter? rows,
    CompositeNode<L>? heldAs,
  }) {
    final CompositeGroup<L>(:children, :opacity, :blendMode, :effects) = node;
    // R27 #29: one buffer for the group, one blend on it — and
    // because the ACTIVE layer is a node in here, a stroke drawn
    // inside a blended folder finally reads the way it will play
    // back. R6: the folder's effect chain lands on the same buffer, in
    // CANVAS units (the camera projection is a canvas transform, so the
    // engine maps a blur's sigma through the CTM for us).
    final groupPlan = resolveCompositeEffectPlan(
      effects,
      paper: route.paper,
    );
    final groupPaint = layerCompositePaint(
      opacity: opacity,
      blendMode: blendMode,
      effects: groupPlan.finalPaint,
    );
    final groupRect = _groupRectOf(node, within, groupPlan);
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
      held: _holdOf(heldAs ?? node, within),
      cell: rasterCellFor(groupPlan.outsetPixels),
      rows: rows,
    );
  }

  /// The rect [node]'s buffer covers — what of it lies [within] what reads
  /// it, grown by the spread of its chain ([plan]).
  Rect _groupRectOf(
    CompositeGroup<L> node,
    Rect within,
    CompositeEffectPlan plan,
  ) {
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
    return effectBufferBounds(contentRect, plan.outsetPixels);
  }

  /// An adjustment scope: the rows under it buffered and graded as one.
  void _adjustment(
    Canvas canvas,
    CompositeAdjustment<L> node,
    double rasterScale,
    Rect within, {
    RowPainter? rows,
    CompositeNode<L>? heldAs,
  }) {
    final children = node.children;
    final pass = _adjustmentPassOf(node, within);
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
      held: _holdOf(heldAs ?? node, within),
      cell: rasterCellFor(pass.outsetPixels),
      rows: rows,
    );
  }

  /// How [node]'s scope is buffered and graded, what of it lies [within]
  /// what reads it.
  ///
  /// R6b: the scope into one buffer, the row's chain onto it — which is
  /// what lets a stroke drawn UNDER an adjustment read through the grade
  /// while you draw it.
  AdjustmentScopePass _adjustmentPassOf(
    CompositeAdjustment<L> node,
    Rect within,
  ) => resolveAdjustmentScopePass(
    bounds: _bufferBoundsOf(node, within),
    effects: node.effects,
    mix: node.mix,
    paper: route.paper,
  );

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

/// What lies below a pen in one list ([_CompositeTreeWalk._belowThePen]):
/// its [nodes], laid onto nothing at [rasterScale] [within] what reads
/// them, and what they draw ([key]).
typedef _Run<L> = ({
  List<CompositeNode<L>> nodes,
  _Below key,
  double rasterScale,
  Rect within,
});

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

/// One cell ([belowCellSide]) of what the nodes below a pen draw ([below])
/// — the key of its picture.
final class _BelowCell {
  _BelowCell(this.below, this.column, this.row);

  final _Below below;
  final int column;
  final int row;

  @override
  bool operator ==(Object other) =>
      other is _BelowCell &&
      other.below == below &&
      other.column == column &&
      other.row == row;

  @override
  int get hashCode => Object.hash(below, column, row);
}
