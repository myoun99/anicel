import 'package:flutter/widgets.dart';

/// A scroll controller pulled to the offset the layout resolved for it, one
/// frame later — the clamp machinery of UI-R9 #9: shrinking content (a
/// collapsed lane group, a shorter cut) leaves the controller's pixels
/// where they were, and windowing from that stale, now-out-of-range offset
/// inflated the leading spacer and pushed every section along.
///
/// 🚨One object for the rail's two axes and the sheet's frame axis. Each
/// kept its own copy of this body around its own `_scheduled…Correction`
/// field; the audit's clone scan (2026-09-03) found the three and this is
/// the one that stays.
class TimelineScrollOffsetSync {
  TimelineScrollOffsetSync(this.controller, {required this.isMounted});

  final ScrollController controller;

  /// Whether the host State is still mounted when the frame ends.
  final bool Function() isMounted;

  double? _scheduled;

  /// Pulls [controller] to [effectiveOffset] after this frame, unless it is
  /// already there or a pull to the same offset is already scheduled.
  void synchronize(double effectiveOffset) {
    if (!controller.hasClients ||
        controller.offset == effectiveOffset ||
        _scheduled == effectiveOffset) {
      return;
    }

    _scheduled = effectiveOffset;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!isMounted() || !controller.hasClients) {
        _scheduled = null;
        return;
      }

      final maxScrollExtent = controller.position.maxScrollExtent;
      final targetOffset = effectiveOffset.clamp(0.0, maxScrollExtent).toDouble();

      _scheduled = null;
      if (controller.offset != targetOffset) {
        controller.jumpTo(targetOffset);
      }
    });
  }
}
