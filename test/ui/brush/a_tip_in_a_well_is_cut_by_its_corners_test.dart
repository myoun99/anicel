import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/brush/brush_tip_preview.dart';
import 'package:anicel/src/ui/theme/app_theme.dart';

/// 🗣️a-live-dock-frame-costs-a-whole-draw-Q10 (유저 2026-11-08, 2: 「그림 안의
/// 자르기를 『자르지 않고 그 모양으로 칠하는』 그리기로 다시 짠다」): a tip's
/// grid in a well is not clipped to the well's corner — a cell that reaches
/// the corner is the well's shape where the cell lies, and the grid is drawn
/// so once.
void main() {
  const side = 16;
  // A square tip: every cell covered, so the corner cells reach the corner.
  final full = Uint8List(side * side)..fillRange(0, side * side, 255);
  const ink = Color(0xFFE6E1E5);
  const ground = Color(0xFF101010);
  const extent = 28.0;
  final well = AppShapes.container(AppShapes.wellRadius);
  final shape = well.borderRadius
      .resolve(TextDirection.ltr)
      .toRSuperellipse(Offset.zero & const Size.square(extent));

  test('in a well, the corner cells are the well cut where they lie, the '
      'rest are cells', () {
    final canvas = TestRecordingCanvas();
    paintBrushTipGrid(
      canvas,
      const Size.square(extent),
      full,
      side,
      ink,
      within: shape,
    );
    final cuts = [
      for (final call in canvas.invocations)
        if (call.invocation.memberName == #clipRect)
          call.invocation.positionalArguments.first as Rect,
    ];
    final shapes = canvas.invocations.where(
      (call) => call.invocation.memberName == #drawRSuperellipse,
    );
    final cells = canvas.invocations.where(
      (call) => call.invocation.memberName == #drawRect,
    );
    expect(cuts, isNotEmpty, reason: 'a corner cell is cut');
    expect(shapes, hasLength(cuts.length));
    expect(cuts.length + cells.length, side * side, reason: 'every cell');
    for (final cut in cuts) {
      expect(
        [
          cut.topLeft,
          cut.topRight,
          cut.bottomLeft,
          cut.bottomRight,
        ].every(shape.contains),
        isFalse,
        reason: 'only a cell reaching past the corner is cut: $cut',
      );
    }
    expect(
      canvas.invocations.where(
        (call) =>
            call.invocation.memberName == #clipRSuperellipse ||
            call.invocation.memberName == #clipPath,
      ),
      isEmpty,
    );
  });

  testWidgets('nothing of a square tip is drawn past its well\'s corner', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(colorScheme: const ColorScheme.dark(onSurface: ink)),
        home: Center(
          child: RepaintBoundary(
            key: const ValueKey<String>('well'),
            child: ColoredBox(
              color: ground,
              child: SizedBox.square(
                dimension: extent,
                child: BrushTipMaskPreview(
                  alpha: full,
                  side: side,
                  well: well,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(const ValueKey<String>('well')),
    );
    final pixels = (await tester.runAsync(() async {
      final image = await boundary.toImage();
      final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      image.dispose();
      return bytes!.buffer.asUint8List();
    }))!;
    int fromGround(int x, int y) =>
        (pixels[(y * extent.round() + x) * 4] - (ground.r * 255).round())
            .abs();

    final last = extent.round() - 1;
    for (final (x, y) in [(0, 0), (last, 0), (0, last), (last, last)]) {
      expect(fromGround(x, y), lessThan(64), reason: 'the corner ($x, $y)');
    }
    expect(
      fromGround(extent ~/ 2, extent ~/ 2),
      greaterThan(200),
      reason: 'fixture: the tip is drawn where it lies',
    );
  });
}
