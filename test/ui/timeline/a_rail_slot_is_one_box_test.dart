import 'package:anicel/src/ui/input/control_press_claim.dart';
import 'package:anicel/src/ui/timeline/layer_label_controls.dart';
import 'package:anicel/src/ui/timeline/row_control_surface.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// Every slot of every rail row wears these two, so a wrapper that only
/// forwards its child is paid once per slot on every panel reopen (card
/// frame-panels-build-in-one-frame, 2026-10-25). They ARE the box they
/// stand for; what they do is held by the tests of the row's drag and of
/// the swipe columns.
void main() {
  Element only(Element parent) {
    final children = <Element>[];
    parent.visitChildren(children.add);
    expect(children, hasLength(1));
    return children.single;
  }

  testWidgets('a control slot is the marker the row asks for', (
    tester,
  ) async {
    const body = ValueKey<String>('body');
    await tester.pumpWidget(
      const RowControlSurface(child: SizedBox(key: body)),
    );
    final slot = tester.element(find.byType(RowControlSurface));
    expect(
      tester.renderObject(find.byType(RowControlSurface)),
      isA<RenderMetaData>()
          .having((m) => m.metaData, 'metaData', RowControlSurface.marker)
          .having(
            (m) => m.behavior,
            'behavior',
            HitTestBehavior.translucent,
          ),
    );
    expect(only(slot).widget.key, body);
  });

  testWidgets('a swipe column is the claim it adds', (tester) async {
    const body = ValueKey<String>('body');
    await tester.pumpWidget(
      RailSwipeColumnPointer(child: const SizedBox(key: body)),
    );
    final column = tester.element(find.byType(RailSwipeColumnPointer));
    expect(
      tester.renderObject(find.byType(RailSwipeColumnPointer)),
      isA<RenderDragVerbClaim>(),
    );
    final scope = only(column);
    expect(
      scope.widget,
      isA<PressFireScope>().having(
        (s) => s.fireOn,
        'fireOn',
        PressFire.down,
      ),
    );
    expect(only(scope).widget.key, body);
  });
}
