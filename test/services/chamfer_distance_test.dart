// THE 3-4 CHAMFER: AN ORTHOGONAL STEP COSTS 3, A DIAGONAL 4, AND THE
// BORDER COSTS WHAT THE CALLER SAYS IT COSTS.
//
// The mutation that raised a diagonal weight to 5 survived every fill and
// feather pin (their thresholds are multiples of 3, so 4 and 5 fall in the
// same bucket). This reads the distances themselves.
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/services/mask_soft_edge.dart';

void main() {
  const infinity = 60000;

  Uint16List distancesFrom(
    List<int> source, {
    required int width,
    required int height,
    required int borderDistance,
  }) {
    final target = Uint16List(width * height);
    chamferDistance34(
      target,
      from: Uint8List.fromList(source),
      zeroWhen: 1,
      width: width,
      height: height,
      infinity: infinity,
      borderDistance: borderDistance,
    );
    return target;
  }

  test('one source in the top-left corner: 3 per orthogonal step, 4 per '
      'diagonal, and the forward pass alone reaches every pixel', () {
    final dist = distancesFrom(
      [1, 0, 0, 0, 0, 0, 0, 0, 0],
      width: 3,
      height: 3,
      borderDistance: infinity,
    );
    expect(dist, [0, 3, 6, 3, 4, 7, 6, 7, 8]);
  });

  test('one source in the bottom-right corner: the backward pass carries '
      'the same weights', () {
    final dist = distancesFrom(
      [0, 0, 0, 0, 0, 0, 0, 0, 1],
      width: 3,
      height: 3,
      borderDistance: infinity,
    );
    expect(dist, [8, 7, 6, 7, 4, 3, 6, 3, 0]);
  });

  test('no source at all saturates at infinity — the canvas edge is not '
      'a barrier', () {
    final dist = distancesFrom(
      [0, 0, 0, 0],
      width: 2,
      height: 2,
      borderDistance: infinity,
    );
    expect(dist, [infinity, infinity, infinity, infinity]);
  });

  test('a border distance seeds the four border lines and propagates '
      'inward from them', () {
    // 4×4, no source: the rim is 3, the middle four are 6.
    final dist = distancesFrom(
      List.filled(16, 0),
      width: 4,
      height: 4,
      borderDistance: 3,
    );
    expect(dist, [3, 3, 3, 3, 3, 6, 6, 3, 3, 6, 6, 3, 3, 3, 3, 3]);
  });

  test('a source on the border still reads 0, not the border distance', () {
    final dist = distancesFrom(
      [1, 0, 0, 0],
      width: 2,
      height: 2,
      borderDistance: 3,
    );
    expect(dist, [0, 3, 3, 3]);
  });
}
