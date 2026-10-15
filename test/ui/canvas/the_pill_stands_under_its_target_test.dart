import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/canvas/canvas_capsule.dart';
import 'package:anicel/src/ui/canvas/canvas_target_pill.dart';

/// 🗣️I-79-Q1 (유저 2026-10-08): 「아니 그냥 위쪽 가운데 말고 아래쪽 가운데로
/// 하자」 — the pill a canvas verb wears stands under its target, centred —
/// and F-332 (유저 2026-10-10): 「위치 고정적으로 움직이지않도록.
/// 확인버튼 안보여져도되니까」 — wherever that is.
void main() {
  const pill = Size(68, 28);

  group('targetPillOffset', () {
    test('under the target, centred on it, a gap below its edge', () {
      expect(
        targetPillOffset(
          target: const Rect.fromLTRB(100, 100, 300, 200),
          pill: pill,
        ),
        const Offset(200 - 34, 200 + targetPillGap),
      );
    });

    test('🚨it does not move for the room — a target at the edge of the view '
        'or past it keeps its pill under it all the same (F-332)', () {
      expect(
        targetPillOffset(
          target: const Rect.fromLTRB(100, 100, 300, 580),
          pill: pill,
        ),
        const Offset(200 - 34, 580 + targetPillGap),
        reason: 'no stepping inside the box where there is no room under it',
      );
      expect(
        targetPillOffset(
          target: const Rect.fromLTRB(-400, -100, 30, 900),
          pill: pill,
        ),
        const Offset(-185 - 34, 900 + targetPillGap),
        reason: 'and no pulling in from past the edges',
      );
    });
  });

  group('CanvasTargetPill', () {
    Future<void> mount(WidgetTester tester, {required Rect target}) async {
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 400,
              height: 300,
              child: CanvasTargetPill(
                keyValue: 'probe-pill',
                target: target,
                children: const [
                  SizedBox(width: 30, height: 24),
                  SizedBox(width: 30, height: 24),
                ],
              ),
            ),
          ),
        ),
      );
    }

    Rect pillRect(WidgetTester tester) =>
        tester.getRect(find.byKey(const ValueKey<String>('probe-pill')));

    testWidgets('it MEASURES its pill: the controls, an end each side, the '
        'view pill\'s height', (tester) async {
      await mount(tester, target: const Rect.fromLTRB(100, 50, 300, 150));
      const width = 2 * CanvasCapsule.barPillEnd + 60;
      expect(
        pillRect(tester),
        const Rect.fromLTWH(
          200 - width / 2,
          150 + targetPillGap,
          width,
          CanvasCapsule.barPillHeight,
        ),
      );
    });

    testWidgets('past the edge of what it stands in, it stands under its '
        'target all the same', (tester) async {
      await mount(tester, target: const Rect.fromLTRB(100, 50, 300, 290));
      expect(pillRect(tester).top, 290 + targetPillGap);
    });
  });
}
