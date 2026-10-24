import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/ui/widgets/tick_layer.dart';

/// Every repaint boundary under [root] waiting to repaint in the scene that
/// is not one of [allowed] or inside one — what a tick, a scrub or a page
/// turn repaints besides the layers it is allowed to.
///
/// Only a boundary IN the scene counts: one under an `Offstage` (a folded
/// panel's grid) waits forever and costs nothing.
///
/// ONE walk for every pin that asks it (the playback tick's, the scrub's,
/// the folded row's page turn): each spelled it on its own until the third
/// arrived. What differs is the question — where to look and what may
/// repaint — and that is what a caller hands in.
Set<RenderObject> repaintStrays(
  RenderObject root, {
  required Set<RenderObject> allowed,
}) {
  bool inAllowed(RenderObject boundary) {
    for (RenderObject? up = boundary; up != null; up = up.parent) {
      if (allowed.contains(up)) {
        return true;
      }
    }
    return false;
  }

  final found = <RenderObject>{};
  void walk(RenderObject node) {
    if (node.isRepaintBoundary &&
        node.debugNeedsPaint &&
        (node.debugLayer?.attached ?? false) &&
        !inAllowed(node)) {
      found.add(node);
    }
    node.visitChildren(walk);
  }

  walk(root);
  return found;
}

/// What a playback tick may repaint anywhere on screen: every tick layer's
/// boundary ([tickBoundariesUnder]) and the canvas, whose picture changing
/// IS the tick.
Set<RenderObject> tickLayersAndCanvas(WidgetTester tester) => {
  for (final view in tester.binding.renderViews) ...tickBoundariesUnder(view),
  ..._canvas(tester),
};

/// What an EDIT may repaint: the tick layers, the canvas — and the panels'
/// hosts ([TickLayer.host]), which stand on layers of their own to be
/// painted again for their panels' edits.
Set<RenderObject> panelsTicksAndCanvas(WidgetTester tester) => {
  for (final layer in find.byType(TickLayer).evaluate()) layer.renderObject!,
  ..._canvas(tester),
};

/// What a gesture repaints under [root] besides its ticks, by name — the
/// strays ([repaintStrays]) of a region whose tick boundaries
/// ([tickBoundariesUnder]) alone may repaint.
///
/// ONE question for the pins that ask a region (a scrub's, a sheet's pan,
/// a carried block's): each built that allow list on its own, and each
/// built it of every [TickLayer] — a panel's host among them (10-24).
List<String> tickStraysUnder(RenderObject root) => [
  for (final stray in repaintStrays(root, allowed: tickBoundariesUnder(root)))
    nameOfBoundary(stray),
];

/// The boundaries a tick is laid out and painted on under [root] — every
/// [RenderTickBoundary].
///
/// 🚨⛔Not every [TickLayer]: a panel's host stands on one too
/// ([TickLayer.host]), whose boundary is the panel's, and a pin that let it
/// repaint let everything in every panel repaint. 🪦Asked that way, the
/// drag-step pin read nothing while a cut-end trim on the user's cut laid
/// out and repainted the timeline's whole rows viewport at every step
/// (F-446, 10-24).
Set<RenderObject> tickBoundariesUnder(RenderObject root) {
  final found = <RenderObject>{};
  void walk(RenderObject node) {
    if (node is RenderTickBoundary) {
      found.add(node);
    }
    node.visitChildren(walk);
  }

  walk(root);
  return found;
}

Iterable<RenderObject> _canvas(WidgetTester tester) => {
  for (final canvas in find
      .byKey(const ValueKey<String>('canvas-editor-panel-content'))
      .evaluate())
    tester.renderObject(
      find
          .ancestor(
            of: find.byElementPredicate((e) => identical(e, canvas)),
            matching: find.byType(RepaintBoundary),
          )
          .first,
    ),
};

/// A stray named by the widgets that made it — its type and the creator
/// chain above it, [depth] deep.
String nameOfBoundary(RenderObject node, {int depth = 24}) {
  final creator = node.debugCreator;
  return '${node.runtimeType} <- '
      '${creator is DebugCreator ? creator.element.debugGetCreatorChain(depth) : '?'}';
}
