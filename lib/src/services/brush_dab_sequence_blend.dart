import '../models/brush_dab_sequence.dart';
import '../models/brush_pixel_blend_operation.dart';
import '../models/brush_pixel_coverage.dart';
import '../models/rgba_color.dart';
import '../models/stroke_pixel.dart';
import 'brush_dab_coverage.dart';
import 'brush_pixel_blend.dart';

typedef DestinationPixelReader = RgbaColor Function(int x, int y);

List<BrushPixelBlendOperation> brushPixelBlendOperationsForDabSequence({
  required BrushDabSequence sequence,
  required DestinationPixelReader destinationAt,
}) {
  final operations = <BrushPixelBlendOperation>[];
  // Each pixel as the sequence piles it up — on its 16-bit plane, widened
  // from the destination's bytes the first time a dab reaches it, the way
  // the commit scratch widens a tile ([StrokePixel], ABI 40).
  final currentPixels = <_PixelKey, StrokePixel>{};

  for (final dab in sequence.dabs) {
    // The VISITOR, not the list: this walk folds each pixel as it arrives, so
    // the list the other form builds — and the `unmodifiable` copy of it —
    // would be built only to be thrown away one dab later. (The coverage
    // OBJECT still gets made, because that is what `blendBrushDabStrokePixel`
    // takes; it is the container around them that goes.)
    forEachBrushPixelCoverage(dab, (x, y, value) {
      final coverage = BrushPixelCoverage(x: x, y: y, coverage: value);
      final key = _PixelKey(coverage.x, coverage.y);
      final before =
          currentPixels[key] ??
          StrokePixel.widened(destinationAt(coverage.x, coverage.y));
      final after = blendBrushDabStrokePixel(
        dab: dab,
        coverage: coverage,
        destination: before,
      );

      if (after == before) {
        return;
      }

      currentPixels[key] = after;
      // An operation is a change of BYTES — the plane can move under a
      // view that stays put.
      if (after.bytes == before.bytes) {
        return;
      }
      operations.add(
        BrushPixelBlendOperation(
          x: coverage.x,
          y: coverage.y,
          before: before.bytes,
          after: after.bytes,
        ),
      );
    });
  }

  return List<BrushPixelBlendOperation>.unmodifiable(operations);
}

class _PixelKey {
  const _PixelKey(this.x, this.y);

  final int x;
  final int y;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is _PixelKey && other.x == x && other.y == y;

  @override
  int get hashCode => Object.hash(x, y);
}
