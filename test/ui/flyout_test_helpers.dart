import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/widgets/app_icon_button.dart';
import 'package:anicel/src/ui/widgets/panel_flyout.dart';

/// R-toolbar round: these command keys moved from standalone toolbar
/// buttons into the Layer ▾ / Frame ▾ / Cut ▾ flyouts. Key strings were
/// preserved as the menu ITEM keys, so tests reach them by opening the
/// owning flyout first.
const Map<String, String> flyoutOwnerByItemKey = {
  // ⛔'rename-layer-button' is NOT here any more: ① moved it out of the
  // layer menu and onto the pill, the same way 'delete-cut-button' left the
  // cut menu below.
  'duplicate-layer-button': 'timeline-layer-menu-button',
  'copy-layer-button': 'timeline-layer-menu-button',
  'paste-layer-button': 'timeline-layer-menu-button',
  'delete-layer-button': 'timeline-layer-menu-button',
  'toggle-storyboard-layer-button': 'timeline-layer-menu-button',
  'timeline-rasterize-layer-button': 'timeline-layer-menu-button',
  // R5 #5/#14: import audio, the two SECTION switches and both
  // folder-making commands left the Layer menu. Sections keep their own
  // door — the legend's sections cell, which is where they always also
  // lived and the only one left.
  'legend-section-se': 'legend-sections',
  'legend-section-camera': 'legend-sections',
  // R5 #6: the effect chain has a button of its own now.
  'add-effect-blur': 'timeline-effects-button',
  // 'timeline-se-name-tag-button' is gone (R5 #7): the tag's controls are
  // lanes on the SE row now, so the window it opened had nothing left to
  // hold.
  // ⛔'rename-frame-button' (Edit Instance) left the frame menu for the
  // frame pill — ① again.
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
  // ⛔'delete-cut-button' is NOT here any more: ① moved it out of the cut
  // menu and onto the pill, so it is a plain bar button with no owner to
  // open first.
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
///
/// A command that has MOVED onto a pill is a plain button with no owner to
/// open, and its enablement is a null `onPressed` rather than an item flag.
/// Reading both here is what lets a test survive the move: what the test
/// wanted to know — 「이 명령이 지금 눌리나」 — did not change.
Future<bool> readCommandEnabled(
  WidgetTester tester,
  ValueKey<String> key,
) async {
  await openOwningFlyout(tester, key.value);
  if (flyoutOwnerByItemKey[key.value] == null) {
    final button = tester.widget(find.byKey(key));
    return switch (button) {
      AppIconButton(:final onPressed) => onPressed != null,
      IconButton(:final onPressed) => onPressed != null,
      _ => throw StateError(
        'readCommandEnabled: ${key.value} is neither a flyout item nor a '
        'known button type (${button.runtimeType})',
      ),
    };
  }
  // The item key sits ON the PopupMenuItem itself.
  final item = tester.widget<PopupMenuItem<PanelFlyoutItem>>(find.byKey(key));
  final enabled = item.enabled;
  await dismissFlyout(tester);
  return enabled;
}
