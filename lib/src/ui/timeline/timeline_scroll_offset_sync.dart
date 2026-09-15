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
  ///
  /// 🚨F-4 (유저 2026-08-31): 「왼쪽 최대치 넘어서 드래그하면 타임라인이
  /// 오른쪽으로 쭉 밀려서 왼쪽이랑 갭 발생하는 애니메이션이 존재해. 거기서 손
  /// 떼면 원래위치로 돌아가고, 이거 마음에 드는데 레이어쪽 드래그 스크롤은
  /// 그렇지 않단거야」. ⛔A pull never lands on a position that is SCROLLING —
  /// a hand dragging it past its end, or the bounce bringing it home. The
  /// row axis re-plans its window each time a drag crosses a row boundary,
  /// and that build handed this the clamped offset: the next frame jumped the
  /// dragged rows back to the edge, every row the finger passed (measured
  /// under iOS physics, 09-16: 0, −12, −17.8, −23.3, 0, 0, −12 …). The frame
  /// axis kept its bounce only because its build does not run on a scroll.
  /// What is left to pull is a position at rest that the content left out of
  /// range; a bounce comes home on its own.
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

      final position = controller.position;
      _scheduled = null;
      // ⛔A pull never lands on a position a HAND or a BOUNCE has taken out
      // of range. `isScrollingNotifier` alone was not enough: between two
      // drag updates the position rests, reads "not scrolling", and this
      // post-frame pull jumped the dragged rows back to the edge — the very
      // snap F-4 is about (measured under iOS physics, 09-16: 0, −12, −17.8,
      // −23.3, 0, 0, −12 …, one reset per row boundary the finger crossed).
      // Out of range IS the pull the user is making; a bounce comes home on
      // its own, and what is left for this to correct is a position at rest
      // that the CONTENT moved out from under.
      if (position.isScrollingNotifier.value ||
          position.pixels < position.minScrollExtent ||
          position.pixels > position.maxScrollExtent) {
        return;
      }
      final targetOffset = effectiveOffset
          .clamp(0.0, position.maxScrollExtent)
          .toDouble();
      if (controller.offset != targetOffset) {
        controller.jumpTo(targetOffset);
      }
    });
  }
}
