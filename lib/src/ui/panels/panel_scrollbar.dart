import 'package:flutter/material.dart';

import '../timeline/axis_turn.dart' show stripAcross;
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
/// panels' — the behaviour is its one caller now. It stays here because
/// moving it would be churn.
class PanelScrollbar extends StatefulWidget {
  const PanelScrollbar({
    super.key,
    required this.controller,
    required this.child,
    required this.axis,
  });

  final ScrollController controller;
  final Widget child;

  /// The axis, as the scroll behaviour knows it up front
  /// (`ScrollableDetails.direction`). ⛔Never read off the controller: before
  /// it attaches that was a guess, the guess was always vertical, and a
  /// horizontal scroller flashed a bar down its right edge before
  /// correcting itself.
  final Axis axis;

  @override
  State<PanelScrollbar> createState() => _PanelScrollbarState();
}

class _PanelScrollbarState extends State<PanelScrollbar> {
  bool _metricsRefreshScheduled = false;

  /// The controller's position, or null when it is attached to anything
  /// other than exactly ONE view.
  ///
  /// 🚨`ScrollController.position` asserts `_positions.length == 1` and
  /// then returns `_positions.single`, so it fails on TWO as well as on
  /// zero — and `hasClients` only rules out zero. That stopped being a
  /// theoretical hazard the moment this bar became something the app hands
  /// out automatically: on the mobile platforms every controller-less
  /// vertical scroll view inherits the ROUTE's `PrimaryScrollController`
  /// (`PrimaryScrollController.shouldInherit`), so two open panels are
  /// enough to give one controller two positions and take the frame down.
  ///
  /// Null means the bar has nothing it can honestly say — it cannot know
  /// which of several viewports it is over — so it stands down. That is
  /// also the right answer before the first attach, and the metrics
  /// notification below brings us back.
  ScrollPosition? get _position {
    final positions = widget.controller.positions;
    return positions.length == 1 ? positions.first : null;
  }

  /// Whether there is anything to scroll — the bar's entire visibility
  /// rule.
  bool get _overflows {
    final position = _position;
    return position != null &&
        position.hasContentDimensions &&
        position.maxScrollExtent > 0;
  }

  /// What the bar shows of its scrollable besides the offset — whether there
  /// is anything to scroll, and the lengths the thumb is measured from — as
  /// the last build saw it. The offset is the thumb's own: it follows the
  /// controller ([AppControllerScrollbar]).
  ({double viewport, double maxExtent})? _built;

  static ({double viewport, double maxExtent})? _shapeOf(
    ScrollMetrics? metrics,
  ) =>
      metrics == null ||
          !metrics.hasContentDimensions ||
          !metrics.hasViewportDimension
      ? null
      : (
          viewport: metrics.viewportDimension,
          maxExtent: metrics.maxScrollExtent,
        );

  @override
  Widget build(BuildContext context) {
    final axis = widget.axis;
    _built = _shapeOf(_position);
    return NotificationListener<ScrollMetricsNotification>(
      onNotification: (notification) {
        // 🚨ITS OWN SCROLLABLE, AND ONLY WHAT THE BAR SHOWS
        // (playback-frame-raster-is-the-whole-window, 10-12). A metrics
        // notification climbs through every scrollable around the one that
        // sent it, and this bar was built again for any of them — and for an
        // offset alone. A rebuild is laid out by the nearest LayoutBuilder
        // above it, and that layout repaints the boundary above THAT:
        // 🔬after 27 of 329 frames of a run (the frame grid's page turns),
        // the timeline dock's scroller bars laid its panel out again and
        // painted the bottom region whole. Depth 0 is Flutter's own bars'
        // rule (`defaultScrollNotificationPredicate`).
        if (notification.depth != 0 ||
            _shapeOf(notification.metrics) == _built) {
          return false;
        }
        // Metrics notifications arrive during layout — defer the rebuild
        // (the bar comes or goes, the thumb is measured again).
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
          // ⛔NO `ScrollConfiguration(scrollbars: false)` here. The obvious
          // way to stop an explicit caller being doubled by
          // `AppScrollBehavior` is to switch bars off for the child — and
          // it is wrong, because the child is the whole scroll CONTENT and
          // the config is inherited: every scrollable NESTED inside would
          // lose its bar too. The media pool's asset list went silent
          // the moment its panel was narrow enough to need the horizontal
          // escape valve above it. Nothing is doubled because nothing calls
          // this by hand any more — the behaviour is the only caller.
          widget.child,
          if (_overflows)
            stripAcross(
              axis,
              across: 0,
              fromEnd: true,
              // The lane is laid OVER the content, so this width costs the
              // panel nothing — it is reach for the pointer, not layout.
              acrossExtent: AppScrollbarLane.narrow,
              child: AppControllerScrollbar(
                controller: widget.controller,
                axis: axis,
                // ㉔: flush with the edge it is pinned to. This lane is
                // reach, not geometry — see [AppScrollbarThumbSeat.endEdge].
                thumbSeat: AppScrollbarThumbSeat.endEdge,
              ),
            ),
        ],
      ),
    );
  }
}
