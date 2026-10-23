import 'dart:ui' as ui;

import 'package:anicel/src/ui/brush/tool_cursor_look.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/app_faces.dart';

/// 🗣️F-441 (유저 2026-10-23): 「채우기도구, 커서가 정확히 어느 포인트가
/// 채워지는 포인트인지 모르겟음 … 다른 도구 다 왼쪽아래가 포인트니까」.
///
/// The first ink along the bucket's lowest row is its drop, and the drop is
/// where the fill lands: the hot spot. A bucket pouring right, a bar left
/// along its foot, or a drop hung above the box's foot each put that ink
/// somewhere else.
void main() {
  testWidgets('the first ink along the bucket\'s foot is its drop, at the '
      'hot spot', (tester) async {
    await tester.runAsync(loadIcons);
    final look = fillCursorLook();
    const scale = 4.0;
    final side = (look.extent.longestSide * scale).ceil();
    final rgba = (await tester.runAsync(() async {
      final recorder = ui.PictureRecorder();
      look.painter.paint(ui.Canvas(recorder)..scale(scale), look.extent);
      final image = await recorder.endRecording().toImage(side, side);
      try {
        return await image.toByteData();
      } finally {
        image.dispose();
      }
    }))!;

    bool inked(int x, int y) => rgba.getUint8((y * side + x) * 4 + 3) > 64;
    final lowest = [
      for (var y = side - 1; y >= 0; y -= 1)
        if (List.generate(side, (x) => x).any((x) => inked(x, y))) y,
    ].first;
    // The bucket's own corner comes down as far, further right.
    final left = List.generate(side, (x) => x).firstWhere(
      (x) => inked(x, lowest),
    );
    var right = left;
    while (right + 1 < side && inked(right + 1, lowest)) {
      right += 1;
    }
    final foot = Offset((left + right + 1) / 2 / scale, (lowest + 1) / scale);
    expect(
      (foot - look.hotspot).distance,
      lessThan(1.5),
      reason: 'the foot of the drop, $foot, is the hot spot ${look.hotspot}',
    );
  });
}
