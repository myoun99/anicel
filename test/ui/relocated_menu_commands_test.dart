import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/home_page.dart';

import 'flyout_test_helpers.dart';

/// Commands that used to exist ONLY in the top menu bar now also reach the
/// surface where their result shows up — the timeline's Layer ▾ and Cut ▾
/// flyouts. The menu bar is going away; these are the entrances that have
/// to outlive it, so each one is pinned here by key.
void main() {
  Future<void> pumpHome(WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: HomePage()));
    await tester.pumpAndSettle();
  }

  Future<void> expectInFlyout(WidgetTester tester, String itemKey) async {
    await openOwningFlyout(tester, itemKey);
    expect(
      find.byKey(ValueKey<String>(itemKey)),
      findsOneWidget,
      reason: '$itemKey should be reachable from its flyout',
    );
    await dismissFlyout(tester);
  }

  testWidgets('the relocated LAYER commands reach the Layer flyout', (
    tester,
  ) async {
    await pumpHome(tester);

    // R5 #14: the two folder-making commands left. A folder is ADDED empty
    // from the Add Layer menu now and filled by dropping rows on it, and
    // an attach folder is made the same way — so neither has a Layer-menu
    // entry to relocate any more.
    await expectInFlyout(tester, 'timeline-rasterize-layer-button');
    await expectInFlyout(tester, 'timeline-se-name-tag-button');
  });

  testWidgets('the relocated CUT commands reach the Cut flyouts', (
    tester,
  ) async {
    await pumpHome(tester);

    // Making a linked cut belongs with the other ways of making a cut, so
    // it sits under the New-cut split button rather than the Cut menu.
    await expectInFlyout(tester, 'add-cut-create-linked');
    await expectInFlyout(tester, 'convert-cut-to-linked-button');
    await expectInFlyout(tester, 'copy-cut-ae-camera-button');
  });
}
