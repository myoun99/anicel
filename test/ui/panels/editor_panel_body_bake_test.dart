import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/ui/panels/editor_panel_body.dart';
import 'package:anicel/src/ui/panels/editor_panel_frame.dart';
import 'package:anicel/src/ui/widgets/static_raster.dart';

/// The contract behind "a new panel is light without its author doing
/// anything": whatever goes through the shared body gets baked, and the
/// bake sits INSIDE the scroll view so scrolling is a layer offset
/// rather than a re-raster.
///
/// Both halves are load-bearing and neither is visible by inspection —
/// a panel that lost its bake looks exactly like one that has it.
class _CountingPainter extends CustomPainter {
  _CountingPainter(this.counter);

  final List<int> counter;

  @override
  void paint(Canvas canvas, Size size) {
    counter[0] += 1;
    canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xFF123456));
  }

  @override
  bool shouldRepaint(_CountingPainter oldDelegate) => false;
}

Widget _host(Widget child) => MaterialApp(
  home: Scaffold(body: SizedBox(width: 260, height: 300, child: child)),
);

void main() {
  testWidgets('the shared body bakes its child, scrolling or not', (
    tester,
  ) async {
    for (final scrolls in <bool>[true, false]) {
      await tester.pumpWidget(
        _host(
          EditorPanelBody(
            scrollable: scrolls,
            debugLabel: 'probe',
            child: const SizedBox(height: 100),
          ),
        ),
      );
      expect(
        find.byType(StaticRaster),
        findsOneWidget,
        reason: 'a panel body is baked whether or not it scrolls ($scrolls)',
      );
    }
  });

  testWidgets('the bake is INSIDE the scroll view, not around it', (
    tester,
  ) async {
    // A viewport is itself a repaint boundary, so a bake wrapped AROUND
    // a scrolling body can never capture anything — it would find the
    // viewport and paint through, silently, forever. This is the
    // assertion that would have caught that.
    await tester.pumpWidget(
      _host(
        EditorPanelBody(
          debugLabel: 'probe',
          child: const SizedBox(height: 100),
        ),
      ),
    );

    expect(
      find.descendant(
        of: find.byType(SingleChildScrollView),
        matching: find.byType(StaticRaster),
      ),
      findsOneWidget,
    );
    final render = tester.renderObject<RenderStaticRaster>(
      find.byType(StaticRaster),
    );
    expect(
      render.debugNestedBoundary,
      isFalse,
      reason: 'nothing in the way: ${render.debugNestedBoundaryPath}',
    );
    expect(render.captureCount, 1, reason: 'and it actually baked');
  });

  testWidgets('scrolling a baked body does not re-bake it', (tester) async {
    final counter = <int>[0];
    await tester.pumpWidget(
      _host(
        EditorPanelBody(
          debugLabel: 'probe',
          child: SizedBox(
            height: 900,
            child: CustomPaint(painter: _CountingPainter(counter)),
          ),
        ),
      ),
    );
    final render = tester.renderObject<RenderStaticRaster>(
      find.byType(StaticRaster),
    );
    final baked = render.captureCount;
    expect(baked, 1);
    expect(counter[0], 1);

    await tester.drag(find.byType(SingleChildScrollView), const Offset(0, -200));
    await tester.pump();
    await tester.drag(find.byType(SingleChildScrollView), const Offset(0, -200));
    await tester.pump();

    expect(
      render.captureCount,
      baked,
      reason:
          'the viewport composites a boundaried child at the new offset — '
          'scrolling is a layer move, not a repaint',
    );
    expect(counter[0], 1);
  });

  testWidgets('a framed panel names its bake after the panel', (tester) async {
    await tester.pumpWidget(
      _host(
        const EditorPanelFrame(
          title: 'Probe',
          child: SizedBox(height: 100),
        ),
      ),
    );
    final render = tester.renderObject<RenderStaticRaster>(
      find.byType(StaticRaster),
    );
    expect(
      render.debugLabel,
      'body:Probe',
      reason: 'the standing report has to say WHICH panel it is talking about',
    );
  });
}
