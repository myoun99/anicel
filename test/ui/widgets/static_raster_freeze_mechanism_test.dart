import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/ui/widgets/static_raster.dart';

/// Proof that the invariant [StaticRaster] enforces is REAL.
///
/// The wrapper refuses to bake a subtree that contains another repaint
/// boundary, and everything about that refusal — the per-capture walk,
/// the paint-through fallback, the standing report of which panels
/// therefore pay full price — is built on a claim about the framework:
///
/// > `markNeedsPaint` stops at the first boundary it reaches. Once the
/// > child's layers are detached, `_skippedPaintingOnLayer` walks up,
/// > stops at the first ATTACHED ancestor, and does not mark it. So an
/// > inner boundary can never be reached again.
///
/// That claim was read out of the SDK, not observed. If it were wrong,
/// the guard would be pure cost — every scrolling panel in the app
/// declines to bake because of it.
///
/// So this file builds the unguarded version of the same render object
/// and shows the freeze happening. It touches nothing in `lib/`: the
/// mechanism belongs to Flutter, not to us, and the point is to pin the
/// framework behaviour our design leans on. If a Flutter upgrade ever
/// makes this test fail, the guard can be deleted — and until it does,
/// nobody has to take the invariant on trust.
class _UnguardedBake extends SingleChildRenderObjectWidget {
  const _UnguardedBake({required Widget super.child});

  @override
  _RenderUnguardedBake createRenderObject(BuildContext context) =>
      _RenderUnguardedBake();
}

/// [StaticRaster] with the nested-boundary check removed, and nothing
/// else changed.
class _RenderUnguardedBake extends RenderProxyBox {
  @override
  bool get isRepaintBoundary => true;

  ui.Image? _raster;
  Size? _sourceSize;
  int captures = 0;

  @override
  void paint(PaintingContext context, Offset offset) {
    if (size.isEmpty) {
      return;
    }
    _raster?.dispose();
    final layer = OffsetLayer();
    final captureContext = PaintingContext(layer, Offset.zero & size);
    super.paint(captureContext, Offset.zero);
    // ignore: invalid_use_of_protected_member
    captureContext.stopRecordingIfNeeded();
    _raster = layer.toImageSync(Offset.zero & size, pixelRatio: 1);
    layer.dispose();
    _sourceSize = size;
    captures += 1;

    context.canvas.drawImageRect(
      _raster!,
      Offset.zero & _sourceSize!,
      offset & size,
      Paint()..filterQuality = FilterQuality.none,
    );
  }

  @override
  void dispose() {
    _raster?.dispose();
    _raster = null;
    super.dispose();
  }
}

class _CountingPainter extends CustomPainter {
  _CountingPainter({required this.counter, super.repaint});

  final List<int> counter;

  @override
  void paint(Canvas canvas, Size size) {
    counter[0] += 1;
    canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xFF00FF00));
  }

  @override
  bool shouldRepaint(_CountingPainter oldDelegate) => false;
}

Widget _host(Widget child) => MaterialApp(
  home: Center(child: SizedBox(width: 80, height: 80, child: child)),
);

void main() {
  testWidgets('WITHOUT the guard, an inner boundary freezes forever', (
    tester,
  ) async {
    final counter = <int>[0];
    final repaint = ValueNotifier<int>(0);
    addTearDown(repaint.dispose);

    await tester.pumpWidget(
      _host(
        _UnguardedBake(
          child: RepaintBoundary(
            child: CustomPaint(
              painter: _CountingPainter(counter: counter, repaint: repaint),
            ),
          ),
        ),
      ),
    );
    final painted = counter[0];
    expect(painted, greaterThan(0));

    // Dirty the inner subtree, hard, many times over many frames.
    for (var i = 0; i < 20; i += 1) {
      repaint.value += 1;
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(
      counter[0],
      painted,
      reason:
          'THIS is the freeze the guard exists to prevent: twenty explicit '
          'repaint requests and the inner subtree never painted again. Its '
          'layer is detached, so markNeedsPaint marks IT, flushPaint sends '
          'it to _skippedPaintingOnLayer, and that stops at the first '
          'attached ancestor — the bake — without marking it.',
    );
  });

  testWidgets('WITH the guard, the same tree stays live', (tester) async {
    final counter = <int>[0];
    final repaint = ValueNotifier<int>(0);
    addTearDown(repaint.dispose);

    await tester.pumpWidget(
      _host(
        StaticRaster(
          debugLabel: 'guarded',
          child: RepaintBoundary(
            child: CustomPaint(
              painter: _CountingPainter(counter: counter, repaint: repaint),
            ),
          ),
        ),
      ),
    );
    final painted = counter[0];

    for (var i = 0; i < 20; i += 1) {
      repaint.value += 1;
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(
      counter[0],
      greaterThan(painted),
      reason: 'the guard declines to bake, so the subtree keeps updating',
    );
    final render = tester.renderObject<RenderStaticRaster>(
      find.byType(StaticRaster),
    );
    expect(render.captureCount, 0);
    expect(render.debugNestedBoundary, isTrue);
  });
}
