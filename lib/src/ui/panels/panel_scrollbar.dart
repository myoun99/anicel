import 'package:flutter/material.dart';

import '../widgets/app_scrollbar.dart';

/// The shared panel scrollbar: the app-wide [AppScrollbar] laid over the
/// wrapped scrollable's end edge (right for vertical, bottom for
/// horizontal — detected from the controller's attached position).
///
/// This is the app's SHOWS-WHEN-IT-OVERFLOWS bar: it appears only while
/// there is something to scroll and it reserves NO width, so a panel that
/// fits pays nothing for it. That is the whole point on surfaces where
/// width is the scarce axis — the tool rail cannot spend 12px to announce
/// a scrollbar it does not need.
///
/// The other kind — always visible, in its own reserved lane — is not a
/// mode of this widget: the timeline and the canvas own that shape in
/// their own rail widgets, where the lane is part of the grid's geometry
/// rather than something laid over content.
class PanelScrollbar extends StatefulWidget {
  const PanelScrollbar({
    super.key,
    required this.controller,
    required this.child,
  });

  final ScrollController controller;
  final Widget child;

  @override
  State<PanelScrollbar> createState() => _PanelScrollbarState();
}

class _PanelScrollbarState extends State<PanelScrollbar> {
  bool _metricsRefreshScheduled = false;

  Axis get _axis {
    if (widget.controller.hasClients) {
      return axisDirectionToAxis(widget.controller.position.axisDirection);
    }
    return Axis.vertical;
  }

  /// Whether there is anything to scroll — the bar's entire visibility
  /// rule. Before the controller attaches this is false, which is the
  /// right answer: a bar cannot be over content that has not been laid
  /// out, and the metrics notification below brings us back.
  bool get _overflows {
    if (!widget.controller.hasClients) {
      return false;
    }
    final position = widget.controller.position;
    return position.hasContentDimensions && position.maxScrollExtent > 0;
  }

  @override
  Widget build(BuildContext context) {
    final axis = _axis;
    final vertical = axis == Axis.vertical;
    return NotificationListener<ScrollMetricsNotification>(
      onNotification: (notification) {
        // Metrics notifications arrive during layout — defer the rebuild
        // (axis detection on first attach, thumb resize on content growth).
        if (!_metricsRefreshScheduled) {
          _metricsRefreshScheduled = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _metricsRefreshScheduled = false;
            if (mounted) {
              setState(() {});
            }
          });
        }
        return false;
      },
      child: Stack(
        children: [
          widget.child,
          if (_overflows)
            Positioned(
              left: vertical ? null : 0,
              right: 0,
              top: vertical ? 0 : null,
              bottom: 0,
              // The lane is laid OVER the content, so this width costs the
              // panel nothing — it is reach for the pointer, not layout.
              width: vertical ? AppScrollbarLane.narrow : null,
              height: vertical ? null : AppScrollbarLane.narrow,
              child: AppControllerScrollbar(
                controller: widget.controller,
                axis: axis,
              ),
            ),
        ],
      ),
    );
  }
}
