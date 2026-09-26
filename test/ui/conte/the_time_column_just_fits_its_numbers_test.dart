import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/conte/conte_sheet_layout.dart';
import 'package:anicel/src/ui/conte/conte_fonts.dart';

import '../../helpers/app_faces.dart';

/// The time column is just a total wide (유저 2026-09-25: 「초수 칸 너무 좌우
/// 기니까 좀 더 슬림하게. 00+00 이정도 크기가 딱 들어갈정도로」) — measured
/// in the app's own face, which is what the sheet prints in. BIZ's digits
/// are all one width, so 「00+00」 is every two-digit total.
void main() {
  testWidgets('「00+00」 at the total\'s 9pt bold fits the column between its '
      'insets, with less than a point to spare', (tester) async {
    await loadTheAppFaces();
    final painter = TextPainter(
      text: TextSpan(text: '00+00', style: conteTextStyle(9, bold: true)),
      textDirection: TextDirection.ltr,
    )..layout();
    final total = painter.width;
    painter.dispose();
    const m = ConteSheetMetrics();
    final room = m.timeColumnWidth - 2 * m.timeInset;

    expect(total, greaterThan(30), reason: 'measured in the app\'s face');
    expect(total, lessThanOrEqualTo(room), reason: 'it fits');
    expect(room - total, lessThan(1), reason: 'and no more than that');
  });
}
