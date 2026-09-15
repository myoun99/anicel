import 'package:flutter/rendering.dart';

/// 🚨ONE ANSWER for 「자식을 옮겨 그리는 렌더 박스의 히트테스트」.
///
/// A box that PAINTS its single child at an offset has to HIT-TEST it
/// through the same offset, or a press lands where the child used to be.
/// The body is always the same four lines around
/// [BoxHitTestResult.addWithPaintOffset]; only the name of the field
/// holding the offset ever differed.
///
/// ⛔It is shared because the THIRD one arrived (3의 규칙, 2026-09-16): the
/// rail window's shift and the frame axis's child offset had each written
/// it out, and F-95's scroll-position translate would have made three
/// texts of one algorithm — the clone scan said so in the same round
/// (`one_algorithm_one_place_test`, 90 → 93).
///
/// ⚠️A mixer that already inherits a `hitTestChildren` (every
/// `RenderProxyBox` does) must list this mixin LAST in its `with` clause,
/// or the inherited one wins and the offset is dropped.
mixin RenderShiftedChildHitTest
    on RenderBox, RenderObjectWithChildMixin<RenderBox> {
  /// Where this box paints its child, in this box's own coordinates.
  Offset get childPaintOffset;

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    final child = this.child;
    if (child == null) {
      return false;
    }
    return result.addWithPaintOffset(
      offset: childPaintOffset,
      position: position,
      hitTest: (result, transformed) =>
          child.hitTest(result, position: transformed),
    );
  }
}
