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

/// What a playback tick may repaint anywhere on screen: every [TickLayer]
/// (a tick layer's first render object is its boundary) and the canvas,
/// whose picture changing IS the tick.
Set<RenderObject> tickLayersAndCanvas(WidgetTester tester) => {
  for (final layer in find.byType(TickLayer).evaluate()) layer.renderObject!,
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
