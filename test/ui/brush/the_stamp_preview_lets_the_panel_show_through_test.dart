import 'dart:typed_data';
import 'dart:ui' show ImageByteFormat;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/brush_stamp_image.dart';
import 'package:anicel/src/models/cut_piece.dart';
import 'package:anicel/src/ui/brush/cut_piece_preview.dart';

import '../../helpers/settle_async.dart';

/// 🗣️F-271 (유저 2026-10-08, 정정): 「흰색말고 투명인채로 하는데, 격자무늬가
/// 아니라 브러시 프리뷰에서 쓰는것마냥 뒤 패널색이 되는것? 즉 뒤가 비치도록.」
///
/// ↩️The preview stood on the app's transparency checker, then on white
/// (유저 10-03). Now it paints no ground at all, as the brush's stroke in
/// the same box paints none: what is behind the box is what shows.
void main() {
  const width = 96;
  const height = 64;
  const red = 0xFFFF0000;

  /// A piece whose left half is opaque red and whose right half is empty.
  CutPiece halfRed() {
    final rgba = Uint8List(40 * 24 * 4);
    for (var y = 0; y < 24; y++) {
      for (var x = 0; x < 20; x++) {
        final i = (y * 40 + x) * 4;
        rgba[i] = 0xFF;
        rgba[i + 3] = 0xFF;
      }
    }
    return CutPiece(
      image: BrushStampImage(id: 'half-red', width: 40, height: 24, rgba: rgba),
      originLeft: 0,
      originTop: 0,
    );
  }

  /// The preview of [piece] over a panel of [panel], as ARGB pixels in rows,
  /// once its image has been decoded and drawn — or once [settleAsync]'s
  /// patience has run out.
  Future<List<int>> pixelsOver(
    WidgetTester tester,
    CutPiece piece,
    Color panel,
  ) async {
    const capture = ValueKey<String>('capture');
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: RepaintBoundary(
            key: capture,
            child: ColoredBox(
              color: panel,
              child: SizedBox(
                width: width.toDouble(),
                height: height.toDouble(),
                child: CutPiecePreview(piece: piece),
              ),
            ),
          ),
        ),
      ),
    );
    late List<int> pixels;
    // The piece decodes off the fake clock.
    await settleAsync(tester, () async {
      final image = tester
          .renderObject<RenderRepaintBoundary>(find.byKey(capture))
          .toImageSync();
      await tester.runAsync(() async {
        final data = await image.toByteData(format: ImageByteFormat.rawRgba);
        final bytes = data!.buffer.asUint8List();
        pixels = [
          for (var i = 0; i < bytes.length; i += 4)
            (bytes[i + 3] << 24) |
                (bytes[i] << 16) |
                (bytes[i + 1] << 8) |
                bytes[i + 2],
        ];
      });
      image.dispose();
      return pixels.contains(red);
    });
    return pixels;
  }

  for (final panel in const [Color(0xFF203040), Color(0xFFE0E4E8)]) {
    testWidgets('🚨where the piece is empty the panel behind it shows — no '
        'white ground and no checker cell (panel '
        '${panel.toARGB32().toRadixString(16)})', (tester) async {
      final pixels = await pixelsOver(tester, halfRed(), panel);
      expect(
        pixels,
        contains(red),
        reason: '⛔premise: the piece is drawn — a preview that drew nothing '
            'would show the panel everywhere too',
      );
      expect(
        pixels[(height ~/ 2) * width + width - 2],
        panel.toARGB32(),
        reason: 'the empty half, at the box\'s right edge, is the panel',
      );
      expect(pixels, isNot(contains(0xFFFFFFFF)), reason: 'no white ground');
      expect(pixels, isNot(contains(0xFFCCCCCC)), reason: 'no checker cell');
    });
  }
}
