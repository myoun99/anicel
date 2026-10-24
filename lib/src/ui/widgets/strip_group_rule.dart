import 'package:flutter/material.dart';

/// The rule between a strip's groups — the same one the tool rail draws
/// between its history head and its tools, stood on its end.
///
/// [run] is the way the groups it parts are laid: across the top strip, a
/// line standing between them; down the canvas's brush pill (I-34), the
/// same line lying between its blend and its bars.
class StripGroupRule extends StatelessWidget {
  const StripGroupRule({super.key, this.run = Axis.horizontal});

  final Axis run;

  /// Its extent along [run].
  static const double width = 1;

  /// The room left on either side of it, between it and the groups it
  /// parts.
  static const double margin = 6;

  /// How far it stops short of the strip's edges, at each end.
  static const double _indent = 6;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.outlineVariant;
    return run == Axis.horizontal
        ? VerticalDivider(
            width: width,
            thickness: 1,
            indent: _indent,
            endIndent: _indent,
            color: color,
          )
        : Divider(
            height: width,
            thickness: 1,
            indent: _indent,
            endIndent: _indent,
            color: color,
          );
  }
}
