import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import 'still_raster.dart' show TickSceneLayer;

/// Where what a tick moves is laid out, painted and described — ALONE.
///
/// 🚨I-22 ③: a tick has to be kept in on both halves, and each half leaks
/// its own way. PAINT: without a boundary the move repaints the region
/// around it (R12-⑥ kept the storyboard's strips out of the playhead's way
/// with one). LAYOUT is Flutter's: a rebuild inside a `LayoutBuilder`'s
/// subtree lays THAT LayoutBuilder out again — it owns the rebuild's build
/// scope — and a layout ends by asking for a paint of everything up to the
/// nearest boundary above it. So a tick rebuilt under a big LayoutBuilder
/// relaid it out and repainted what it holds on every playback frame, a
/// boundary of the tick's own notwithstanding. Measured at the ten-minute
/// zoom (09-27): the transport's readouts relaid out the workspace floor and
/// repainted the PAGE; the frame counters, the dock's panel scroller; the
/// timeline's cursor layer, its frame grid area — and the storyboard's
/// playhead tint and standing ring, its body. This LayoutBuilder takes the
/// rebuild's scope for itself.
///
/// 🚨SEMANTICS IS THE THIRD HALF (2026-10-10): a layout ends by marking its
/// semantics, and that mark climbs to the nearest semantics boundary, whose
/// share of the tree is walked again down to what changed — and the nodes
/// nearest under what was laid out are put together again (I-57, 10-14:
/// [LaidOutAlone]). With none here a playback step
/// re-walked four of them for a few moved nodes — the timeline panel's
/// scroll view, the frame grid's, the canvas panel and the bottom dock,
/// over a thousand render objects (the real app, accessibility tree on as
/// this machine's release build runs it). The layer is a boundary of its
/// own, so a tick re-walks the layer; it reads as one group to a screen
/// reader, which is what it is — the dock regions' law (2026-09-26).
///
/// ⚠️It keeps the layout in only where its size is decided from above —
/// TIGHT constraints: a `Positioned.fill`, a box sized on both axes. Handed
/// loose ones it lays its parent out again on every tick, and the boundary
/// holds nothing back.
///
/// 🚨WHAT STANDS BESIDE A TICK ON THE LAYER IS PAINTED WITH IT (the third
/// time, 10-11 — a tab strip around its level meter, the timeline's command
/// bar around its counter): a tick lays out and paints the WHOLE layer. So
/// where what ticks has a size of its own, the layer holds it and nothing
/// more (the meter in its seat); where its size moves its row (the
/// counter), the heavy things beside it stand on boundaries of their own.
/// 🔬A steady run painted 90 + 52 + 78 render objects of unchanging chrome
/// on every frame played. Boundaries of BOTH kinds (10-12): a tick that
/// moves its row lays the row out, and the layout marks the layer's
/// semantics — the counter's bar re-walked 50 render objects a frame for
/// the zoom beside it, painted alone since 10-11 and still described with
/// the counter.
///
/// 🚨A LAYER BUILT AGAIN ROUND THE SAME CHILD IS THE SAME LAYER (I-57,
/// 10-13). Its LayoutBuilder was made anew on every build, and a
/// LayoutBuilder handed a new builder runs it again in layout — which lays
/// the layer out and so paints and describes it again: everything the layer
/// exists to keep in, spent on a child that had not changed. A host that
/// rebuilt for anything rebuilt every tick layer under it that way (the
/// timeline: a notify that changed nothing laid out 27 LayoutBuilders and
/// repainted 17 boundaries, measured). So the layer is built once per
/// child and handed back whole while the child is the same widget.
class TickLayer extends StatefulWidget {
  const TickLayer({super.key, required this.child}) : _kind = _Kind.built;

  /// A layer whose ticks are HEARD — what moves on it listens to its tick
  /// and lays out or paints itself (a canvas tool cursor), so nothing is
  /// built for one — laid out, painted and described alone as a built
  /// tick's is, with no build scope of its own. A frame panel's command bar
  /// stands on one too, out of its host's repaints (F-463).
  ///
  /// 🚨A build scope is what a built tick needs and what a heard one pays
  /// for (I-57, 10-14). The command bar stood on a layer with one for its
  /// counter, and the host handed it a toolbar made anew on every notify:
  /// its seat was built in the layer's scope, and the bar was laid out and
  /// painted again (🔬24 render objects) for a toolbar handing back the
  /// buttons it had. Without a scope of its own the seat is built in its
  /// host's, and a toolbar handed back as it was touches nothing. ↩️The
  /// tick the bar heard was its counter's line (`TickText`), until F-463
  /// took the counter off.
  const TickLayer.heard({super.key, required this.child})
    : _kind = _Kind.heard;

  /// A panel's HOST on a layer of its own — laid out, painted and described
  /// alone, as a tick is, for the same reasons — that a still region keeps
  /// in its image like the rest of the region: it changes on its panel's
  /// edits, not on a tick, and what ticks INSIDE it is what the region
  /// draws live between its strata ([TickSceneLayer]).
  ///
  /// 🔬Taken for a tick, the timeline's host — the whole panel, 808×287 —
  /// was the region's one tick, every tick of the panel inside it out of
  /// sight (10-12). A host changed by its panel's edits would read as a
  /// tick moving, and the whole panel would be drawn live.
  ///
  /// 🚨A HOST BUILT AGAIN IS NOT ITS PANEL PAINTED AGAIN (I-57, 10-14). A
  /// host is built again on every notify of what it listens to, and that
  /// rebuild is this layer's LayoutBuilder's to run: it lays the layer out,
  /// and a layout paints everything up to the boundary above it — the
  /// whole panel, for a notify that changed nothing in it (the timesheet
  /// repainted its pill, swatches and panbars on every cut crossed,
  /// measured). So the panel stands on a layer of its own INSIDE the
  /// host's: the host's layer holds the LayoutBuilder alone, and the
  /// panel's is painted again for what changed in it — and on a semantics
  /// node of its own, which a layout of the host rebuilds alone
  /// ([LaidOutAlone] has why).
  const TickLayer.host({super.key, required this.child}) : _kind = _Kind.host;

  final Widget child;
  final _Kind _kind;

  @override
  State<TickLayer> createState() => _TickLayerState();
}

/// What a [TickLayer] holds: a tick that is built, one that is heard, or a
/// panel's host.
enum _Kind { built, heard, host }

class _TickLayerState extends State<TickLayer> {
  /// The layer as built round the child it holds.
  late Widget _built = _layer();

  @override
  void didUpdateWidget(covariant TickLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.child, widget.child) ||
        oldWidget._kind != widget._kind) {
      _built = _layer();
    }
  }

  Widget _layer() {
    final child = widget.child;
    return Semantics(
      container: true,
      child: switch (widget._kind) {
        _Kind.built => _TickBoundary(child: _laidOutAlone((_, _) => child)),
        _Kind.heard => _TickBoundary(child: child),
        _Kind.host => LaidOutAlone(builder: (_, _) => child),
      },
    );
  }

  @override
  Widget build(BuildContext context) => _built;
}

/// What [build] makes under a LayoutBuilder of its own — the scope a build
/// inside runs in — that keeps its layout in, as only tight constraints
/// let it.
Widget _laidOutAlone(LayoutWidgetBuilder build) => LayoutBuilder(
  builder: (context, constraints) {
    assert(
      constraints.isTight,
      'What is laid out alone keeps its layout in only under tight '
      'constraints (got $constraints).',
    );
    return build(context, constraints);
  },
);

/// What a LayoutBuilder makes of its size, laid out, painted and described
/// ALONE when its host builds it again — a panel's host ([TickLayer.host]),
/// a grid's body.
///
/// A host that builds again runs this LayoutBuilder again: its layout stays
/// in, as a tick layer's does (tight constraints), and it paints a layer
/// that holds nothing but [builder]'s, which is painted again only for
/// what changed in it.
///
/// 🚨AND A NODE OF ITS OWN (I-57, 10-14). A layout drops the semantics
/// geometry of every node nearest under what it laid out, and the flush
/// puts each of those together again (Flutter 3.47.4, `flushSemantics`) —
/// the walk follows only what changed, the rebuilds do not. So a host laid
/// out for a notify that changed nothing in it rebuilt its panel's top
/// nodes, and a grid's body its rows': 🔬58 nodes of a crossing in a test
/// app, 26 of them the host's. Under a node of its own the layout drops
/// that node alone, and what [builder] made keeps its nodes — 🔬a crossing
/// in a test app rebuilt 58, and 34 with the host's layout dropping its
/// own node alone.
/// ↩️(10-14, the same day) the host's node was taken away for sparing no
/// walk — the pin counted WALKS, and never saw a node rebuilt.
class LaidOutAlone extends StatelessWidget {
  const LaidOutAlone({super.key, required this.builder});

  final LayoutWidgetBuilder builder;

  @override
  Widget build(BuildContext context) => RepaintBoundary(
    child: _laidOutAlone(
      (context, constraints) => Semantics(
        container: true,
        child: RepaintBoundary(child: builder(context, constraints)),
      ),
    ),
  );
}

/// A tick's repaint boundary, whose layer a still region draws live
/// between its strata rather than in them ([TickSceneLayer]) — so a region
/// holding a tick stays still while it moves.
class _TickBoundary extends SingleChildRenderObjectWidget {
  const _TickBoundary({required super.child});

  @override
  RenderTickBoundary createRenderObject(BuildContext context) =>
      RenderTickBoundary();
}

class RenderTickBoundary extends RenderRepaintBoundary {
  @override
  OffsetLayer updateCompositedLayer({
    required covariant OffsetLayer? oldLayer,
  }) => (oldLayer is TickSceneLayer ? oldLayer : TickSceneLayer())
    ..size = size;
}

/// The marks a tick moves over a [Stack] — each a `Positioned` of that stack's
/// own coordinates — on one [TickLayer] filling it.
///
/// 🚨F-244: a drag step is a tick. The cut's end and its のりしろ ride every
/// step of every drag, on the ruler, the sheet's rail and the body alike;
/// rebuilt bare in the grid's layout scope, a step laid it out again and
/// repainted the panel around them. The fill is what makes the layer's
/// constraints tight, so it keeps the layout in.
class TickOverlay extends StatelessWidget {
  const TickOverlay({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Positioned.fill(
    child: TickLayer(child: Stack(children: children)),
  );
}
