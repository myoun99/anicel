import 'package:flutter/widgets.dart';

import 'device_grid.dart';

/// [SafeArea] whose insets land on whole device pixels.
///
/// 🎯**This is the FIRST link in the chain, and the chain is only as good
/// as its first link.** The quantization invariant is top-down: the root
/// child's origin is exactly on the grid because `RenderView` installs a
/// pure scale with no translation, and every descendant stays there only
/// if every offset the app chooses below it is an integral count of
/// device pixels. A plain [SafeArea] is the first thing to break that —
/// its inset comes from the platform, and nothing makes it a whole number
/// of device pixels.
///
/// ⚠️On Windows the inset is zero, so this changes nothing there and the
/// defect is invisible on the machine most of this round is verified on.
/// On a tablet it is the status bar or the notch, whose logical height is
/// whatever the OS reports — a value the app never chose and cannot
/// assume is on the grid.
///
/// ⛔Flooring, not rounding, and never per-edge rounding of a WIDTH: the
/// insets are positions measured from the window edge, so flooring each
/// one keeps the content box's own edges on the grid.
class DeviceGridSafeArea extends StatelessWidget {
  const DeviceGridSafeArea({
    super.key,
    this.left = true,
    this.top = true,
    this.right = true,
    this.bottom = true,
    this.minimum = EdgeInsets.zero,
    required this.child,
  });

  final bool left;
  final bool top;
  final bool right;
  final bool bottom;
  final EdgeInsets minimum;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final grid = DeviceGrid.of(context);
    final padding = MediaQuery.paddingOf(context);

    double snap(bool honour, double inset, double floor) {
      final wanted = honour ? (inset > floor ? inset : floor) : floor;
      return grid.position(wanted);
    }

    final resolved = EdgeInsets.only(
      left: snap(left, padding.left, minimum.left),
      top: snap(top, padding.top, minimum.top),
      right: snap(right, padding.right, minimum.right),
      bottom: snap(bottom, padding.bottom, minimum.bottom),
    );

    return MediaQuery.removePadding(
      context: context,
      removeLeft: left,
      removeTop: top,
      removeRight: right,
      removeBottom: bottom,
      child: Padding(padding: resolved, child: child),
    );
  }
}
