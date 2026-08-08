import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/ui/widgets/static_raster.dart';

/// Counts its own paints. The whole point of [StaticRaster] is that this
/// number stops going up.
class _CountingPainter extends CustomPainter {
  _CountingPainter({required this.counter, super.repaint});

  final List<int> counter;

  @override
  void paint(Canvas canvas, Size size) {
    counter[0] += 1;
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0xFF336699),
    );
  }

  @override
  bool shouldRepaint(_CountingPainter oldDelegate) => false;
}

/// An ancestor that repaints on demand WITHOUT touching its child. This
/// is the shape of the real problem: the cursor moves, a frame is
/// produced, and everything downstream is asked for pixels again.
class _RepaintingParent extends StatelessWidget {
  const _RepaintingParent({required this.repaint, required this.child});

  final Listenable repaint;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _CountingPainter(counter: <int>[0], repaint: repaint),
      child: child,
    );
  }
}

Widget _host(Widget child) => MaterialApp(
  home: Directionality(
    textDirection: TextDirection.ltr,
    child: Center(child: SizedBox(width: 100, height: 100, child: child)),
  ),
);

void main() {
  tearDown(() {
    StaticRaster.globallyEnabled.value = true;
  });

  testWidgets('an ancestor repainting does not re-bake the child', (
    tester,
  ) async {
    final counter = <int>[0];
    final parentRepaint = ValueNotifier<int>(0);
    addTearDown(parentRepaint.dispose);

    await tester.pumpWidget(
      _host(
        _RepaintingParent(
          repaint: parentRepaint,
          child: StaticRaster(
            debugLabel: 'test',
            child: CustomPaint(painter: _CountingPainter(counter: counter)),
          ),
        ),
      ),
    );
    expect(counter[0], 1, reason: 'the first frame has to actually paint');

    for (var i = 0; i < 10; i += 1) {
      parentRepaint.value += 1;
      await tester.pump();
    }

    expect(
      counter[0],
      1,
      reason: 'ten ancestor repaints, and the panel was baked once',
    );
  });

  testWidgets('the child re-bakes when it genuinely changes', (tester) async {
    final counter = <int>[0];
    final childRepaint = ValueNotifier<int>(0);
    addTearDown(childRepaint.dispose);

    await tester.pumpWidget(
      _host(
        StaticRaster(
          debugLabel: 'test',
          child: CustomPaint(
            painter: _CountingPainter(counter: counter, repaint: childRepaint),
          ),
        ),
      ),
    );
    expect(counter[0], 1);

    childRepaint.value += 1;
    await tester.pump();
    expect(
      counter[0],
      2,
      reason: "Flutter's own dirty bit is the invalidation, and it fired",
    );
  });

  testWidgets('resizing re-bakes', (tester) async {
    final counter = <int>[0];

    Widget sized(double width) => MaterialApp(
      home: Center(
        child: SizedBox(
          width: width,
          height: 100,
          child: StaticRaster(
            debugLabel: 'test',
            child: CustomPaint(painter: _CountingPainter(counter: counter)),
          ),
        ),
      ),
    );

    await tester.pumpWidget(sized(100));
    expect(counter[0], 1);
    await tester.pumpWidget(sized(140));
    expect(counter[0], 2);
  });

  testWidgets('a nested repaint boundary makes it paint through, not lie', (
    tester,
  ) async {
    // The one thing that would be a correctness bug rather than a missed
    // optimisation: an inner boundary can never be re-reached once its
    // layers are detached, so it would freeze. The wrapper has to notice
    // and stand down.
    final counter = <int>[0];
    final innerRepaint = ValueNotifier<int>(0);
    addTearDown(innerRepaint.dispose);

    await tester.pumpWidget(
      _host(
        StaticRaster(
          debugLabel: 'test',
          child: RepaintBoundary(
            child: CustomPaint(
              painter: _CountingPainter(counter: counter, repaint: innerRepaint),
            ),
          ),
        ),
      ),
    );

    final render = tester.renderObject<RenderStaticRaster>(
      find.byType(StaticRaster),
    );
    expect(render.debugNestedBoundary, isTrue);
    expect(render.captureCount, 0, reason: 'it must not have baked anything');

    final before = counter[0];
    innerRepaint.value += 1;
    await tester.pump();
    expect(
      counter[0],
      greaterThan(before),
      reason: 'the inner subtree still updates — it was not frozen',
    );
  });

  testWidgets('a surface that changes every frame stands itself down', (
    tester,
  ) async {
    final counter = <int>[0];
    final repaint = ValueNotifier<int>(0);
    addTearDown(repaint.dispose);

    await tester.pumpWidget(
      _host(
        StaticRaster(
          debugLabel: 'test',
          maxConsecutiveCaptures: 3,
          child: CustomPaint(
            painter: _CountingPainter(counter: counter, repaint: repaint),
          ),
        ),
      ),
    );
    final render = tester.renderObject<RenderStaticRaster>(
      find.byType(StaticRaster),
    );
    expect(render.debugStoodDown, isFalse);

    // Back-to-back frames, the shape of playback or a live drag.
    for (var i = 0; i < 6; i += 1) {
      repaint.value += 1;
      await tester.pump(const Duration(milliseconds: 16));
    }

    expect(
      render.debugStoodDown,
      isTrue,
      reason: 'baking costs a paint PLUS a copy — alive surfaces must opt out',
    );
    final capturesWhileAlive = render.captureCount;
    repaint.value += 1;
    await tester.pump(const Duration(milliseconds: 16));
    expect(
      render.captureCount,
      capturesWhileAlive,
      reason: 'stood down means stood down: no more copies',
    );

    // ...and it comes back when the surface goes quiet again.
    repaint.value += 1;
    await tester.pump(const Duration(seconds: 1));
    expect(render.debugStoodDown, isFalse);
  });

  testWidgets('disabled is byte-for-byte pass-through', (tester) async {
    final counter = <int>[0];
    final parentRepaint = ValueNotifier<int>(0);
    addTearDown(parentRepaint.dispose);

    await tester.pumpWidget(
      _host(
        _RepaintingParent(
          repaint: parentRepaint,
          child: StaticRaster(
            debugLabel: 'test',
            enabled: false,
            child: CustomPaint(painter: _CountingPainter(counter: counter)),
          ),
        ),
      ),
    );
    final render = tester.renderObject<RenderStaticRaster>(
      find.byType(StaticRaster),
    );
    expect(render.captureCount, 0);

    // Still a boundary, so the ancestor's repaint is still absorbed —
    // disabling gives up the raster win, not the recording win.
    parentRepaint.value += 1;
    await tester.pump();
    expect(render.captureCount, 0);
  });

  testWidgets('the global switch turns every surface into pass-through', (
    tester,
  ) async {
    final counter = <int>[0];
    await tester.pumpWidget(
      _host(
        StaticRaster(
          debugLabel: 'test',
          child: CustomPaint(painter: _CountingPainter(counter: counter)),
        ),
      ),
    );
    final render = tester.renderObject<RenderStaticRaster>(
      find.byType(StaticRaster),
    );
    expect(render.captureCount, 1);

    StaticRaster.globallyEnabled.value = false;
    await tester.pump();
    expect(render.captureCount, 1, reason: 'no further bakes');
    expect(counter[0], greaterThan(1), reason: 'and it paints through');
  });

  testWidgets('taps still reach the child, and semantics survive', (
    tester,
  ) async {
    // Only PAINTING is replaced; the render subtree stays in the tree,
    // so hit testing and the semantics tree are untouched. If that ever
    // stops being true, every panel becomes unusable at once.
    var tapped = false;
    final handle = tester.ensureSemantics();

    await tester.pumpWidget(
      _host(
        StaticRaster(
          debugLabel: 'test',
          child: GestureDetector(
            onTap: () => tapped = true,
            child: Semantics(
              label: 'inside the raster',
              child: const ColoredBox(color: Color(0xFF000000)),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byType(GestureDetector));
    expect(tapped, isTrue);
    expect(find.bySemanticsLabel('inside the raster'), findsOneWidget);
    handle.dispose();
  });
}
