import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/brush/brush_tip_preview.dart';

/// 🚨A SAMPLED TIP'S GRID IS DRAWN ONCE AND PLACED 1:1 EVERY FRAME
/// (유저 2026-09-24, `tip-icons-every-frame-Q1`: 「한 번 그린 그림을 쓴다」).
/// A panel may move by the offscreen blend's rounding — only the canvas may
/// not — so the drawing is held to the grid painted live within 3/255, at
/// every ratio, overhang included.
void main() {
  const side = 32;
  final mask = _softDisc(side);
  const ink = Color(0xFFE6E1E5);
  const well = Color(0xFF36343B);

  testWidgets('a repaint places the drawing it made, and paints no rect', (
    tester,
  ) async {
    await tester.pumpWidget(_icon(mask, side, ink: ink, extent: 24));
    final grid = tester.renderObject<RenderBrushTipGrid>(
      find.byType(BrushTipMaskPreview),
    );
    final first = grid.debugDrawing;
    expect(first, isNotNull);

    grid.markNeedsPaint();
    await tester.pump();
    expect(grid.debugDrawing, same(first));
    expect(grid, paints..drawImageRect(image: first));
    expect(grid, paintsExactlyCountTimes(#drawRect, 0));
  });

  for (final ratio in const [1.0, 1.5, 2.0, 3.0]) {
    testWidgets('at $ratio the drawing is the grid painted live, within 3/255', (
      tester,
    ) async {
      tester.view.devicePixelRatio = ratio;
      addTearDown(tester.view.resetDevicePixelRatio);
      final drawn = GlobalKey();
      final live = GlobalKey();
      // A non-square box: the grid is its shortest side, from the top left.
      Widget framed(Key key, Widget icon) => RepaintBoundary(
        key: key,
        child: ColoredBox(
          color: well,
          child: Padding(
            padding: const EdgeInsets.all(4),
            child: SizedBox(width: 30, height: 24, child: icon),
          ),
        ),
      );
      await tester.pumpWidget(
        _themed(
          ink,
          Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              framed(drawn, BrushTipMaskPreview(alpha: mask, side: side)),
              framed(
                live,
                CustomPaint(
                  painter: _LiveGrid(mask, side, ink),
                  size: Size.infinite,
                ),
              ),
            ],
          ),
        ),
      );

      final a = await _pixels(tester, drawn, ratio);
      final b = await _pixels(tester, live, ratio);
      expect(a.length, b.length);
      var worst = 0;
      var inked = 0;
      final background = [well.r, well.g, well.b].map(_byte).toList();
      for (var i = 0; i < a.length; i += 4) {
        for (var c = 0; c < 4; c += 1) {
          worst = math.max(worst, (a[i + c] - b[i + c]).abs());
        }
        if (b[i] != background[0]) {
          inked += 1;
        }
      }
      expect(inked, greaterThan(100), reason: 'the live grid painted a tip');
      expect(worst, lessThanOrEqualTo(3));
    });
  }

  testWidgets('a new look, a new size and leaving each let the old drawing '
      'go', (tester) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(_icon(mask, side, ink: ink, extent: 24));
    final grid = tester.renderObject<RenderBrushTipGrid>(
      find.byType(BrushTipMaskPreview),
    );
    final first = grid.debugDrawing!;
    expect(first.width, 25, reason: '24 across and the half-pixel overhang');

    await tester.pumpWidget(
      _icon(mask, side, ink: const Color(0xFF6750A4), extent: 24),
    );
    expect(first.debugDisposed, isTrue);
    final recoloured = grid.debugDrawing!;
    expect(recoloured, isNot(same(first)));

    await tester.pumpWidget(
      _icon(mask, side, ink: const Color(0xFF6750A4), extent: 30),
    );
    expect(recoloured.debugDisposed, isTrue);
    final resized = grid.debugDrawing!;
    expect(resized.width, 31);

    tester.view.devicePixelRatio = 2;
    await tester.pump();
    expect(resized.debugDisposed, isTrue);
    final sharper = grid.debugDrawing!;
    expect(sharper.width, 61);

    await tester.pumpWidget(const SizedBox());
    expect(sharper.debugDisposed, isTrue);
  });
}

/// A `Theme` of its own rather than the app's: `MaterialApp` animates a new
/// theme in, and the first frame after a change still paints the old ink.
Widget _themed(Color ink, Widget child) => MaterialApp(
  home: Theme(
    data: ThemeData(colorScheme: ColorScheme.dark(onSurface: ink)),
    child: Align(alignment: Alignment.topLeft, child: child),
  ),
);

Widget _icon(
  Uint8List mask,
  int side, {
  required Color ink,
  required double extent,
}) => _themed(
  ink,
  SizedBox.square(
    dimension: extent,
    child: BrushTipMaskPreview(alpha: mask, side: side),
  ),
);

/// A disc that fades from its centre, so neighbouring cells differ and the
/// edge cells are partly covered.
Uint8List _softDisc(int side) {
  final alpha = Uint8List(side * side);
  final centre = side / 2;
  for (var y = 0; y < side; y += 1) {
    for (var x = 0; x < side; x += 1) {
      final d = math.sqrt(
        math.pow(x + 0.5 - centre, 2) + math.pow(y + 0.5 - centre, 2),
      );
      alpha[y * side + x] = (255 * (1 - d / centre)).clamp(0, 255).round();
    }
  }
  return alpha;
}

int _byte(double channel) => (channel * 255).round();

Future<Uint8List> _pixels(WidgetTester tester, GlobalKey key, double ratio) {
  final boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  return tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: ratio);
    try {
      final bytes = await image.toByteData();
      return bytes!.buffer.asUint8List();
    } finally {
      image.dispose();
    }
  }).then((bytes) => bytes!);
}

class _LiveGrid extends CustomPainter {
  _LiveGrid(this.alpha, this.side, this.color);

  final Uint8List alpha;
  final int side;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) =>
      paintBrushTipGrid(canvas, size, alpha, side, color);

  @override
  bool shouldRepaint(_LiveGrid oldDelegate) => false;
}
