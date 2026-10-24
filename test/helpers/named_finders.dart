import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/ui/timeline/berth_row.dart';
import 'package:anicel/src/ui/timeline/timeline_frame_cells_row.dart';
import 'package:anicel/src/ui/timeline/timeline_layer_controls_row.dart';
import 'package:anicel/src/ui/widgets/named.dart';

/// `find.byKey` for a handle that is a NAME ([Named]) — a handle the tree
/// does not reconcile by.
extension NamedFinders on CommonFinders {
  /// The widget [Named] calls [name]: its child, the widget the key used
  /// to sit on — so a test holds what it held.
  Finder named(String name, {bool skipOffstage = true}) => namedWhere(
    (given) => given == name,
    description: 'the widget named "$name"',
    skipOffstage: skipOffstage,
  );

  /// Every widget whose name passes [test] — a family of rows, by the
  /// start of their names.
  Finder namedWhere(
    bool Function(String name) test, {
    String description = 'the widgets named as asked',
    bool skipOffstage = true,
  }) => byElementPredicate(
    (element) => switch (nameOf(element)) {
      final name? => test(name),
      null => false,
    },
    description: description,
    skipOffstage: skipOffstage,
  );
}

/// The name [element]'s widget carries itself ([NamesItself]), else the
/// name a [Named] directly over it gives it, or null.
///
/// A KEPT row's names are spelled with the layer it was BUILT for — a
/// controls row's ([BerthRow], I-57 ㉣) and a cells row's (kept by its
/// shape, I-57) — and a cut switch may have stood it for another since, so
/// a name is read as the row stands: the built-for id that ends it is read
/// as the id of the layer the row stands for now. Every name in a row that
/// carries its layer ENDS with the layer's id
/// (`a_kept_row_acts_on_the_layer_it_stands_for_test.dart` holds that).
String? nameOf(Element element) {
  if (element.widget case NamesItself(name: final given?)) {
    return _asTheRowStands(element, given);
  }
  String? name;
  element.visitAncestorElements((parent) {
    if (parent.widget case Named(name: final given?)) {
      name = _asTheRowStands(parent, given);
    }
    return false;
  });
  return name;
}

String _asTheRowStands(Element named, String name) {
  final now = BerthRow.at(named)?.id.value;
  if (now == null) {
    return name;
  }
  final builtFor = _keptRowAround(named)?.id.value;
  if (builtFor == null || builtFor == now || !name.endsWith('-$builtFor')) {
    return name;
  }
  return '${name.substring(0, name.length - builtFor.length)}$now';
}

/// The layer the kept row around [named] was built for.
Layer? _keptRowAround(Element named) =>
    named.findAncestorWidgetOfExactType<TimelineLayerControlsRow>()?.layer ??
    named.findAncestorWidgetOfExactType<TimelineFrameCellsRow>()?.layer;
