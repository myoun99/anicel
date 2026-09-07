/// A node that knows what it contains — the only thing a walk over a tree
/// needs, and the only thing every composite hierarchy in this app agrees
/// on.
///
/// ⛔`children` is ABSTRACT on purpose: a new node kind cannot compile
/// until it says what it holds, which is the same protection the sealed
/// switches give and the reason the recursion can be shared without
/// weakening them. What a leaf MEANS stays a switch at each reader.
abstract interface class TreeNode<N extends TreeNode<N>> {
  List<N> get children;
}

/// Every node under [roots], depth-first, parent before its children —
/// bottom → top for the composite trees, whose lists paint in order.
///
/// The RECURSION is what was written out three times (twice for the
/// signature and stack `layers`, once for the active-node lookup); the
/// exhaustive leaf dispatch stays at each call site, where it belongs.
Iterable<N> preorderNodes<N extends TreeNode<N>>(Iterable<N> roots) sync* {
  for (final node in roots) {
    yield node;
    yield* preorderNodes(node.children);
  }
}
