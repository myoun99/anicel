import '../models/brush_dab_sequence.dart';
import '../models/brush_pixel_blend_operation.dart';
import '../models/rgba_color.dart';
import 'brush_dab_coverage.dart';
import 'brush_pixel_blend.dart';

typedef DestinationPixelReader = RgbaColor Function(int x, int y);

List<BrushPixelBlendOperation> brushPixelBlendOperationsForDabSequence({
  required BrushDabSequence sequence,
  required DestinationPixelReader destinationAt,
}) {
  final operations = <BrushPixelBlendOperation>[];
  final currentColors = <_PixelKey, RgbaColor>{};

  for (final dab in sequence.dabs) {
    for (final coverage in brushPixelCoveragesForDab(dab)) {
      final key = _PixelKey(coverage.x, coverage.y);
      final before =
          currentColors[key] ?? destinationAt(coverage.x, coverage.y);
      final after = blendBrushDabPixelCoverage(
        dab: dab,
        coverage: coverage,
        destination: before,
      );

      if (after == before) {
        continue;
      }

      currentColors[key] = after;
      operations.add(
        BrushPixelBlendOperation(
          x: coverage.x,
          y: coverage.y,
          before: before,
          after: after,
        ),
      );
    }
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
