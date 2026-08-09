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

  testWidgets('the nested-boundary report is about THIS frame', (tester) async {
    // The diagnostic is the only thing that tells anyone a panel quietly
    // stopped being free, and the enforcement test branches on it. It
    // used to be written only on the path that reached the guard, so a
    // surface that stood itself down reported `false` no matter what was
    // inside it — the detector going blind exactly when a panel is at
    // its most expensive.
    // The shape has to have BOTH: an inner boundary, and something
    // outside it that dirties us every frame. (Dirt from under the inner
    // boundary stops there and never reaches us — which is the whole
    // reason the guard exists — so a nested boundary alone can never
    // stand a surface down.)
    final counter = <int>[0];
    final repaint = ValueNotifier<int>(0);
    addTearDown(repaint.dispose);

    Widget tree({required bool withInnerBoundary}) => _host(
      StaticRaster(
        debugLabel: 'test',
        maxConsecutiveCaptures: 2,
        child: Column(
          children: <Widget>[
            Expanded(
              child: withInnerBoundary
                  ? const RepaintBoundary(
                      child: ColoredBox(color: Color(0xFF111111)),
                    )
                  : const ColoredBox(color: Color(0xFF111111)),
            ),
            Expanded(
              child: CustomPaint(
                painter: _CountingPainter(counter: counter, repaint: repaint),
              ),
            ),
          ],
        ),
      ),
    );

    await tester.pumpWidget(tree(withInnerBoundary: true));
    final render = tester.renderObject<RenderStaticRaster>(
      find.byType(StaticRaster),
    );
    expect(render.debugNestedBoundary, isTrue);

    // Dirty the SIBLING every frame until the surface stands down.
    for (var i = 0; i < 5; i += 1) {
      repaint.value += 1;
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(render.debugStoodDown, isTrue);
    expect(render.debugNestedBoundary, isTrue);

    // Now take the inner boundary away while it is STILL stood down. If
    // the guard ran after the stand-down check, this frame would return
    // before reaching it and the flag would still read `true` — a
    // diagnostic describing a tree that no longer exists.
    await tester.pumpWidget(tree(withInnerBoundary: false));
    repaint.value += 1;
    await tester.pump(const Duration(milliseconds: 16));

    expect(render.debugStoodDown, isTrue, reason: 'still alive every frame');
    expect(
      render.debugNestedBoundary,
      isFalse,
      reason:
          'the report has to describe the tree as it is now, not as it was '
          'the last time one particular branch happened to run',
    );
  });

  testWidgets('a zero-size box still paints its child through', (tester) async {
    // Every other bail-out paints through; this one used to return
    // without painting, so a child that draws outside a zero box
    // vanished for a layout pass.
    final counter = <int>[0];
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 0,
            height: 0,
            child: StaticRaster(
              debugLabel: 'test',
              child: CustomPaint(painter: _CountingPainter(counter: counter)),
            ),
          ),
        ),
      ),
    );
    expect(counter[0], greaterThan(0));
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

  testWidgets('zones re-bake independently, and nesting would not', (
    tester,
  ) async {
    // PARTIAL RE-BAKE, without anyone declaring anything.
    //
    // GIMP keeps its cache validity as a region and re-renders only the
    // invalid part; doing that here would mean a panel announcing which
    // rectangle changed — and an announcement can be WRONG, which is the
    // one class of bug this design currently makes impossible.
    //
    // Siblings get the same result for free. Dirt from zone A walks up to
    // A's own boundary and stops, so B is untouched; the invalidation is
    // still Flutter's dirty bit and still cannot be wrong. The parent
    // must NOT be a bake itself — a bake inside a bake is the freeze —
    // which is exactly why this is a Column of two, not one wrapping the
    // other.
    final zoneA = <int>[0];
    final zoneB = <int>[0];
    final repaintA = ValueNotifier<int>(0);
    addTearDown(repaintA.dispose);

    await tester.pumpWidget(
      _host(
        Column(
          // ⚠️Stretch, or the cross axis stays LOOSE and a childless
          // `CustomPaint` takes `constraints.smallest` — width zero, so
          // the zones paint through instead of baking and this test
          // measures nothing. That is the fifth time `constraints
          // .smallest` has caught this project.
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Expanded(
              child: StaticRaster(
                debugLabel: 'zone-a',
                child: CustomPaint(
                  painter: _CountingPainter(counter: zoneA, repaint: repaintA),
                ),
              ),
            ),
            Expanded(
              child: StaticRaster(
                debugLabel: 'zone-b',
                child: CustomPaint(painter: _CountingPainter(counter: zoneB)),
              ),
            ),
          ],
        ),
      ),
    );
    expect(zoneA[0], 1);
    expect(zoneB[0], 1);

    final rasters = tester
        .renderObjectList<RenderStaticRaster>(find.byType(StaticRaster))
        .toList();
    expect(rasters, hasLength(2));
    final bakesBefore = rasters.map((r) => r.captureCount).toList();

    // Change ONE zone, three times over.
    for (var i = 0; i < 3; i += 1) {
      repaintA.value += 1;
      await tester.pump(const Duration(seconds: 1));
    }

    expect(zoneA[0], 4, reason: 'the changed zone repainted each time');
    expect(
      zoneB[0],
      1,
      reason:
          'the untouched zone never repainted — that is the partial '
          're-bake, and nobody had to declare a region to get it',
    );
    expect(rasters[0].captureCount, greaterThan(bakesBefore[0]));
    expect(
      rasters[1].captureCount,
      bakesBefore[1],
      reason: 'and it never re-baked either',
    );
  });

  testWidgets('the census prices what the bakes cost', (tester) async {
    // Qt warns about this exact mechanism used exactly the way we use it
    // — a layer per item, `w × h × 4` each. We install bakes on blanket
    // funnels, so the price has to be visible or the default gets
    // abused.
    expect(StaticRaster.censusBytes, 0, reason: 'nothing mounted yet');

    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 100,
            height: 50,
            child: StaticRaster(
              debugLabel: 'test',
              child: CustomPaint(painter: _CountingPainter(counter: <int>[0])),
            ),
          ),
        ),
      ),
    );

    expect(StaticRaster.census, hasLength(1));
    final dpr = tester.view.devicePixelRatio;
    expect(
      StaticRaster.censusBytes,
      (100 * dpr * 50 * dpr * 4).round(),
      reason: 'width x height x 4, at the ratio it was captured for',
    );
    expect(StaticRaster.censusCaptures, greaterThan(0));

    // Unmounting has to give it back, or the report grows for ever.
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    expect(StaticRaster.census, isEmpty);
    expect(StaticRaster.censusBytes, 0);
  });

  testWidgets('a surface painting through holds no bytes', (tester) async {
    await tester.pumpWidget(
      _host(
        StaticRaster(
          debugLabel: 'test',
          child: RepaintBoundary(
            child: CustomPaint(painter: _CountingPainter(counter: <int>[0])),
          ),
        ),
      ),
    );
    expect(StaticRaster.census, hasLength(1));
    expect(
      StaticRaster.censusBytes,
      0,
      reason: 'it declined to bake, so it is holding nothing',
    );
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
