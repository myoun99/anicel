import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/widgets/page_turn_strip.dart';
import '../../helpers/app_icon_button_probe.dart';

/// The one page cluster the timesheet, the conte and the media viewer
/// mount (유저 확정 ⑥ 2026-08-13, 「최대한 통일」): ◀ n/N ▶ stood upright,
/// drag and typed entry on the readout, empty below two pages, inert with
/// nowhere to turn to.
void main() {
  const prev = ValueKey<String>('sheet-previous-page-button');
  const next = ValueKey<String>('sheet-next-page-button');
  const readout = ValueKey<String>('sheet-page-readout');
  const input = ValueKey<String>('sheet-page-input');

  Future<void> pump(
    WidgetTester tester, {
    required int pageIndex,
    required int pageCount,
    required ValueChanged<int>? onTurnTo,
    List<Widget> leading = const [],
  }) => tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Column(
          key: const ValueKey<String>('strip'),
          children: pageTurnStrip(
            keyPrefix: 'sheet',
            page: (
              index: pageIndex,
              count: pageCount,
              readout: '${pageIndex + 1} / $pageCount',
              firstNumbered: 0,
            ),
            onTurnTo: onTurnTo,
            leading: leading,
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

  testWidgets('the chevrons turn one page and disable at the ends; leading '
      'widgets come first, and the cluster reads downward', (tester) async {
    final turns = <int>[];
    await pump(
      tester,
      pageIndex: 0,
      pageCount: 3,
      onTurnTo: turns.add,
      leading: const [SizedBox(key: ValueKey('lead'), height: 10)],
    );
    expect(enabled(tester, prev), isFalse);
    expect(enabled(tester, next), isTrue);
    expect(find.text('1 / 3'), findsOneWidget);
    await tester.tap(find.byKey(next));
    expect(turns, [1]);

    final leadY = tester.getCenter(find.byKey(const ValueKey('lead'))).dy;
    final prevY = tester.getCenter(find.byKey(prev)).dy;
    final readoutY = tester.getCenter(find.byKey(readout)).dy;
    final nextY = tester.getCenter(find.byKey(next)).dy;
    expect(leadY, lessThan(prevY));
    expect(prevY, lessThan(readoutY));
    expect(readoutY, lessThan(nextY));

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

    // 40px, of which the touch slop (18px) eats the first stretch: 22px of
    // travel at ⅛ page per pixel is two whole pages. The harness never
    // rebuilds, so each report is a delta off page 0.
    await tester.drag(find.byKey(readout), const Offset(40, 0));
    await tester.pumpAndSettle();
    expect(turns.fold<int>(0, (sum, turn) => sum + turn), 2);

    await tester.tap(find.byKey(readout));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(input), '3/7');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(turns.last, 2, reason: 'page three is index 2');

    await tester.tap(find.byKey(readout));
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
    await tester.drag(find.byKey(readout), const Offset(40, 0));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(readout));
    await tester.pumpAndSettle();
    if (tester.any(find.byKey(input))) {
      await tester.enterText(find.byKey(input), '2');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
    }
    expect(find.text('1 / 3'), findsOneWidget);
  });
}
