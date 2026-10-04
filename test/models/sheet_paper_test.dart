import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/sheet_paper.dart';

/// A SHEET PANEL'S PAPER (F-294, 유저 2026-10-05): a format at a resolution,
/// and so a size in pixels — 「이런 패널들은 사이즈 생각할때 dpi를 기준으로
/// 생각할거야. 즉 용지 크기 바꾼다면 dpi사이즈 바꾸는느낌으로」.
void main() {
  test('the three sheets stand on the papers the user named, to the pixel',
      () {
    // 「타임시트 용지패널 용지크기 너무 작음 … 1754x2480을 기본으로 할것.
    // 콘티패널이랑 컷봉투패널의 용지는 300dpi인 2480x3508으로함」 ·
    // 「컷봉투 가로a4 수용할게」.
    expect(
      SheetPaper.timesheet.pixelSize,
      const CanvasSize(width: 1754, height: 2480),
    );
    expect(
      SheetPaper.conte.pixelSize,
      const CanvasSize(width: 2480, height: 3508),
    );
    expect(
      SheetPaper.envelope.pixelSize,
      const CanvasSize(width: 3508, height: 2480),
    );
  });

  test('a paper is its format at its dpi — the dpi alone makes it larger, '
      'and a sheet on its side swaps its sides', () {
    const a4 = SheetPaperFormat.a4;
    expect(
      const SheetPaper(a4, dpi: 150).pixelSize,
      const CanvasSize(width: 1240, height: 1754),
    );
    expect(
      const SheetPaper(a4, dpi: 600).pixelSize,
      const CanvasSize(width: 4961, height: 7016),
    );
    expect(
      const SheetPaper(SheetPaperFormat.a3, dpi: 300).pixelSize,
      const CanvasSize(width: 3508, height: 4961),
    );
    expect(
      const SheetPaper(a4, dpi: 150, landscape: true).pixelSize,
      const CanvasSize(width: 1754, height: 1240),
    );
    expect(const SheetPaper(a4, dpi: 150).extent, const Size(1240, 1754));
  });

  group('a form on its paper', () {
    test('a form taller than the paper\'s shape fills its height and stands '
        'centred across it', () {
      // The timesheet's own: a 24fps sheet's form on 1754×2480.
      final fit = SheetPaper.timesheet.around(const Size(1096, 1574));

      expect(fit.scale, 2480 / 1574);
      expect(fit.sheet.height, 1574);
      expect(fit.sheet.width * fit.scale, closeTo(1754, 1e-9));
      expect(fit.inset.dy, 0);
      expect(fit.inset.dx, (fit.sheet.width - 1096) / 2);
      expect(fit.inset.dx, closeTo(8.61, 0.01));
    });

    test('a form wider than the paper\'s shape fills its width and stands '
        'centred down it', () {
      // The envelope's digital form on 3508×2480.
      final fit = SheetPaper.envelope.around(const Size(660, 452));

      expect(fit.scale, 3508 / 660);
      expect(fit.sheet.width, 660);
      expect(fit.sheet.height * fit.scale, closeTo(2480, 1e-9));
      expect(fit.inset, Offset(0, (fit.sheet.height - 452) / 2));
      expect(fit.inset.dy, closeTo(7.30, 0.01));
    });

    test('the side the form fills is the form\'s own measure, to the bit — '
        'the paper divided back by the scale is a rounding off it', () {
      const paper = SheetPaper(SheetPaperFormat.a4, dpi: 72);
      expect(paper.pixelSize.width, 595, reason: 'fixture');
      expect(
        595 / (595 / 15),
        isNot(15),
        reason: 'fixture: the division back misses',
      );

      final fit = paper.around(const Size(15, 1));

      expect(fit.sheet.width, 15);
      expect(fit.inset.dx, 0);
    });
  });
}
