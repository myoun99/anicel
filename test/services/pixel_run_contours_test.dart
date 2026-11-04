import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/services/pixel_run_contours.dart';

/// The outline walk the selection's ants and a held fill's mark share
/// ([pixelRunContours]), pinned by the exact points it gives: the order is
/// the law — a contour starts where the scan first met it, so the dashes
/// stay put.
void main() {
  List<List<(double, double)>> walk(
    List<List<int>> rows, {
    required int width,
    int left = 0,
    int top = 0,
  }) => [
    for (final contour in pixelRunContours(
      rows,
      left: left,
      top: top,
      width: width,
    ))
      [for (final point in contour) (point.x, point.y)],
  ];

  List<List<int>> rowsOf(
    bool Function(int x, int y) covered, {
    required int width,
    required int height,
  }) => [
    for (var y = 0; y < height; y += 1)
      [
        for (var x = 0; x <= width; x += 1)
          if ((x < width && covered(x, y)) !=
              (x > 0 && covered(x - 1, y)))
            x,
      ],
  ];

  test('a block is its four corners, from its top-left going right, in '
      'canvas space', () {
    expect(walk([[0, 3], [0, 3]], width: 3, left: 10, top: 20), [
      [(10.0, 20.0), (13.0, 20.0), (13.0, 22.0), (10.0, 22.0)],
    ]);
  });

  test('two pixels that meet only at a corner are one walk through that '
      'corner — its later edge first', () {
    expect(walk([[0, 1], [1, 2]], width: 2), [
      [
        (0.0, 0.0),
        (1.0, 0.0),
        (1.0, 1.0),
        (2.0, 1.0),
        (2.0, 2.0),
        (1.0, 2.0),
        (1.0, 1.0),
        (0.0, 1.0),
      ],
    ]);
  });

  test('holes come after the outline that holds them, in the order the scan '
      'meets them — past the size the edge table starts at', () {
    // 225 one-pixel holes: over a thousand vertices with an edge, so the
    // table grows twice on the way.
    bool hole(int x, int y) => x % 4 == 1 && y % 4 == 1 && x < 60 && y < 60;
    final contours = walk(
      rowsOf((x, y) => !hole(x, y), width: 64, height: 64),
      width: 64,
    );
    expect(contours, [
      [(0.0, 0.0), (64.0, 0.0), (64.0, 64.0), (0.0, 64.0)],
      for (var y = 1; y < 60; y += 4)
        for (var x = 1; x < 60; x += 4)
          [
            (x + 1.0, y.toDouble()),
            (x.toDouble(), y.toDouble()),
            (x.toDouble(), y + 1.0),
            (x + 1.0, y + 1.0),
          ],
    ]);
  });
}
