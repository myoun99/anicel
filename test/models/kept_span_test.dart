import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/kept_span.dart';

void main() {
  test('no IN/OUT keeps the whole source', () {
    final span = KeptSpan(length: 10);

    expect((span.first, span.last, span.count), (0, 9, 10));
  });

  test('IN and OUT keep the frames between them, both ends included', () {
    final span = KeptSpan(length: 10, inFrame: 2, outFrame: 5);

    expect((span.first, span.last, span.count), (2, 5, 4));
  });

  test('IN outside the source is clamped into it', () {
    expect(KeptSpan(length: 10, inFrame: -3).first, 0);
    expect(KeptSpan(length: 10, inFrame: 40).first, 9);
  });

  test('OUT past the source is its last frame, and OUT before IN is IN', () {
    expect(KeptSpan(length: 10, outFrame: 40).last, 9);
    expect(KeptSpan(length: 10, inFrame: 6, outFrame: 3).last, 6);
  });
}
