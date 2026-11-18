import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/brush_tip_entry.dart'
    show brushTipThumbnailSide;
import 'package:anicel/src/ui/brush/brush_tip_preview.dart';

/// 🚨ONE CELL A BYTE (tip-coverage-is-a-second-r1-Q1): a tip's picture is
/// its mask already read down by the engine's R1, so the grid draws each
/// byte as its cell — no average of its own beside that resampler.
void main() {
  test('each cell of the grid is its byte of the picture, where it lies, '
      'and a clear byte is no cell', () {
    const side = brushTipThumbnailSide;
    final picture = Uint8List.fromList([
      // Every other byte clear, the rest each its own.
      for (var i = 0; i < side * side; i += 1) i % 2 * (i % 251 + 1),
    ]);
    const ink = Color(0xFFE6E1E5);
    final canvas = TestRecordingCanvas();
    paintBrushTipGrid(
      canvas,
      const Size.square(side * 2.0),
      picture,
      ink,
    );

    final cells = [
      for (final call in canvas.invocations)
        if (call.invocation.memberName == #drawRect)
          (
            call.invocation.positionalArguments[0] as Rect,
            call.invocation.positionalArguments[1] as Paint,
          ),
    ];
    expect(cells, hasLength(side * side ~/ 2));
    for (final (at, paint) in cells) {
      final index = (at.top / 2).round() * side + (at.left / 2).round();
      expect(
        (paint.color.a * 255).round(),
        picture[index],
        reason: 'the cell at $at',
      );
    }
  });
}
