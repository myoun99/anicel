import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/widgets/panel_flyout.dart';

/// R-toolbar round: these command keys moved from standalone toolbar
/// buttons into the Layer ▾ / Frame ▾ / Cut ▾ flyouts. Key strings were
/// preserved as the menu ITEM keys, so tests reach them by opening the
/// owning flyout first.
const Map<String, String> flyoutOwnerByItemKey = {
  'rename-layer-button': 'timeline-layer-menu-button',
  'duplicate-layer-button': 'timeline-layer-menu-button',
  'copy-layer-button': 'timeline-layer-menu-button',
  'paste-layer-button': 'timeline-layer-menu-button',
  'delete-layer-button': 'timeline-layer-menu-button',
  'import-audio-button': 'timeline-layer-menu-button',
  'toggle-storyboard-layer-button': 'timeline-layer-menu-button',
  'toggle-se-section-button': 'timeline-layer-menu-button',
  'toggle-camera-section-button': 'timeline-layer-menu-button',
  'timeline-group-attach-into-folder-button': 'timeline-layer-menu-button',
  'timeline-rasterize-layer-button': 'timeline-layer-menu-button',
  'timeline-se-name-tag-button': 'timeline-layer-menu-button',
  'rename-frame-button': 'timeline-frame-menu-button',
  'copy-frame-button': 'timeline-frame-menu-button',
  'paste-linked-frame-button': 'timeline-frame-menu-button',
  'delete-cell-button': 'timeline-frame-menu-button',
  'add-cut-create-linked': 'new-cut-menu',
  'rename-cut-button': 'cut-menu-button',
  'convert-cut-to-linked-button': 'cut-menu-button',
  'copy-cut-ae-camera-button': 'cut-menu-button',
  'edit-cut-note-button': 'cut-menu-button',
  'resize-cut-canvas-button': 'cut-menu-button',
  'duplicate-cut-button': 'cut-menu-button',
  'set-cut-thumbnail-button': 'cut-menu-button',
  'move-cut-left-button': 'cut-menu-button',
  'move-cut-right-button': 'cut-menu-button',
  'delete-cut-button': 'cut-menu-button',
};

/// Opens the flyout that owns [itemKey] (no-op for direct buttons).
Future<void> openOwningFlyout(WidgetTester tester, String itemKey) async {
  final owner = flyoutOwnerByItemKey[itemKey];
  if (owner == null) {
    return;
  }
  final menuButton = find.byKey(ValueKey<String>(owner));
  await tester.ensureVisible(menuButton);
  await tester.pumpAndSettle();
  await tester.tap(menuButton);
  await tester.pumpAndSettle();
}

/// Closes an open flyout without picking anything.
Future<void> dismissFlyout(WidgetTester tester) async {
  await tester.sendKeyEvent(LogicalKeyboardKey.escape);
  await tester.pumpAndSettle();
}

/// Taps a command by key — opening its owning flyout first when the command
/// lives in one. Drop-in replacement for the old direct toolbar tap.
Future<void> tapCommandButton(WidgetTester tester, ValueKey<String> key) async {
  await openOwningFlyout(tester, key.value);
  final button = find.byKey(key);
  await tester.ensureVisible(button);
  await tester.pumpAndSettle();
  await tester.tap(button, warnIfMissed: false);
  await tester.pumpAndSettle();
}

/// Whether the (possibly flyout-hosted) command is enabled right now.
/// Opens and closes the owning flyout to read the item.
Future<bool> readCommandEnabled(
  WidgetTester tester,
  ValueKey<String> key,
) async {
  await openOwningFlyout(tester, key.value);
  // The item key sits ON the PopupMenuItem itself.
  final item = tester.widget<PopupMenuItem<PanelFlyoutItem>>(find.byKey(key));
  final enabled = item.enabled;
  await dismissFlyout(tester);
  return enabled;
}
