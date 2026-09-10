import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/widgets/panel_flyout.dart';

/// The shared flyout's opening direction (UI-R6 #1): plenty of room below
/// opens downward as always; a cramped bottom anchor opens the whole list
/// UPWARD (bottom hugging the anchor's top) with the item order unchanged —
/// Material's default clamp read as the list growing bottom-up.
void main() {
  List<PanelFlyoutEntry> entries(int count) => [
    for (var i = 0; i < count; i++)
      PanelFlyoutItem(keyValue: 'flyout-item-$i', label: 'Item $i'),
  ];

  Future<void> pumpAnchored(
    WidgetTester tester, {
    required Alignment alignment,
    required int itemCount,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: alignment,
            child: Builder(
              builder: (context) => SizedBox(
                width: 96,
                height: 24,
                child: TextButton(
                  key: const ValueKey<String>('flyout-anchor'),
                  onPressed: () =>
                      showPanelFlyout(context, entries: entries(itemCount)),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey<String>('flyout-anchor')));
    await tester.pumpAndSettle();
  }

  testWidgets('opens downward when the space below fits', (tester) async {
    await pumpAnchored(tester, alignment: Alignment.topLeft, itemCount: 5);

    final anchorBottom = tester
        .getBottomLeft(find.byKey(const ValueKey<String>('flyout-anchor')))
        .dy;
    final firstItemTop = tester
        .getTopLeft(find.byKey(const ValueKey<String>('flyout-item-0')))
        .dy;
    expect(firstItemTop, greaterThanOrEqualTo(anchorBottom));
  });

  testWidgets('opens UPWARD above a bottom-edge anchor, order unchanged', (
    tester,
  ) async {
    await pumpAnchored(tester, alignment: Alignment.bottomLeft, itemCount: 10);

    final anchorTop = tester
        .getTopLeft(find.byKey(const ValueKey<String>('flyout-anchor')))
        .dy;
    final firstItemTop = tester
        .getTopLeft(find.byKey(const ValueKey<String>('flyout-item-0')))
        .dy;
    final lastItemBottom = tester
        .getBottomLeft(find.byKey(const ValueKey<String>('flyout-item-9')))
        .dy;

    // The whole list sits ABOVE the anchor…
    expect(lastItemBottom, lessThanOrEqualTo(anchorTop));
    // …with the first item still on top (order preserved).
    expect(firstItemTop, lessThan(lastItemBottom));
  });

  /// **F-49 — A ROW'S INK IS THE ROW, WHETHER OR NOT IT HAS A CHILD.**
  ///
  /// 유저 2026-08-29: 「색라벨 열어서 겹이 있는 행에서 호버하면 호버색이 다른
  /// 용지처럼 전면 흰색되는게 아니라 **작게 글자만큼만** 흰 배경 생기고 버튼
  /// 취급? **인식도 그 안에서만** 되. 즉 버튼이 작은거같은데」.
  ///
  /// A submenu row is `enabled: false`, which drops Material's InkWell, so
  /// this widget puts one back. That InkWell used to wrap the row's CONTENT —
  /// a `Row` about 16px tall, inside `PopupMenuItem`'s own padding — so both
  /// the wash and the hit area were the text rather than the row.
  ///
  /// ⚠️Shared UI: seventeen files mount this flyout, and both kinds of row
  /// now lay out through the same surface, so measuring here measures all.
  testWidgets('every row is the same full box, child or not', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              key: const ValueKey<String>('flyout-anchor'),
              onPressed: () => showPanelFlyout(
                context,
                entries: [
                  const PanelFlyoutItem(keyValue: 'plain', label: '용지'),
                  PanelFlyoutItem(
                    keyValue: 'has-child',
                    label: '미술',
                    submenuBuilder: () => const [
                      PanelFlyoutItem(keyValue: 'kid', label: '연출'),
                    ],
                  ),
                ],
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey<String>('flyout-anchor')));
    await tester.pumpAndSettle();

    // 🚨THE INK, not the layout box. A `SizedBox` inside the row is the same
    // size whether or not `PopupMenuItem` pads around it — measuring that
    // would report success while the wash still stopped short of the edge.
    // The InkWell IS what lights up, so that is what gets measured.
    Rect inkOf(String label) => tester.getRect(
      find
          .ancestor(of: find.text(label), matching: find.byType(InkWell))
          .first,
    );

    final plain = inkOf('용지');
    final withChild = inkOf('미술');

    // 🚨전제: 두 행이 실제로 그려졌고 서로 다른 자리에 있다. 같은 사각형을
    // 두 번 재고 「일치한다」고 말하는 것이 이 테스트의 유일한 거짓 통과다.
    expect(plain.top, isNot(withChild.top), reason: '⛔같은 행을 두 번 쟀다');

    expect(
      withChild.height,
      plain.height,
      reason: '겹이 있는 행이 더 낮다 — 잉크가 글자 높이뿐이라는 뜻',
    );
    expect(
      withChild.width,
      plain.width,
      reason: '겹이 있는 행이 더 좁다 — 안쪽 padding 안에만 칠해진다는 뜻',
    );
  });

  /// 유저 2026-08-29: 「겹으로 들어가면 들어간 위치. 즉 **부모 버튼도
  /// 흰색인채로 유지**하도록」.
  ///
  /// 🚨Hover cannot carry this. By the time the child is open the pointer has
  /// moved off the parent, so Material's highlight has already faded — the
  /// row has to say 「my child is up」 from state, not from the pointer.
  testWidgets('a parent stays lit while its child is open', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              key: const ValueKey<String>('flyout-anchor'),
              onPressed: () => showPanelFlyout(
                context,
                entries: [
                  PanelFlyoutItem(
                    keyValue: 'has-child',
                    label: '미술',
                    submenuBuilder: () => const [
                      PanelFlyoutItem(keyValue: 'kid', label: '연출'),
                    ],
                  ),
                ],
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey<String>('flyout-anchor')));
    await tester.pumpAndSettle();

    Color washOf(String label) => tester
        .widgetList<ColoredBox>(
          find.ancestor(
            of: find.text(label),
            matching: find.byType(ColoredBox),
          ),
        )
        .first
        .color;

    final closed = washOf('미술');
    expect(
      closed.a,
      0,
      reason: '전제: 아직 겹을 안 열었으니 부모는 칠해져 있지 않다',
    );

    // A finger has no hover, so the tap is how a tablet opens the child —
    // and it is the same call hovering makes.
    await tester.tap(find.text('미술'));
    await tester.pumpAndSettle();
    expect(find.text('연출'), findsOneWidget, reason: '전제: 겹이 실제로 열렸다');

    expect(
      washOf('미술').a,
      greaterThan(0),
      reason: '겹이 열렸는데 부모가 꺼져 있다 — 어느 행이 열었는지 잃었다',
    );
  });

  // 🚨A CONTROL ROW IS DRAWN AT FULL STRENGTH (유저 2026-09-10: 「한번 그냥
  // 흐리지않게 해보자」). A row is a DISABLED PopupMenuItem so a knob never
  // doubles as a command — and a disabled item also dims what it holds:
  // IconTheme opacity 0.38 (0.5 in dark mode) and inherited text `onSurface`
  // at 0.38. The rotate/flip accents in the canvas pill's settings list sat
  // at 38% for that reason alone. Both themes, because Flutter dims them by
  // different amounts.
  for (final (name, theme) in [
    ('light', ThemeData.light()),
    ('dark', ThemeData.dark()),
  ]) {
    testWidgets('a control row\'s icons and inherited text are not dimmed '
        '($name)', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: Scaffold(
            body: Center(
              child: Builder(
                builder: (context) => TextButton(
                  key: const ValueKey<String>('strength-anchor'),
                  onPressed: () => showPanelFlyout(
                    context,
                    entries: [
                      PanelFlyoutRow(
                        keyValue: 'strength-row',
                        builder: (_) => const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.rotate_left,
                              key: ValueKey<String>('strength-icon'),
                            ),
                            Text('15°', key: ValueKey<String>('strength-text')),
                          ],
                        ),
                      ),
                    ],
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(const ValueKey<String>('strength-anchor')));
      await tester.pumpAndSettle();

      final icon = find.byKey(const ValueKey<String>('strength-icon'));
      expect(
        IconTheme.of(tester.element(icon)).opacity,
        1.0,
        reason: 'the disabled menu item dims every icon it holds',
      );
      final text = find.byKey(const ValueKey<String>('strength-text'));
      final painted = tester
          .widget<RichText>(
            find.descendant(of: text, matching: find.byType(RichText)),
          )
          .text
          .style!
          .color;
      expect(
        painted,
        Theme.of(tester.element(text)).colorScheme.onSurface,
        reason: 'inherited text takes M3\'s ENABLED label colour, not 0.38',
      );
    });
  }
}
