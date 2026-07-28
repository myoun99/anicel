import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/brush_dab.dart';
import 'package:anicel/src/models/brush_tip_shape.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/services/brush_live_stroke_rasterizer.dart';

BrushDab _dab({required double x, required double y, double size = 10}) {
  return BrushDab(
    center: CanvasPoint(x: x, y: y),
    color: 0xFF204080,
    size: size,
    opacity: 1,
    flow: 1,
    hardness: 1,
    tipShape: BrushTipShape.round,
    pressure: 1,
    sequence: 0,
  );
}

void main() {
  group('BrushLiveStrokeRasterizer sparseness', () {
    test('a small stroke on a huge canvas allocates only its tiles', () {
      // The point of the sparse storage: the timesheet ink planes are
      // logically huge, and a stroke must never pay for the whole surface.
      final rasterizer = BrushLiveStrokeRasterizer(
        canvasSize: const CanvasSize(width: 8000, height: 40000),
      );
      expect(rasterizer.allocatedTileCount, 0);

      rasterizer.blendFrom([_dab(x: 5000.5, y: 30000.5)], from: 0);
      expect(
        rasterizer.allocatedTileCount,
        lessThanOrEqualTo(4),
        reason: 'a 10px dab spans at most a 2x2 tile neighborhood',
      );

      rasterizer.clear();
      expect(rasterizer.allocatedTileCount, 0);
      expect(rasterizer.strokeBounds, isNull);
    });

    test('copyRow reads painted pixels and zeros elsewhere, across tile '
        'boundaries', () {
      final rasterizer = BrushLiveStrokeRasterizer(
        canvasSize: const CanvasSize(width: 512, height: 512),
      );
      // Straddle the 128px tile boundary at x=128.
      rasterizer.blendFrom([_dab(x: 128.0, y: 64.5, size: 8)], from: 0);
      final bounds = rasterizer.strokeBounds!;
      expect(bounds.left, lessThan(128));
      expect(bounds.rightExclusive, greaterThan(128));

      final row = Uint8List(512 * 4);
      rasterizer.copyRow(0, 64, 512, row, 0);
      // Painted at the dab center on both sides of the boundary.
      expect(row[127 * 4 + 3], 255);
      expect(row[128 * 4 + 3], 255);
      // Transparent far away (unallocated tiles read as zeros).
      expect(row[300 * 4 + 3], 0);
      expect(row[0 + 3], 0);
    });

    test('strokePixelsWithinBounds is bounds-local row-major', () {
      final rasterizer = BrushLiveStrokeRasterizer(
        canvasSize: const CanvasSize(width: 512, height: 512),
      );
      expect(rasterizer.strokePixelsWithinBounds(), isNull);

      rasterizer.blendFrom([_dab(x: 200.5, y: 300.5, size: 8)], from: 0);
      final bounds = rasterizer.strokeBounds!;
      final buffer = rasterizer.strokePixelsWithinBounds()!;
      final width = bounds.rightExclusive - bounds.left;
      final height = bounds.bottomExclusive - bounds.top;
      expect(buffer.length, width * height * 4);

      // The dab center maps to the bounds-local coordinate.
      final centerOffset =
          ((300 - bounds.top) * width + (200 - bounds.left)) * 4;
      expect(buffer[centerOffset + 3], 255);
      expect(buffer[centerOffset], 0x20);
      expect(buffer[centerOffset + 1], 0x40);
      expect(buffer[centerOffset + 2], 0x80);
    });
  });
}
