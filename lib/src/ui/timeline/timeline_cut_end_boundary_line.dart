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
///
/// 🚨In a layer of its own (10-27, F-244-drag-start ③): painted into the
/// layer of the overlay it stands on — the whole grid — its picture's
/// bounds were the grid's, and over the moving cursor of a drag a still
/// dock region kept a part of its image the size of the rows for a line
/// two pixels wide (`StillRaster`).
Widget timelineCutEndBoundaryLine({
  required double left,
  required Axis axis,
  Color? color,
}) {
  final line = IgnorePointer(
    child: RepaintBoundary(
      child: DecoratedBox(
        decoration: BoxDecoration(color: color ?? AppColors.danger),
      ),
    ),
  );
  if (axis == Axis.vertical) {
    return Positioned(top: left, left: 0, right: 0, height: 2, child: line);
  }
  return Positioned(left: left, top: 0, bottom: 0, width: 2, child: line);
}
