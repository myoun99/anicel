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
}
