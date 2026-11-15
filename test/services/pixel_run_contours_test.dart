import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/services/pixel_run_contours.dart';

/// The app's door to the outline walk the selection's ants and a held
/// fill's mark share ([pixelRunContours]): the rows handed over as the
/// engine reads runs, and its points brought back into canvas space.
/// ⛔Where the walk goes — its order, its merges, its holes — is pinned once,
/// on the walk itself (`rust/src/kernels/mask/contours_tests.rs`); these
/// pin only what this side adds.
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
    ).points)
      [for (final point in contour) (point.x, point.y)],
  ];

  test('a block is its four corners, from its top-left going right, in '
      'canvas space', () {
    expect(walk([[0, 3], [0, 3]], width: 3, left: 10, top: 20), [
      [(10.0, 20.0), (13.0, 20.0), (13.0, 22.0), (10.0, 22.0)],
    ]);
  });

  test('rows of runs of their own lengths are each read as their own — a '
      'hole between two runs of a row, a row of none below', () {
    expect(
      walk(
        [
          [0, 5],
          [0, 1, 3, 5],
          [0, 5],
          [],
        ],
        width: 5,
        left: -2,
        top: 7,
      ),
      [
        [(-2.0, 7.0), (3.0, 7.0), (3.0, 10.0), (-2.0, 10.0)],
        [(-1.0, 8.0), (-1.0, 9.0), (1.0, 9.0), (1.0, 8.0)],
      ],
    );
  });

  test('nothing held is no contour', () {
    expect(walk([[], []], width: 4), isEmpty);
    expect(walk([], width: 4), isEmpty);
  });
}
