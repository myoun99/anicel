import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/core/red_and_blue_swapped.dart';

/// The swap the cursor and the screen check share: each texel's first and
/// third bytes trade places, the second and fourth stand, and what was
/// handed in stands too.
void main() {
  test('each texel\'s first and third bytes trade places, alone', () {
    final pixels = Uint8List.fromList([1, 2, 3, 4, 11, 12, 13, 14]);

    final swapped = redAndBlueSwapped(ByteData.sublistView(pixels));

    expect(swapped, [3, 2, 1, 4, 13, 12, 11, 14]);
    expect(pixels, [1, 2, 3, 4, 11, 12, 13, 14], reason: 'a copy');
  });
}
