import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/input/hit_path.dart';
import 'package:anicel/src/ui/input/pan_slide.dart';
import 'package:anicel/src/ui/timeline/row_control_surface.dart';

/// WHAT IS UNDER A POINT ON SCREEN, asked the one way (`hit_path.dart`) by
/// each that asks: a pan for the slide it landed on, a row for its
/// controls, a drop from the OS for its place.
void main() {
  List<Object?> marksOn(Iterable<HitTestTarget> path) => [
    for (final target in path)
      if (target is RenderMetaData) target.metaData,
  ];

  // Away from the screen's corner, so that a point is the box's own only
  // once it is asked in the box's terms.
  Widget awayFromTheCorner(Widget child) => Directionality(
    textDirection: TextDirection.ltr,
    child: Align(
      alignment: Alignment.topLeft,
      child: Padding(
        padding: const EdgeInsets.only(left: 300, top: 200),
        child: child,
      ),
    ),
  );

  testWidgets('the path under a point is read the deepest first — of the '
      'view, and of a box away from the corner', (tester) async {
    const outer = Key('outer');
    await tester.pumpWidget(
      awayFromTheCorner(
        const MetaData(
          key: outer,
          metaData: 'outer',
          behavior: HitTestBehavior.translucent,
          child: MetaData(
            metaData: 'inner',
            behavior: HitTestBehavior.translucent,
            child: SizedBox.square(dimension: 100),
          ),
        ),
      ),
    );
    final at = tester.getCenter(find.byKey(outer));

    expect(marksOn(hitPathInView(at, tester.view.viewId)), ['inner', 'outer']);
    expect(
      marksOn(hitPathWithin(tester.renderObject(find.byKey(outer)), at)),
      ['inner', 'outer'],
    );
  });

  testWidgets('a pan slides the deepest slide it landed on', (tester) async {
    final outer = _Slide();
    final inner = _Slide();
    await tester.pumpWidget(
      awayFromTheCorner(
        PanSlideRegion(
          slide: outer,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: PanSlideRegion(
              slide: inner,
              child: const SizedBox.square(dimension: 100),
            ),
          ),
        ),
      ),
    );
    final press = PointerDownEvent(
      position: tester.getCenter(find.byType(SizedBox)),
      viewId: tester.view.viewId,
    );

    expect(panSlideUnder(press), same(inner));
  });

  testWidgets("a row's control is the mark the row puts on it — not any mark "
      'a press lands on', (tester) async {
    const row = Key('row');
    const another = Key('another');
    const control = Key('control');
    await tester.pumpWidget(
      awayFromTheCorner(
        const Row(
          key: row,
          mainAxisSize: MainAxisSize.min,
          children: [
            MetaData(
              key: another,
              metaData: 'not a control',
              behavior: HitTestBehavior.translucent,
              child: SizedBox.square(dimension: 50),
            ),
            RowControlSurface(
              key: control,
              child: SizedBox.square(dimension: 50),
            ),
          ],
        ),
      ),
    );
    final host = tester.element(find.byKey(row));

    expect(
      RowControlSurface.covers(host, tester.getCenter(find.byKey(another))),
      isFalse,
    );
    expect(
      RowControlSurface.covers(host, tester.getCenter(find.byKey(control))),
      isTrue,
    );
  });
}

class _Slide implements PanSlide {
  @override
  Axis get axis => Axis.vertical;

  @override
  bool get canSlide => true;

  @override
  void slideWithHand(Offset delta) {}
}
