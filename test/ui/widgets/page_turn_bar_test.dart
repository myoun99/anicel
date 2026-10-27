import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/brush/brush_canvas_panel.dart'
    show CanvasTransportBand;
import 'package:anicel/src/ui/theme/app_theme.dart' show AppTypography;
import 'package:anicel/src/ui/widgets/drag_value_label.dart';
import 'package:anicel/src/ui/widgets/page_turn_bar.dart';
import 'package:anicel/src/ui/widgets/transport_bar.dart';
import '../../helpers/app_faces.dart';
import '../../helpers/app_icon_button_probe.dart';
import '../../helpers/number_pad_keyboard.dart';

/// The one page turner every panel that turns pages wears in the band under
/// it (F-383, 「최대한 통일」): ◀ n/N ▶ lying in a row, a drag on the
/// readout and a typed page from the pencil after them, no band below two
/// pages, inert with nowhere to turn to.
void main() {
  const prev = ValueKey<String>('sheet-previous-page-button');
  const next = ValueKey<String>('sheet-next-page-button');
  const readout = ValueKey<String>('sheet-page-readout');
  const input = ValueKey<String>('sheet-page-input');
  const pencil = ValueKey<String>('sheet-page-readout-edit');

  /// The band [page] puts under a panel, null where it puts none.
  CanvasTransportBand? bandOf(
    BuildContext context,
    TurnedPage page,
    ValueChanged<int>? onTurnTo,
  ) => CanvasTransportBand.ofPages(
    context,
    keyPrefix: 'sheet',
    page: page,
    onTurnTo: onTurnTo,
  );

  Future<void> pump(
    WidgetTester tester, {
    required int pageIndex,
    required int pageCount,
    required ValueChanged<int>? onTurnTo,
    TurnedPage? page,
    ThemeData? theme,
    double width = 400,
  }) => tester.pumpWidget(
    MaterialApp(
      theme: theme,
      home: Scaffold(
        body: Builder(
          builder: (context) {
            final band = bandOf(
              context,
              page ?? viewerPage(pageIndex, pageCount),
              onTurnTo,
            );
            return band == null
                ? const SizedBox.shrink()
                : Center(
                    child: SizedBox(
                      key: const ValueKey<String>('band'),
                      width: width,
                      height: band.height,
                      child: band.child,
                    ),
                  );
          },
        ),
      ),
    ),
  );

  bool enabled(WidgetTester tester, Key key) =>
      tester.appIconButton(find.byKey(key)).onPressed != null;

  testWidgets('below two pages there is no band — no permanently disabled '
      'promise', (tester) async {
    await pump(tester, pageIndex: 0, pageCount: 1, onTurnTo: (_) {});
    expect(find.byKey(const ValueKey<String>('band')), findsNothing);
    expect(find.byKey(prev), findsNothing);
    expect(find.byKey(readout), findsNothing);
    expect(find.byKey(next), findsNothing);
  });

  testWidgets('🗣️F-383: the band is the transport\'s row of buttons, alone '
      '— the space a movie\'s player stands in', (tester) async {
    await pump(tester, pageIndex: 0, pageCount: 3, onTurnTo: (_) {});
    final context = tester.element(find.byKey(const ValueKey<String>('band')));
    expect(
      tester.getSize(find.byKey(const ValueKey<String>('band'))).height,
      TransportBar.buttonRowHeightIn(context),
    );
    expect(
      TransportBar.heightIn(context, range: false),
      greaterThan(TransportBar.buttonRowHeightIn(context)),
      reason: '⛔premise: the player has a track over its buttons',
    );
  });

  testWidgets('the chevrons turn one page and disable at the ends, and the '
      'turner reads rightward — ◀ · page · ▶ unbroken, then the pencil — in '
      'the middle of its band', (tester) async {
    final turns = <int>[];
    await pump(tester, pageIndex: 0, pageCount: 3, onTurnTo: turns.add);
    expect(enabled(tester, prev), isFalse);
    expect(enabled(tester, next), isTrue);
    expect(find.text('1 / 3'), findsOneWidget);
    await tester.tap(find.byKey(next));
    expect(turns, [1]);

    // 🗣️유저 2026-10-11: 「위/페이지/아래 이런건 이어지는게 이쁘잖아」 —
    // said of the strip standing up, and true of it lying down.
    final prevRect = tester.getRect(find.byKey(prev));
    final readoutRect = tester.getRect(find.byKey(readout));
    final nextRect = tester.getRect(find.byKey(next));
    final pencilRect = tester.getRect(find.byKey(pencil));
    expect(prevRect.right, lessThanOrEqualTo(readoutRect.left + 0.01));
    expect(readoutRect.right, lessThanOrEqualTo(nextRect.left + 0.01));
    expect(nextRect.right, lessThanOrEqualTo(pencilRect.left + 0.01));
    final band = tester.getRect(find.byKey(const ValueKey<String>('band')));
    expect(
      (prevRect.left + pencilRect.right) / 2,
      closeTo(band.center.dx, 0.5),
      reason: 'the turner holds the middle of the band',
    );
    for (final rect in [prevRect, readoutRect, nextRect, pencilRect]) {
      expect(rect.top, greaterThanOrEqualTo(band.top - 0.01));
      expect(rect.bottom, lessThanOrEqualTo(band.bottom + 0.01));
    }

    await pump(tester, pageIndex: 2, pageCount: 3, onTurnTo: turns.add);
    expect(enabled(tester, prev), isTrue);
    expect(enabled(tester, next), isFalse);
    await tester.tap(find.byKey(prev));
    expect(turns, [1, 1]);
  });

  testWidgets('the readout is as wide as the widest page it could say, on '
      'one line — the ▶ does not walk as the pages turn', (tester) async {
    await pump(tester, pageIndex: 0, pageCount: 120, onTurnTo: (_) {});
    final first = tester.getRect(find.byKey(next));
    final firstReadout = tester.getRect(find.byKey(readout));
    await pump(tester, pageIndex: 99, pageCount: 120, onTurnTo: (_) {});
    expect(tester.getRect(find.byKey(next)), first);
    // One line: no taller than a line of its words.
    final line = tester.getSize(find.text('100 / 120'));
    expect(firstReadout.height, lessThan(line.height * 1.5));
    expect(firstReadout.width, greaterThanOrEqualTo(line.width - 0.01));
  });

  testWidgets('🚨in the app\'s own face the readout holds every page it can '
      'say — a 0 is wider there than a 1, so the last page is not the widest '
      'of them', (tester) async {
    await loadTheAppFaces();
    await pump(
      tester,
      pageIndex: 0,
      pageCount: 21,
      onTurnTo: (_) {},
      theme: ThemeData(fontFamily: AppTypography.bundledFamily),
    );
    final box = tester
        .widget<DragValueLabel>(
          find.ancestor(
            of: find.byKey(readout),
            matching: find.byType(DragValueLabel),
          ),
        )
        .width;
    // The style the number is painted in, read off it.
    final style = tester
        .widget<RichText>(
          find.descendant(
            of: find.byKey(readout),
            matching: find.byType(RichText),
          ),
        )
        .text
        .style!;
    double widthOf(String text) {
      final painter = TextPainter(
        text: TextSpan(text: text, style: style),
        textDirection: TextDirection.ltr,
      )..layout();
      final width = painter.width;
      painter.dispose();
      return width;
    }

    expect(
      widthOf('1'),
      lessThan(widthOf('0')),
      reason: 'fixture: the app\'s face did not load — in the test font\'s '
          'squares every page measures alike',
    );
    final page = viewerPage(0, 21);
    for (var index = 0; index < page.count; index += 1) {
      expect(
        widthOf(page.spell(index)),
        lessThanOrEqualTo(box),
        reason: '"${page.spell(index)}" does not fit the readout\'s ${box}px',
      );
    }
  });

  testWidgets('the readout says the page as its host spells it, and is as '
      'wide as the host\'s spelling of its last page', (tester) async {
    // The timesheet's '1/2', the spelling of its printed ページ header.
    await pump(
      tester,
      pageIndex: 0,
      pageCount: 12,
      onTurnTo: (_) {},
      page: (index: 0, count: 12, spell: (page) => '${page + 1}/12'),
    );
    expect(find.text('1/12'), findsOneWidget);
    final width = tester.getSize(find.byKey(readout)).width;
    await pump(
      tester,
      pageIndex: 11,
      pageCount: 12,
      onTurnTo: (_) {},
      page: (index: 11, count: 12, spell: (page) => '${page + 1}/12'),
    );
    expect(tester.getSize(find.byKey(readout)).width, width);
    expect(
      tester.getSize(find.text('12/12')).width,
      lessThanOrEqualTo(width + 0.01),
    );
  });

  testWidgets('the readout turns one page per 8px of drag from the page it '
      'shows, and a typed "3/7" or "3" means page three', (tester) async {
    final turns = <int>[];
    await pump(tester, pageIndex: 3, pageCount: 7, onTurnTo: turns.add);

    // 20px from the first pixel — the readout has no tap left to keep
    // apart from a drag — at ⅛ page per pixel is two whole pages on from
    // page four. The harness never rebuilds, so each report is a delta off
    // page four.
    await tester.drag(find.byKey(readout), const Offset(20, 0));
    await tester.pumpAndSettle();
    expect(turns.fold<int>(0, (sum, turn) => sum + turn - 3), 2);

    // A press on the readout that does not move turns nothing.
    turns.clear();
    await tester.tap(find.byKey(readout));
    await tester.pumpAndSettle();
    expect(turns, isEmpty);
    expect(find.byKey(input), findsNothing);

    // Its pencil types one.
    await tester.tap(find.byKey(pencil));
    await tester.pumpAndSettle();
    await openThePadsKeyboard(tester);
    await tester.enterText(find.byKey(input), '3');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(turns, [2], reason: 'page three is index 2');

    turns.clear();
    await tester.tap(find.byKey(pencil));
    await tester.pumpAndSettle();
    await openThePadsKeyboard(tester);
    await tester.enterText(find.byKey(input), '5');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(turns, [4]);
  });

  testWidgets('a band narrower than the turner holds the whole of it, '
      'smaller — no control runs off it', (tester) async {
    await pump(
      tester,
      pageIndex: 0,
      pageCount: 3,
      onTurnTo: (_) {},
      width: 60,
    );
    expect(tester.takeException(), isNull);
    final band = tester.getRect(find.byKey(const ValueKey<String>('band')));
    for (final key in [prev, readout, next, pencil]) {
      final rect = tester.getRect(find.byKey(key));
      expect(rect.left, greaterThanOrEqualTo(band.left - 0.01));
      expect(rect.right, lessThanOrEqualTo(band.right + 0.01));
    }
  });

  testWidgets('with nowhere to turn to the turner stays MOUNTED and inert: '
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
