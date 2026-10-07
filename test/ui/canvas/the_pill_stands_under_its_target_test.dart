import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/canvas/canvas_capsule.dart';
import 'package:anicel/src/ui/canvas/canvas_target_pill.dart';

/// 🗣️I-79-Q1 (유저 2026-10-08): 「아니 그냥 위쪽 가운데 말고 아래쪽 가운데로
/// 하자」 — the pill a canvas verb wears stands under its target, centred,
/// steps inside when there is no room under it, and never leaves the room
/// it is given.
void main() {
  const room = Rect.fromLTWH(0, 0, 800, 600);
  const pill = Size(68, 28);

  group('targetPillOffset', () {
    test('under the target, centred on it, a gap below its edge', () {
      expect(
        targetPillOffset(
          target: const Rect.fromLTRB(100, 100, 300, 200),
          pill: pill,
          room: room,
        ),
        const Offset(200 - 34, 200 + targetPillGap),
      );
    });

    test('no room under it: it steps inside, over the same edge', () {
      expect(
        targetPillOffset(
          target: const Rect.fromLTRB(100, 100, 300, 580),
          pill: pill,
          room: room,
        ),
        const Offset(200 - 34, 580 - targetPillGap - 28),
      );
    });

    test('it never leaves the room — a target past the edges keeps it in',
        () {
      expect(
        targetPillOffset(
          target: const Rect.fromLTRB(-400, -100, 30, 900),
          pill: pill,
          room: const Rect.fromLTRB(10, 40, 790, 500),
        ),
        const Offset(10, 500 - 28),
      );
    });
  });

  group('CanvasTargetPill', () {
    Future<void> mount(
      WidgetTester tester, {
      required Rect target,
      EdgeInsets cover = EdgeInsets.zero,
    }) async {
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
                cover: cover,
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

    testWidgets('the cover is not room: it keeps out from under what stands '
        'on its edges', (tester) async {
      await mount(
        tester,
        target: const Rect.fromLTRB(100, 50, 300, 260),
        cover: const EdgeInsets.only(bottom: 100),
      );
      expect(
        pillRect(tester).bottom,
        300 - 100,
        reason: 'under the target is under the cover — it stands on the '
            'cover\'s edge instead',
      );
    });
  });
}
