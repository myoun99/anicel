import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/theme/app_theme.dart';
import 'package:anicel/src/ui/widgets/panel_flyout.dart';
import 'package:anicel/src/ui/widgets/split_icon_button.dart';

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

  testWidgets('SplitIconButton: body fires the primary action, the arrow '
      'zone opens the flyout', (tester) async {
    var primary = 0;
    var variant = 0;
    await tester.pumpWidget(
      harness(
        SplitIconButton(
          buttonKey: 'split-main',
          menuKey: 'split-menu',
          icon: Icons.add,
          tooltip: 'Add',
          onPressed: () => primary += 1,
          entriesBuilder: () => [
            PanelFlyoutItem(
              keyValue: 'split-variant',
              label: 'Variant',
              onSelected: () => variant += 1,
            ),
          ],
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey<String>('split-main')));
    await tester.pumpAndSettle();
    expect(primary, 1);
    expect(variant, 0);

    await tester.tap(find.byKey(const ValueKey<String>('split-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('split-variant')));
    await tester.pumpAndSettle();
    expect(primary, 1);
    expect(variant, 1);
  });
}
