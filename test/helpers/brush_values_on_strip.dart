import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/menu/editor_top_strip.dart';

/// Stands the brush's values on the top strip, as Settings › 패널 ›
/// 「브러시 값을 상단띠로」 does — by default the canvas's pill holds them
/// (I-34). For the tests about the strip's own bars.
Future<void> standBrushValuesOnStrip(WidgetTester tester) async {
  tester
      .widget<EditorTopStrip>(find.byType(EditorTopStrip))
      .panelsMenu
      .setBrushValuesOnStrip(true);
  await tester.pumpAndSettle();
}
