import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// Rolls the vertical rows [inRowsOf] stands in until [found] is built — a
/// rail builds no row past its viewport. By the rows' position, not by a
/// drag: a drag on the rows is their cells' own and never reaches the
/// Scrollable.
Future<void> rollRowsUntilBuilt(
  WidgetTester tester,
  Finder found, {
  required Finder inRowsOf,
}) async {
  final rows = tester
      .state<ScrollableState>(
        find
            .ancestor(
              of: inRowsOf,
              matching: find.byWidgetPredicate(
                (widget) =>
                    widget is Scrollable &&
                    axisDirectionToAxis(widget.axisDirection) == Axis.vertical,
              ),
            )
            .first,
      )
      .position;
  while (found.evaluate().isEmpty && rows.pixels < rows.maxScrollExtent) {
    rows.jumpTo(math.min(rows.pixels + 100, rows.maxScrollExtent));
    await tester.pump();
  }
}
