import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/widgets/page_turn_strip.dart';
import '../../helpers/app_icon_button_probe.dart';

/// The one page cluster the timesheet, the conte and the media viewer
/// mount (유저 확정 ⑥ 2026-08-13, 「최대한 통일」): ◀ n/N ▶ stood upright,
/// a drag on the readout and a typed page from the pencil under them, empty
/// below two pages, inert with nowhere to turn to.
void main() {
  const prev = ValueKey<String>('sheet-previous-page-button');
  const next = ValueKey<String>('sheet-next-page-button');
  const readout = ValueKey<String>('sheet-page-readout');
  const input = ValueKey<String>('sheet-page-input');
  const pencil = ValueKey<String>('sheet-page-readout-edit');

  Future<void> pump(
    WidgetTester tester, {
    required int pageIndex,
    required int pageCount,
    required ValueChanged<int>? onTurnTo,
  }) => tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Column(
          key: const ValueKey<String>('strip'),
          children: pageTurnStrip(
            keyPrefix: 'sheet',
            page: viewerPage(pageIndex, pageCount),
            onTurnTo: onTurnTo,
          ),
        ),
      ),
    ),
  );

  bool enabled(WidgetTester tester, Key key) =>
      tester.appIconButton(find.byKey(key)).onPressed != null;

  testWidgets('below two pages there is nothing — no permanently disabled '
      'promise', (tester) async {
    await pump(tester, pageIndex: 0, pageCount: 1, onTurnTo: (_) {});
    expect(find.byKey(prev), findsNothing);
    expect(find.byKey(readout), findsNothing);
    expect(find.byKey(next), findsNothing);
  });

  testWidgets('the chevrons turn one page and disable at the ends, and the '
      'cluster reads downward — up · page · down unbroken, then the pencil', (
    tester,
  ) async {
    final turns = <int>[];
    await pump(tester, pageIndex: 0, pageCount: 3, onTurnTo: turns.add);
    expect(enabled(tester, prev), isFalse);
    expect(enabled(tester, next), isTrue);
    expect(find.text('1 / 3'), findsOneWidget);
    await tester.tap(find.byKey(next));
    expect(turns, [1]);

    // 🗣️유저 2026-10-11: 「페이지띠는 아래버튼 밑에 연필버튼오도록.
    // 위/페이지/아래 이런건 이어지는게 이쁘잖아」.
    final prevRect = tester.getRect(find.byKey(prev));
    final readoutRect = tester.getRect(find.byKey(readout));
    final nextRect = tester.getRect(find.byKey(next));
    final pencilRect = tester.getRect(find.byKey(pencil));
    expect(prevRect.bottom, lessThanOrEqualTo(readoutRect.top + 0.01));
    expect(readoutRect.bottom, lessThanOrEqualTo(nextRect.top + 0.01));
    expect(nextRect.bottom, lessThanOrEqualTo(pencilRect.top + 0.01));

    await pump(tester, pageIndex: 2, pageCount: 3, onTurnTo: turns.add);
    expect(enabled(tester, prev), isTrue);
    expect(enabled(tester, next), isFalse);
    await tester.tap(find.byKey(prev));
    expect(turns, [1, 1]);
  });

  testWidgets('the readout turns one page per 8px of drag, and a typed '
      '"3/7" or "3" means page three', (tester) async {
    final turns = <int>[];
    await pump(tester, pageIndex: 0, pageCount: 7, onTurnTo: turns.add);

    // 20px from the first pixel — the readout has no tap left to keep
    // apart from a drag — at ⅛ page per pixel is two whole pages. The
    // harness never rebuilds, so each report is a delta off page 0.
    await tester.drag(find.byKey(readout), const Offset(20, 0));
    await tester.pumpAndSettle();
    expect(turns.fold<int>(0, (sum, turn) => sum + turn), 2);

    // A press on the readout that does not move turns nothing.
    final turned = turns.length;
    await tester.tap(find.byKey(readout));
    await tester.pumpAndSettle();
    expect(turns, hasLength(turned));
    expect(find.byKey(input), findsNothing);

    // Its pencil types one.
    await tester.tap(find.byKey(pencil));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(input), '3/7');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(turns.last, 2, reason: 'page three is index 2');

    await tester.tap(find.byKey(pencil));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(input), '5');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(turns.last, 4);
  });

  testWidgets('with nowhere to turn to the cluster stays MOUNTED and inert: '
      'both chevrons disabled, a drag and a typed page go nowhere', (
    tester,
  ) async {
    await pump(tester, pageIndex: 0, pageCount: 3, onTurnTo: null);
    expect(find.byKey(prev), findsOneWidget);
    expect(find.byKey(next), findsOneWidget);
    expect(enabled(tester, prev), isFalse);
    expect(enabled(tester, next), isFalse);
    // The readout is off with them: its pencil opens nothing.
    expect(enabled(tester, pencil), isFalse);
    await tester.drag(find.byKey(readout), const Offset(40, 0));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(pencil), warnIfMissed: false);
    await tester.pumpAndSettle();
    if (tester.any(find.byKey(input))) {
      await tester.enterText(find.byKey(input), '2');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
    }
    expect(find.text('1 / 3'), findsOneWidget);
  });
}
