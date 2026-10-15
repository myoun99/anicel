import 'package:flutter/widgets.dart';

/// THE NAME a widget is found by — a test's handle, the probe's — kept
/// apart from its KEY, which is what the element tree reconciles by.
///
/// 🚨I-57 (10-13, measured on the user's project): a timeline row and
/// everything in it was KEYED by its layer, so a cut switch — every row a
/// layer of the new cut — threw away every element the window held and
/// built them again: twelve row roots, 1577 elements, on every crossing a
/// scrub or a play made. Those keys did no key's work. Nothing reorders
/// among a row's single children; the strings were there so a test could
/// say which row it meant, and the tree took them as identity. A name is
/// the same handle without the identity: the tree keeps a row's elements
/// while the row shows another layer, and the test still says which.
///
/// The name belongs to [child]: a finder for it finds the child, as
/// `find.byKey` found the keyed widget itself — so a name replaces a key
/// without the test changing what it holds.
///
/// ⛔Nothing in lib reads a name. A decision that needs to know which
/// widget is which reads the model, never this.
class Named extends StatelessWidget {
  const Named(this.name, {super.key, required this.child});

  /// What a finder calls [child]. Null names nothing — a name that comes
  /// and goes (the selected row's) changes nothing in the tree's shape.
  final String? name;

  final Widget child;

  @override
  Widget build(BuildContext context) => child;
}
