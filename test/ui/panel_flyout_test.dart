import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/panels/panel_scrollbar.dart';
import 'package:anicel/src/ui/theme/app_scroll_behavior.dart';
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

  List<PanelFlyoutEntry> rows(String prefix, int count) => [
    for (var i = 0; i < count; i++)
      PanelFlyoutItem(keyValue: '$prefix-$i', label: '$prefix $i'),
  ];

  /// 🚨A DRAWER TALLER THAN THE WINDOW SCROLLS — the way the parent list
  /// (Material's menu) always has (a-flyout-taller-than-the-screen-runs-off-it).
  /// 🧪At 800×600 the panels drawer's last row centred at y=632: off the
  /// window, and a tap there landed on nothing.
  testWidgets('a drawer taller than the window stays inside it and scrolls '
      'to its last row', (tester) async {
    var picked = '';
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
                    keyValue: 'drawer',
                    label: '패널',
                    submenuBuilder: () => [
                      for (var i = 0; i < 30; i++)
                        PanelFlyoutItem(
                          keyValue: 'kid-$i',
                          label: 'kid $i',
                          onSelected: () => picked = 'kid-$i',
                        ),
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
    // A finger has no hover: the tap opens the drawer, as hovering does.
    await tester.tap(find.text('패널'));
    await tester.pumpAndSettle();

    final window = tester.view.physicalSize / tester.view.devicePixelRatio;
    final last = find.byKey(const ValueKey<String>('kid-29'));
    Rect drawer() => tester.getRect(
      find
          .ancestor(
            of: find.byKey(const ValueKey<String>('kid-0')),
            matching: find.byType(Material),
          )
          .first,
    );
    expect(
      tester.getCenter(last).dy,
      greaterThan(window.height),
      reason: '⛔전제: 서른 줄은 창보다 길다 — 마지막 줄은 처음엔 창 밖이다',
    );
    expect(
      drawer().top,
      greaterThanOrEqualTo(8),
      reason: 'the drawer stops 8px inside the window, where the parent does',
    );
    expect(
      drawer().bottom,
      lessThanOrEqualTo(window.height - 8),
      reason: 'a drawer that ran off the bottom is the bug itself',
    );

    // A wheel over the drawer — how a mouse reaches the rest of any list.
    // ⛔Not a drag: a press on a row belongs to the row (ControlPressClaim).
    final wheel = TestPointer(1, PointerDeviceKind.mouse)
      ..hover(tester.getCenter(find.byKey(const ValueKey<String>('kid-3'))));
    await tester.sendEventToBinding(wheel.scroll(const Offset(0, 2000)));
    await tester.pumpAndSettle();
    expect(
      drawer().contains(tester.getCenter(last)),
      isTrue,
      reason: 'the last row scrolled into the drawer',
    );

    await tester.tap(last);
    await tester.pumpAndSettle();
    expect(picked, 'kid-29', reason: 'and a tap on it is a pick');
  });

  testWidgets('both levels wear the APP\'s bar while they overflow — one '
      'scroll behaviour for the two', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        scrollBehavior: const AppScrollBehavior(),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              key: const ValueKey<String>('flyout-anchor'),
              onPressed: () => showPanelFlyout(
                context,
                entries: [
                  PanelFlyoutItem(
                    keyValue: 'drawer',
                    label: '패널',
                    submenuBuilder: () => rows('kid', 30),
                  ),
                  ...rows('item', 30),
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
    await tester.tap(find.text('패널'));
    await tester.pumpAndSettle();

    Finder barOver(String key) => find.ancestor(
      of: find.byKey(ValueKey<String>(key)),
      matching: find.byType(PanelScrollbar),
    );
    expect(
      barOver('item-0'),
      findsOneWidget,
      reason: 'the parent — Material\'s menu — scrolls under the app\'s bar',
    );
    expect(
      barOver('kid-0'),
      findsOneWidget,
      reason: '⛔스크롤바를 자동으로 숨기지 않는다 — the drawer wears the same '
          'bar, from the same behaviour',
    );
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

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

  /// 🗣️유저 2026-09-26: the cut button's 색 라벨 is the label list 「그대로」 —
  /// the cut menu, then the stages, then a stage's corrections. A child's
  /// row opens a child of its own by the same rules, one level down.
  testWidgets('a child\'s row opens a child of its own — a plain row of that '
      'level closes it and keeps its own level up, and a pick at the '
      'deepest level closes them all', (tester) async {
    String? picked;
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
                    keyValue: 'labels',
                    label: '색 라벨',
                    submenuBuilder: () => [
                      PanelFlyoutItem(
                        keyValue: 'none',
                        label: '라벨 없음',
                        onSelected: () => picked = 'none',
                      ),
                      PanelFlyoutItem(
                        keyValue: 'stage',
                        label: '원화',
                        submenuBuilder: () => [
                          PanelFlyoutItem(
                            keyValue: 'fix',
                            label: '작감',
                            onSelected: () => picked = 'fix',
                          ),
                        ],
                      ),
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
    await tester.tap(find.text('색 라벨'));
    await tester.pumpAndSettle();
    expect(find.text('원화'), findsOneWidget, reason: '전제: 첫 겹이 열렸다');

    await tester.tap(find.text('원화'));
    await tester.pumpAndSettle();
    expect(find.text('작감'), findsOneWidget, reason: '둘째 겹이 안 열린다');
    expect(find.text('원화'), findsOneWidget, reason: '첫 겹이 닫혔다');

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: tester.getCenter(find.text('원화')));
    await mouse.moveTo(tester.getCenter(find.text('라벨 없음')));
    await tester.pumpAndSettle();
    expect(find.text('작감'), findsNothing, reason: '둘째 겹이 남았다');
    expect(find.text('원화'), findsOneWidget, reason: '첫 겹까지 닫혔다');

    await tester.tap(find.text('원화'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('작감'));
    await tester.pumpAndSettle();
    expect(picked, 'fix');
    expect(find.text('색 라벨'), findsNothing, reason: '고른 뒤에도 목록이 남았다');
    expect(find.text('원화'), findsNothing);
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
