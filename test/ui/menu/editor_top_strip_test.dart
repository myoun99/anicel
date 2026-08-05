import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/debug/input_inspector.dart';
import 'package:anicel/src/ui/debug/measurement_mode.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/widgets/field_slider.dart';
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

  testWidgets('Settings: the panel rows are the show/hide switch now', (
    tester,
  ) async {
    await pumpHome(tester);

    // The tab's X is gone with the rest of the panel chrome (고정 도킹), so
    // this list is not just the way BACK any more — it is the only switch
    // in either direction.
    await openStrip(tester, 'top-strip-settings-button');
    await tapEntry(tester, 'panels-menu-item-brushes');
    expect(
      find.byKey(const ValueKey<String>('panel-tab-brushes')),
      findsNothing,
    );

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

    await openStrip(tester, 'top-strip-settings-button');
    await tapEntry(tester, 'panels-menu-item-brushes');
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

  testWidgets('the size and opacity bars ride the right end', (tester) async {
    await pumpHome(tester);

    expect(
      find.byKey(const ValueKey<String>('top-strip-size-bar')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('top-strip-opacity-bar')),
      findsOneWidget,
    );
  });

  testWidgets('the bars show the ACTIVE tool — brush and eraser bank apart', (
    tester,
  ) async {
    await pumpHome(tester);

    double sizeOnBar() => tester
        .widget<FieldSlider>(
          find.byKey(const ValueKey<String>('top-strip-size-bar')),
        )
        .value;

    final bar = find.byKey(const ValueKey<String>('top-strip-size-bar'));
    Future<void> dragBarTo(double dx) async {
      await tester.tapAt(tester.getCenter(bar) + Offset(dx, 0));
      await tester.pumpAndSettle();
    }

    await dragBarTo(50);
    final brushSize = sizeOnBar();

    // The FIRST switch carries the settings across — the eraser's bank is
    // empty until it has been the active tool once (R11-④), so this is not
    // where the split shows.
    await tester.tap(find.byKey(const ValueKey<String>('tool-eraser-button')));
    await tester.pumpAndSettle();
    await dragBarTo(-50);
    final eraserSize = sizeOnBar();
    expect(eraserSize, isNot(brushSize));

    // Now both banks are filled, and the bar is a WINDOW onto whichever
    // tool is active rather than one global number.
    await tester.tap(find.byKey(const ValueKey<String>('tool-brush-button')));
    await tester.pumpAndSettle();
    expect(sizeOnBar(), brushSize, reason: 'the brush gets its own back');

    await tester.tap(find.byKey(const ValueKey<String>('tool-eraser-button')));
    await tester.pumpAndSettle();
    expect(sizeOnBar(), eraserSize, reason: 'and the eraser keeps its own');
  });

  testWidgets('the blend mode is a popover beside the bars', (tester) async {
    await pumpHome(tester);

    // A list, not a bar: you pick one and go. It is also one of the three
    // settings a preset never carries, which is why it stands with the
    // hand's own choices instead of living inside a preset.
    await openStrip(tester, 'top-strip-blend-button');
    await tapEntry(tester, 'top-strip-blend-multiply');

    await openStrip(tester, 'top-strip-blend-button');
    final item = tester.widget<PopupMenuItem<PanelFlyoutItem>>(
      find.byKey(const ValueKey<String>('top-strip-blend-multiply')),
    );
    expect(item.value?.checked, isTrue);
  });

  testWidgets('the strip survives a narrow window', (tester) async {
    // 844x390 is the size that used to overflow the bottom dock; the strip
    // now carries two 140px bars, so it has to be checked too.
    tester.view.physicalSize = const Size(844, 390);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await pumpHome(tester);

    expect(tester.takeException(), isNull);
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
