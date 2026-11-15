import 'dart:typed_data';

/// Where a box's ink is: its weight, the centre of that weight, and the
/// rows that hold any — and the box.
typedef CoverageInk = ({
  double sum,
  double cx,
  double cy,
  List<int> rows,
  ({int width, int height}) box,
});

/// The ink of [alpha] — coverage, a byte a pixel, [width] × [height] row by
/// row: what a word's bake is told from another's by.
CoverageInk coverageInkOf(Uint8List alpha, int width, int height) {
  var sum = 0.0;
  var sumX = 0.0;
  var sumY = 0.0;
  final rows = <int>[];
  for (var y = 0; y < height; y += 1) {
    var inked = false;
    for (var x = 0; x < width; x += 1) {
      final a = alpha[y * width + x];
      sum += a;
      sumX += a * (x + 0.5);
      sumY += a * (y + 0.5);
      inked = inked || a > 0;
    }
    if (inked) {
      rows.add(y);
    }
  }
  return (
    sum: sum,
    cx: sumX / sum,
    cy: sumY / sum,
    rows: rows,
    box: (width: width, height: height),
  );
}
