import 'package:flutter/material.dart';

/// A draggable divider between two areas that share an extent.
///
/// It began as the workspace dock's edge grip and is now the app's ONE
/// splitter: the layer rails use it too (the rail-window round), which is
/// why it lives beside the other shared widgets instead of inside the dock
/// host. [onDragDelta] receives the raw pointer delta along the splitter's
/// axis; the owner applies the sign for which side grows.
class DockEdgeSplitter extends StatelessWidget {
  const DockEdgeSplitter({
    super.key,
    required this.axis,
    required this.onDragDelta,
    this.onDoubleTap,
    this.tooltip,
  });

  /// [Axis.vertical] separates side-by-side areas (drag left-right);
  /// [Axis.horizontal] separates stacked ones (drag up-down).
  final Axis axis;
  final ValueChanged<double> onDragDelta;

  /// Double-click action, when the owner has a meaningful "back to the
  /// natural size" (the rails do; the docks do not).
  final VoidCallback? onDoubleTap;

  final String? tooltip;

  static const double thickness = 5;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final vertical = axis == Axis.vertical;
    Widget grip = MouseRegion(
      cursor: vertical
          ? SystemMouseCursors.resizeLeftRight
          : SystemMouseCursors.resizeUpDown,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onDoubleTap: onDoubleTap,
        onHorizontalDragUpdate: vertical
            ? (details) => onDragDelta(details.delta.dx)
            : null,
        onVerticalDragUpdate: vertical
            ? null
            : (details) => onDragDelta(details.delta.dy),
        child: Container(
          width: vertical ? thickness : null,
          height: vertical ? null : thickness,
          color: colorScheme.surfaceContainerLow,
          alignment: Alignment.center,
          child: Container(
            width: vertical ? 1 : null,
            height: vertical ? null : 1,
            color: colorScheme.outlineVariant,
          ),
        ),
      ),
    );
    final tooltip = this.tooltip;
    if (tooltip != null) {
      grip = Tooltip(message: tooltip, child: grip);
    }
    return grip;
  }
}
