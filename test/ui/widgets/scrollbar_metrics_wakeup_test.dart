import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/widgets/app_scrollbar.dart';

/// T7 — the thumb must answer about the CONTENT THAT IS THERE NOW.
///
/// 유저 2026-08-13: 「컷1에서 레이어 많이 만들고 스크롤바 작아진 다음, 컷2 만들고
/// 컷2 가서 타임라인 패널 가면 스크롤바가 작은 채로 있음. 아마 가로스크롤바 등
/// 프레임셀쪽도 그렇고 그런 게 있을 것임」 — and the guess was right, because
/// there is one bar behind every one of those.
///
/// A [ScrollController] notifies when the OFFSET moves and at no other time.
/// Content that grows or shrinks under a still offset rings no bell, and the
/// scrollable lays out AFTER this widget builds, so even the frame in which
/// everything changed carries the previous frame's numbers.
void main() {
  /// A scroll view whose content length this test can change, with the rail
  /// beside it exactly as the panels mount it.
  Widget harness({
    required ScrollController controller,
    required int rows,
    required double viewport,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: Row(
          children: [
            SizedBox(
              width: 200,
              height: viewport,
              child: ListView.builder(
                controller: controller,
                itemCount: rows,
                itemExtent: 20,
                itemBuilder: (context, index) => SizedBox(height: 20),
              ),
            ),
            SizedBox(
              width: 16,
              height: viewport,
              child: AppControllerScrollbar(
                controller: controller,
                axis: Axis.vertical,
                thumbKey: const ValueKey<String>('probe-thumb'),
                laneKey: const ValueKey<String>('probe-lane'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  double thumbExtent(WidgetTester tester) => tester
      .getSize(find.byKey(const ValueKey<String>('probe-thumb')))
      .height;

  testWidgets('the thumb re-measures when the CONTENT changes under a still '
      'offset', (tester) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);

    // 40 rows of 20px in a 200px viewport: a small thumb.
    await tester.pumpWidget(
      harness(controller: controller, rows: 40, viewport: 200),
    );
    await tester.pumpAndSettle();
    final crowded = thumbExtent(tester);

    // Now the same viewport holds 12 rows — the shape of switching to a cut
    // with fewer layers. The offset never moves, so the controller stays
    // silent; only a post-frame look can catch this.
    await tester.pumpWidget(
      harness(controller: controller, rows: 12, viewport: 200),
    );
    await tester.pumpAndSettle();
    final roomy = thumbExtent(tester);

    expect(
      controller.offset,
      0,
      reason: 'nothing scrolled — that is what makes the controller silent',
    );
    expect(
      roomy,
      greaterThan(crowded),
      reason: 'less content must mean a longer thumb; a stale bar keeps the '
          'small one, which is exactly the report',
    );

    // And back the other way, so the check is not one-directional.
    await tester.pumpWidget(
      harness(controller: controller, rows: 40, viewport: 200),
    );
    await tester.pumpAndSettle();
    expect(thumbExtent(tester), closeTo(crowded, 0.01));
  });
}
