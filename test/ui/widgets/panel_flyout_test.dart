import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/theme/app_theme.dart';
import 'package:anicel/src/ui/widgets/command_pill.dart';
import 'package:anicel/src/ui/widgets/panel_flyout.dart';

void main() {
  Widget harness(Widget child) {
    return MaterialApp(
      theme: buildAppTheme(),
      home: Scaffold(body: Center(child: child)),
    );
  }

  testWidgets('PanelFlyoutButton opens entries and runs onSelected after '
      'the menu closes', (tester) async {
    var picked = 0;
    await tester.pumpWidget(
      harness(
        PanelFlyoutButton(
          key: const ValueKey<String>('flyout-under-test'),
          label: 'Test',
          entriesBuilder: () => [
            const PanelFlyoutHeader('Section'),
            PanelFlyoutItem(
              keyValue: 'flyout-item-a',
              label: 'Pick me',
              icon: Icons.check,
              onSelected: () => picked += 1,
            ),
            const PanelFlyoutDivider(),
            const PanelFlyoutItem(
              keyValue: 'flyout-item-disabled',
              label: 'Disabled',
              enabled: false,
            ),
          ],
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey<String>('flyout-under-test')));
    await tester.pumpAndSettle();
    expect(find.text('Section'), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('flyout-item-a')), findsOneWidget);
    expect(
      tester
          .widget<PopupMenuItem<PanelFlyoutItem>>(
            find.byKey(const ValueKey<String>('flyout-item-disabled')),
          )
          .enabled,
      isFalse,
    );

    await tester.tap(find.byKey(const ValueKey<String>('flyout-item-a')));
    await tester.pumpAndSettle();
    expect(picked, 1);
    expect(find.byKey(const ValueKey<String>('flyout-item-a')), findsNothing);
  });

  testWidgets('a swatch row keeps ITS OWN colour where a glyph would be '
      'tinted — a list may ink a symbol, never a colour it is naming', (
    tester,
  ) async {
    const swatch = Color(0xFFCC3344);
    await tester.pumpWidget(
      harness(
        PanelFlyoutTrigger(
          key: const ValueKey<String>('swatch-trigger'),
          entriesBuilder: () => const [
            PanelFlyoutItem(
              keyValue: 'swatch-live',
              label: 'Red',
              swatch: swatch,
            ),
            PanelFlyoutItem(
              keyValue: 'swatch-dimmed',
              label: 'Red',
              swatch: swatch,
              enabled: false,
            ),
          ],
          child: const Icon(Icons.circle, size: 16),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey<String>('swatch-trigger')));
    await tester.pumpAndSettle();

    Color swatchOf(String key) {
      final box = tester.widget<Container>(
        find.descendant(
          of: find.byKey(ValueKey<String>(key)),
          matching: find.byType(Container),
        ),
      );
      return (box.decoration! as BoxDecoration).color!;
    }

    Color? labelOf(String key) => tester
        .widget<Text>(
          find.descendant(
            of: find.byKey(ValueKey<String>(key)),
            matching: find.byType(Text),
          ),
        )
        .style
        ?.color;

    expect(swatchOf('swatch-live'), swatch);
    // The disabled row DIMS — and the dimming reaches the label and stops
    // there. A swatch drawn through the row's ink would name a colour the
    // layer will not get.
    expect(labelOf('swatch-dimmed'), isNot(labelOf('swatch-live')));
    expect(swatchOf('swatch-dimmed'), swatch);
  });

  testWidgets('PanelFlyoutTrigger opens the shared list from an arbitrary '
      'child — R6 #4: the four raw PopupMenuButtons had no other door', (
    tester,
  ) async {
    var picked = 0;
    await tester.pumpWidget(
      harness(
        PanelFlyoutTrigger(
          key: const ValueKey<String>('trigger-under-test'),
          tooltip: 'Options',
          entriesBuilder: () => [
            PanelFlyoutItem(
              keyValue: 'trigger-item-a',
              label: 'Pick me',
              onSelected: () => picked += 1,
            ),
          ],
          child: const Icon(Icons.more_vert, size: 16),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey<String>('trigger-under-test')));
    await tester.pumpAndSettle();
    final row = tester.widget<PopupMenuItem<PanelFlyoutItem>>(
      find.byKey(const ValueKey<String>('trigger-item-a')),
    );
    expect(
      row.height,
      32,
      reason:
          'the point of the migration: rows come from the shared list, not '
          'from whatever Material picks (48 in two of the four hosts)',
    );

    await tester.tap(find.byKey(const ValueKey<String>('trigger-item-a')));
    await tester.pumpAndSettle();
    expect(picked, 1);
  });

  testWidgets('a SELECTED row accents and grows no glyph — 유저 R11-①: '
      '어차피 선택하면 ui적으로 색 바뀌니까 그거로 충분해', (tester) async {
    // The overflow tab list tinted its active glyph and had to keep doing
    // so through the migration. A check would have been the M3 habit the
    // rule exists to refuse, and it would widen the row besides.
    await tester.pumpWidget(
      harness(
        PanelFlyoutButton(
          key: const ValueKey<String>('flyout-under-test'),
          label: 'Test',
          entriesBuilder: () => const [
            PanelFlyoutItem(
              keyValue: 'flyout-item-current',
              label: 'Current',
              icon: Icons.layers,
              selected: true,
            ),
            PanelFlyoutItem(
              keyValue: 'flyout-item-other',
              label: 'Other',
              icon: Icons.layers,
            ),
          ],
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey<String>('flyout-under-test')));
    await tester.pumpAndSettle();

    Text labelOf(String key) => tester.widget<Text>(
      find.descendant(
        of: find.byKey(ValueKey<String>(key)),
        matching: find.byType(Text),
      ),
    );
    expect(labelOf('flyout-item-current').style?.color, AppColors.accent);
    expect(labelOf('flyout-item-other').style?.color, AppColors.text);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey<String>('flyout-item-current')),
        matching: find.byIcon(Icons.check),
      ),
      findsNothing,
      reason: 'selection is colour and never a check glyph',
    );
  });

  testWidgets('StrapIconButton: the body fires the primary action, the top '
      'band opens the flyout', (tester) async {
    var primary = 0;
    var variant = 0;
    await tester.pumpWidget(
      harness(
        StrapIconButton(
          buttonKey: 'strap-main',
          menuKey: 'strap-menu',
          icon: Icons.add,
          tooltip: 'Add',
          accent: true,
          onPressed: () => primary += 1,
          entriesBuilder: () => [
            PanelFlyoutItem(
              keyValue: 'strap-variant',
              label: 'Variant',
              onSelected: () => variant += 1,
            ),
          ],
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey<String>('strap-main')));
    await tester.pumpAndSettle();
    expect(primary, 1);
    expect(variant, 0);

    await tester.tap(find.byKey(const ValueKey<String>('strap-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('strap-variant')));
    await tester.pumpAndSettle();
    expect(primary, 1);
    expect(variant, 1);
  });

  testWidgets('StrapIconButton: the opener is its own target beside the '
      'button, and a tap there never runs the action', (tester) async {
    // 🚨T27 (유저 확정 2026-08-14): 「옛날처럼 +버튼 오른쪽에 펼치기아이콘으로
    // 버튼 했었잖아. 그거 그대로하자.」
    //
    // ⛔This used to assert the opposite geometry — an 8px band ON the
    // button's top edge — reasoning that a band costs no WIDTH so the price
    // should be paid in height instead. The price it actually charged was
    // that nobody could find it, and since the `＋` makes only an animation
    // layer, every other KIND was unreachable for a first-time user.
    //
    // What still has to hold is the part that was never about geometry: the
    // two targets do not overlap, so a tap aimed at the variants cannot run
    // the ADD.
    var primary = 0;
    await tester.pumpWidget(
      harness(
        StrapIconButton(
          buttonKey: 'strap-main',
          menuKey: 'strap-menu',
          icon: Icons.add,
          tooltip: 'Add',
          onPressed: () => primary += 1,
          entriesBuilder: () => [
            const PanelFlyoutItem(keyValue: 'strap-variant', label: 'Variant'),
          ],
        ),
      ),
    );

    final body = tester.getRect(
      find.byKey(const ValueKey<String>('strap-main')),
    );
    final opener = tester.getRect(
      find.byKey(const ValueKey<String>('strap-menu')),
    );
    expect(
      opener.left,
      greaterThanOrEqualTo(body.right - 1),
      reason: 'beside it, on the right',
    );
    expect(
      opener.width,
      lessThan(body.width),
      reason: 'a second door onto that button, not a second button',
    );

    // Aimed at the opener's far side from the body — the corner a stray tap
    // would be most likely to miss into — and it still opens the menu.
    await tester.tapAt(Offset(opener.right - 1, opener.center.dy));
    await tester.pumpAndSettle();
    expect(primary, 0);
    expect(
      find.byKey(const ValueKey<String>('strap-variant')),
      findsOneWidget,
    );
  });

  testWidgets('StrapIconButton fits inside the pill — the band comes out of '
      'the body, not out of thin air', (tester) async {
    // The bug this pins: the first version pushed the body BELOW the band's
    // 8px and aligned it in what was left — 24px of button in a 20px box.
    // A `Stack` neither clips nor complains, so it shipped as a silent 4px
    // spill. The pill is exactly the command bar's content height, so there
    // is no margin above to borrow.
    await tester.pumpWidget(
      harness(
        CommandPill(
          head: PillNameCell(
            keyValue: 'pill-head',
            label: '레이어',
            entriesBuilder: () => const [],
          ),
          children: [
            const PillDivider(),
            StrapIconButton(
              buttonKey: 'strap-main',
              menuKey: 'strap-menu',
              icon: Icons.add,
              tooltip: 'Add',
              onPressed: () {},
              entriesBuilder: () => const [],
            ),
          ],
        ),
      ),
    );

    final pill = tester.getRect(find.byType(CommandPill));
    final body = tester.getRect(find.byKey(const ValueKey<String>('strap-main')));
    final band = tester.getRect(find.byKey(const ValueKey<String>('strap-menu')));

    expect(pill.height, CommandPill.height);
    expect(body.top, greaterThanOrEqualTo(pill.top - 0.01));
    expect(body.bottom, lessThanOrEqualTo(pill.bottom + 0.01));
    // The band lies over the body's top edge rather than beside it — that is
    // the whole point of moving the menu off the horizontal axis.
    expect(band.top, moreOrLessEquals(pill.top, epsilon: 0.01));
    expect(band.bottom, greaterThan(body.top));
  });

  testWidgets('StrapIconButton without entries wears no band at all', (
    tester,
  ) async {
    // 「띠가 있으면 고를 게 있다」 — the frame pill's `＋` makes one thing in
    // the place you are standing, so its absence is the signal.
    await tester.pumpWidget(
      harness(
        StrapIconButton(
          buttonKey: 'strap-main',
          icon: Icons.add,
          tooltip: 'Add',
          onPressed: () {},
        ),
      ),
    );
    expect(find.byKey(const ValueKey<String>('strap-menu')), findsNothing);
  });

  testWidgets('CommandPill: the name cell is the noun and opens its menu', (
    tester,
  ) async {
    await tester.pumpWidget(
      harness(
        CommandPill(
          head: PillNameCell(
            keyValue: 'pill-head',
            label: '레이어',
            entriesBuilder: () => [
              const PanelFlyoutItem(keyValue: 'pill-entry', label: 'Rename'),
            ],
          ),
          children: const [PillDivider()],
        ),
      ),
    );

    expect(find.text('레이어'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey<String>('pill-head')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey<String>('pill-entry')), findsOneWidget);
  });
}
