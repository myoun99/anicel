import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/debug/input_inspector.dart';
import 'package:anicel/src/ui/debug/measurement_mode.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/widgets/panel_flyout.dart';

/// The top strip that replaced the seven-menu bar: a Project button, a
/// Settings button, and the work's name.
///
/// The commands that left are not tested here any more — they are tested
/// where they landed (the timeline flyouts, the tool rail). What stays is
/// what belongs to no surface in particular: the project file, and the
/// app's own switches.
void main() {
  Future<void> pumpHome(WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: HomePage()));
    await tester.pumpAndSettle();
  }

  Future<void> openStrip(WidgetTester tester, String buttonKey) async {
    final button = find.byKey(ValueKey<String>(buttonKey));
    await tester.ensureVisible(button);
    await tester.pumpAndSettle();
    await tester.tap(button);
    await tester.pumpAndSettle();
  }

  Future<void> tapEntry(WidgetTester tester, String itemKey) async {
    final item = find.byKey(ValueKey<String>(itemKey));
    await tester.ensureVisible(item);
    await tester.pumpAndSettle();
    await tester.tap(item);
    await tester.pumpAndSettle();
  }

  testWidgets('the strip carries two buttons and none of the old menus', (
    tester,
  ) async {
    await pumpHome(tester);

    expect(find.byType(AppBar), findsNothing);
    expect(
      find.byKey(const ValueKey<String>('top-strip-project-button')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('top-strip-settings-button')),
      findsOneWidget,
    );

    for (final menu in ['file', 'edit', 'cut', 'layer', 'playback', 'help']) {
      expect(
        find.byKey(ValueKey<String>('menu-$menu')),
        findsNothing,
        reason: 'the $menu menu is gone; its commands moved to their surface',
      );
    }
  });

  testWidgets('Project: the persistence entries are live and export opens', (
    tester,
  ) async {
    await pumpHome(tester);
    await openStrip(tester, 'top-strip-project-button');

    for (final slot in ['file-open', 'file-save', 'file-save-as']) {
      final item = tester.widget<PopupMenuItem<PanelFlyoutItem>>(
        find.byKey(ValueKey<String>('menu-$slot')),
      );
      expect(item.enabled, isTrue, reason: '$slot is live since P3');
    }

    // Export used to be its own icon in the strip; it is a once-a-session
    // verb, so it lives behind the same button as saving now.
    await tapEntry(tester, 'menu-file-export');
    expect(
      find.byKey(const ValueKey<String>('export-run-button')),
      findsOneWidget,
    );
  });

  testWidgets('Settings: a closed panel comes back from the panel rows', (
    tester,
  ) async {
    await pumpHome(tester);

    await tester.tap(find.byKey(const ValueKey<String>('panel-close-brushes')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey<String>('panel-tab-brushes')),
      findsNothing,
    );

    // The old Window menu, now a section of Settings. This is the ONLY way
    // back for an X-ed panel, which is why it survived the teardown.
    await openStrip(tester, 'top-strip-settings-button');
    await tapEntry(tester, 'panels-menu-item-brushes');

    expect(
      find.byKey(const ValueKey<String>('panel-tab-brushes')),
      findsOneWidget,
    );
  });

  testWidgets('Settings: Reset Workspace Layout restores closed panels', (
    tester,
  ) async {
    await pumpHome(tester);

    await tester.tap(find.byKey(const ValueKey<String>('panel-close-brushes')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey<String>('panel-tab-brushes')),
      findsNothing,
    );

    await openStrip(tester, 'top-strip-settings-button');
    await tapEntry(tester, 'menu-window-reset-layout');

    expect(
      find.byKey(const ValueKey<String>('panel-tab-brushes')),
      findsOneWidget,
    );
  });

  testWidgets('Settings: About opens the framework about dialog', (
    tester,
  ) async {
    await pumpHome(tester);

    await openStrip(tester, 'top-strip-settings-button');
    await tapEntry(tester, 'menu-help-about');

    expect(find.byType(AboutDialog), findsOneWidget);
  });

  testWidgets('Settings: Input Inspector toggles the diagnosis overlay', (
    tester,
  ) async {
    addTearDown(InputInspector.reset);
    await pumpHome(tester);

    await openStrip(tester, 'top-strip-settings-button');
    await tapEntry(tester, 'menu-edit-input-inspector');
    expect(
      find.byKey(const ValueKey<String>('input-inspector-card')),
      findsOneWidget,
    );

    await openStrip(tester, 'top-strip-settings-button');
    await tapEntry(tester, 'menu-edit-input-inspector');
    expect(
      find.byKey(const ValueKey<String>('input-inspector-card')),
      findsNothing,
    );
  });

  testWidgets('Settings: Frame Timing Overlay drives the measurement switch', (
    tester,
  ) async {
    addTearDown(MeasurementMode.reset);
    await pumpHome(tester);
    expect(MeasurementMode.frameTimingOverlay.value, isFalse);

    await openStrip(tester, 'top-strip-settings-button');
    await tapEntry(tester, 'menu-edit-frame-timing-overlay');
    expect(
      MeasurementMode.frameTimingOverlay.value,
      isTrue,
      reason: 'the entry drives the switch MaterialApp reads',
    );

    await openStrip(tester, 'top-strip-settings-button');
    await tapEntry(tester, 'menu-edit-frame-timing-overlay');
    expect(MeasurementMode.frameTimingOverlay.value, isFalse);
  });
}
