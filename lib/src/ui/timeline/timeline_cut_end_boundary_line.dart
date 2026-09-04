import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// The line that says where the film stops, positioned on [axis].
///
/// ⛔TWO WIDGETS DRAW IT, ON PURPOSE. `one_cut_end_stack_test` tells the
/// STACK's overlay from the RULER's line by TYPE — that scan is what
/// caught the x-sheet growing its own copy of the four overlays — so
/// merging the classes would blind it. The NORI-SHIRO boundary is a third
/// widget on the same drawing — it differs by [color] alone. What was
/// duplicated is the drawing,
/// and only that is shared here.
Widget timelineCutEndBoundaryLine({
  required double left,
  required Axis axis,
  Color color = AppColors.danger,
}) {
  final line = IgnorePointer(
    child: DecoratedBox(decoration: BoxDecoration(color: color)),
  );
  if (axis == Axis.vertical) {
    return Positioned(top: left, left: 0, right: 0, height: 2, child: line);
  }
  return Positioned(left: left, top: 0, bottom: 0, width: 2, child: line);
}
