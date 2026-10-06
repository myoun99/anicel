import 'dart:typed_data';
import 'dart:ui' show ImageByteFormat;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/brush_stamp_image.dart';
import 'package:anicel/src/models/cut_piece.dart';
import 'package:anicel/src/ui/brush/cut_piece_preview.dart';

/// 🗣️F-271 (유저 2026-10-03): 「잘라내기도구의 스탬프 서브도구, 도구설정의
/// 프리뷰의 배경이 투명(격자무늬)인데 투명인건 맞는데 배경 그냥 흰색으로.」
///
/// ↩️The preview stood on the app's transparency checker — white with 8px
/// grey cells — so that open alpha read as open. The user asked for the
/// plain ground under this one.
void main() {
  testWidgets('the held piece is shown on plain white — no checker cell '
      'anywhere under it', (tester) async {
    // A piece with nothing in it: every pixel of the preview is its ground.
    final piece = CutPiece(
      image: BrushStampImage(
        id: 'empty',
        width: 40,
        height: 24,
        rgba: Uint8List(40 * 24 * 4),
      ),
      originLeft: 0,
      originTop: 0,
    );
    const capture = ValueKey<String>('capture');
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: RepaintBoundary(
            key: capture,
            // Wider and taller than several 8px checker cells.
            child: SizedBox(
              width: 96,
              height: 64,
              child: CutPiecePreview(piece: piece),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final image = tester
        .renderObject<RenderRepaintBoundary>(find.byKey(capture))
        .toImageSync();
    late Set<int> colours;
    await tester.runAsync(() async {
      final data = await image.toByteData(format: ImageByteFormat.rawRgba);
      final bytes = data!.buffer.asUint8List();
      colours = {
        for (var i = 0; i < bytes.length; i += 4)
          (bytes[i + 3] << 24) |
              (bytes[i] << 16) |
              (bytes[i + 1] << 8) |
              bytes[i + 2],
      };
    });
    image.dispose();

    expect(
      colours,
      {0xFFFFFFFF},
      reason: '⛔a second colour is a checker cell (0xFFCCCCCC) or a ground '
          'that is not white',
    );
  });
}
