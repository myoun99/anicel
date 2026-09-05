import 'dart:math' as math;
import 'dart:typed_data';

/// Area-average downscale of an 8-bit COVERAGE map.
///
/// 🚨AVERAGED, not sampled. A tip mask is coverage, and a resize that
/// reads one source pixel per destination pixel drops the thin parts of a
/// stroke entirely — the failure `resample_kernel.dart` describes for
/// point sampling under reduction ("a destination pixel is not a point").
/// Averaging every source pixel the destination covers keeps the ink that
/// was drawn, at the weight it was drawn.
///
/// The two-value argument that keeps the stamp path on Pick does not
/// apply here: a tip mask is coverage, and a partly covered tip pixel is
/// a real thing rather than an invented mid-alpha edge.
///
/// ⛔DOWNSCALE only. Every destination pixel is taken to cover at least
/// one source pixel — `math.max(start + 1, …)` is what keeps a degenerate
/// box from being empty — which is true while `new <= old`. Enlarging
/// through here would nearest-neighbour, and the shared resampler
/// (`resampleRgbaReferenceInto`) is the answer for that.
Uint8List areaAveragedGray(
  Uint8List source, {
  required int width,
  required int height,
  required int newWidth,
  required int newHeight,
}) {
  final out = Uint8List(newWidth * newHeight);
  for (var y = 0; y < newHeight; y += 1) {
    final srcTop = y * height ~/ newHeight;
    final srcBottom = math.max(srcTop + 1, (y + 1) * height ~/ newHeight);
    for (var x = 0; x < newWidth; x += 1) {
      final srcLeft = x * width ~/ newWidth;
      final srcRight = math.max(srcLeft + 1, (x + 1) * width ~/ newWidth);
      var sum = 0;
      var count = 0;
      for (var sy = srcTop; sy < srcBottom && sy < height; sy += 1) {
        for (var sx = srcLeft; sx < srcRight && sx < width; sx += 1) {
          sum += source[sy * width + sx];
          count += 1;
        }
      }
      out[y * newWidth + x] = count == 0 ? 0 : sum ~/ count;
    }
  }
  return out;
}
