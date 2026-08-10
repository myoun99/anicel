import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/theme/app_theme.dart';
import 'package:anicel/src/ui/widgets/command_pill.dart';
import 'package:anicel/src/ui/widgets/grip_band.dart';
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

  testWidgets('StrapIconButton: the band zone is the full 8px of the top '
      'edge, and the body never reaches into it', (tester) async {
    // The whole point of moving the menu from a `▾` beside the button to a
    // band above it is that the band costs no WIDTH — so the price is paid
    // in height, and this is where that price has to be checked. A tap one
    // pixel inside the band must open the menu, not run the action.
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

    final band = tester.getRect(
      find.byKey(const ValueKey<String>('strap-menu')),
    );
    expect(band.height, GripBand.hitExtent);

    // Just inside the band's BOTTOM edge — the far end from where a stray
    // tap would land — still opens the menu rather than adding.
    await tester.tapAt(Offset(band.center.dx, band.bottom - 1));
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
