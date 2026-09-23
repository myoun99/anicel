import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/widgets/boolean_dot.dart';

/// Reads the app's one boolean inside whatever a test's finder holds — a
/// settings row by its tile key, a flyout toggle, a table cell, a
/// [BooleanDotButton] by its key.
///
/// A row keeps no value of its own; the dot it draws is where the value, the
/// enabled look and the pick-one question can be read. The Material switches
/// these rows used to wrap carried them on the tile itself, so every test
/// that asked 「is it on」 read a `SwitchListTile` — this is that read, for
/// the control that replaced it (guide-sym ⑥⑧).
extension BooleanDotProbe on WidgetTester {
  BooleanDot booleanDotIn(Finder scope) => widget<BooleanDot>(
    find.descendant(of: scope, matching: find.byType(BooleanDot)),
  );
}
