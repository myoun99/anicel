import 'package:flutter/material.dart';

/// The app's small switch: the Material switch shrunk to a line's height.
///
/// ⛔ONE spelling of it. The export window's toggle rows wrote this shape in
/// place, and the import window's bake cells need the same one — two copies
/// of "a switch that fits a row" drift apart the first time either is
/// touched.
///
/// [width] bounds it where a column has to know its width in advance; left
/// null the switch keeps its own proportions at [height].
class CompactSwitch extends StatelessWidget {
  const CompactSwitch({
    super.key,
    required this.value,
    required this.onChanged,
    this.height = 24,
    this.width,
    this.switchKey,
  });

  final bool value;

  /// Null draws it disabled — which is also how a value the context decided
  /// is shown: on screen, and not the user's to change.
  final ValueChanged<bool>? onChanged;
  final double height;
  final double? width;

  /// Put on the inner [Switch], where the tests and the rows find it.
  final Key? switchKey;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: width,
    height: height,
    child: FittedBox(
      child: Switch(key: switchKey, value: value, onChanged: onChanged),
    ),
  );
}
