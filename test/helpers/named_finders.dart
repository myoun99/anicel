import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
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

/// The name a [Named] directly over [element] gives it, or null.
String? nameOf(Element element) {
  String? name;
  element.visitAncestorElements((parent) {
    if (parent.widget case Named(name: final given)) {
      name = given;
    }
    return false;
  });
  return name;
}
