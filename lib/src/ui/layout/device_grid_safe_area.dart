import 'dart:math' as math;

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
/// ⚠️**The platform's inset is already on the RAW grid** — measured, 9 of
/// 9 real inset × ratio pairs, because the engine reports insets in whole
/// physical pixels and MediaQuery divides by the same ratio. So this
/// widget is a no-op today and an earlier draft of this comment justified
/// it with a defect that does not exist. What takes those insets OFF the
/// grid is a **UI scale**: the inset is divided by the raw ratio and then
/// composited against the product, and nothing reconciles the two.
///
/// ⛔That means benefit and hazard switch on together, in the UI-scale PR,
/// on the platform nobody in this round can test. It has to be right now.
///
/// ⛔**CEIL, via [DeviceGrid.clearance], not floor.** An inset is not a
/// position — it is a clearance the OS asserts, and the two directions
/// are equally on-grid (measured: both off-grid zero times in 9,800
/// samples) but not equally safe. Flooring makes the safe area SMALLER,
/// sliding up to a device pixel of content under a notch it can never be
/// seen past; ceiling costs at most one device pixel of chrome. Measured
/// with a real 36px status bar at an effective 1.35, flooring lost
/// 0.80 × 0.40 device px of content, and 0.80 × 0.80 at a 132px notch.
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

    double snap(bool honour, double inset, double minimum) {
      // SafeArea's own clamp, verbatim. The 0.0 is load-bearing twice: it
      // is what keeps a negative `minimum` off `Padding`'s
      // `isNonNegative` assert — an earlier draft passed -4 straight
      // through and threw — and it is what keeps `minimum` meaning
      // minimum, since taking the max AFTER honouring the flag is the
      // only order that applies the greater of the two.
      final wanted = math.max(honour ? inset : 0.0, minimum);
      return grid.clearance(wanted);
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
