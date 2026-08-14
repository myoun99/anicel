import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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

  testWidgets('Settings: Reset Workspace Layout restores EVERY remembered '
      'thing, not only the docks', (tester) async {
    // It used to reset the docks, the extents and the locks — most of a
    // layout, but not a layout. Which groups were open, which edge the
    // region was on and whether it was collapsed all survived, so the
    // button could not get anyone out of an arrangement they disliked.
    await tester.binding.setSurfaceSize(const Size(1600, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await pumpHome(tester);

    final leftGroup = find.byKey(const ValueKey<String>('rail-group-rail-L1'));
    expect(
      find.byKey(const ValueKey<String>('panel-tab-brushes')),
      findsOneWidget,
    );

    // Close a rail group, and put the floating region on the other edge.
    await tester.tap(leftGroup);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey<String>('panel-tab-brushes')),
      findsNothing,
    );
    await openStrip(tester, 'top-strip-settings-button');
    await tapEntry(tester, 'menu-window-region-on-top');
    final movedTimeline = tester.getRect(
      find.byKey(const ValueKey<String>('floating-bottom-region')),
    );

    await openStrip(tester, 'top-strip-settings-button');
    await tapEntry(tester, 'menu-window-reset-layout');

    expect(
      find.byKey(const ValueKey<String>('panel-tab-brushes')),
      findsOneWidget,
      reason: 'the closed group is open again',
    );
    final resetTimeline = tester.getRect(
      find.byKey(const ValueKey<String>('floating-bottom-region')),
    );
    expect(
      resetTimeline.top,
      greaterThan(movedTimeline.top),
      reason: 'the region is back on the bottom edge',
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

  // TP1/TP2 (유저: 툴마다 기억하게해서 필 툴도 불투명도 설정하면 그거대로
  // 채워지게 … 적용안되는툴이나 모드면 비활성화시키도록).
  group('the strip follows the armed tool', () {
    FieldSlider barOf(WidgetTester tester, String key) =>
        tester.widget<FieldSlider>(find.byKey(ValueKey<String>(key)));

    Future<void> arm(WidgetTester tester, String railKey) async {
      await tester.tap(find.byKey(ValueKey<String>(railKey)));
      await tester.pumpAndSettle();
    }

    testWidgets('opacity is per tool: the fill keeps its own', (tester) async {
      await pumpHome(tester);
      final bar = find.byKey(const ValueKey<String>('top-strip-opacity-bar'));

      // Half-ish on the BRUSH.
      await tester.tapAt(
        tester.getTopLeft(bar) + Offset(tester.getSize(bar).width / 2, 20),
      );
      await tester.pumpAndSettle();
      final brushOpacity = barOf(tester, 'top-strip-opacity-bar').value;
      expect(brushOpacity, lessThan(0.95), reason: 'the drag moved it');

      // The FILL starts at its own default and takes its own value.
      await arm(tester, 'tool-fill-button');
      expect(
        barOf(tester, 'top-strip-opacity-bar').value,
        1.0,
        reason: "the brush's opacity did not follow the tool switch",
      );
      await tester.tapAt(
        tester.getTopLeft(bar) + Offset(tester.getSize(bar).width / 4, 20),
      );
      await tester.pumpAndSettle();
      final fillOpacity = barOf(tester, 'top-strip-opacity-bar').value;
      expect(fillOpacity, lessThan(brushOpacity));

      // …and neither leaks into the other, in either direction.
      await arm(tester, 'tool-brush-button');
      expect(barOf(tester, 'top-strip-opacity-bar').value, brushOpacity);
      await arm(tester, 'tool-fill-button');
      expect(barOf(tester, 'top-strip-opacity-bar').value, fillOpacity);
    });

    testWidgets('a parameter the tool does not read is DIMMED, not gone', (
      tester,
    ) async {
      await pumpHome(tester);
      // The eyedropper reads none of them.
      await arm(tester, 'tool-eyedropper-button');
      for (final key in const [
        'top-strip-size-bar',
        'top-strip-opacity-bar',
        'brush-tool-blend-menu-button',
        'brush-tool-pressure-size',
        'brush-tool-pressure-opacity',
      ]) {
        expect(
          find.byKey(ValueKey<String>(key)),
          findsOneWidget,
          reason: '$key stays on the strip — the row must not change shape',
        );
      }
      expect(
        barOf(tester, 'top-strip-size-bar').onChanged,
        isNull,
        reason: 'and it is dead while it is dim',
      );
      expect(barOf(tester, 'top-strip-opacity-bar').onChanged, isNull);

      // The FILL takes opacity and blend but not size or pressure.
      await arm(tester, 'tool-fill-button');
      expect(barOf(tester, 'top-strip-size-bar').onChanged, isNull);
      expect(barOf(tester, 'top-strip-opacity-bar').onChanged, isNotNull);
    });
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

    // ⛔CONTRACT CHANGE (유저, R4 #12: 잠궜는데 바꿀 수 있으면 잠금이
    // 아니잖아). While pinned the button REFUSES TO OPEN. It used to open
    // and edit the pin, which made the padlock a label rather than a lock —
    // the same control both fixed the brush to a mode and changed which
    // mode it was fixed to.
    await openStrip(tester, 'brush-tool-blend-menu-button');
    expect(
      find.byKey(const ValueKey<String>('brush-tool-blend-screen')),
      findsNothing,
      reason: 'a locked blend has no menu to pick from',
    );
    expect(
      find.descendant(of: button, matching: find.text('Color')),
      findsOneWidget,
    );

    // Unlocking gives it back, and the hand setting underneath was never
    // touched by any of this.
    await tester.tap(lock);
    await tester.pumpAndSettle();
    await openStrip(tester, 'brush-tool-blend-menu-button');
    await tapEntry(tester, 'brush-tool-blend-screen');
    expect(
      find.descendant(of: button, matching: find.text('Screen')),
      findsOneWidget,
      reason: 'unlock, choose, lock again — the lock is one tap away',
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

  testWidgets('the strip right group reads: blend | size, opacity — the '
      'colour has left it', (tester) async {
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
    ];
    for (var i = 1; i < order.length; i++) {
      expect(
        leftOf(order[i]),
        greaterThan(leftOf(order[i - 1])),
        reason: '${order[i]} sits right of ${order[i - 1]}',
      );
    }
  });

  testWidgets('the colour left the strip for the sub-strip, and took its '
      'swatch with it', (tester) async {
    await pumpHome(tester);

    // 컬러 창은 상단띠에서 오른쪽 서브띠 맨 위로 (유저 확정). It was the one
    // surface that opened DOWNWARD out of a strip; as a rail group it opens
    // sideways like every other panel.
    final swatch = find.byKey(const ValueKey<String>('tool-color-button'));
    expect(
      find.descendant(of: find.byType(EditorTopStrip), matching: swatch),
      findsNothing,
    );
    // And it is exactly ONE place, still: the group's rail button IS the
    // pair, so the two colours you paint with stay readable without opening
    // anything — which is what the strip swatch was for.
    expect(
      find.descendant(
        of: find.byKey(
          const ValueKey<String>('editor-panel-dock-tool-right'),
        ),
        matching: swatch,
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey<String>('tools-panel')),
        matching: swatch,
      ),
      findsNothing,
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
