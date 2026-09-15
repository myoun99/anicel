import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/layout/render_shifted_child.dart';

/// 🚨THE SHARED BODY, pinned (2026-09-16).
///
/// Three render boxes paint their child at an offset — the device grid's
/// translate, the rail window's shift, the frame axis's child offset — and
/// each had written the same hit test out. They read
/// [RenderShiftedChildHitTest] now, and NOTHING in the suite noticed when
/// that body dropped the offset: measured by mutating it to `Offset.zero`
/// and running the grid, rail, storyboard and device-grid tests — 48 cases,
/// all green. A press landing where the child USED to be is invisible to
/// every one of them, so the shared body gets its own case here.
void main() {
  testWidgets('a box that paints its child at an offset hits it there too', (
    tester,
  ) async {
    var taps = 0;
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 200,
            height: 40,
            child: _ShiftedBy(
              const Offset(80, 0),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => taps += 1,
                child: const SizedBox(width: 40, height: 40),
              ),
            ),
          ),
        ),
      ),
    );

    // The child is 40 wide and PAINTS at x 80..120.
    await tester.tapAt(const Offset(100, 20));
    expect(taps, 1, reason: 'the press lands where the child is drawn');

    await tester.tapAt(const Offset(20, 20));
    expect(
      taps,
      1,
      reason: 'and not where it would be without the offset — the box is '
          'wider than its child, so this point is inside the BOX',
    );
  });
}

class _ShiftedBy extends SingleChildRenderObjectWidget {
  const _ShiftedBy(this.offset, {super.child});

  final Offset offset;

  @override
  _RenderShiftedBy createRenderObject(BuildContext context) =>
      _RenderShiftedBy(offset);

  @override
  void updateRenderObject(BuildContext context, _RenderShiftedBy renderObject) {
    renderObject.childPaintOffset = offset;
  }
}

/// The smallest twin of the three real boxes: it lays its child out loose,
/// parks it at [childPaintOffset], and leaves both painting and hit-testing
/// to the shared code.
class _RenderShiftedBy extends RenderShiftedBox
    with RenderShiftedChildHitTest {
  _RenderShiftedBy(this._childPaintOffset) : super(null);

  Offset _childPaintOffset;

  @override
  Offset get childPaintOffset => _childPaintOffset;

  set childPaintOffset(Offset value) {
    if (_childPaintOffset == value) {
      return;
    }
    _childPaintOffset = value;
    markNeedsLayout();
  }

  @override
  void performLayout() {
    size = constraints.biggest;
    final child = this.child;
    if (child != null) {
      child.layout(constraints.loosen(), parentUsesSize: true);
      (child.parentData! as BoxParentData).offset = childPaintOffset;
    }
  }
}
