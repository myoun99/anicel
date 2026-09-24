import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Why the timeline's axes are built on a sliver viewport and not on a
/// `SingleChildScrollView` — the framework behaviour the choice rests on.
///
/// 🚨`_RenderSingleChildViewport.performLayout` pulls an out-of-range
/// `offset.pixels` back into range on EVERY layout
/// (`single_child_scroll_view.dart`, the `offset.correctBy` pair). It goes
/// through `correctBy`, which is the one writer that does not pass through
/// `correctPixels`, so nothing an overridden `ScrollPosition` can watch ever
/// fires. `RenderViewport` has no such step: its two corrections are the
/// ones a sliver asked for.
///
/// F-4 (유저 2026-08-31) is what that costs. Both timeline axes were written
/// the same way; the frame axis kept the bounce the user likes only because
/// its build does not run during a scroll, while the row axis re-plans its
/// window each time the finger crosses a row and was clamped back to the
/// edge on every one of those layouts.
///
/// ⛔So this is not a style preference and not a "sliver is more modern"
/// note. Only one of the four cells below is red, and a Flutter upgrade that
/// changes it should land here rather than in a timeline drag.
void main() {
  /// One finger dragging [viewport] past its start, sampled every frame.
  Future<List<double>> dragPastStart(
    WidgetTester tester,
    Widget Function(ScrollController controller, Widget child) viewport, {
    required bool relayoutEachFrame,
  }) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    // The content's extent is what changes when a window re-plans, so this
    // is the product's relayout with nothing else attached to it.
    final contentExtent = ValueNotifier<double>(4000);
    addTearDown(contentExtent.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 300,
            child: ValueListenableBuilder<double>(
              valueListenable: contentExtent,
              builder: (context, extent, child) =>
                  viewport(controller, SizedBox(height: extent, width: 400)),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final finger = await tester.startGesture(
      const Offset(200, 150),
      kind: PointerDeviceKind.touch,
    );
    final samples = <double>[];
    for (var i = 0; i < 12; i += 1) {
      await finger.moveBy(const Offset(0, 12));
      if (relayoutEachFrame) contentExtent.value = 4000 + i.toDouble();
      await tester.pump(const Duration(milliseconds: 16));
      samples.add(controller.position.pixels);
    }
    await finger.up();
    await tester.pumpAndSettle();
    return samples;
  }

  /// Whether the gap the finger pulled open stayed open for the rest of the
  /// drag — the same question F-4's own test asks of the real rows.
  bool heldPastStart(List<double> drag) {
    final first = drag.indexWhere((pixels) => pixels < 0);
    return first >= 0 && drag.skip(first).every((pixels) => pixels < 0);
  }

  Widget singleChild(ScrollController controller, Widget child) =>
      SingleChildScrollView(controller: controller, child: child);

  Widget sliver(ScrollController controller, Widget child) => CustomScrollView(
    controller: controller,
    slivers: <Widget>[SliverToBoxAdapter(child: child)],
  );

  testWidgets(
    '🚨a relayout mid-drag clamps a single-child viewport, and only that one',
    (tester) async {
      final stillSingle = await dragPastStart(
        tester,
        singleChild,
        relayoutEachFrame: false,
      );
      final stillSliver = await dragPastStart(
        tester,
        sliver,
        relayoutEachFrame: false,
      );
      expect(
        heldPastStart(stillSingle),
        isTrue,
        reason: 'fixture: with no relayout the single-child viewport bounces '
            '— this is the timeline FRAME axis. $stillSingle',
      );
      expect(
        heldPastStart(stillSliver),
        isTrue,
        reason: 'fixture: so does the sliver viewport. $stillSliver',
      );

      final busySingle = await dragPastStart(
        tester,
        singleChild,
        relayoutEachFrame: true,
      );
      expect(
        heldPastStart(busySingle),
        isFalse,
        reason: 'the one red cell: a layout pass returns an out-of-range '
            'offset to the edge under the finger — this is the timeline ROW '
            'axis before F-4. $busySingle',
      );
      expect(
        busySingle.skip(1).every((pixels) => pixels == 0),
        isTrue,
        reason: 'and it is a clamp to the edge, not a slower bounce. '
            '$busySingle',
      );

      final busySliver = await dragPastStart(
        tester,
        sliver,
        relayoutEachFrame: true,
      );
      expect(
        heldPastStart(busySliver),
        isTrue,
        reason: 'the sliver viewport keeps the overscroll across the same '
            'relayouts, which is why the axes are built on it. $busySliver',
      );
      expect(
        busySliver,
        stillSliver,
        reason: 'and keeps it identically — the relayout changes nothing '
            'about the position at all.',
      );
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );
}
