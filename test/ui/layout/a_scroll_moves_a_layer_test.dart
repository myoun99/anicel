import 'package:anicel/src/ui/effective_device_pixel_ratio.dart';
import 'package:anicel/src/ui/layout/device_grid_scroll_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

/// 🚨★★★**A SCROLL MOVES A LAYER; IT REPAINTS NOTHING**
/// (playback-page-turn-repaints-the-whole-timeline, 10-11).
///
/// What follows a scroll from outside it — a ruler over the frame cells, a
/// rail beside them ([ScrollFollower]) — repainted on every pixel of
/// scroll, and being no repaint boundary that repaint climbed to the
/// panel's: 🔬379 of the timeline's render objects for a one-pixel scroll
/// of its frame axis, the same 379 at every page a running playhead turned.
///
/// ⚠️The panels' own pins read positions off the RENDER tree, and those were
/// right before and are right now: the move is a LAYER's here, so what is
/// pinned is what the compositor is handed.
void main() {
  const ruler = ValueKey<String>('follower-ruler');
  const cells = ValueKey<String>('scrolled-cells');
  const beside = ValueKey<String>('beside');

  void useRatio(WidgetTester tester, double ratio) {
    tester.view.devicePixelRatio = ratio;
    tester.view.physicalSize = Size(800 * ratio, 600 * ratio);
    addTearDown(tester.view.reset);
  }

  /// A ruler following a horizontal scroll of cells [viewportWidth] wide,
  /// both 2000 long, and a neighbour beside them — all on one layer.
  Widget harness(
    ScrollController controller, {
    required double ratio,
    double viewportWidth = 300,
    CustomPainter? rulerPainter,
    CustomPainter? besidePainter,
  }) => MediaQuery(
    data: MediaQueryData(devicePixelRatio: ratio),
    child: Directionality(
      textDirection: TextDirection.ltr,
      child: EffectiveDevicePixelRatioScope(
        child: Align(
          alignment: Alignment.topLeft,
          child: RepaintBoundary(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 300,
                  height: 20,
                  child: ClipRect(
                    child: OverflowBox(
                      alignment: Alignment.topLeft,
                      maxWidth: 2000,
                      child: ScrollFollower(
                        controller: controller,
                        axisDirection: AxisDirection.right,
                        child: CustomPaint(
                          key: ruler,
                          painter: rulerPainter,
                          size: const Size(2000, 20),
                        ),
                      ),
                    ),
                  ),
                ),
                SizedBox(
                  width: viewportWidth,
                  height: 40,
                  child: SingleChildScrollView(
                    controller: controller,
                    scrollDirection: Axis.horizontal,
                    child: DeviceGridScrollBody(
                      controller: controller,
                      axisDirection: AxisDirection.right,
                      child: const SizedBox(key: cells, width: 2000, height: 40),
                    ),
                  ),
                ),
                CustomPaint(
                  key: beside,
                  painter: besidePainter,
                  size: const Size(300, 20),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );

  /// Where the compositor puts the ruler: the offset of the follower's own
  /// layer, which sits straight on the boundary's here.
  double rulerOnScreen(WidgetTester tester) {
    final follower = tester.renderObject(find.byKey(ruler)).parent!;
    final layer = follower.debugLayer;
    expect(layer, isA<OffsetLayer>(), reason: 'the follower has a layer');
    return (layer! as OffsetLayer).offset.dx;
  }

  /// Where the cells landed, on the same boundary.
  double cellsOnScreen(WidgetTester tester) =>
      tester.getTopLeft(find.byKey(cells)).dx;

  testWidgets('🚨a pixel of scroll repaints neither what follows it nor what '
      'stands beside it', (tester) async {
    useRatio(tester, 1);
    final controller = ScrollController();
    addTearDown(controller.dispose);
    final rulerPaints = _Counting();
    final besidePaints = _Counting();
    await tester.pumpWidget(
      harness(
        controller,
        ratio: 1,
        rulerPainter: rulerPaints,
        besidePainter: besidePaints,
      ),
    );
    final before = (ruler: rulerPaints.paints, beside: besidePaints.paints);
    expect(before.ruler, greaterThan(0), reason: 'fixture: it painted once');

    for (var step = 1; step <= 5; step += 1) {
      controller.jumpTo(step.toDouble());
      await tester.pump();
    }

    expect(
      rulerPaints.paints,
      before.ruler,
      reason: 'the ruler is painted once and moved — ↩️it was repainted at '
          'every pixel',
    );
    expect(
      besidePaints.paints,
      before.beside,
      reason: '🚨and the repaint does not climb to what stands beside it — '
          '↩️it repainted the panel\'s whole layer',
    );
    expect(rulerOnScreen(tester), cellsOnScreen(tester), reason: 'it moved');
  });

  for (final ratio in <double>[1, 1.35]) {
    testWidgets('🚨what follows lands where the cells land — by its layer, '
        'on the device grid, ratio $ratio (F-32)', (tester) async {
      useRatio(tester, ratio);
      final controller = ScrollController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(harness(controller, ratio: ratio));

      for (final at in <double>[123.37, 0.5, 777.77, 1000]) {
        controller.jumpTo(at);
        await tester.pump();
        expect(
          rulerOnScreen(tester),
          cellsOnScreen(tester),
          reason: 'scrolled to $at',
        );
      }
    });
  }

  testWidgets('🚨a viewport that pulls its position back during layout takes '
      'what follows it along — with no listener told (F-95)', (tester) async {
    useRatio(tester, 1);
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(harness(controller, ratio: 1));
    controller.jumpTo(controller.position.maxScrollExtent);
    await tester.pump();
    final scrolledTo = controller.offset;
    expect(scrolledTo, 1700, reason: 'fixture: at the end');

    var told = 0;
    controller.addListener(() => told += 1);
    // The cells' viewport grows past their end; the ruler's box does not
    // change at all, so nothing lays it out or paints it.
    await tester.pumpWidget(
      harness(controller, ratio: 1, viewportWidth: 800),
    );

    expect(controller.offset, lessThan(scrolledTo), reason: 'fixture: pulled');
    expect(told, 0, reason: 'fixture: and nobody was told');
    expect(
      rulerOnScreen(tester),
      cellsOnScreen(tester),
      reason: 'the ruler still stands over the cells it numbers',
    );
  });
}

/// A painter that counts its paints and never asks to repaint.
class _Counting extends CustomPainter {
  int paints = 0;

  @override
  void paint(Canvas canvas, Size size) => paints += 1;

  @override
  bool shouldRepaint(_Counting oldDelegate) => false;
}
