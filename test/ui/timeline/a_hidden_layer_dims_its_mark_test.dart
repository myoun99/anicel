import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/layer_mark.dart';
import 'package:anicel/src/models/layer_process.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/ui/timeline/layer_label_controls.dart';

/// 🚨★★★OFF IS ONE LANGUAGE ACROSS THE ROW (유저 2026-08-31, F-56):
///
/// > 「레이어, 비지블 off면 추가로 색도 비활성화색. **어니언스킨 off상태나
/// > 그런 다른 버튼 off상태랑 동급으로** 색 바꿈」
///
/// The mark plate is the one control on the rail that kept its full colour
/// while the layer it belongs to was hidden — so a row could read as off in
/// every icon and on in the one thing the eye lands on first.
///
/// ⚠️It wears the SAME alpha the onion and fx icons wear rather than a colour
/// of its own. A second faded-looking value would be a second design for one
/// meaning, and the next person would have to keep them in step by hand.
void main() {
  const mark = LayerMark(process: LayerProcess.layout);

  Future<Color?> plateFill(WidgetTester tester, {required bool dimmed}) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 120,
              height: 40,
              child: LayerMarkChip(
                keyPrefix: 'test',
                layerId: const LayerId('L1'),
                mark: mark,
                onMarkSelected: (_, _) {},
                isVisible: !dimmed,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    // ⚠️`ColoredBox`, not `DecoratedBox`: the plate is a flat fill under a
    // clip, and looking for the wrong widget is how a test measures nothing.
    final boxes = tester.widgetList<ColoredBox>(find.byType(ColoredBox));
    for (final box in boxes) {
      // The plate is the only opaque fill in this tree.
      if (box.color.a > 0) return box.color;
    }
    return null;
  }

  testWidgets('a visible layer wears the mark colour at full strength', (
    tester,
  ) async {
    final fill = await plateFill(tester, dimmed: false);
    expect(fill, isNotNull, reason: 'the plate did not draw — this measures nothing');
    expect(fill!.a, closeTo(1, 0.001));
  });

  testWidgets('🚨a hidden layer dims it to the rail\'s own off alpha', (
    tester,
  ) async {
    final fill = await plateFill(tester, dimmed: true);
    expect(fill, isNotNull);
    expect(
      fill!.a,
      closeTo(0.45, 0.001),
      reason: '유저: 「다른 버튼 off상태랑 동급으로」 — 0.45 is that alpha',
    );
  });
}
