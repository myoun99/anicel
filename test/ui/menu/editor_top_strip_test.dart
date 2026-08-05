import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/color/color_button_window.dart';
import 'package:anicel/src/ui/debug/input_inspector.dart';
import 'package:anicel/src/ui/debug/measurement_mode.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/menu/editor_top_strip.dart';
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

  testWidgets('the blend button says its mode, and picking one changes what '
      'it says', (tester) async {
    await pumpHome(tester);

    // A NAMED button, not the icon popover the strip briefly wore: a blend
    // you cannot read without opening it is a blend you check by opening
    // it. This is the tool-settings dropdown, moved here whole.
    final button = find.byKey(
      const ValueKey<String>('brush-tool-blend-menu-button'),
    );
    expect(
      find.descendant(of: button, matching: find.text('Color')),
      findsOneWidget,
      reason: 'the resting label IS the current mode',
    );

    await openStrip(tester, 'brush-tool-blend-menu-button');
    await tapEntry(tester, 'brush-tool-blend-multiply');

    expect(
      find.descendant(of: button, matching: find.text('Multiply')),
      findsOneWidget,
    );
  });

  testWidgets('the blend button keeps ONE width, so changing the mode never '
      'shoves the bars sideways', (tester) async {
    await pumpHome(tester);

    final button = find.byKey(
      const ValueKey<String>('brush-tool-blend-menu-button'),
    );
    final sizeBar = find.byKey(const ValueKey<String>('top-strip-size-bar'));
    final widthBefore = tester.getSize(button).width;
    final barLeftBefore = tester.getTopLeft(sizeBar).dx;

    // 'Color' and 'Color Dodge' are nowhere near the same length.
    await openStrip(tester, 'brush-tool-blend-menu-button');
    await tapEntry(tester, 'brush-tool-blend-colorDodge');

    expect(tester.getSize(button).width, widthBefore);
    expect(tester.getTopLeft(sizeBar).dx, barLeftBefore);
  });

  testWidgets('the blend lock pins and releases', (tester) async {
    await pumpHome(tester);
    final lock = find.byKey(
      const ValueKey<String>('brush-tool-blend-lock-toggle'),
    );
    final button = find.byKey(
      const ValueKey<String>('brush-tool-blend-menu-button'),
    );

    // Pin the CURRENT mode, so the stroke does not change under you at the
    // moment you pin it, and the button keeps saying what it said.
    await tester.tap(lock);
    await tester.pumpAndSettle();
    expect(
      find.descendant(of: button, matching: find.text('Color')),
      findsOneWidget,
    );

    // While pinned, picking a mode edits the PIN rather than the hand
    // setting — the button still follows.
    await openStrip(tester, 'brush-tool-blend-menu-button');
    await tapEntry(tester, 'brush-tool-blend-screen');
    expect(
      find.descendant(of: button, matching: find.text('Screen')),
      findsOneWidget,
    );

    // Releasing drops back to the hand setting, which was never touched.
    await tester.tap(lock);
    await tester.pumpAndSettle();
    expect(
      find.descendant(of: button, matching: find.text('Color')),
      findsOneWidget,
      reason: 'the pin edited itself, not the hand setting underneath',
    );
  });

  testWidgets('the ERASER locks the blend — a lock chip, no flyout, and the '
      'bars do not move', (tester) async {
    await pumpHome(tester);

    final sizeBar = find.byKey(const ValueKey<String>('top-strip-size-bar'));
    final barLeftWithBrush = tester.getTopLeft(sizeBar).dx;

    await tester.tap(find.byKey(const ValueKey<String>('tool-eraser-button')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('brush-tool-blend-locked')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('brush-tool-blend-menu-button')),
      findsNothing,
      reason: 'the eraser IS the erase blend; there is nothing to choose',
    );
    // The lock toggle retires with the flyout, and its width has to stay
    // spoken for — otherwise picking up the eraser slides every bar left.
    expect(tester.getTopLeft(sizeBar).dx, barLeftWithBrush);
  });

  testWidgets('the strip right group reads: blend | size, opacity, colour — '
      'each value followed by its own lock', (tester) async {
    await pumpHome(tester);

    double leftOf(String key) =>
        tester.getTopLeft(find.byKey(ValueKey<String>(key))).dx;

    // 유저 확정 order. Asserted by POSITION, because the order is the
    // point — a list of findsOneWidget would pass on any arrangement.
    final order = [
      'brush-tool-blend-menu-button',
      'brush-tool-blend-lock-toggle',
      'top-strip-size-bar',
      'brush-tool-pressure-size',
      'top-strip-opacity-bar',
      'brush-tool-pressure-opacity',
      'tool-color-button',
    ];
    for (var i = 1; i < order.length; i++) {
      expect(
        leftOf(order[i]),
        greaterThan(leftOf(order[i - 1])),
        reason: '${order[i]} sits right of ${order[i - 1]}',
      );
    }
  });

  testWidgets('the colour rides the strip now, and the rail has none', (
    tester,
  ) async {
    await pumpHome(tester);

    final swatch = find.byKey(const ValueKey<String>('tool-color-button'));
    expect(
      find.descendant(of: find.byType(EditorTopStrip), matching: swatch),
      findsOneWidget,
    );
    // 유저 확정: 「컬러 스와치는 레일에서 빠진다 — 상단 색 버튼이 곧
    // 스와치라」. Two places showing one colour is what this removed.
    expect(
      find.descendant(
        of: find.byKey(const ValueKey<String>('tools-panel')),
        matching: swatch,
      ),
      findsNothing,
    );
  });

  testWidgets('the colour window opens BELOW its button, so the switch that '
      'closes it is never buried under it', (tester) async {
    await pumpHome(tester);

    final anchor = find.byKey(const ValueKey<String>('tool-color-button'));
    final anchorRect = tester.getRect(anchor);
    await tester.tap(anchor);
    await tester.pumpAndSettle();

    // The shared placement flips a popup above its anchor when there is no
    // room below, and clamps it into the overlay when there is room for
    // neither — which for a DISMISSING popup is harmless (anything closes
    // it) but for this one would hide the only thing that can.
    expect(
      tester.getRect(find.byType(ColorButtonWindow)).top,
      greaterThanOrEqualTo(anchorRect.bottom),
    );
  });

  testWidgets('the colour window is PINNED: the size bar still works while it '
      'is open, because there is no barrier over the app', (tester) async {
    await pumpHome(tester);

    await tester.tap(find.byKey(const ValueKey<String>('tool-color-button')));
    await tester.pumpAndSettle();
    expect(find.byType(ColorButtonWindow), findsOneWidget);

    double sizeOnBar() => tester
        .widget<FieldSlider>(
          find.byKey(const ValueKey<String>('top-strip-size-bar')),
        )
        .value;
    final before = sizeOnBar();

    // This is the R27 #5 gesture that closes every other anchored popup. A
    // route-based popup would not merely close — its modal barrier would eat
    // the drag, so the size would not move either.
    final bar = find.byKey(const ValueKey<String>('top-strip-size-bar'));
    await tester.tapAt(tester.getCenter(bar) + const Offset(50, 0));
    await tester.pumpAndSettle();

    expect(sizeOnBar(), isNot(before), reason: 'the drag reached the bar');
    expect(
      find.byType(ColorButtonWindow),
      findsOneWidget,
      reason: 'and the window is still open to be nudged again',
    );
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
