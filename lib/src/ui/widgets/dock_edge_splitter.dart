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
/// THE SPLITTER IS THE PANEL'S OWN EDGE, LIT. It paints nothing at rest and
/// fills its whole [thickness] when the pointer arrives, climbing the same
/// four-state ladder every grip in the app climbs (invisible ->
/// hairlineStrong -> gripHover -> accent).
///
/// ★It does NOT round itself. It is laid inside the panel's own ClipPath,
/// so the panel's silhouette cuts the band's outer corners and the lit edge
/// follows the curve exactly — which a shape of its own could never do,
/// because a 5px-wide band cannot carry a 14px corner (유저, R2 #11: 패널의
/// 옆부분을 형태그대로 색만 바꾸는 느낌). Whoever positions one is therefore
/// responsible for putting it inside the clip.
///
/// It used to paint an opaque [ColorScheme.surfaceContainerLow] band the
/// whole time, OUTSIDE the clip. That band is what covered the floating
/// region's rounded corners and drew two grey bars down its sides, which is
/// why the region read as square no matter how good its silhouette was: the
/// shape was right and something opaque was parked on top of it. The
/// hairline that replaced it was the other half of the mistake — a line is
/// not an edge.
class DockEdgeSplitter extends StatefulWidget {
  const DockEdgeSplitter({
    super.key,
    required this.axis,
    required this.onDragDelta,
    this.onDragStart,
    this.onDragEnd,
    this.onDoubleTap,
    this.tooltip,
  });

  /// [Axis.vertical] separates side-by-side areas (drag left-right);
  /// [Axis.horizontal] separates stacked ones (drag up-down).
  final Axis axis;
  final ValueChanged<double> onDragDelta;

  /// The drag's BOUNDARIES, for owners that accumulate across it.
  ///
  /// [onDragDelta] alone cannot tell "a new drag" from "another frame of
  /// the same one", and an owner that snaps its result to a detent has to
  /// keep the un-snapped total somewhere or the snap eats the travel.
  final VoidCallback? onDragStart;
  final VoidCallback? onDragEnd;

  /// Double-click action, when the owner has a meaningful "back to the
  /// natural size" (the rails do; the docks do not).
  final VoidCallback? onDoubleTap;

  final String? tooltip;

  /// The hit extent, and the band's extent: they are the same thing now.
  static const double thickness = 5;

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
    if (value) {
      widget.onDragStart?.call();
    } else {
      widget.onDragEnd?.call();
    }
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
          child: ColoredBox(color: _lineColor),
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
