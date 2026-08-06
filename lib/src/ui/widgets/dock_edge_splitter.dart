import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// A draggable divider between two areas that share an extent.
///
/// It began as the workspace dock's edge grip and is now the app's ONE
/// splitter: the layer rails use it too (the rail-window round), which is
/// why it lives beside the other shared widgets instead of inside the dock
/// host. [onDragDelta] receives the raw pointer delta along the splitter's
/// axis; the owner applies the sign for which side grows.
///
/// THE SPLITTER IS THE LINE. It keeps [thickness] as its HIT extent — a 1px
/// target is not a target — but it paints nothing at rest and one hairline
/// when the pointer is on it, climbing the same four-state ladder every grip
/// in the app climbs (invisible -> hairlineStrong -> gripHover -> accent).
///
/// It used to paint an opaque [ColorScheme.surfaceContainerLow] band the
/// whole time. That band is what covered the floating region's rounded
/// corners and drew two grey bars down its sides, which is why the region
/// read as square no matter how good its silhouette was: the shape was
/// right and something opaque was parked on top of it.
class DockEdgeSplitter extends StatefulWidget {
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

  /// The HIT extent. The painted extent is [lineExtent].
  static const double thickness = 5;

  /// What is actually drawn, and only while the pointer is here.
  static const double lineExtent = 1;

  @override
  State<DockEdgeSplitter> createState() => _DockEdgeSplitterState();
}

class _DockEdgeSplitterState extends State<DockEdgeSplitter> {
  bool _hovered = false;
  bool _dragging = false;

  Color get _lineColor {
    if (_dragging) {
      return AppColors.accent;
    }
    if (_hovered) {
      return AppColors.gripHover;
    }
    return Colors.transparent;
  }

  void _setDragging(bool value) {
    if (_dragging == value) {
      return;
    }
    setState(() => _dragging = value);
  }

  @override
  Widget build(BuildContext context) {
    final vertical = widget.axis == Axis.vertical;
    Widget grip = MouseRegion(
      cursor: vertical
          ? SystemMouseCursors.resizeLeftRight
          : SystemMouseCursors.resizeUpDown,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onDoubleTap: widget.onDoubleTap,
        onHorizontalDragStart: vertical ? (_) => _setDragging(true) : null,
        onHorizontalDragEnd: vertical ? (_) => _setDragging(false) : null,
        onHorizontalDragCancel: vertical ? () => _setDragging(false) : null,
        onHorizontalDragUpdate: vertical
            ? (details) => widget.onDragDelta(details.delta.dx)
            : null,
        onVerticalDragStart: vertical ? null : (_) => _setDragging(true),
        onVerticalDragEnd: vertical ? null : (_) => _setDragging(false),
        onVerticalDragCancel: vertical ? null : () => _setDragging(false),
        onVerticalDragUpdate: vertical
            ? null
            : (details) => widget.onDragDelta(details.delta.dy),
        child: SizedBox(
          width: vertical ? DockEdgeSplitter.thickness : null,
          height: vertical ? null : DockEdgeSplitter.thickness,
          child: Align(
            alignment: Alignment.center,
            child: ColoredBox(
              color: _lineColor,
              child: SizedBox(
                width: vertical ? DockEdgeSplitter.lineExtent : double.infinity,
                height: vertical
                    ? double.infinity
                    : DockEdgeSplitter.lineExtent,
              ),
            ),
          ),
        ),
      ),
    );
    final tooltip = widget.tooltip;
    if (tooltip != null) {
      grip = Tooltip(message: tooltip, child: grip);
    }
    return grip;
  }
}
