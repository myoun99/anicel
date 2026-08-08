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
///
/// 🆕This is also what `AppScrollBehavior` hands every ordinary scrollable
/// in the app, so it is the app's general scrollbar and not only the
/// panels'. It stays here because that is where its three explicit callers
/// are and moving it would be churn.
class PanelScrollbar extends StatefulWidget {
  const PanelScrollbar({
    super.key,
    required this.controller,
    required this.child,
    this.axis,
  });

  final ScrollController controller;
  final Widget child;

  /// The axis, when the caller already knows it.
  ///
  /// Null means "read it off the controller once it attaches", which is
  /// what the explicit callers do. The scroll BEHAVIOUR knows it up front
  /// (`ScrollableDetails.direction`) and says so, which spares the first
  /// frame a guess — and the guess was always vertical, so a horizontal
  /// scroller flashed a bar down its right edge before correcting itself.
  final Axis? axis;

  @override
  State<PanelScrollbar> createState() => _PanelScrollbarState();
}

class _PanelScrollbarState extends State<PanelScrollbar> {
  bool _metricsRefreshScheduled = false;

  Axis get _axis {
    final stated = widget.axis;
    if (stated != null) {
      return stated;
    }
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
        // ★PASSTHROUGH, not the default LOOSE fit — and this is load-bearing
        // now that the behaviour wraps every scrollable in the app. A loose
        // Stack hands its non-positioned child `constraints.loosen()`, and
        // `SingleChildScrollView` SHRINK-WRAPS when its main axis is loose
        // instead of filling: every scroll view whose content was shorter
        // than its box would quietly collapse to its content's height,
        // taking whatever was aligned or painted against its full size with
        // it. Passthrough hands the constraints along untouched, so the
        // wrapper is layout-invisible — which is the only thing a scrollbar
        // is allowed to be.
        //
        // The clip goes with it. A scroll view already clips what needs
        // clipping, so a second one here could only newly cut off something
        // a caller deliberately let overflow.
        fit: StackFit.passthrough,
        clipBehavior: Clip.none,
        children: [
          // ⛔The child gets NO automatic bar. Whoever built this one is
          // the bar for that scrollable, and without this the three
          // explicit callers below carried two — theirs and the one
          // `AppScrollBehavior` builds. The config lands INSIDE this
          // widget's child, which is where the scrollable is, and it does
          // not reach this widget's own bar.
          ScrollConfiguration(
            behavior: ScrollConfiguration.of(
              context,
            ).copyWith(scrollbars: false),
            child: widget.child,
          ),
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
