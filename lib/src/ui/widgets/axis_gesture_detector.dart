import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

/// A drag along ONE axis: the recogniser family is chosen by [axis], and the
/// other family is never mounted.
///
/// 🚨ONE recogniser family, chosen by the axis — the rail swipe's law, now
/// every axis drag's: a rail's sweep runs DOWN it and the x-sheet's runs
/// ACROSS, and mounting both would put two recognisers in the arena where
/// the host only has one gesture. Five widgets spelled this by hand —
/// `horizontal ? handler : null` eight or ten times each — before it had a
/// name: the cut-end grip, the comma grip, the SE clip span, the scrollbar
/// thumb and the rail column swipe. `one_axis_drag_test` keeps it the one
/// place both families are named.
///
/// The handlers are `GestureDetector`'s own. A site that reads where the
/// pointer is keeps reading `details.localPosition`; one that reads how far
/// it moved along the axis reads `details.primaryDelta`, which the
/// recogniser already reports along its own axis — no `dx`/`dy` fork at the
/// site.
class AxisGestureDetector extends StatelessWidget {
  const AxisGestureDetector({
    super.key,
    required this.axis,
    this.child,
    this.onDragDown,
    this.onDragStart,
    this.onDragUpdate,
    this.onDragEnd,
    this.onDragCancel,
    this.onTapDown,
    this.behavior,
    this.dragStartBehavior = DragStartBehavior.start,
    this.supportedDevices,
  });

  /// The axis the drag runs along; the other axis's recognisers are absent,
  /// not merely idle.
  final Axis axis;

  /// Null is a grip that is nothing but its gesture — the cut-end handle is
  /// one: the Positioned around it gives it its box.
  final Widget? child;

  final GestureDragDownCallback? onDragDown;
  final GestureDragStartCallback? onDragStart;
  final GestureDragUpdateCallback? onDragUpdate;
  final GestureDragEndCallback? onDragEnd;
  final GestureDragCancelCallback? onDragCancel;

  /// A tap on the same surface (the scrollbar lane's jump), unaffected by
  /// the axis.
  final GestureTapDownCallback? onTapDown;

  final HitTestBehavior? behavior;
  final DragStartBehavior dragStartBehavior;
  final Set<PointerDeviceKind>? supportedDevices;

  @override
  Widget build(BuildContext context) {
    final horizontal = axis == Axis.horizontal;
    return GestureDetector(
      behavior: behavior,
      dragStartBehavior: dragStartBehavior,
      supportedDevices: supportedDevices,
      onTapDown: onTapDown,
      onHorizontalDragDown: horizontal ? onDragDown : null,
      onHorizontalDragStart: horizontal ? onDragStart : null,
      onHorizontalDragUpdate: horizontal ? onDragUpdate : null,
      onHorizontalDragEnd: horizontal ? onDragEnd : null,
      onHorizontalDragCancel: horizontal ? onDragCancel : null,
      onVerticalDragDown: horizontal ? null : onDragDown,
      onVerticalDragStart: horizontal ? null : onDragStart,
      onVerticalDragUpdate: horizontal ? null : onDragUpdate,
      onVerticalDragEnd: horizontal ? null : onDragEnd,
      onVerticalDragCancel: horizontal ? null : onDragCancel,
      child: child,
    );
  }
}
